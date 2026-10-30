program uci_game_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, SyncObjs, Math,
  uEngineBase, uEngineRegistry, uChessUciEngine, uChessPosition, uGamePosition,
  uGameOrchestrator, uGameSetupTypes, uGameRunnerThread, uCancellationToken,
  uDraughtsHubEngine, uDraughtsPosition, uEngineParamsJson;
type
  TCancel=class(TThread)
    Token: TCancellationToken;
    procedure Execute; override;
  end;
  TObserver=class
    Lock: TCriticalSection;
    Data: TGameRunnerSnapshot;
    procedure Snapshot(Sender: TObject; S: TGameRunnerSnapshot);
  end;
var Checks: Integer=0; V: TChessVariant; Trace: string;
procedure Check(Value: Boolean; const Text: string);
begin Inc(Checks); if not Value then raise Exception.Create(Text); end;
procedure TCancel.Execute;
begin Sleep(100); Token.Cancel; end;
procedure TObserver.Snapshot(Sender: TObject; S: TGameRunnerSnapshot);
begin Lock.Acquire; try Data.AssignFrom(S); finally Lock.Release; S.Free; end; end;
procedure Peer;
var L,Mode,Fen,Move: string; P: TChessPosition; A: TStringList; I,N: Integer; F: TextFile;
begin
  Mode:=ParamStr(2); AssignFile(F,ParamStr(3)); Rewrite(F); P:=TChessPosition.Create; A:=TStringList.Create;
  try
    while not EOF(Input) do begin
      ReadLn(L); WriteLn(F,L); Flush(F);
      if L='uci' then begin
        WriteLn('id name Clock Peer'); WriteLn('option name UCI_AnalyseMode type check default true');
        WriteLn('option name Ponder type check default true'); WriteLn('uciok');
      end else if L='isready' then WriteLn('readyok')
      else if L='hub' then WriteLn('wait') else if L='init' then WriteLn('ready')
      else if Copy(L,1,9)='position ' then begin
        A.Clear; ExtractStrings([' '],[],PChar(L),A); N:=A.IndexOf('moves');
        if A[1]='startpos' then P.LoadFromFEN(ChessStartingFEN) else begin
          Fen:=''; for I:=2 to 7 do begin if I>2 then Fen+=' '; Fen+=A[I]; end; P.LoadFromFEN(Fen);
        end;
        if N>=0 then for I:=N+1 to A.Count-1 do P.PlayMove(A[I]);
      end else if Copy(L,1,3)='go ' then begin
        if Mode='crash' then Break;
        if (Mode='silent') or (Mode='cancel') or (Mode='hub') then Continue;
        if Mode='slow' then Sleep(350);
        Move:=P.LegalMove(0); if (Mode='promotion') and P.IsLegal('a7a8q') then Move:='a7a8q';
        WriteLn('info depth 8 score cp 25 pv '+Move); WriteLn('bestmove '+Move+' ponder e7e5');
      end else if L='stop' then begin if Mode='hub' then WriteLn('done') else WriteLn('bestmove 0000'); end
      else if L='quit' then Break;
      Flush(Output);
    end;
  finally CloseFile(F); A.Free; P.Free; end;
end;
function Definition(const Mode: string; Kind: TExternalEngineKind=eekUci): TExternalEngineDefinition;
begin
  Result:=TExternalEngineDefinition.Create; Result.Kind:=Kind;
  Result.ExePath:=ExpandFileName(ParamStr(0)); Result.Arguments:='--peer '+Mode+' "'+Trace+'"';
end;
function Wire: string;
var L: TStringList;
begin L:=TStringList.Create; try L.LoadFromFile(Trace); Result:=L.Text; finally L.Free; end; end;
function Count(const S,Sub: string): Integer;
var I: Integer;
begin Result:=0; for I:=1 to Length(S)-Length(Sub)+1 do if Copy(S,I,Length(Sub))=Sub then Inc(Result); end;
procedure Orchestrated(const Mode,Fen: string; Expected: TGameOrchestratorState);
var G: TGameOrchestrator; E: TUciEngine; D: TExternalEngineDefinition; C: TTimeControl;
  Params: TEngineParamArray; Token: TCancellationToken; Stopper: TCancel; Reply: string; Tick: QWord; Raised: Boolean;
