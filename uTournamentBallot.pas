unit uTournamentBallot;
{$mode objfpc}{$H+}
interface
uses Classes,uGamePosition;
function NormalizeBallotFEN(Variant:TGameVariant;const Text:string;RequirePlayable:Boolean=True):string;
procedure ShuffleOpeningPairs(Positions:TStrings);
procedure LoadOpeningBallot(const FileName:string;Variant:TGameVariant;Positions:TStrings);
implementation
uses SysUtils;
function NormalizeBallotFEN(Variant:TGameVariant;const Text:string;RequirePlayable:Boolean):string;
var P:TGamePosition;Rules:TGameRules;Reason:string;
begin
  if Trim(Text)='' then raise EConvertError.Create('Empty opening position');
  P:=Variant.CreatePosition;
  try
    if RequirePlayable then P.LoadOpeningPosition(Trim(Text))
    else P.LoadFromFEN(Trim(Text)); // Archived starting fields stay strict FEN.
    if RequirePlayable then begin
      Rules:=Variant.CreateRules;
      try
        Rules.Reset(P);
        if Rules.Outcome(P,Reason)<>goOngoing then
          raise EConvertError.Create('Opening position is already over: '+Reason);
      finally Rules.Free;end;
    end;
    Result:=P.ToFEN;
  finally P.Free;end;
end;
procedure ShuffleOpeningPairs(Positions:TStrings);
var I,J:Integer;
begin
  // Shuffle entries, never the individual colour-reversed game rows.
  for I:=Positions.Count-1 downto 1 do begin
    J:=Random(I+1);Positions.Exchange(I,J);
  end;
end;
procedure LoadOpeningBallot(const FileName:string;Variant:TGameVariant;Positions:TStrings);
var Lines,Validated:TStringList;I:Integer;Line:string;
begin
  Lines:=TStringList.Create;Validated:=TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for I:=0 to Lines.Count-1 do begin
      Line:=Lines[I];
      if (I=0) and (Copy(Line,1,3)=#$EF#$BB#$BF) then Delete(Line,1,3);
      Line:=Trim(Line);
      if (Line='') or (Copy(Line,1,1)='#') or (Copy(Line,1,1)=';') or
        (Copy(Line,1,2)='//') then Continue;
      try Validated.Add(NormalizeBallotFEN(Variant,Line));
      except on E:Exception do raise EConvertError.CreateFmt('%s, line %d: %s',[FileName,I+1,E.Message]);end;
    end;
    if Validated.Count=0 then raise EConvertError.Create('Opening ballot contains no positions');
    Positions.Assign(Validated);
  finally Validated.Free;Lines.Free;end;
end;
end.
