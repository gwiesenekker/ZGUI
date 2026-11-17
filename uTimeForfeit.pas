unit uTimeForfeit;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,FPJSON,uGamePosition,uEngineBase,uEngineRegistry,uCancellationToken;
type
 TTimeForfeitSettings=record
  EngineKey,EngineName:string; // Empty key: the orchestrator's normal timeout rules.
  Seconds,ThresholdCp:Double;
 end;
function DefaultTimeForfeit:TTimeForfeitSettings;
procedure ValidateTimeForfeit(const S:TTimeForfeitSettings);
function TimeForfeitJson(const S:TTimeForfeitSettings):TJSONObject;
function ReadTimeForfeit(Data:TJSONData):TTimeForfeitSettings;
function TimeForfeitScore(const S:TTimeForfeitSettings;const Score:string;out Reason:string):TGameOutcome;
function AnalyzeTimeForfeit(const S:TTimeForfeitSettings;Definition:TExternalEngineDefinition;
 Position:TGamePosition;Token:TCancellationToken;OnLog:TEngineLogEvent;out Reason:string):TGameOutcome;
implementation
uses Math;
function DefaultTimeForfeit:TTimeForfeitSettings;
begin Result:=Default(TTimeForfeitSettings);Result.Seconds:=1;Result.ThresholdCp:=200;end;
procedure ValidateTimeForfeit(const S:TTimeForfeitSettings);
begin
 if IsNan(S.Seconds) or IsInfinite(S.Seconds) or (S.Seconds<=0) or (S.Seconds>3600) then
  raise EConvertError.Create('Time forfeit analysis requires 0 < seconds <= 3600');
 if IsNan(S.ThresholdCp) or IsInfinite(S.ThresholdCp) or (S.ThresholdCp<=0) or (S.ThresholdCp>1e9) then
  raise EConvertError.Create('Time forfeit requires a positive threshold at most 1000000000 cp');
end;
function TimeForfeitJson(const S:TTimeForfeitSettings):TJSONObject;
begin
 Result:=TJSONObject.Create;Result.Add('version',1);Result.Add('engine_key',S.EngineKey);Result.Add('engine_name',S.EngineName);
 Result.Add('seconds',S.Seconds);Result.Add('threshold_cp',S.ThresholdCp);
end;
function ReadTimeForfeit(Data:TJSONData):TTimeForfeitSettings;
var J:TJSONObject;V:TJSONData;I:Integer;
const Names:array[0..4] of string=('version','engine_key','engine_name','seconds','threshold_cp');
begin
 Result:=DefaultTimeForfeit;if Data=nil then Exit;
 if Data.JSONType<>jtObject then raise EConvertError.Create('Invalid time_forfeit settings');J:=TJSONObject(Data);
 for I:=0 to High(Names) do begin
  V:=J.Find(Names[I]);if V=nil then raise EConvertError.Create('Missing time_forfeit field '+Names[I]);
  if ((I in [1,2]) and (V.JSONType<>jtString)) or ((I in [0,3,4]) and (V.JSONType<>jtNumber)) then
    raise EConvertError.Create('Invalid time_forfeit field '+Names[I]);
 end;
 if J.Get('version',0.0)<>1 then raise EConvertError.Create('Unsupported time_forfeit version');
 Result.EngineKey:=J.Get('engine_key','');Result.EngineName:=J.Get('engine_name','');
 Result.Seconds:=J.Get('seconds',1.0);Result.ThresholdCp:=J.Get('threshold_cp',200.0);ValidateTimeForfeit(Result);
end;
function TimeForfeitScore(const S:TTimeForfeitSettings;const Score:string;out Reason:string):TGameOutcome;
var Value:Double;Mate:Int64;Text,Comparison:string;FS:TFormatSettings;
begin
 ValidateTimeForfeit(S);FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';Text:=Trim(Score);
 if (Text<>'') and (Text[1]='#') then begin
  if not TryStrToInt64(Copy(Text,2,MaxInt),Mate) or (Mate=0) then raise EConvertError.Create('Missing or ambiguous mate evaluation');
  if Mate>0 then Value:=1e12 else Value:=-1e12;
 end else begin
  if not TryStrToFloat(Text,Value,FS) or IsNan(Value) or IsInfinite(Value) then raise EConvertError.Create('No usable exact evaluation');
  Value:=Value*100;if IsInfinite(Value) then raise EConvertError.Create('Evaluation overflow');
  Text:=FormatFloat('0.###',Value,FS);
 end;
 if Value>=S.ThresholdCp then begin Result:=goWhiteWins;Comparison:=' >= '+FloatToStr(S.ThresholdCp,FS);end
 else if Value<=-S.ThresholdCp then begin Result:=goBlackWins;Comparison:=' <= -'+FloatToStr(S.ThresholdCp,FS);end
 else if Value<0 then begin Result:=goDraw;Comparison:=' > -'+FloatToStr(S.ThresholdCp,FS);end
 else begin Result:=goDraw;Comparison:=' < '+FloatToStr(S.ThresholdCp,FS);end;
 Reason:='Adjudicator '+S.EngineName+' evaluation '+Text+Comparison+' cp (White perspective)';
end;
function AnalyzeTimeForfeit(const S:TTimeForfeitSettings;Definition:TExternalEngineDefinition;
 Position:TGamePosition;Token:TCancellationToken;OnLog:TEngineLogEvent;out Reason:string):TGameOutcome;
var E:TGameEngine;Moves:TStringList;MoveText,Canonical,PV,Score,Depth,TimeText,Fen:string;
begin
 Result:=goOngoing;Reason:='Time forfeit adjudication failed';E:=nil;Moves:=TStringList.Create;
 try
  try
   ValidateTimeForfeit(S);
   if (Definition=nil) or (EngineIdentityKey(Definition)<>S.EngineKey) then raise EConvertError.Create('Missing adjudicator registration');
   if Token.IsCancelled then raise EAbort.Create('Cancelled');
   E:=CreateGameEngine(Definition);E.StopToken:=Token;E.OnLog:=OnLog;
   if not (ecAnalysis in E.Capabilities) then raise EConvertError.Create('Adjudicator does not support analysis');
   E.SetGamePonderAllowed(False);
   if not E.LaunchAndInit then raise EConvertError.Create('Adjudicator launch failed: '+E.LastError);
   Fen:=Position.ToFEN;E.NewGame(Fen);E.SetGamePosition(Fen,Moves);
   E.LastScore:='';E.SetClockInfo(1,S.Seconds,0);E.SetMoveTimeLimit(Round(S.Seconds*1000)+2000);
   MoveText:=E.StartThinking;E.ReadSearchInfo(PV,Score,Depth,TimeText);
   if Token.IsCancelled then raise EAbort.Create('Cancelled');
   if E.MoveTimedOut or (E.LastError<>'') or (Trim(MoveText)='') then raise EConvertError.Create('Adjudicator search failed: '+E.LastError);
   if not Position.TryParseMove(MoveText,Canonical) then raise EConvertError.Create('Adjudicator returned an illegal move');
   Result:=TimeForfeitScore(S,Score,Reason);
  except on Ex:Exception do begin
   Result:=goOngoing;Reason:='Time forfeit adjudication failed ('+S.EngineName+'): '+Ex.Message+'; referee attention required';
  end;end;
 finally
  if E<>nil then begin E.OnLog:=nil;E.Free;end;Moves.Free;
 end;
end;
end.