begin
  G:=TGameOrchestrator.Create(V); D:=Definition(Mode); E:=TUciEngine.Create(D); Token:=TCancellationToken.Create; Stopper:=nil;
  try
    E.StopToken:=Token;
    Params:=nil; AddOrUpdateParam(Params,'gui-stop-timeout-ms','string','100',False); E.ConfigureOptions(Params);
    Check(E.LaunchAndInit,'Game peer handshake');
    E.SetClockInfo(1,0.01,0);
    C:=DefaultTimeControl; C.MovesPerPeriod:=0; C.MinutesPerPeriod:=0.02; C.IncrementSeconds:=0;
    if Mode='silent' then C.MinutesPerPeriod:=0.001;
    G.TimeControl:=C;
    if Pos(' b ',Fen)>0 then G.Engine[gsBlack]:=E else G.Engine[gsWhite]:=E;
    G.NewGame(Fen);
    if Mode='cancel' then begin Stopper:=TCancel.Create(True); Stopper.Token:=Token; Stopper.Start; end;
    Raised:=False; Tick:=GetTickCount64;
    try Reply:=G.PlayNextMove; except on X:Exception do begin Raised:=True; Check(Pos('process exited',X.Message)>0,'Crash reason is explicit'); end; end;
    Check(G.State=Expected,'Game state for '+Mode+': '+OrchestratorStateToString(G.State));
    if Mode='cancel' then Check((G.GameResult='*') and not E.MoveTimedOut and (G.UsedSeconds[gsWhite]>0) and (G.MoveHistory.Count=0),'Stop accounts elapsed time without a move or timeout/result');
    if Mode='crash' then Check(Raised and (G.GameResult='*') and not E.MoveTimedOut,'Crash policy is error with unfinished result');
    if Mode='silent' then Check(E.MoveTimedOut and (G.GameResult='0-1') and (G.MoveHistory.Count=0),'Silent engine flags without playing');
    if Expected=gosRunning then begin
      Check((G.MoveHistory.Count=1) and (Reply<>''),'Move uses existing history');
      Check(G.MoveHistory.ExportData[0].HasClockInfo,'Completed move retains clocks');
      if Mode='slow' then Check(GetTickCount64-Tick>=300,'Game wait exceeds old short analysis budget');
      if Mode='promotion' then Check(Reply='a7a8q','Promotion preserved');
    end;
    G.StopEngines;
    if Expected=gosRunning then begin
      Check(Pos('go wtime ',Wire)>0,'Both-clock game go');
      Check(Pos('movetime',Wire)=0,'Game go has no movetime');
      Check(Pos('setoption name UCI_AnalyseMode value false',Wire)>0,'Game mode disables analysis option');
      Check(Count(Wire,'ucinewgame')=1,'Exactly one new-game boundary');
    end;
  finally if Stopper<>nil then begin Stopper.WaitFor; Stopper.Free; end; if (G.Engine[gsWhite]<>E) and (G.Engine[gsBlack]<>E) then E.Free; G.Free; D.Free; Token.Free; end;
end;
procedure ClockWire;
var D: TExternalEngineDefinition; E: TUciEngine; C: TEngineGameClockState; Raised: Boolean;
begin
  D:=Definition('normal'); E:=TUciEngine.Create(D);
  try
    Check(E.LaunchAndInit,'Clock wire handshake'); E.BeginGame(ChessStartingFEN,gsWhite,5,40,2);
    E.SetGamePosition(ChessStartingFEN,nil); C:=Default(TEngineGameClockState);
    C.SideToMove:=gsWhite; C.Remaining[gsWhite]:=298.5; C.Remaining[gsBlack]:=299.25;
    C.Increment[gsWhite]:=2; C.Increment[gsBlack]:=3; C.MovesRemaining:=39;
    E.SetGameClockState(C); Check(E.StartThinking<>'','Two-sided clock search');
    E.SetGamePosition('4k3/8/8/8/8/8/8/R3K3 b - - 0 37',nil);
    C.SideToMove:=gsBlack; C.MovesRemaining:=0; E.SetGameClockState(C); Check(E.StartThinking<>'','Black root clock search');
    E.SetGamePosition(ChessStartingFEN,nil); Raised:=False;
    try E.StartThinking; except on X:EInvalidOperation do Raised:=True; end;
    Check(Raised,'A new game position cannot reuse stale clocks');
    E.SetClockInfo(1,0.01,0); Check(E.StartThinking<>'','Analysis after game context'); E.Stop;
    Check(Pos('go wtime 298500 btime 299250 winc 2000 binc 3000 movestogo 39',Wire)>0,'Exact asymmetric game clocks');
    Check(Pos('go wtime 298500 btime 299250 winc 2000 binc 3000'+LineEnding,Wire)>0,'Sudden death omits moves-to-go');
    Check(Pos('go movetime 10',Wire)>0,'One-shot analysis still finite');
    Check(Pos('setoption name UCI_AnalyseMode value true',Wire)>0,'Analysis option restored');
  finally E.Free; D.Free; end;
