program engine_end_reason_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,SyncObjs,
 Grids,uEngineBase,uEngineRegistry,uGameRunnerThread,uGameSetupTypes,uGameOrchestrator,
 uGamePosition,uDraughtsPosition,uChessPosition,uGameGuiProfile,uRunningGame,
 uGameTreeActor,uGameTreeBuilder,uTournamentDialog,uTournamentGridModel;
type
 TEndingEngine=class(TGameEngine)
 public EndingReason,EndingResult,EndingCode:string;
 protected function DoStartThinking:string;override;
 end;
 TObserver=class
 public Last:TGameRunnerSnapshot;Done:TSimpleEvent;
  constructor Create;
  destructor Destroy;override;
  procedure Snapshot(Sender:TObject;S:TGameRunnerSnapshot);
  procedure Finished(Sender:TObject);
 end;
 TErrors=class
  procedure Report(Sender:TObject;E:Exception);
 end;
var Checks:Integer;Errors:TErrors;FixtureResult,FixtureCode:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
function TEndingEngine.DoStartThinking:string;
begin SetGameResult(EndingResult,EndingReason,EndingCode);Result:='';end;
function Factory(D:TExternalEngineDefinition):TGameEngine;
var E:TEndingEngine;
begin
 E:=TEndingEngine.Create('termination fixture');E.EndingReason:=D.Arguments;
 E.EndingResult:=FixtureResult;E.EndingCode:=FixtureCode;Result:=E;
end;
constructor TObserver.Create;
begin inherited Create;Last:=TGameRunnerSnapshot.Create;Done:=TSimpleEvent.Create;end;
destructor TObserver.Destroy;
begin Last.Free;Done.Free;inherited Destroy;end;
procedure TObserver.Snapshot(Sender:TObject;S:TGameRunnerSnapshot);
begin try Last.AssignFrom(S);finally S.Free;end;end;
procedure TObserver.Finished(Sender:TObject);
begin Done.SetEvent;end;
procedure WriteFixture(const FileName:string;V:TGameVariant);
var L:TStringList;Metadata:string;
begin
 Metadata:='';if GameVariantId(V)='chess' then
  Metadata:='"storage_version":3,"game_variant":"chess","notation_format":"pgn","force_ponder_off":true,';
 L:=TStringList.Create;
 try L.Text:='{'+Metadata+'"tournament_name":"Termination test","games":['+
  '{"game":1,"round":1,"white":"White","black":"Black","result":"*","reason":"","record":{}}]}';
  L.SaveToFile(FileName);
 finally L.Free;end;
end;
procedure RunCase(V:TGameVariant;Kind:TExternalEngineKind;
 const Reason,ResultText,ExpectedRowReason,FileName:string;ErrorOverride:Boolean=False;Side:TGameSide=gsWhite;const Code:string='';const RegisteredName:string='Claim fixture');
var D:TExternalEngineDefinition;Setup:TGameSetup;O:TObserver;R:TGameRunnerThread;
 S:TGameRunnerSnapshot;G:TRunningGame;T,Reloaded:TTournamentDialog;Grid:TStringGrid;
 C:TGameTreeCommand;State:TGameOrchestratorState;Status,ManualReason:string;
