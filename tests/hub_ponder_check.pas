program hub_ponder_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,SyncObjs,uGamePosition,uDraughtsPosition,
  uEngineBase,uEngineRegistry,uEngineParamsJson,uDraughtsHubEngine,uGameOrchestrator;
type TProbe=class
  Lock:TCriticalSection;
  Prediction:string;
  Started,Hits,Early:Integer;
  constructor Create;
  destructor Destroy;override;
  procedure Log(Sender:TObject;const Text:string);
end;
constructor TProbe.Create;
begin inherited Create;Lock:=TCriticalSection.Create;end;
destructor TProbe.Destroy;
begin Lock.Free;inherited Destroy;end;
procedure TProbe.Log(Sender:TObject;const Text:string);
var Lines:TStringList;I,Start:Integer;
begin
  Lock.Enter;
  try
    if Pos('ponder started',Text)>0 then Inc(Started);
    if Pos('ponder hit',Text)>0 then Inc(Hits);
    if Pos('ponder early result reused',Text)>0 then Inc(Early);
    Start:=Pos('stdout; text=',Text);if Start>0 then begin
      Lines:=TStringList.Create;
      try
        Lines.Text:=StringReplace(Copy(Text,Start+13,MaxInt),'\n',LineEnding,[rfReplaceAll]);
        for I:=0 to Lines.Count-1 do if Pos('done ',Lines[I])=1 then Prediction:=ExtractHubArgument(Lines[I],'ponder');
      finally Lines.Free;end;
    end;
  finally Lock.Leave;end;
end;
var Checks:Integer=0;Trace:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
function Wire:string;
var L:TStringList;
begin L:=TStringList.Create;try L.LoadFromFile(Trace);Result:=L.Text;finally L.Free;end;end;
procedure Peer;
var L,Raw,Fen,W,B,Move,Prediction,Mode:string;P,Q:TGamePosition;Moves:TStringList;I:Integer;
    F:TextFile;Active:Boolean;
  procedure Answer;
  begin
    WriteLn('info depth=8 score=0.3 time=0.01 pv="'+Move+'"');
    WriteLn('done move='+Move+' ponder='+Prediction);Active:=False;
  end;
begin
  Mode:=ParamStr(2);AssignFile(F,ParamStr(3));Rewrite(F);P:=TDraughtsPosition.Create;Moves:=TStringList.Create;Active:=False;
  try
    while not EOF(Input) do begin
      ReadLn(L);WriteLn(F,L);Flush(F);
      if L='hub' then begin
        WriteLn('id name=PonderPeer');if Mode<>'nooption' then WriteLn('param name=ponder type=bool value=false');WriteLn('wait');
      end else if L='init' then WriteLn('ready')
      else if Copy(L,1,4)='pos ' then begin
        Raw:=ExtractHubArgument(L,'pos');W:='';B:='';
        for I:=2 to Length(Raw) do begin
          if Raw[I] in ['w','W'] then begin if W<>'' then W+=',';if Raw[I]='W' then W+='K';W+=IntToStr(I-1);end;
          if Raw[I] in ['b','B'] then begin if B<>'' then B+=',';if Raw[I]='B' then B+='K';B+=IntToStr(I-1);end;
        end;
        Fen:=Raw[1]+':W'+W+':B'+B;P.LoadFromFEN(Fen);Moves.Clear;Raw:=ExtractHubArgument(L,'moves');
        ExtractStrings([' '],[],PChar(Raw),Moves);for I:=0 to Moves.Count-1 do P.PlayMoveText(Moves[I]);
      end else if Copy(L,1,3)='go ' then begin
        Move:=P.LegalMove(0);Prediction:='';Q:=P.Clone;
        try Q.PlayMove(Move);if Q.LegalMoveCount>0 then Prediction:=Q.LegalMove(0);finally Q.Free;end;
        if Mode='badreply' then Prediction:='99-99';
        Active:=True;
        if L='go ponder' then begin
          for I:=1 to 2500 do WriteLn('info depth=99 score=999 pv="'+Move+'"');Flush(Output);
          WriteLn(F,'# drained');Flush(F);
          if Mode='early' then Answer;
        end else Answer;
      end else if L='ponder-hit' then Answer
      else if (L='stop') and Active then Answer
      else if L='quit' then Break;
      Flush(Output);
    end;
  finally Moves.Free;P.Free;CloseFile(F);end;
