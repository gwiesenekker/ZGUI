unit uTournamentStorage;
{$mode objfpc}{$H+}
interface
uses FPJSON,uGameTreePdn;
function ReadTournamentDocument(const AFileName: string; AFormat:TGameFileFormat=gffPdn): TJSONObject;
function TournamentDocumentText(AData: TJSONData): string;
function TournamentPdnTag(const AName, AValue: string): string;
function UnusedTournamentPdnPath(const ACandidate: string; AFormat:TGameFileFormat=gffPdn): string;
function TournamentPdnMatchesId(const AFileName, AId: string; AFormat:TGameFileFormat=gffPdn): Boolean;
implementation
uses uSprt, Classes, SysUtils, JSONParser, uTournamentTypes, uTournamentResults, uDraughtsPdn, uChessPgn, Math;

function TournamentDocumentText(AData: TJSONData): string;
var
  Output: TMemoryStream;

  procedure WriteText(const Text: RawByteString);
  begin
    if Text <> '' then Output.WriteBuffer(Text[1], Length(Text));
  end;

  procedure WriteValue(Value: TJSONData; Depth: Integer);
  var
    I: Integer;
    IsObject: Boolean;
  begin
    if Value = nil then
      WriteText('null')
    else if Value.JSONType in [jtObject, jtArray] then
    begin
      IsObject := Value.JSONType = jtObject;
      if IsObject then WriteText('{') else WriteText('[');
      for I := 0 to Value.Count - 1 do
      begin
        if I > 0 then WriteText(',');
        WriteText(LineEnding + StringOfChar(' ', (Depth + 1) * 2));
        if IsObject then
          WriteText('"' + StringToJSONString(TJSONObject(Value).Names[I]) + '": ');
        WriteValue(Value.Items[I], Depth + 1);
      end;
      if Value.Count > 0 then
        WriteText(LineEnding + StringOfChar(' ', Depth * 2));
      if IsObject then WriteText('}') else WriteText(']');
    end
    else
      WriteText(Value.AsJSON);
  end;

begin
  Output := TMemoryStream.Create;
  try
    WriteValue(AData, 0);
    WriteText(LineEnding);
    SetLength(Result, Output.Size);
    if Output.Size > 0 then Move(Output.Memory^, Result[1], Output.Size);
  finally
    Output.Free;
  end;
end;

type
  TTournamentPdnIdentityCheck = class
    Id: string;
    Matches: Boolean;
    procedure CheckGame(Game: TPdnGame; BytesRead, TotalBytes: Int64; var Stop: Boolean);
  end;

procedure TTournamentPdnIdentityCheck.CheckGame(Game: TPdnGame;
  BytesRead, TotalBytes: Int64; var Stop: Boolean);
begin
  if Game.TournamentId <> Id then
  begin
    Matches := False;
    Stop := True;
  end;
end;

function TournamentPdnMatchesId(const AFileName, AId: string; AFormat:TGameFileFormat): Boolean;
var Check: TTournamentPdnIdentityCheck;
begin
  Result := False;
  if (AId = '') or not FileExists(AFileName) then Exit;
  if AFormat=gffPgn then Exit(PgnTournamentFileMatchesId(AFileName,AId));
  Check := TTournamentPdnIdentityCheck.Create;
  try
    Check.Id := AId;
    Check.Matches := True;
    try
      // Ownership needs headers, not move trees or large comment copies.
      ReadPdnGamesFromFile(AFileName, @Check.CheckGame, True);
      Result := Check.Matches;
    except Result := False; end;
  finally Check.Free; end;
end;

function UnusedTournamentPdnPath(const ACandidate: string; AFormat:TGameFileFormat): string;
var
  Id: TGUID;
  BaseName: string;
begin
  Result := ExpandFileName(ACandidate);
  BaseName := ChangeFileExt(Result, '');
  while FileExists(Result) or DirectoryExists(Result) do
  begin
    if CreateGUID(Id) <> 0 then
      raise EInOutError.Create('Could not create a tournament PDN name');
    if AFormat=gffPgn then Result := BaseName + '.' + GUIDToString(Id) + '.pgn'
    else Result := BaseName + '.' + GUIDToString(Id) + '.pdn';
  end;
end;

type
  TAllowedJsonTypes = set of TJSONType;

function TournamentPdnTag(const AName, AValue: string): string;
var
  Value: string;
