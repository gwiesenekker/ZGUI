program time_forfeit_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Classes,SysUtils,Math,FPJSON,uTimeForfeit,uGamePosition,
 uChessPosition,uDraughtsPosition,uGameOrchestrator,uEngineBase,uEngineRegistry,uCancellationToken;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
type
 TMockEngine=class(TGameEngine)
 protected function DoStartThinking:string;override;
 public function LaunchAndInit:Boolean;override;function Capabilities:TEngineCapabilities;override;
 end;
 TAdjudicator=class
  Calls:Integer;Config:TTimeForfeitSettings;Definition:TExternalEngineDefinition;Token:TCancellationToken;
  procedure Forfeit(Sender:TObject;Expired:TGameSide;var Outcome:TGameOutcome;var Reason:string);
 end;
var MockScore,MockFen:string;MockFailed,MockLaunchFailed,MockStopped:Boolean;Clock:Double;
function TMockEngine.LaunchAndInit:Boolean;
begin Result:=not MockLaunchFailed;end;
function TMockEngine.Capabilities:TEngineCapabilities;
begin Result:=[ecAnalysis];end;
function TMockEngine.DoStartThinking:string;
var V:TGameVariant;P:TGamePosition;M:TStringList;
begin
 MockFen:=StartingFEN;Clock:=0;
 if MockFailed then Exit('');
 V:=DefaultGameVariant;P:=V.CreatePosition;M:=TStringList.Create;
 try P.LoadFromFEN(StartingFEN);P.CopyLegalMovesTo(M);Result:=M[0];LastScore:=MockScore;
 finally M.Free;P.Free;end;
end;
function Factory(D:TExternalEngineDefinition):TGameEngine;
begin Result:=TMockEngine.Create;end;
procedure TAdjudicator.Forfeit(Sender:TObject;Expired:TGameSide;var Outcome:TGameOutcome;var Reason:string);
begin Inc(Calls);Outcome:=AnalyzeTimeForfeit(Config,Definition,TGameOrchestrator(Sender).Position,Token,nil,Reason);end;
procedure Run(V:TGameVariant;Kind:TExternalEngineKind);
var O:TGameOrchestrator;A:TAdjudicator;C:TTimeControl;R,Expected,BlackFEN:string;J:TJSONObject;Failed:Boolean;I:Integer;CallsBefore:Integer;
const Scores:array[0..7] of string=('3','-3','1','-1','2','-2','#5','#-4');
 Results:array[0..7] of TGameOutcome=(goWhiteWins,goBlackWins,goDraw,goDraw,goWhiteWins,goBlackWins,goWhiteWins,goBlackWins);
 procedure Terminal(const FEN:string;Outcome:TGameOutcome;const ReasonPart:string);
 var BeforeCalls:Integer;
 begin
  O.NewGame(V.DefaultStartingFEN);
  // Exercise the timeout safeguard with a final position pending its rules check.
  O.Position.LoadFromFEN(FEN);BeforeCalls:=A.Calls;MockLaunchFailed:=True;
  try O.CheckCurrentTurnTimeout(1);finally MockLaunchFailed:=False;end;
  Check(O.GameResult=V.ResultText(Outcome),'Terminal outcome precedes evaluation: '+FEN);
  Check(Pos(ReasonPart,O.GameEndReason)>0,'Terminal reason retained: '+O.GameEndReason);
  Check(A.Calls=BeforeCalls,'Terminal position never invokes adjudicator');
 end;