end;
procedure Scenario(const Mode:string;Hit,Enabled,ForceOff:Boolean);
var Def:TExternalEngineDefinition;E:THubEngine;G:TGameOrchestrator;TC:TTimeControl;
    Params:TEngineParamArray;Move,Pv,Score,Depth,TimeText:string;Tick:QWord;
begin
  Def:=TExternalEngineDefinition.Create;G:=TGameOrchestrator.Create(DraughtsVariant);
  try
    Def.Kind:=eekHub;Def.HubId:='Ponder peer';Def.ExePath:=ExpandFileName(ParamStr(0));
    Def.Arguments:='--peer '+Mode+' "'+Trace+'"';Def.InitText:='init';Params:=nil;
    AddOrUpdateParam(Params,'ponder','bool',BoolToStr(Enabled,True),False);
    if (Mode='no-pondering') or (Mode='no-ponder-hit') then AddOrUpdateParam(Params,'gui-feature-flags','string','["'+Mode+'"]',False);
    if Mode='both-flags' then AddOrUpdateParam(Params,'gui-feature-flags','string','["no-pondering","no-ponder-hit"]',False);
    SaveEngineParamsToJson(EngineParamsFileName(Def.ExePath),'hub',Params);
    E:=THubEngine.Create(Def);G.Engine[gsWhite]:=E;E.SetGamePonderAllowed(not ForceOff);
    Check(E.LaunchAndInit,'Hub ready');TC:=DefaultTimeControl;TC.MinutesPerPeriod:=0.1;
    TC.MovesPerPeriod:=0;TC.IncrementSeconds:=0.2;G.TimeControl:=TC;G.NewGame(DraughtsVariant.DefaultStartingFEN);
    Move:=G.PlayNextMove;Check((Move<>'') and (G.MoveHistory.Count=1),'First clocked Hub move recorded');
    Tick:=GetTickCount64;
    if Enabled and not ForceOff and (Mode<>'nooption') and (Mode<>'badreply') and (Mode<>'no-pondering') and (Mode<>'both-flags') then begin
      repeat Sleep(10);until (Pos('# drained',Wire)>0) or (GetTickCount64-Tick>4000);
      Check(Pos('# drained',Wire)>0,'Idle worker drains ponder output without runner polling');Sleep(80);
      E.ReadSearchInfo(Pv,Score,Depth,TimeText);Check((Score='') and (Depth=''),'Speculative scores remain hidden');
      Check(G.MoveHistory.Count=1,'Pondering does not add predicted moves');
    end;
    Move:=G.Position.LegalMove(0);if not Hit then Move:=G.Position.LegalMove(1);
    G.PlayMove(Move,G.CurrentSide,0.1,'human');
    if Mode='changed-clock' then begin TC.IncrementSeconds:=0.3;G.TimeControl:=TC;end;
    Move:=G.PlayNextMove;
    Check((Move<>'') and (G.MoveHistory.Count=3),'Actual next move accepted legally');
    Check(G.MoveHistory[2].PvScore='0.3','Accepted result retains its own score, including early ponder completion');
    E.Stop; // Joins the worker before inspecting its wire trace.
    if not Enabled or ForceOff or (Mode='nooption') or (Mode='badreply') or (Mode='no-pondering') or (Mode='both-flags') then Check(Pos('go ponder',Wire)=0,'Ponder requires option, opt-in and game permission')
    else if not Hit or (Mode='changed-clock') or (Mode='no-ponder-hit') then Check((Pos('stop',Wire)>0) and (Pos('ponder-hit',Wire)=0),'Miss stops/drains and starts a fresh search')
    else if Mode='early' then Check(Pos('ponder-hit',Wire)=0,'Early Hub completion reused without sending ponder-hit')
    else Check(Pos('ponder-hit',Wire)>0,'Hit reuses live search through Hub ponder-hit');
    Check(Pos(' inc=0.200',Wire)>0,'Hub clock carries the pre-move increment');
  finally G.Free;Def.Free;DeleteFile(EngineParamsFileName(ExpandFileName(ParamStr(0))));end;