begin
 D:=TExternalEngineDefinition.Create;O:=TObserver.Create;R:=nil;G:=nil;T:=nil;Reloaded:=nil;
 S:=TGameRunnerSnapshot.Create;
 try
  D.Kind:=Kind;D.ExePath:=ExpandFileName(ParamStr(0));D.Arguments:=Reason;D.HubId:=RegisteredName;D.DxpId:=RegisteredName;D.UciId:=RegisteredName;
  FixtureResult:=ResultText;FixtureCode:=Code;
  Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.StartingFEN:=V.DefaultStartingFEN;
  Setup.WhitePlayer:=pkRegistered;Setup.BlackPlayer:=pkHuman;Setup.WhiteEngine:=D;
  if Side=gsBlack then begin
   Setup.WhitePlayer:=pkHuman;Setup.WhiteEngine:=nil;Setup.BlackPlayer:=pkRegistered;Setup.BlackEngine:=D;
   if GameVariantId(V)='chess' then Setup.StartingFEN:=StringReplace(Setup.StartingFEN,' w ',' b ',[])
   else Setup.StartingFEN[1]:='B';
  end;
  Setup.TimeControl:=DefaultTimeControl;Setup.TimeControl.MinutesPerPeriod:=5;
  R:=TGameRunnerThread.Create(Setup,1,@O.Snapshot,@O.Finished,V);R.Start;
  if O.Done.WaitFor(5000)<>wrSignaled then begin R.PostStop;raise Exception.Create('runner completion timeout');end;
  R.WaitFor;
  Check((O.Last.State=gosGameOver) and (O.Last.LastError=''),'termination is not an error');
  Check((O.Last.GameResult=ResultText) and (O.Last.EngineEndReason=Reason),'runner publishes separate result/reason');
  Check(O.Last.EngineEndCode=Code,'runner preserves raw reason code');
  if RegisteredName<>'' then
   Check(Pos(RegisteredName+' (',O.Last.EngineEndActor)=1,'runner identifies the configured source engine')
  else Check(Pos(ChangeFileExt(ExtractFileName(ParamStr(0)),'')+' (',O.Last.EngineEndActor)=1,
   'empty registered name falls back to executable');
  Check((O.Last.PlyCount=0) and (O.Last.MovesPlayedText=''),'termination creates no move');
  S.AssignFrom(O.Last);S.MarkStopped('late shutdown');
  Check((S.State=gosGameOver) and (S.EngineEndReason=Reason) and
   (S.EngineEndCode=Code) and (S.EngineEndActor=O.Last.EngineEndActor) and
   (S.GameEndReason=O.Last.GameEndReason),'copy and late Stop preserve all termination metadata');
  G:=TRunningGame.Create(1,'Termination test',nil,pkRegistered,pkHuman,'','','White','Black',nil,Setup);
  G.AssignRunnerSnapshot(S);
  Check(G.EngineEndReasonText=Reason,'running game exposes owned snapshot reason');
  State:=S.State;Status:='';if ErrorOverride then begin State:=gosError;Status:='actual engine error';end;
  C:=G.GameTreeActor.CreateSetHeaderCommand(GameTreeHeaderInput('terminal','Termination test',
    'White','Black',ResultText,Setup.StartingFEN,False,Setup.TimeControl,State,Status));
  try G.GameTreeActor.ExecuteCommand(C);Check(C.Accepted,'fixture terminal header accepted');finally C.Free;end;
  G.MarkFinished;
  Check(G.MainlineCount=0,'no game-tree moves introduced');
  T:=TTournamentDialog.Create(nil,V);WriteFixture(FileName,V);T.LoadTournamentFromFile(FileName);
  T.RegisterRunningGame(1,G);T.GameStopped(G);Grid:=TStringGrid(T.FindComponent('TournamentPairings'));
  Check(Grid.Cells[TournamentColResult,1]=ResultText,'tournament preserves official result');
  Check(Grid.Cells[TournamentColReason,1]=ExpectedRowReason,'tournament displays termination reason or error');
  T.SaveTournamentToFile(FileName);Reloaded:=TTournamentDialog.Create(nil,V);Reloaded.LoadTournamentFromFile(FileName);
  Check(TStringGrid(Reloaded.FindComponent('TournamentPairings')).Cells[TournamentColReason,1]=ExpectedRowReason,
    'termination reason survives tournament save/reload');
  Grid.Row:=1;T.SetSelectedResult(V.ResultText(goDraw));
  ManualReason:=ExpectedRowReason+'. Referee declared draw';
  Check(Grid.Cells[TournamentColReason,1]=ManualReason,'referee result retains original reason');
  T.GameStopped(G);
  Check(Grid.Cells[TournamentColReason,1]=ManualReason,'late completion preserves referee result and original reason');
  T.SetSelectedResult(V.ResultText(goWhiteWins));
  Check(Grid.Cells[TournamentColReason,1]=ExpectedRowReason+'. Referee declared win for White',
   'white referee declaration uses the same wording for both games');
  T.SetSelectedResult(V.ResultText(goBlackWins));
  ManualReason:=ExpectedRowReason+'. Referee declared win for Black';
  Check(Grid.Cells[TournamentColReason,1]=ManualReason,'repeated referee edit replaces previous suffix');
  Reloaded.Free;Reloaded:=nil;T.SaveTournamentToFile(FileName);
  Reloaded:=TTournamentDialog.Create(nil,V);Reloaded.LoadTournamentFromFile(FileName);
  Check(TStringGrid(Reloaded.FindComponent('TournamentPairings')).Cells[TournamentColReason,1]=ManualReason,
   'referee provenance survives save/reload');
  Reloaded.Free;Reloaded:=nil;
  with TStringList.Create do try
   LoadFromFile(FileName);Text:=StringReplace(Text,'Referee declared win for Black',
    'Operator set result to '+V.ResultText(goBlackWins),[rfReplaceAll]);SaveToFile(FileName);
  finally Free;end;
  Reloaded:=TTournamentDialog.Create(nil,V);Reloaded.LoadTournamentFromFile(FileName);
  Check(TStringGrid(Reloaded.FindComponent('TournamentPairings')).Cells[TournamentColReason,1]=ManualReason,
   'legacy operator suffix loads as a referee declaration without losing the cause');
  T.SetSelectedResult('*');
  Check(Grid.Cells[TournamentColReason,1]=ExpectedRowReason,'clearing override restores original cause');
 finally Reloaded.Free;T.Free;G.Free;if R<>nil then begin R.PostStop;R.WaitFor;R.Free;end;
  S.Free;O.Free;D.Free;end;