end;
procedure IdleAndRules;
var G: TGameOrchestrator; C: TTimeControl; Move: string;
begin
  G:=TGameOrchestrator.Create(V);
  try
    C:=DefaultTimeControl; C.MovesPerPeriod:=0; C.MinutesPerPeriod:=0.001; C.IncrementSeconds:=0.1; G.TimeControl:=C;
    G.NewGame(ChessStartingFEN); G.CheckCurrentTurnTimeout(0.159); Check(G.State=gosRunning,'Idle check grants same increment as a move');
    Move:=G.Position.LegalMove(0); G.PlayMove(Move,gsWhite,0.159,'human'); Check(G.MoveHistory.Count=1,'Move just inside deadline accepted');
    G.NewGame(ChessStartingFEN); G.CheckCurrentTurnTimeout(0.161);
    Check((G.State=gosGameOver) and (G.GameResult='0-1') and (G.MoveHistory.Count=0),'Idle expiry has no phantom move');
    G.NewGame('7k/5Q2/6K1/8/8/8/8/8 b - - 0 37'); Check((G.State=gosGameOver) and (G.GameResult='1/2-1/2'),'Initial stalemate adjudicated');
    G.NewGame('7k/8/8/8/8/8/8/K7 w - - 0 1'); Check(G.State=gosGameOver,'Initial dead-material root adjudicated');
    G.NewGame('7k/8/8/8/8/8/8/KR6 w - - 0 1'); G.PlayMove(G.Position.LegalMove(0),gsWhite,1,'human');
    Check(G.GameResult='1/2-1/2','Timeout draw uses existing material rule');
  finally G.Free; end;
end;
procedure Periods;
var G: TGameOrchestrator; D: TExternalEngineDefinition; E: TUciEngine; C: TTimeControl;
begin
  G:=TGameOrchestrator.Create(V); D:=Definition('normal'); E:=TUciEngine.Create(D);
  try
    Check(E.LaunchAndInit,'Period handshake'); G.Engine[gsWhite]:=E;
    C:=DefaultTimeControl; C.MovesPerPeriod:=2; C.MinutesPerPeriod:=0.02;
    C.IncrementSeconds:=0.5; C.IncrementMode:=cimAfterMoveLimit; G.TimeControl:=C; G.NewGame(ChessStartingFEN);
    G.PlayNextMove; G.PlayMove(G.Position.LegalMove(0),gsBlack,0,'human'); G.PlayNextMove; G.StopEngines;
    Check(Pos('winc 0 binc 0 movestogo 2',Wire)>0,'Delayed increment absent before threshold');
    Check(Pos('winc 500 binc 500 movestogo 1',Wire)>0,'Both next-move increments become active at boundary');
    Check((G.RemainingSeconds[gsWhite]>2.4) and (G.RemainingSeconds[gsWhite]<2.9),'Increment and new period credited exactly once');
    Check(G.MoveHistory.Count=3,'Period transition preserves history');
  finally if G.Engine[gsWhite]<>E then E.Free; G.Free; D.Free; end;
end;
procedure RealGames(const Path: string);
var G: TGameOrchestrator; D: TExternalEngineDefinition; E: TUciEngine; Side: TGameSide;
  C: TTimeControl; I: Integer;
begin
  G:=TGameOrchestrator.Create(V); D:=TExternalEngineDefinition.Create;
  try
    D.Kind:=eekUci; D.ExePath:=ExpandFileName(Path);
    for Side:=Low(TGameSide) to High(TGameSide) do begin
      E:=TUciEngine.Create(D); if not E.LaunchAndInit then begin E.Free; raise Exception.Create('Stockfish launch'); end;
      G.Engine[Side]:=E;
    end;
    C:=DefaultTimeControl; C.MovesPerPeriod:=2; C.MinutesPerPeriod:=0.02; C.IncrementSeconds:=0.05;
    G.TimeControl:=C; G.NewGame(ChessStartingFEN);
    for I:=1 to 6 do if G.State=gosRunning then G.PlayNextMove;
    Check((G.MoveHistory.Count=6) and (G.State=gosRunning),'Real Stockfish clocked game crosses period boundary');
    Check((G.UsedSeconds[gsWhite]>0) and (G.UsedSeconds[gsBlack]>0),'Both real engine clocks charged');
    G.NewGame('4k3/8/8/8/8/8/8/R3K3 b - - 0 37'); G.PlayNextMove;
    Check(G.MoveHistory.Count=1,'Real Stockfish Black custom root');
    G.NewGame('7k/P7/8/8/8/8/8/7K w - - 0 1'); G.PlayNextMove;
    Check(G.MoveHistory.Count=1,'Real Stockfish promotion root');
    G.StopEngines;
  finally G.Free; D.Free; end;
