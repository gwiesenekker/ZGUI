program uci_ponder_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uEngineBase,uEngineRegistry,
 uEngineParamsJson,uChessUciEngine,uChessPosition,uGamePosition,uGameOrchestrator,
 uCancellationToken;
type
 TAcceptedProbe=class(TGameEngine)
  Notifications:Integer;
  LastClock:TEngineGameClockState;
  AcceptedMoves:string;
  function DoStartThinking:string;override;
  procedure GameMoveAccepted(const RootFEN:string;ActualMoves:TStrings;
   const NextOwnClock:TEngineGameClockState);override;
 end;
 TWireObserver=class
  Hits,Misses:LongInt;
  procedure Observe(Sender:TObject;const Text:string);
 end;
 TCancelThread=class(TThread)
  Token:TCancellationToken;
  procedure Execute;override;
 end;
var Checks:Integer=0; V:TChessVariant; Trace:string;
procedure TCancelThread.Execute;
begin Sleep(100);Token.Cancel;end;
function TAcceptedProbe.DoStartThinking:string;
begin Result:='e2e4';end;
procedure TAcceptedProbe.GameMoveAccepted(const RootFEN:string;ActualMoves:TStrings;
 const NextOwnClock:TEngineGameClockState);
begin Inc(Notifications);LastClock:=NextOwnClock;AcceptedMoves:=ActualMoves.Text;end;
procedure TWireObserver.Observe(Sender:TObject;const Text:string);
begin
 if Pos('send; message=ponderhit',Text)>0 then InterlockedIncrement(Hits);
 if Pos('ponder miss;',Text)>0 then InterlockedIncrement(Misses);
end;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
function Preferred(P:TChessPosition):string;
const A:array[0..5]of string=('e2e4','e7e5','g1f3','b8c6','f1c4','g8f6');
var S:string;
begin for S in A do if P.IsLegal(S) then Exit(S);Result:=P.LegalMove(0);end;
procedure Peer;
var L,Mode,Fen,Best,Prediction:string; P,Q:TChessPosition; Words:TStringList;
 F:TextFile; I,N:Integer; Pondering:Boolean;
 procedure Answer;
 begin
  Best:=Preferred(P); Q:=TChessPosition(P.Clone);
  try Q.PlayMove(Best);Prediction:=Preferred(Q);finally Q.Free;end;
  if Mode='badreply' then Prediction:='a1a8';
  WriteLn('info depth 8 score cp 37 time 10 pv '+Best);
  WriteLn('bestmove '+Best+' ponder '+Prediction);Flush(Output);
 end;
begin
 Mode:=ParamStr(2);AssignFile(F,ParamStr(3));Rewrite(F);
 P:=TChessPosition.Create;Words:=TStringList.Create;Pondering:=False;
 try
  while not EOF(Input) do begin
   ReadLn(L);WriteLn(F,L);Flush(F);
   if L='uci' then begin
    WriteLn('id name Ponder Peer');
    if Mode<>'nooption' then WriteLn('option name Ponder type check default true');
    WriteLn('option name UCI_AnalyseMode type check default true');WriteLn('uciok');
   end else if L='isready' then WriteLn('readyok')
   else if Copy(L,1,9)='position ' then begin
    Words.Clear;ExtractStrings([' '],[],PChar(L),Words);N:=Words.IndexOf('moves');
    if Words[1]='startpos' then P.LoadFromFEN(ChessStartingFEN) else begin
     Fen:='';for I:=2 to 7 do begin if I>2 then Fen+=' ';Fen+=Words[I];end;P.LoadFromFEN(Fen);
    end;
    if N>=0 then for I:=N+1 to Words.Count-1 do P.PlayMove(Words[I]);
   end else if Copy(L,1,3)='go ' then begin
    Pondering:=Pos('go ponder ',L)=1;
    if not Pondering then Answer
    else begin
     if Mode='crash' then Break;
     for I:=1 to 4000 do WriteLn('info depth 99 score cp 999 time 999999 pv '+Preferred(P));
     Flush(Output);WriteLn(F,'# ponder output drained');Flush(F);
     if (Mode='early') or (Mode='duplicate') then begin
      Answer;
      if Mode='duplicate' then Answer;
     end else if Mode='illegal' then WriteLn('bestmove a1a8');
    end;
   end else if L='ponderhit' then begin
    if Mode<>'silent-hit' then Answer;Pondering:=False;
   end
   else if (L='stop') and Pondering then begin
    if Mode<>'noack' then begin
     if Mode='slowstop' then Sleep(300);
     Answer;Pondering:=False;
    end;
   end else if L='quit' then Break;
   Flush(Output);
  end;
 finally Words.Free;P.Free;CloseFile(F);end;