end;
procedure RunRulesCase(V:TGameVariant;const FEN,ResultText,Reason,FileName:string;Timeout:Boolean=False);
var Setup:TGameSetup;O:TObserver;R:TGameRunnerThread;G:TRunningGame;
 T,Reloaded:TTournamentDialog;Grid:TStringGrid;C:TGameTreeCommand;Expected:string;
begin
 O:=TObserver.Create;R:=nil;G:=nil;T:=nil;Reloaded:=nil;
 try
  Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.StartingFEN:=FEN;
  Setup.WhitePlayer:=pkHuman;Setup.BlackPlayer:=pkHuman;Setup.TimeControl:=DefaultTimeControl;
  if Timeout then begin Setup.TimeControl.MinutesPerPeriod:=0.0001;Setup.TimeControl.IncrementSeconds:=0;end;
  R:=TGameRunnerThread.Create(Setup,1,@O.Snapshot,@O.Finished,V);R.Start;
  if O.Done.WaitFor(5000)<>wrSignaled then begin R.PostStop;raise Exception.Create('rules runner timeout');end;
  R.WaitFor;
  Check((O.Last.State=gosGameOver) and (O.Last.GameResult=ResultText),'rules runner result');
  Check(O.Last.GameEndReason=Reason,'rules runner cause: '+O.Last.GameEndReason);
  Check((O.Last.EngineEndActor='') and (O.Last.EngineEndCode=''),'rules finish has no engine source/code');
  O.Last.MarkStopped('late shutdown');Check(O.Last.GameEndReason=Reason,'late stop preserves rule cause');
  G:=TRunningGame.Create(1,'Termination test',nil,pkHuman,pkHuman,'','','White','Black',nil,Setup);
  G.AssignRunnerSnapshot(O.Last);
  C:=G.GameTreeActor.CreateSetHeaderCommand(GameTreeHeaderInput('terminal','Termination test',
   'White','Black',ResultText,FEN,False,Setup.TimeControl,gosGameOver,''));
  try G.GameTreeActor.ExecuteCommand(C);Check(C.Accepted,'rules header accepted');finally C.Free;end;
  G.MarkFinished;
  T:=TTournamentDialog.Create(nil,V);WriteFixture(FileName,V);T.LoadTournamentFromFile(FileName);
  T.RegisterRunningGame(1,G);T.GameStopped(G);Grid:=TStringGrid(T.FindComponent('TournamentPairings'));
  if Pos('draw by ',Reason)=1 then Expected:='Orchestrator declared '+Reason
  else if Reason='stalemate' then Expected:='Orchestrator declared draw by stalemate'
  else if Reason='checkmate' then Expected:='Orchestrator declared checkmate'
  else Expected:='Orchestrator: '+UpperCase(Copy(Reason,1,1))+Copy(Reason,2,MaxInt);
  Check(Grid.Cells[TournamentColResult,1]=ResultText,'rules row result unchanged');
  Check(Grid.Cells[TournamentColReason,1]=Expected,'rules row specific cause');
  T.SaveTournamentToFile(FileName);Reloaded:=TTournamentDialog.Create(nil,V);Reloaded.LoadTournamentFromFile(FileName);
  Check(TStringGrid(Reloaded.FindComponent('TournamentPairings')).Cells[TournamentColReason,1]=Expected,
   'rules cause survives save/reload');
 finally Reloaded.Free;T.Free;G.Free;if R<>nil then begin R.PostStop;R.WaitFor;R.Free;end;O.Free;end;