begin
  Value := StringReplace(AValue, '\', '\\', [rfReplaceAll]);
  Value := StringReplace(Value, '"', '\"', [rfReplaceAll]);
  Value := StringReplace(Value, #13, ' ', [rfReplaceAll]);
  Value := StringReplace(Value, #10, ' ', [rfReplaceAll]);
  Result := '[' + AName + ' "' + Value + '"]';
end;

procedure CheckField(AObject: TJSONObject; const AName: string;
  ATypes: TAllowedJsonTypes);
var
  Value: TJSONData;
begin
  Value := AObject.Find(AName);
  if (Value <> nil) and not (Value.JSONType in ATypes) then
    raise EConvertError.Create('Invalid tournament field: ' + AName);
end;

procedure CheckInteger(AObject: TJSONObject; const AName: string; AMinimum: Integer);
var
  Value: TJSONData;
begin
  CheckField(AObject, AName, [jtNumber]);
  Value := AObject.Find(AName);
  if Value = nil then
    Exit;
  if IsNan(Value.AsFloat) or IsInfinite(Value.AsFloat) or
    (Value.AsFloat < AMinimum) or (Value.AsFloat > High(Integer)) or
    (Value.AsFloat <> Trunc(Value.AsFloat)) then
    raise EConvertError.Create('Invalid tournament integer: ' + AName);
end;

procedure ValidateRecord(Data: TJSONObject; AHistoryAllowed: Boolean; AFormat:TGameFileFormat);
var
  Items: TJSONArray;
  I: Integer;
  Value: string;
  Y,M,D:Integer;
  DateValue:TDateTime;
begin
  CheckInteger(Data, 'attempt', 1);
  CheckField(Data, 'pdn', [jtString]);
  CheckField(Data, 'starting_fen', [jtString]);
  CheckField(Data, 'start_date', [jtString]);
  Value:=Data.Get('start_date','');
  if (AFormat=gffPgn) and (Value<>'') then
    if (Length(Value)<>10) or (Value[5]<>'.') or (Value[8]<>'.') or
      not TryStrToInt(Copy(Value,1,4),Y) or not TryStrToInt(Copy(Value,6,2),M) or
      not TryStrToInt(Copy(Value,9,2),D) or (Y<1) or (Y>9999) or (M<1) or (M>12) or
      (D<1) or (D>31) or not TryEncodeDate(Y,M,D,DateValue) then
      raise EConvertError.Create('Invalid tournament game start date');
  CheckField(Data, 'capture_error', [jtString]);
  CheckField(Data, 'white_engine_key', [jtString]);
  CheckField(Data, 'black_engine_key', [jtString]);
  CheckField(Data, 'played_result', [jtString]);
  CheckField(Data, 'manual_result', [jtString]);
  Value := Data.Get('played_result', '');
  if (Value <> '') and (Value <> '*') and
    not TournamentResultIsKnown(ParseTournamentResult(Value,AFormat)) then
    raise EConvertError.Create('Invalid played tournament result');
  Value := Data.Get('manual_result', '');
  if (Value <> '') and (Value <> '*') and
    not TournamentResultIsKnown(ParseTournamentResult(Value,AFormat)) then
    raise EConvertError.Create('Invalid manual tournament result');
  CheckField(Data, 'history', [jtArray]);
  Items := TJSONArray(Data.Find('history'));
  if Items <> nil then
  begin
    if not AHistoryAllowed then
      raise EConvertError.Create('Tournament attempt history must not be nested');
    for I := 0 to Items.Count - 1 do
    begin
      if Items[I].JSONType <> jtObject then
        raise EConvertError.Create('Invalid tournament attempt history');
      ValidateRecord(TJSONObject(Items[I]), False,AFormat);
    end;
  end;
end;

procedure ValidateDocument(Data: TJSONObject; AFormat:TGameFileFormat);
var
  Value: TJSONData;
  Games, Engines, Positions: TJSONArray;
  Game, Ballot, RecordData: TJSONObject;
  I: Integer;
  PairingType, ResultText: string;
  Seen: TStringList;
  PairingKey: string;
begin
  ReadSprtConfig(Data.Find('sprt_view'));
  CheckInteger(Data, 'storage_version', 1);
  if Data.Get('storage_version', 1) > 4 then
    raise EConvertError.Create('Unsupported tournament storage version');
  if Data.Get('storage_version',1)=4 then begin
    CheckField(Data,'game_variant',[jtString]);CheckField(Data,'notation_format',[jtString]);
    CheckField(Data,'force_ponder_off',[jtBoolean]);
    if ((AFormat=gffPgn) and ((Data.Get('game_variant','')<>'chess') or
      (Data.Get('notation_format','')<>'pgn') or not Data.Get('force_ponder_off',False))) or
      ((AFormat=gffPdn) and ((Data.Get('game_variant','')<>'draughts') or
      (Data.Get('notation_format','')<>'pdn') or Data.Get('force_ponder_off',True))) then
      raise EConvertError.Create('Unsupported tournament variant, format or ponder policy');
    CheckField(Data,'opening_ballot',[jtObject]);
    Ballot:=TJSONObject(Data.Find('opening_ballot'));
    if Ballot=nil then raise EConvertError.Create('Opening ballot is missing');
    CheckField(Ballot,'file_name',[jtString]);CheckField(Ballot,'positions',[jtArray]);
    Positions:=TJSONArray(Ballot.Find('positions'));
    if (Positions=nil) or (Positions.Count=0) then raise EConvertError.Create('Opening ballot has no positions');
    for I:=0 to Positions.Count-1 do
      if (Positions[I].JSONType<>jtString) or (Trim(Positions[I].AsString)='') then
        raise EConvertError.Create('Invalid opening ballot position');
    if Data.Get('pairing_type','')<>TournamentTypeDoubleRoundRobin then
      raise EConvertError.Create('Opening ballots require double round-robin');
  end else if Data.Get('storage_version',1)=3 then begin
    CheckField(Data,'game_variant',[jtString]);CheckField(Data,'notation_format',[jtString]);
    CheckField(Data,'force_ponder_off',[jtBoolean]);
    if (AFormat<>gffPgn) or (Data.Get('game_variant','')<>'chess') or
      (Data.Get('notation_format','')<>'pgn') or not Data.Get('force_ponder_off',False) then
      raise EConvertError.Create('Unsupported tournament variant, format or ponder policy');
  end else begin
    if AFormat<>gffPdn then raise EConvertError.Create('This is a draughts tournament; chess cannot load it');
    if (Data.Find('game_variant')<>nil) or (Data.Find('notation_format')<>nil) or
      (Data.Find('force_ponder_off')<>nil) then raise EConvertError.Create('Unexpected tournament format metadata');
  end;
  if (Data.Get('storage_version',1)<4) and (Data.Find('opening_ballot')<>nil) then
    raise EConvertError.Create('Opening ballots require tournament storage version 4');
  if (Data.Find('tournament_id') <> nil) and
    (Data.Find('tournament_id').JSONType = jtString) and
    (Trim(Data.Find('tournament_id').AsString) = '') then
    raise EConvertError.Create('Empty tournament identity');
  CheckField(Data, 'legacy_pdn_file_name', [jtString]);
  CheckField(Data, 'tournament_name', [jtString]);
  CheckField(Data, 'starting_fen', [jtString]);
  CheckField(Data, 'tournament_id', [jtString]);
  CheckField(Data, 'pdn_file_name', [jtString]);
  if (AFormat=gffPgn) and (Data.Get('pdn_file_name','')<>'') and
    not SameText(ExtractFileExt(Data.Get('pdn_file_name','')),'.pgn') then
    raise EConvertError.Create('Chess tournament companion must use .pgn');
  CheckField(Data, 'pdn_owned', [jtBoolean]);
  CheckField(Data, 'pdn_published_hash', [jtString]);
  CheckInteger(Data, 'moves_per_period', 0);
  CheckInteger(Data, 'concurrent_games', 1);
  CheckField(Data, 'minutes_per_period', [jtNumber]);
  CheckField(Data, 'increment_seconds', [jtNumber]);
  Value := Data.Find('minutes_per_period');
  if (Value <> nil) and (IsNan(Value.AsFloat) or IsInfinite(Value.AsFloat) or
    (Value.AsFloat<0) or ((AFormat=gffPgn) and (Value.AsFloat=0))) then
    raise EConvertError.Create('Invalid tournament time control');
  Value := Data.Find('increment_seconds');
  if (Value <> nil) and (IsNan(Value.AsFloat) or IsInfinite(Value.AsFloat) or (Value.AsFloat<0)) then
    raise EConvertError.Create('Invalid tournament increment');
  CheckField(Data, 'time_unit', [jtString]);
  PairingType:=Data.Get('time_unit','minutes');
  if (PairingType<>'minutes') and (PairingType<>'seconds') then
    raise EConvertError.Create('Invalid tournament time unit');
  CheckField(Data, 'increment_mode', [jtString]);
  PairingType := Data.Get('increment_mode', 'from-start');
  if (PairingType <> 'from-start') and (PairingType <> 'after-move-limit') then
    raise EConvertError.Create('Unknown tournament increment mode');
  CheckField(Data, 'pairing_type', [jtString]);
  PairingType := Data.Get('pairing_type', TournamentTypeSingleRoundRobin);
  if (PairingType <> TournamentTypeSingleRoundRobin) and
    (PairingType <> TournamentTypeDoubleRoundRobin) and
    (PairingType <> TournamentTypeSwiss) then
    raise EConvertError.Create('Unknown tournament pairing type');
  CheckField(Data, 'selected_engines', [jtArray]);
  Engines := TJSONArray(Data.Find('selected_engines'));
  if Engines <> nil then
    for I := 0 to Engines.Count - 1 do
      if Engines[I].JSONType <> jtString then
        raise EConvertError.Create('Invalid selected tournament engine');
  CheckField(Data, 'selected_engine_keys', [jtArray]);
  Engines := TJSONArray(Data.Find('selected_engine_keys'));
  if Engines <> nil then
    for I := 0 to Engines.Count - 1 do
      if Engines[I].JSONType <> jtString then
        raise EConvertError.Create('Invalid selected tournament engine identity');
  CheckField(Data, 'games', [jtArray]);
  Games := TJSONArray(Data.Find('games'));
  if Games = nil then
    Exit;
  for I := 0 to Games.Count - 1 do
  begin
    if Games[I].JSONType <> jtObject then
      raise EConvertError.Create('Invalid tournament game');
    Game := TJSONObject(Games[I]);
    CheckField(Game, 'white_engine_key', [jtString]);
    CheckField(Game, 'black_engine_key', [jtString]);
    CheckField(Game, 'record', [jtObject]);
    if Game.Find('record') <> nil then
      ValidateRecord(TJSONObject(Game.Find('record')), True,AFormat)
    else if Data.Get('storage_version', 1) >= 2 then
      raise EConvertError.Create('Tournament game record is missing');
    if Data.Get('storage_version',1)=4 then begin
      RecordData:=TJSONObject(Game.Find('record'));
      if Trim(RecordData.Get('starting_fen',''))='' then
        raise EConvertError.Create('Opening ballot game position is missing');
    end;
    CheckInteger(Game, 'game', 1);
    CheckInteger(Game, 'round', 1);
    if Data.Get('storage_version',1)=4 then begin
      if Game.Get('round',1)>Positions.Count then
        raise EConvertError.Create('Opening ballot game index is out of range');
      if RecordData.Get('starting_fen','')<>Positions.Strings[Game.Get('round',1)-1] then
        raise EConvertError.Create('Opening ballot game position does not match its entry');
    end;
    CheckField(Game, 'white', [jtString]);
    CheckField(Game, 'black', [jtString]);
    CheckField(Game, 'result', [jtString]);
    CheckField(Game, 'reason', [jtString]);
    ResultText := Game.Get('result', '*');
    if (ResultText <> '') and (ResultText <> '*') and
      not TournamentResultIsKnown(ParseTournamentResult(ResultText,AFormat)) then
      raise EConvertError.Create('Invalid tournament game result');
  end;
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    for I := 0 to Games.Count - 1 do
    begin
      Game := TJSONObject(Games[I]);
      PairingKey := IntToStr(Game.Get('round', 1)) + ':' +
        IntToStr(Game.Get('game', I + 1));
      if Seen.IndexOf(PairingKey) >= 0 then
        raise EConvertError.Create('Duplicate tournament pairing identity');
      Seen.Add(PairingKey);
    end;
  finally
    Seen.Free;
  end;
end;

function ReadTournamentDocument(const AFileName: string; AFormat:TGameFileFormat): TJSONObject;
var
  Lines: TStringList;
  Data: TJSONData;
begin
  Result := nil;
  Data := nil;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(AFileName);
    Data := GetJSON(Lines.Text);
    if (Data = nil) or (Data.JSONType <> jtObject) then
      raise EConvertError.Create('Tournament document must be a JSON object');
    ValidateDocument(TJSONObject(Data),AFormat);
    Result := TJSONObject(Data);
    Data := nil;
  finally
    Data.Free;
    Lines.Free;
  end;
end;
end.
