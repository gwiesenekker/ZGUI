program game_end_reason_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils,uGamePosition,uDraughtsPosition,
 uChessPosition,uGameOrchestrator,uEngineBase;
type TTimeoutEngine=class(TGameEngine)
 protected function DoStartThinking:string;override;
 end;
var Checks:Integer;
function TTimeoutEngine.DoStartThinking:string;
begin MarkMoveTimedOut;Result:='';end;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Root(V:TGameVariant;const FEN,ResultText,Reason:string);
var G:TGameOrchestrator;
begin
 G:=TGameOrchestrator.Create(V);
 try
  G.NewGame(FEN);
  Check((G.State=gosGameOver) and (G.GameResult=ResultText),'terminal root result');
  Check(G.GameEndReason=Reason,'terminal root cause: '+G.GameEndReason);
  G.NewGame(V.DefaultStartingFEN);
  Check(G.GameEndReason='','new game clears terminal cause');
 finally G.Free;end;
end;
procedure Clock(V:TGameVariant;Side:TGameSide;Charged:Boolean;const FEN:string='');
var G:TGameOrchestrator;TC:TTimeControl;Start,Reason,Expected:string;
begin
 G:=TGameOrchestrator.Create(V);
 try
  TC:=DefaultTimeControl;TC.MinutesPerPeriod:=1;TC.IncrementSeconds:=0;G.TimeControl:=TC;
  Start:=FEN;if Start='' then Start:=V.DefaultStartingFEN;
  if Side=gsBlack then
   if V is TChessVariant then Start:=StringReplace(Start,' w ',' b ',[])
   else Start[1]:='B';
  G.NewGame(Start);
  Reason:='flag fell for ';if Side=gsWhite then Reason+='white' else Reason+='black';
  if Charged then G.PlayMove(G.Position.LegalMove(0),Side,61,'fixture')
  else begin G.CheckCurrentTurnTimeout(61);Reason+='; idle move deadline expired';end;
  if FEN<>'' then begin Expected:=V.ResultText(goDraw);Reason+='; opponent has insufficient mating material';end
  else if Side=gsWhite then Expected:=V.ResultText(goBlackWins) else Expected:=V.ResultText(goWhiteWins);
  Check((G.State=gosGameOver) and (G.GameResult=Expected),'timeout keeps rules result');
  Check(G.GameEndReason=Reason,'timeout cause: '+G.GameEndReason);
  Check(G.MovesPlayed.Count=0,'expired move is not recorded');
 finally G.Free;end;
end;
procedure EngineDeadline(V:TGameVariant;Side:TGameSide);
var G:TGameOrchestrator;Start,Reason,Expected:string;
begin
 G:=TGameOrchestrator.Create(V);
 try
  Start:=V.DefaultStartingFEN;
  if Side=gsBlack then
   if V is TChessVariant then Start:=StringReplace(Start,' w ',' b ',[]) else Start[1]:='B';
  G.Engine[Side]:=TTimeoutEngine.Create;G.NewGame(Start);G.PlayNextMove;
  if Side=gsWhite then begin Reason:='white';Expected:=V.ResultText(goBlackWins);end
  else begin Reason:='black';Expected:=V.ResultText(goWhiteWins);end;
  Check(G.GameResult=Expected,'engine deadline result');
  Check(G.GameEndReason='flag fell for '+Reason+'; engine move deadline expired',
   'engine deadline retains cause: '+G.GameEndReason);
  Check(not G.EngineEndHasSide,'timeout is not a peer termination claim');
 finally G.Free;end;
end;
procedure Repetition(V:TGameVariant;const FEN:string;const Moves:array of string;const Reason:string);
var G:TGameOrchestrator;I:Integer;
begin
 G:=TGameOrchestrator.Create(V);
 try
  G.NewGame(FEN);
  for I:=0 to 7 do begin
   if G.State=gosGameOver then Break;
   G.PlayMove(Moves[I mod 4],G.CurrentSide,0,'fixture');
  end;
  Check(G.GameResult=V.ResultText(goDraw),'repetition result');
  Check(G.GameEndReason=Reason,'repetition cause: '+G.GameEndReason);
 finally G.Free;end;
end;
var V,ChessGame:TGameVariant;I:Integer;S:TGameSide;
begin
 RegisterDefaultGameVariant(DraughtsVariant);ChessGame:=TChessVariant.Create;
 for I:=0 to 1 do begin
  if I=0 then V:=DraughtsVariant else V:=ChessGame;
  for S:=gsWhite to gsBlack do begin Clock(V,S,False);Clock(V,S,True);EngineDeadline(V,S);end;
 end;
 Clock(ChessGame,gsWhite,False,'7k/8/8/8/8/8/8/KR6 w - - 0 1');
 Clock(ChessGame,gsWhite,True,'7k/8/8/8/8/8/8/KR6 w - - 0 1');
 Root(ChessGame,'7k/6Q1/6K1/8/8/8/8/8 b - - 0 1','1-0','checkmate');
 Root(ChessGame,'7k/5Q2/6K1/8/8/8/8/8 b - - 0 1','1/2-1/2','stalemate');
 Root(ChessGame,'7k/8/6K1/8/8/8/8/8 w - - 0 1','1/2-1/2','draw by insufficient mating material');
 Root(ChessGame,'7k/8/6K1/8/8/8/8/R7 w - - 150 1','1/2-1/2','draw by 75-move rule');
 Root(ChessGame,'7k/8/6K1/8/8/8/8/R7 w - - 100 1','1/2-1/2','draw by 50-move rule (claim accepted)');
 Repetition(ChessGame,ChessGame.DefaultStartingFEN,['g1f3','g8f6','f3g1','f6g8'],
  'draw by intended threefold repetition (claim accepted)');
 Repetition(DraughtsVariant,'W:WK46:BK1',['46-41','1-6','41-46','6-1'],
  'draw by repetition; repetitions=3');
 ChessGame.Free;
 WriteLn('Game end reason checks passed (',Checks,' checks)');
end.