end;
procedure CheckReset(V:TGameVariant);
var E:TEndingEngine;G:TGameOrchestrator;
begin
 E:=TEndingEngine.Create;G:=TGameOrchestrator.Create(V);
 try
  E.EndingReason:='Draw claimed';E.EndingResult:='*';E.EndingCode:='DXP reason 2';G.Engine[gsWhite]:=E;G.NewGame(V.DefaultStartingFEN);
  G.PlayNextMove;Check(G.EngineEndReason='Draw claimed','orchestrator captured reason');
  G.NewGame(V.DefaultStartingFEN);
  Check((G.EngineEndReason='') and (G.GameEndReason='') and not G.EngineEndHasSide and
   (G.EngineEndCode='') and (E.GameEndReason='') and (E.GameEndCode=''),'new game resets reason, source and code');
  E.EndingReason:='';G.PlayNextMove;
  Check((G.EngineEndReason='') and (G.GameResult='*'),'ordinary empty move has no stale reason');
 finally G.Free;end;
end;
var V:TGameVariant;Directory,FileName:string;Id:TGUID;Search:TSearchRec;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);RegisterGame(TChessVariant.Create,ChessGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));
 RegisterGameEngineFactory(eekDxp,@Factory);RegisterGameEngineFactory(eekHub,@Factory);RegisterGameEngineFactory(eekUci,@Factory);
 CreateGUID(Id);Directory:=GetTempDir+'end-reason-'+GUIDToString(Id);ForceDirectories(Directory);FileName:=Directory+'/tournament.json';
 try
  V:=RegisteredGame(0);CheckReset(V);
  RunCase(V,eekDxp,'Draw claimed','*','Claim fixture (White) claimed draw (DXP reason 2)',FileName,False,gsWhite,'DXP reason 2');
  RunCase(V,eekDxp,'Draw claimed','*','Claim fixture (Black) claimed draw (DXP reason 2)',FileName,False,gsBlack,'DXP reason 2');
  RunCase(V,eekDxp,'Win claimed','*','Claim fixture (White) claimed win (DXP reason 3)',FileName,False,gsWhite,'DXP reason 3');
  RunCase(V,eekDxp,'Engine ended game','*','Claim fixture (Black) ended game (DXP reason 0)',FileName,False,gsBlack,'DXP reason 0');
  RunCase(V,eekDxp,'Resigned','0-2','Claim fixture (White) resigned (DXP reason 1)',FileName,False,gsWhite,'DXP reason 1');
  RunCase(V,eekDxp,'Engine ended game (DXP reason 9)','*','Claim fixture (White) ended game (DXP reason 9)',FileName,False,gsWhite,'DXP reason 9');
  RunCase(V,eekDxp,'Draw claimed','*','actual engine error',FileName,True,gsWhite,'DXP reason 2');
  RunCase(V,eekHub,'','*','Claim fixture (White): Engine returned no move; side=white',FileName);
  RunCase(V,eekHub,'','*',ChangeFileExt(ExtractFileName(ParamStr(0)),'')+
   ' (White): Engine returned no move; side=white',FileName,False,gsWhite,'','');
  RunRulesCase(V,V.DefaultStartingFEN,'0-2','flag fell for white; idle move deadline expired',FileName,True);
  RunRulesCase(V,'B:WK32:B','2-0','Black has no legal move',FileName);
  V:=RegisteredGame(1);CheckReset(V);
  RunRulesCase(V,V.DefaultStartingFEN,'0-1','flag fell for white; idle move deadline expired',FileName,True);
  RunRulesCase(V,'7k/8/8/8/8/8/8/KR6 w - - 0 1','1/2-1/2',
   'flag fell for white; idle move deadline expired; opponent has insufficient mating material',FileName,True);
  RunRulesCase(V,'7k/6Q1/6K1/8/8/8/8/8 b - - 0 1','1-0','checkmate',FileName);
  RunRulesCase(V,'7k/5Q2/6K1/8/8/8/8/8 b - - 0 1','1/2-1/2','stalemate',FileName);
  RunRulesCase(V,'7k/8/6K1/8/8/8/8/R7 w - - 150 1','1/2-1/2','draw by 75-move rule',FileName);
  RunCase(V,eekUci,'','*','Claim fixture (White): Engine returned no move; side=white',FileName);
  RunCase(V,eekUci,'','1-0','Claim fixture (White) ended game; side=white',FileName);
  RunCase(V,eekUci,'','1/2-1/2','Claim fixture (White) ended game; side=white',FileName);
 finally
  if FindFirst(Directory+'/*',faAnyFile,Search)=0 then begin
   repeat if (Search.Name<>'.') and (Search.Name<>'..') then DeleteFile(Directory+'/'+Search.Name);until FindNext(Search)<>0;
   FindClose(Search);end;RemoveDir(Directory);
  RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;
 end;
 WriteLn('Engine termination reason GUI checks passed (',Checks,' checks)');
end.