begin
 RegisterDefaultGameVariant(V);RegisterGameEngineFactory(Kind,@Factory);
 A:=TAdjudicator.Create;O:=TGameOrchestrator.Create(V);
 A.Config:=DefaultTimeForfeit;A.Definition:=TExternalEngineDefinition.Create;A.Definition.Kind:=Kind;
 A.Definition.ExePath:='/test/adjudicator';A.Config.EngineKey:=EngineIdentityKey(A.Definition);A.Config.EngineName:='Mock judge';A.Token:=TCancellationToken.Create;
 try
 C:=Default(TTimeControl);C.MinutesPerPeriod:=0.001;O.TimeControl:=C;
 // Default is still the rules-based timeout, including chess material rules.
 O.NewGame(V.DefaultStartingFEN);O.CheckCurrentTurnTimeout(1);
 Check(O.GameResult=V.ResultText(goBlackWins),'Normal timeout behavior preserved');
 O.OnTimeForfeit:=@A.Forfeit;
 for I:=0 to High(Scores) do begin
  MockScore:=Scores[I];O.NewGame(V.DefaultStartingFEN);Expected:=O.Position.ToFEN;
  O.CheckCurrentTurnTimeout(1);
  Check(O.GameResult=V.ResultText(Results[I]),'Threshold adjudication '+Scores[I]);
  Check((MockFen=Expected) and (O.Position.ToFEN=Expected) and (O.MovesPlayed.Count=0),'Analyze exact final position without playing suggested move');
  Check(Pos('Adjudicator Mock judge evaluation',O.GameEndReason)=1,'Reason identifies adjudicator');
 end;
 // Symmetric results stay unchanged when Black is the side whose clock expires.
 BlackFEN:=V.DefaultStartingFEN;
 if Kind=eekUci then BlackFEN:=StringReplace(BlackFEN,' w ',' b ',[])
 else BlackFEN[1]:='B';
 for I:=0 to High(Scores) do begin
  MockScore:=Scores[I];CallsBefore:=A.Calls;O.NewGame(BlackFEN);O.CheckCurrentTurnTimeout(1);
  Check(O.GameResult=V.ResultText(Results[I]),'Black timeout symmetric adjudication '+Scores[I]);
  Check(A.Calls=CallsBefore+1,'Nonterminal position invokes adjudicator');
 end;
 if Kind=eekUci then begin
  Terminal('7k/6Q1/5K2/8/8/8/8/8 b - - 0 1',goWhiteWins,'checkmate');
  Terminal('8/8/8/8/8/5k2/6q1/7K w - - 0 1',goBlackWins,'checkmate');
  Terminal('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1',goDraw,'stalemate');
  Terminal('8/8/8/8/8/6k1/5q2/7K w - - 0 1',goDraw,'stalemate');
  Terminal('7k/8/8/8/8/8/8/K7 w - - 0 1',goDraw,'insufficient mating material');
  Terminal('7k/8/8/8/8/8/8/K7 b - - 0 1',goDraw,'insufficient mating material');
  Terminal('7k/8/8/8/8/8/8/KR6 w - - 150 80',goDraw,'75-move rule');
 end else begin
  Terminal('W:W:B1',goBlackWins,'White has no legal move');
  Terminal('B:W50:B',goWhiteWins,'Black has no legal move');
 end;
 MockScore:='1';Check(TimeForfeitScore(A.Config,MockScore,R)=goDraw,'Positive draw');Check(Pos('100 < 200',R)>0,'Positive comparison reason');
 MockScore:='-1';TimeForfeitScore(A.Config,MockScore,R);Check(Pos('-100 > -200',R)>0,'Negative comparison reason');
 MockScore:='';O.NewGame(V.DefaultStartingFEN);O.CheckCurrentTurnTimeout(1);
 Check((O.GameResult='*') and (Pos('referee attention',O.GameEndReason)>0),'Missing score leaves unresolved');
 MockScore:='3';MockFailed:=True;O.NewGame(V.DefaultStartingFEN);O.CheckCurrentTurnTimeout(1);MockFailed:=False;
 Check(O.GameResult='*','No move leaves unresolved');
 MockLaunchFailed:=True;O.NewGame(V.DefaultStartingFEN);O.CheckCurrentTurnTimeout(1);MockLaunchFailed:=False;Check(O.GameResult='*','Failed launch leaves unresolved');
 A.Token.Cancel;O.NewGame(V.DefaultStartingFEN);O.CheckCurrentTurnTimeout(1);Check(O.GameResult='*','Cancellation never declares win or draw');
 J:=TimeForfeitJson(A.Config);try Check(ReadTimeForfeit(J).EngineKey=A.Config.EngineKey,'Settings round trip');
  J.Floats['threshold_cp']:=0;Failed:=False;try ReadTimeForfeit(J);except on E:EConvertError do Failed:=True;end;Check(Failed,'Invalid persisted threshold rejected');
 finally J.Free;end;
 finally O.Free;A.Token.Free;A.Definition.Free;A.Free;end;
end;
var C,D:TGameVariant;
begin
 C:=TChessVariant.Create;D:=TDraughtsVariant.Create;
 try Run(C,eekUci);Run(D,eekHub);WriteLn('Time forfeit checks passed: ',Checks);
 finally RegisterDefaultGameVariant(nil);C.Free;D.Free;end;
end.