end;
function Wire:string;
var S:TStringList;
begin S:=TStringList.Create;try S.LoadFromFile(Trace);Result:=S.Text;finally S.Free;end;end;
function Count(const S,Sub:string):Integer;
var I:Integer;
begin Result:=0;for I:=1 to Length(S)-Length(Sub)+1 do if Copy(S,I,Length(Sub))=Sub then Inc(Result);end;
function Def(const Mode:string):TExternalEngineDefinition;
begin
 Result:=TExternalEngineDefinition.Create;Result.Kind:=eekUci;
 Result.ExePath:=ExpandFileName(ParamStr(0));Result.Arguments:='--peer '+Mode+' "'+Trace+'"';
end;
procedure WaitPonder;
var Start:QWord;
begin
 Start:=GetTickCount64;
 // Do not call PollOutput: the owner worker must drain >64 KiB autonomously.
 while (GetTickCount64-Start<2500) and (Pos('# ponder output drained',Wire)=0) do Sleep(10);
 Check(Pos('# ponder output drained',Wire)>0,'Idle worker drains ponder output without runner polling');
end;
procedure Scenario(const Mode:string;Hit,Enable:Boolean; Side:TGameSide=gsWhite;
 Period:Boolean=False);
var D:TExternalEngineDefinition;E:TUciEngine;G:TGameOrchestrator;TC:TTimeControl;
 Params:TEngineParamArray;Reply,Before,Root:string; T:QWord;Used:Double;Failed:Boolean;
begin
 D:=Def(Mode);E:=TUciEngine.Create(D);G:=TGameOrchestrator.Create(V);
 try
  G.Engine[Side]:=E;Params:=nil;
  if Enable then AddOrUpdateParam(Params,'pOnDeR','check','TrUe',False);
  AddOrUpdateParam(Params,'gui-stop-timeout-ms','string','150',False);E.ConfigureOptions(Params);
  if Mode='slowstop' then begin
   AddOrUpdateParam(Params,'gui-stop-timeout-ms','string','1000',False);E.ConfigureOptions(Params);
  end;
  Check(E.LaunchAndInit,'Peer ready');
  TC:=DefaultTimeControl;TC.MinutesPerPeriod:=0.1;TC.IncrementSeconds:=0.1;
  if Period then begin TC.MovesPerPeriod:=1;TC.IncrementMode:=cimAfterMoveLimit;end else TC.MovesPerPeriod:=0;
  G.TimeControl:=TC;Root:=ChessStartingFEN;
  if Side=gsBlack then Root:='rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
  G.NewGame(Root);T:=GetTickCount64;Reply:=G.PlayNextMove;
  Check(GetTickCount64-T<1500,'Acceptance notification does not wait for ponder result');
  Check(G.MoveHistory.Count=1,'Only accepted move in history');
  if not Enable or (Mode='badreply') or (Mode='nooption') then begin
   E.PollOutput;Check(Pos('go ponder ',Wire)=0,'No pondering without explicit opt-in/legal candidate');Exit;
  end;
  if Mode='crash' then Sleep(150) else WaitPonder;
  Sleep(60);E.ReadSearchInfo(Reply,Before,Root,Reply);
  Check((Before='') and (Root=''),'Speculative scores/depth stay hidden');
  Check((G.MoveHistory.Count=1) and (G.Position.SideToMove<>Side),'Prediction does not play a move');
  if Side=gsWhite then begin if Hit then Reply:='e7e5' else Reply:='c7c5';end
  else begin if Hit then Reply:='g1f3' else Reply:='d2d4';end;
  G.PlayMove(Reply,G.CurrentSide,0.2,'human');Before:=Wire;Used:=G.UsedSeconds[Side];T:=GetTickCount64;
  Failed:=False;
  try Reply:=G.PlayNextMove;except on X:Exception do begin
   Failed:=True;Check((Pos('ponder',LowerCase(X.Message))>0) or (Pos('bestmove',X.Message)>0) or
    (Pos('acknowledgement',X.Message)>0),'Explicit ponder failure reason: '+X.Message);
  end;end;
  if (Mode='illegal') or (Mode='duplicate') or (Mode='crash') or (Mode='noack') then begin
   Check(Failed and (G.State=gosError) and (G.GameResult='*') and not E.MoveTimedOut,'Background/stop failure uses M2 unfinished result');
   Check(G.MoveHistory.Count=2,'Fault never plays speculative result');Exit;
  end;
  Check(not Failed and (G.MoveHistory.Count=3) and (Reply<>''),'Real reply accepted exactly once');
  if Hit then begin
   if Mode='early' then Check(Count(Wire,'ponderhit')=0,'M4 early completed hit returns without ponderhit')
   else Check(Count(Wire,'ponderhit')=1,'Hit sends exactly one ponderhit');
   Check(Count(Wire,'go wtime ')=1,'Hit does not restart ordinary search');
   if Mode<>'early' then
    Check(Count(Copy(Wire,1,Pos('ponderhit',Wire)),'position ')=2,'Hit sends no replacement position');
  end else begin
   Check(Count(Wire,'ponderhit')=0,'Miss has no ponderhit');
   Check(Count(Wire,'go wtime ')=2,'Miss starts one actual search');
   if Mode='early' then Check(Count(Wire,'stop')=0,'M4 completed miss does not wait for stop')
   else Check(Count(Wire,'stop')=1,'Live miss fences old search');
   if Mode='slowstop' then Check((GetTickCount64-T>=300) and
    (G.UsedSeconds[Side]-Used>=0.3),'Miss fence time charged once to real turn');
  end;
 finally G.Free;D.Free;end;