end;
procedure RunnerIdle;
var O: TObserver; R: TGameRunnerThread; Setup: TGameSetup; Tick: QWord; Done: Boolean;
  WR,BR,WU,BU: Double;
begin
  O:=TObserver.Create; O.Lock:=TCriticalSection.Create; O.Data:=TGameRunnerSnapshot.Create;
  Setup:=Default(TGameSetup); Setup.Variant:=DefaultGameVariant; Setup.StartingFEN:=ChessStartingFEN; Setup.TimeControl:=DefaultTimeControl;
  Setup.TimeControl.MovesPerPeriod:=0; Setup.TimeControl.MinutesPerPeriod:=0.002; Setup.TimeControl.IncrementSeconds:=0.1;
  R:=TGameRunnerThread.Create(Setup,900,@O.Snapshot,nil);
  try
    R.Start; Tick:=GetTickCount64;
    repeat
      Sleep(10); O.Lock.Acquire;
      try O.Data.ProjectClocks(GetTickCount64+50,WR,BR,WU,BU);
        Done:=(O.Data.State=gosRunning) and (WR<O.Data.WhiteRemainingSeconds);
      finally O.Lock.Release; end;
    until Done or (GetTickCount64-Tick>3000);
    Check(Done,'Existing runner publishes a projected human turn');
    repeat Sleep(10); O.Lock.Acquire; try Done:=O.Data.State=gosGameOver; finally O.Lock.Release; end; until Done or (GetTickCount64-Tick>3000);
    Check(Done,'Existing idle loop adjudicates silent human');
    R.WaitFor; Check(O.Data.PlyCount=0,'Runner timeout keeps topology empty');
  finally R.PostStop; R.WaitFor; R.Free; O.Data.Free; O.Lock.Free; O.Free; end;
end;
procedure HubStop;
var DV: TDraughtsVariant; G: TGameOrchestrator; E: THubEngine; D: TExternalEngineDefinition; Token: TCancellationToken; S: TCancel;
begin
  DV:=TDraughtsVariant.Create; G:=TGameOrchestrator.Create(DV); D:=Definition('hub',eekHub); E:=THubEngine.Create(D); Token:=TCancellationToken.Create; S:=TCancel.Create(True);
  try
    E.StopToken:=Token; Check(E.LaunchAndInit,'Hub stop handshake'); G.Engine[gsWhite]:=E; G.NewGame(DV.DefaultStartingFEN);
    S.Token:=Token; S.Start; G.PlayNextMove;
    Check((G.State=gosStopped) and (G.GameResult='*'),'Hub Stop guard preserves unfinished result');
  finally S.WaitFor; S.Free; G.StopEngines; if (G.Engine[gsWhite]<>E) and (G.Engine[gsBlack]<>E) then E.Free; G.Free; D.Free; Token.Free; DV.Free; end;
end;
begin
  if ParamStr(1)='--peer' then begin Peer; Halt; end;
  Trace:=GetTempFileName(GetTempDir,'zuci'); V:=TChessVariant.Create; RegisterDefaultGameVariant(V);
  try
    ClockWire; IdleAndRules; Periods; RunnerIdle; HubStop;
    Orchestrated('normal',ChessStartingFEN,gosRunning);
    Orchestrated('slow',ChessStartingFEN,gosRunning);
    Orchestrated('normal','4k3/8/8/8/8/8/8/R3K3 b - - 0 37',gosRunning);
    Orchestrated('promotion','7k/P7/8/8/8/8/8/7K w - - 0 1',gosRunning);
    Orchestrated('cancel',ChessStartingFEN,gosStopped);
    Orchestrated('silent',ChessStartingFEN,gosGameOver);
    Orchestrated('crash',ChessStartingFEN,gosError);
    if ParamStr(1)<>'' then RealGames(ParamStr(1));
    WriteLn('UCI game checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(DraughtsVariant); V.Free; DeleteFile(Trace); end;
end.
