program engine_end_reason_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,SyncObjs,
 Grids,uEngineBase,uEngineRegistry,uGameRunnerThread,uGameSetupTypes,uGameOrchestrator,
 uGamePosition,uDraughtsPosition,uChessPosition,uGameGuiProfile,uRunningGame,
 uGameTreeActor,uGameTreeBuilder,uTournamentDialog,uTournamentGridModel;
type
 TEndingEngine=class(TGameEngine)
 public EndingReason,EndingResult:string;
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
var Checks:Integer;Errors:TErrors;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
function TEndingEngine.DoStartThinking:string;
begin SetGameResult(EndingResult,EndingReason);Result:='';end;
function Factory(D:TExternalEngineDefinition):TGameEngine;
var E:TEndingEngine;
begin
 E:=TEndingEngine.Create('termination fixture');E.EndingReason:=D.Arguments;
 E.EndingResult:=D.HubId;Result:=E;
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
 const Reason,ResultText,ExpectedRowReason,FileName:string;ErrorOverride:Boolean=False);
var D:TExternalEngineDefinition;Setup:TGameSetup;O:TObserver;R:TGameRunnerThread;
 S:TGameRunnerSnapshot;G:TRunningGame;T,Reloaded:TTournamentDialog;Grid:TStringGrid;
 C:TGameTreeCommand;State:TGameOrchestratorState;Status:string;
begin
 D:=TExternalEngineDefinition.Create;O:=TObserver.Create;R:=nil;G:=nil;T:=nil;Reloaded:=nil;
 S:=TGameRunnerSnapshot.Create;
 try
  D.Kind:=Kind;D.ExePath:=ExpandFileName(ParamStr(0));D.Arguments:=Reason;D.HubId:=ResultText;
  Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.StartingFEN:=V.DefaultStartingFEN;
  Setup.WhitePlayer:=pkRegistered;Setup.BlackPlayer:=pkHuman;Setup.WhiteEngine:=D;
  Setup.TimeControl:=DefaultTimeControl;Setup.TimeControl.MinutesPerPeriod:=5;
  R:=TGameRunnerThread.Create(Setup,1,@O.Snapshot,@O.Finished,V);R.Start;
  if O.Done.WaitFor(5000)<>wrSignaled then begin R.PostStop;raise Exception.Create('runner completion timeout');end;
  R.WaitFor;
  Check((O.Last.State=gosGameOver) and (O.Last.LastError=''),'termination is not an error');
  Check((O.Last.GameResult=ResultText) and (O.Last.EngineEndReason=Reason),'runner publishes separate result/reason');
  Check((O.Last.PlyCount=0) and (O.Last.MovesPlayedText=''),'termination creates no move');
  S.AssignFrom(O.Last);S.MarkStopped('late shutdown');
  Check((S.State=gosGameOver) and (S.EngineEndReason=Reason),'copy and late Stop preserve terminal reason');
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
  Check(Grid.Cells[TournamentColReason,1]='Manual result','manual override retains reason precedence');
  T.GameStopped(G);
  Check(Grid.Cells[TournamentColReason,1]='Manual result','late completion preserves manual override');
 finally Reloaded.Free;T.Free;G.Free;if R<>nil then begin R.PostStop;R.WaitFor;R.Free;end;
  S.Free;O.Free;D.Free;end;
end;
procedure CheckReset(V:TGameVariant);
var E:TEndingEngine;G:TGameOrchestrator;
begin
 E:=TEndingEngine.Create;G:=TGameOrchestrator.Create(V);
 try
  E.EndingReason:='Draw claimed';E.EndingResult:='*';G.Engine[gsWhite]:=E;G.NewGame(V.DefaultStartingFEN);
  G.PlayNextMove;Check(G.EngineEndReason='Draw claimed','orchestrator captured reason');
  G.NewGame(V.DefaultStartingFEN);
  Check((G.EngineEndReason='') and (E.GameEndReason=''),'new game resets both reasons');
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
  RunCase(V,eekDxp,'Draw claimed','*','Draw claimed',FileName);
  RunCase(V,eekDxp,'Win claimed','*','Win claimed',FileName);
  RunCase(V,eekDxp,'Engine ended game','*','Engine ended game',FileName);
  RunCase(V,eekDxp,'Resigned','0-2','Resigned',FileName);
  RunCase(V,eekDxp,'Draw claimed','*','actual engine error',FileName,True);
  RunCase(V,eekHub,'','*','Unknown result',FileName);
  V:=RegisteredGame(1);CheckReset(V);
  RunCase(V,eekUci,'','*','Unknown result',FileName);
  RunCase(V,eekUci,'','1-0','Game finished',FileName);
  RunCase(V,eekUci,'','1/2-1/2','Draw',FileName);
 finally
  if FindFirst(Directory+'/*',faAnyFile,Search)=0 then begin
   repeat if (Search.Name<>'.') and (Search.Name<>'..') then DeleteFile(Directory+'/'+Search.Name);until FindNext(Search)<>0;
   FindClose(Search);end;RemoveDir(Directory);
  RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;
 end;
 WriteLn('Engine termination reason GUI checks passed (',Checks,' checks)');
end.