end;
procedure NotificationBoundary;
var G:TGameOrchestrator;E:TAcceptedProbe;TC:TTimeControl;Token:TCancellationToken;Bad:Boolean;
begin
 G:=TGameOrchestrator.Create(V);E:=TAcceptedProbe.Create;Token:=TCancellationToken.Create;
 try
  G.Engine[gsWhite]:=E;E.StopToken:=Token;TC:=DefaultTimeControl;
  TC.MovesPerPeriod:=0;TC.MinutesPerPeriod:=1;TC.IncrementSeconds:=1;G.TimeControl:=TC;
  G.NewGame(ChessStartingFEN);Bad:=False;
  try G.PlayMove('e2e5',gsWhite,0,'test');except on X:Exception do Bad:=True;end;
  Check(Bad and (E.Notifications=0),'Illegal moves do not notify');
  G.PlayMove('e2e4',gsWhite,0.25,'test');
  Check((E.Notifications=1) and (E.AcceptedMoves='e2e4'+LineEnding),'Notification sees only accepted history');
  Check((E.LastClock.SideToMove=gsWhite) and (E.LastClock.Remaining[gsWhite]=60.75),'Notification has post-move own clock');
  G.NewGame(ChessStartingFEN);G.PlayMove('e2e4',gsWhite,62,'test');
  Check((G.State=gosGameOver) and (E.Notifications=1),'Flagged move does not notify');
  G.NewGame('7k/8/5KQ1/8/8/8/8/8 w - - 0 1');G.PlayMove('g6g7',gsWhite,0,'test');
  Check((G.State=gosGameOver) and (E.Notifications=1),'Terminal accepted move does not notify');
  G.NewGame(ChessStartingFEN);Token.Cancel;G.PlayMove('e2e4',gsWhite,0,'test');
  Check(E.Notifications=1,'Stop prevents optional background notification');
 finally G.Free;Token.Free;end;
end;
procedure DirectContext(ChangeOwn,ChangeHistory:Boolean;Expire:Boolean=False);
var D:TExternalEngineDefinition;E:TUciEngine;P:TEngineParamArray;M:TStringList;
 C:TEngineGameClockState;S:TGameSide;Reply:string;
