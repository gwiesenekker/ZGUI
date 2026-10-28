program hub_worker_trace_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, uDraughtsHubEngine,
  uDraughtsPosition, uGamePosition, uDraughtsBoard, uEngineRegistry, uEngineBase;
procedure Fake;
var Line: string; Stream: TFileStream; Active: Boolean;
begin
  Stream:=TFileStream.Create(ParamStr(2),fmCreate); Active:=False;
  try
    while not EOF(Input) do begin
      ReadLn(Line); Line+=LineEnding;
      Stream.WriteBuffer(Line[1],Length(Line));
      Line:=Trim(Line);
      if Line='hub' then WriteLn('wait') else if Line='init' then WriteLn('ready')
      else if Line='go think' then WriteLn('done move=32-28')
      else if Pos('go ',Line)=1 then Active:=True
      else if (Line='stop') and Active then begin WriteLn('done'); Active:=False; end
      else if Line='quit' then Break;
      Flush(Output);
    end;
  finally Stream.Free; end;
end;
function Bytes(const Name: string): string;
var F: TFileStream;
begin F:=TFileStream.Create(Name,fmOpenRead); try SetLength(Result,F.Size); if Result<>'' then F.ReadBuffer(Result[1],Length(Result)); finally F.Free; end; end;
function ClockWire(const Name: string; Legacy: Boolean): string;
var D: TExternalEngineDefinition; E: THubEngine;
  {$IFNDEF GWDGUI_LEGACY_CLOCK} C: TEngineGameClockState; {$ENDIF}
begin
  D:=TExternalEngineDefinition.Create; E:=nil;
  try
    D.ExePath:=ExpandFileName(ParamStr(0)); D.Arguments:='--fake-trace "'+Name+'"';
    E:=THubEngine.Create(D); if not E.LaunchAndInit then raise Exception.Create('Clock handshake');
    E.BeginGame(DraughtsVariant.DefaultStartingFEN,gsWhite,5,40,2);
    E.SetGamePosition(DraughtsVariant.DefaultStartingFEN,nil);
    {$IFNDEF GWDGUI_LEGACY_CLOCK}
    if not Legacy then begin
      C:=Default(TEngineGameClockState); C.SideToMove:=gsWhite; C.MovesRemaining:=39;
      C.Remaining[gsWhite]:=298.5; C.Used[gsWhite]:=1.5; C.Increment[gsWhite]:=2;
      C.Remaining[gsBlack]:=299.25; C.Increment[gsBlack]:=3;
      E.SetGameClockState(C);
    end else
    {$ENDIF}
      E.SetClockInfoWithIncrement(39,298.5,1.5,2);
    if E.StartThinking<>'32-28' then raise Exception.Create('Clock think');
    FreeAndNil(E); Result:=Bytes(Name);
  finally E.Free; D.Free; end;
end;
var Def: TExternalEngineDefinition; Engine: THubEngine; Moves: TStringList;
  Trace,Expected,Root,ClockBefore,ClockAfter: string;
begin
  if ParamStr(1)='--fake-trace' then begin Fake; Halt; end;
  Root:=GetEnvironmentVariable('GWDGUI_ROOT'); if Root='' then Root:=GetCurrentDir;
  Trace:=GetTempFileName(GetTempDir,'hub'); Def:=TExternalEngineDefinition.Create; Moves:=TStringList.Create;
  Engine:=nil;
  try
    Def.ExePath:=ExpandFileName(ParamStr(0)); Def.Arguments:='--fake-trace "'+Trace+'"';
    Engine:=THubEngine.Create(Def); if not Engine.LaunchAndInit then raise Exception.Create('Handshake');
    Engine.SetGamePosition(DefaultGameVariant.DefaultStartingFEN,Moves);
    Engine.SetClockInfo(1,2,0); Engine.StartAnalyzing; Engine.StopSearch;
    Moves.Add('32-28'); Engine.SetGamePosition(DefaultGameVariant.DefaultStartingFEN,Moves);
    Engine.StartAnalyzing; Engine.StopSearch;
    Engine.StartMcts; Engine.StopSearch; FreeAndNil(Engine);
    if ParamStr(1)='--record' then begin
      with TFileStream.Create(ParamStr(2),fmCreate) do try
        Expected:=Bytes(Trace); if Expected<>'' then WriteBuffer(Expected[1],Length(Expected));
      finally Free; end;
    end else begin
      Expected:=Bytes(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/hub-worker.trace');
      {$IFDEF MSWINDOWS}Expected:=StringReplace(Expected,#10,LineEnding,[rfReplaceAll]);{$ENDIF}
      if Bytes(Trace)<>Expected then raise Exception.Create('Hub wire stream differs from pre-extraction baseline');
    end;
    ClockBefore:=ClockWire(Trace,True);
    if ParamStr(1)='--record-clock' then begin
      with TFileStream.Create(ParamStr(2),fmCreate) do try
        if ClockBefore<>'' then WriteBuffer(ClockBefore[1],Length(ClockBefore));
      finally Free; end;
    end else begin
      ClockAfter:=ClockWire(Trace,False);
      Expected:=Bytes(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/hub-clocked.trace');
      {$IFDEF MSWINDOWS}Expected:=StringReplace(Expected,#10,LineEnding,[rfReplaceAll]);{$ENDIF}
      if (ClockBefore<>Expected) or (ClockAfter<>Expected) then raise Exception.Create('Clocked Hub wire differs from pre-clock-contract baseline');
    end;
    WriteLn('Hub clocked go think matches baseline');
    WriteLn('Hub wire trace matches pre-extraction launch/analysis/navigation/MCTS/quit');
  finally Engine.Free; Moves.Free; Def.Free; DeleteFile(Trace); end;
end.