end;
procedure RealScenario(const Executable:string);
var Def:TExternalEngineDefinition;E:THubEngine;G:TGameOrchestrator;Params:TEngineParamArray;
    TC:TTimeControl;Probe:TProbe;Original:TMemoryStream;HadFile:Boolean;Path,Pred,Move:string;
begin
  Path:=EngineParamsFileName(Executable);Original:=TMemoryStream.Create;HadFile:=FileExists(Path);
  Def:=TExternalEngineDefinition.Create;G:=TGameOrchestrator.Create(DraughtsVariant);Probe:=TProbe.Create;
  try
    if HadFile then Original.LoadFromFile(Path);
    LoadEngineParamsFromJson(Path,'hub',Params);AddOrUpdateParam(Params,'ponder','bool','true',False);
    SaveEngineParamsToJson(Path,'hub',Params);
    Def.Kind:=eekHub;Def.ExePath:=Executable;Def.Arguments:='hub';Def.InitText:='init';Def.HubId:='Scan reference';
    E:=THubEngine.Create(Def);G.Engine[gsWhite]:=E;E.OnLog:=@Probe.Log;
    Check(E.LaunchAndInit,'Real Scan handshake');TC:=DefaultTimeControl;TC.MovesPerPeriod:=0;
    TC.MinutesPerPeriod:=0.03;TC.IncrementSeconds:=0.1;G.TimeControl:=TC;G.NewGame(DraughtsVariant.DefaultStartingFEN);
    Move:=G.PlayNextMove;Probe.Lock.Enter;try Pred:=Probe.Prediction;finally Probe.Lock.Leave;end;
    Check((Move<>'') and (Pred<>'') and G.Position.IsLegal(Pred),'Scan supplies a legal ponder prediction: move='+Move+'; prediction='+Pred);
    Sleep(200);G.PlayMove(Pred,G.CurrentSide,0.2,'human');Move:=G.PlayNextMove;
    Check((Move<>'') and (G.MoveHistory.Count=3),'Real Scan hit produces a legal actual move');
    E.Stop;Check((Probe.Started>0) and (Probe.Hits+Probe.Early>0),'Real Scan reuses live or early ponder result');
  finally
    G.Free;Probe.Free;Def.Free;
    if HadFile then Original.SaveToFile(Path) else DeleteFile(Path);Original.Free;
  end;
end;

begin
  if ParamStr(1)='--peer' then begin Peer;Halt;end;
  Trace:=GetTempFileName(GetTempDir,'hpc');
  try
    if ParamCount>0 then begin RealScenario(ExpandFileName(ParamStr(1)));WriteLn('Real Scan ponder checks passed (',Checks,' checks)');end
    else begin
    Scenario('normal',True,True,False);Scenario('normal',False,True,False);
    Scenario('early',True,True,False);Scenario('early',False,True,False);
    Scenario('normal',True,False,False);Scenario('normal',True,True,True);
    Scenario('nooption',True,True,False);Scenario('badreply',True,True,False);
    Scenario('changed-clock',True,True,False);Scenario('both-flags',True,True,False);Scenario('no-pondering',True,True,False);Scenario('no-ponder-hit',True,True,False);
    WriteLn('Hub ponder contract checks passed (',Checks,' checks)');end;
  finally DeleteFile(Trace);end;
end.