begin
 if Expire then D:=Def('slowstop') else D:=Def('hold');
 E:=TUciEngine.Create(D);M:=TStringList.Create;
 try
  P:=nil;AddOrUpdateParam(P,'Ponder','check','true',False);
  AddOrUpdateParam(P,'gui-stop-timeout-ms','string','1000',False);E.ConfigureOptions(P);
  Check(E.LaunchAndInit,'Context peer ready');E.BeginGame(ChessStartingFEN,gsWhite,1,0);
  C.SideToMove:=gsWhite;C.MovesRemaining:=0;
  for S:=Low(TGameSide) to High(TGameSide) do begin C.Remaining[S]:=60;C.Used[S]:=0;C.Increment[S]:=0;end;
  E.SetGamePosition(ChessStartingFEN,M);E.SetGameClockState(C);E.SetMoveTimeLimit(2000);
  Reply:=E.StartThinking;M.Add(Reply);E.GameMoveAccepted(ChessStartingFEN,M,C);WaitPonder;
  E.SetMoveTimeLimit(50);Sleep(80);E.PollOutput;
  Check(not E.MoveTimedOut,'Pondering outlives the normal move watchdog');E.SetMoveTimeLimit(2000);
  if ChangeHistory then begin
   M.Clear;M.Add('g1f3');M.Add('g8f6');M.Add('f3g1');M.Add('f6g8');M.Add('e2e4');
  end;
  if Expire then M.Add('c7c5') else M.Add('e7e5');E.SetGamePosition(ChessStartingFEN,M);
  // M5: stale opponent clock and increment are deliberately irrelevant to a hit.
  C.Remaining[gsBlack]:=1;C.Increment[gsBlack]:=5;
  if ChangeOwn then C.Remaining[gsWhite]:=59;
  E.SetGameClockState(C);
  if Expire then begin
   E.SetMoveTimeLimit(100);
   try E.StartThinking;except on X:Exception do ;end;
   Check(E.MoveTimedOut,'Real deadline expiry during miss fence is a time loss');
   Check(Count(Wire,'go wtime ')=1,'Expired reconciliation cannot start another search');Exit;
  end;
  Reply:=E.StartThinking;
  Check(Reply<>'','Context reconciliation returns a move');
  if ChangeOwn or ChangeHistory then Check(Count(Wire,'ponderhit')=0,'Own budget/history mismatch restarts')
  else Check(Count(Wire,'ponderhit')=1,'M5 ignores changed opponent clock fields');
 finally E.Free;M.Free;D.Free;end;
end;
procedure RealGame(const Path:string);
var D:TExternalEngineDefinition;E:TUciEngine;G:TGameOrchestrator;TC:TTimeControl;
 P:TEngineParamArray;Side:TGameSide;N:Integer;Observer:TWireObserver;
begin
 G:=TGameOrchestrator.Create(V);D:=TExternalEngineDefinition.Create;Observer:=TWireObserver.Create;
 try
  D.Kind:=eekUci;D.ExePath:=ExpandFileName(Path);
  for Side:=Low(TGameSide) to High(TGameSide) do begin
   E:=TUciEngine.Create(D);G.Engine[Side]:=E;E.OnLog:=@Observer.Observe;P:=nil;
   AddOrUpdateParam(P,'Ponder','check','true',False);AddOrUpdateParam(P,'Threads','spin','1',False);
   AddOrUpdateParam(P,'Hash','spin','16',False);E.ConfigureOptions(P);
   Check(E.LaunchAndInit,'Real ponder engine initialized');
  end;
  TC:=DefaultTimeControl;TC.MinutesPerPeriod:=0.1;TC.MovesPerPeriod:=0;TC.IncrementSeconds:=0.05;
  G.TimeControl:=TC;G.NewGame(ChessStartingFEN);N:=0;
  while (G.State=gosRunning) and (N<180) do begin G.PlayNextMove;Inc(N);end;
  Check((G.State=gosRunning) or (G.State=gosGameOver),'Real ponder game has no protocol failure');
  Check(G.MoveHistory.Count>10,'Real engines play a sustained ponder game');
  Check(Observer.Hits>0,'Real engine actually reuses ponder searches');
  WriteLn('Real ponder game: ',D.ExecutableName,'; plies=',N,'; result=',G.GameResult,'; hits=',Observer.Hits,'; misses=',Observer.Misses);
 finally G.Free;D.Free;Observer.Free;end;
end;
procedure CancelRealTurn(Hit:Boolean);
var D:TExternalEngineDefinition;E:TUciEngine;G:TGameOrchestrator;Token:TCancellationToken;
 P:TEngineParamArray;TC:TTimeControl;Stopper:TCancelThread;T:QWord;Reply:string;
begin
 if Hit then D:=Def('silent-hit') else D:=Def('slowstop');
 E:=TUciEngine.Create(D);G:=TGameOrchestrator.Create(V);Token:=TCancellationToken.Create;Stopper:=nil;
 try
  G.Engine[gsWhite]:=E;E.StopToken:=Token;P:=nil;AddOrUpdateParam(P,'Ponder','check','true',False);E.ConfigureOptions(P);
  Check(E.LaunchAndInit,'Cancellation peer ready');TC:=DefaultTimeControl;TC.MinutesPerPeriod:=0.1;TC.MovesPerPeriod:=0;G.TimeControl:=TC;
  G.NewGame(ChessStartingFEN);G.PlayNextMove;WaitPonder;
  if Hit then Reply:='e7e5' else Reply:='c7c5';G.PlayMove(Reply,gsBlack,0.01,'human');
  Stopper:=TCancelThread.Create(True);Stopper.Token:=Token;Stopper.Start;T:=GetTickCount64;G.PlayNextMove;
  Check((G.State=gosStopped) and (G.GameResult='*') and not E.MoveTimedOut,'Stop wins over timeout/error during hit/miss');
  Check((G.MoveHistory.Count=2) and (G.UsedSeconds[gsWhite]>0.1),'Cancelled real turn charges time without a move');
  Check(GetTickCount64-T<2000,'Cancellation interrupts real-turn reconciliation/wait');
 finally if Stopper<>nil then begin Stopper.WaitFor;Stopper.Free;end;G.Free;D.Free;Token.Free;end;
end;
procedure CancellationAndAnalysis;
var D:TExternalEngineDefinition;E:TUciEngine;G:TGameOrchestrator;Token:TCancellationToken;
 P:TEngineParamArray;TC:TTimeControl;T:QWord;S:string;
begin
 D:=Def('hold');E:=TUciEngine.Create(D);G:=TGameOrchestrator.Create(V);Token:=TCancellationToken.Create;
 try
  G.Engine[gsWhite]:=E;E.StopToken:=Token;P:=nil;AddOrUpdateParam(P,'Ponder','check','true',False);E.ConfigureOptions(P);
  Check(E.LaunchAndInit,'Cancel peer ready');TC:=DefaultTimeControl;TC.MinutesPerPeriod:=0.1;TC.MovesPerPeriod:=0;G.TimeControl:=TC;
  G.NewGame(ChessStartingFEN);G.PlayNextMove;WaitPonder;
  // Analysis setup stages an actual position while pondering, then stops/fences.
  E.SetGamePosition(ChessStartingFEN,nil);E.SetClockInfo(1,0.01,0);E.SetMoveTimeLimit(1000);
  S:=E.StartThinking;Check(S='e2e4','Analysis restores requested actual root');
  Check(Pos('setoption name Ponder value false',Wire)>0,'Analysis forces effective Ponder false');
  G.NewGame(ChessStartingFEN);G.PlayNextMove;WaitPonder;
  Check(Count(Wire,'setoption name Ponder value true')=2,'Game restores saved opt-in after analysis');
  Token.Cancel;T:=GetTickCount64;E.Stop;Check(GetTickCount64-T<1500,'Idle worker shutdown remains prompt');
 finally G.Free;D.Free;Token.Free;end;
end;
begin
 if ParamStr(1)='--peer' then begin Peer;Halt;end;
 Trace:=GetTempFileName(GetTempDir(False),'zponder');V:=TChessVariant.Create;
 try
  Scenario('hold',True,True);Scenario('hold',True,True,gsBlack);
  Scenario('hold',True,True,gsWhite,True);Scenario('hold',False,True);
  Scenario('early',True,True);Scenario('early',False,True);
  Scenario('slowstop',False,True);Scenario('badreply',True,True);
  Scenario('nooption',True,True);Scenario('hold',True,False);Scenario('illegal',True,True);
  Scenario('duplicate',True,True);Scenario('crash',True,True);Scenario('noack',False,True);
  NotificationBoundary;
  DirectContext(False,False);DirectContext(True,False);DirectContext(False,True);DirectContext(False,False,True);
  CancelRealTurn(True);CancelRealTurn(False);
  CancellationAndAnalysis;
  if ParamStr(1)<>'' then RealGame(ParamStr(1));
  WriteLn('UCI ponder checks passed (',Checks,' checks)');
 finally V.Free;DeleteFile(Trace);end;
end.
