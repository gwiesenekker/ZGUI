program sprt_check;
{$mode objfpc}{$H+}
uses SysUtils,Math,Classes,FPJSON,uSprt,uTournamentPairResults,uTournamentResults,uGameTreePdn;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Reference;
const Counts:array[0..5] of TSprtCounts=((0,0,79,0,0),(0,0,0,0,10),(10,0,0,0,0),(12,9,33,17,8),(1,2,3,4,5),(0,1,10,0,7));
 Values:array[0..5] of Double=(-1.1374948265897,0.14290443254416,-0.1449762437618,-0.024460444282098,0.14133994194973,0.25709782853321);
var I:Integer;Value:Double;Zero:TSprtCounts;
begin
 for I:=0 to 5 do begin Value:=SprtLogLikelihood(Counts[I],0,5);Check(Abs(Value-Values[I])<1e-7,Format('Fishtest logistic reference %d: %.12f != %.12f',[I,Value,Values[I]]));end;
 Zero:=Default(TSprtCounts);Check(SprtLogLikelihood(Zero,0,5)=0,'No pseudo evidence before a pair completes');
 Check(Abs(SprtLogLikelihood(Counts[0],-5,5))<1e-8,'Symmetric hypotheses and draw-only evidence');
end;
procedure Sequence;
var C:TSprtConfig;P:TSprtPairs;R:TSprtReport;I:Integer;J:TJSONObject;Failed:Boolean;
begin
 C:=DefaultSprtConfig;C.CandidateKey:='candidate';C.BaselineKey:='baseline';C.Elo1:=400;
 SetLength(P,79);for I:=0 to 78 do begin P[I].Opening:=I+1;P[I].Scores[0]:=1;P[I].Scores[1]:=1;end;
 R:=EvaluateSprt(C,P);Check((R.Decision='h1') and (R.DecisionPair=5),'First H1 crossing');
 Check((R.Complete=79) and (R.Included=5) and (R.Counts[4]=5) and (Length(R.Trace)=5),'Decision sample freezes while fixed match continues');
 R:=EvaluateSprt(C,P);Check(R.DecisionPair=5,'Replay produces identical first crossing');
 for I:=0 to 78 do begin P[I].Scores[0]:=0;P[I].Scores[1]:=0;end;
 R:=EvaluateSprt(C,P);Check((R.Decision='h0') and (R.DecisionPair=2),'First H0 crossing');
 P[0].Scores[0]:=-1;R:=EvaluateSprt(C,P);
 Check((R.Included=0) and (R.Complete=78) and (R.WaitingAt=1) and (R.Decision='continue'),'Wait for scheduled prefix despite later complete pairs');
 P[0].Scores[0]:=0;P[1].Scores[1]:=-1;R:=EvaluateSprt(C,P);
 Check((R.Included=1) and (R.WaitingAt=2) and (R.Decision='continue'),'No crossing across missing pair');
 C.BeforePlay:=True;C.Stored:=True;J:=SprtReportJson(C,R,False);
 try Check(J.Get('mode','')='configured_before_play','Configured provenance');finally J.Free;end;
 J:=SprtReportJson(C,R,True);try Check(J.Get('mode','')='amended','Referee/replay amendments visible');finally J.Free;end;
 P[0].Scores[0]:=0.2;Failed:=False;try R:=EvaluateSprt(C,P);except on E:EConvertError do Failed:=True;end;
 Check(Failed,'Reject unsupported scores');
 C.Alpha:=0;Failed:=False;try ValidateSprtConfig(C);except on E:EConvertError do Failed:=True;end;Check(Failed,'Reject invalid nominal error rates');
 C:=DefaultSprtConfig;C.CandidateKey:='candidate';C.BaselineKey:='baseline';C.Alpha:=1e-310;C.Beta:=1e-310;
 R:=EvaluateSprt(C,nil);Check(not IsInfinite(R.Upper) and not IsInfinite(R.Lower),'Small valid error rates retain finite log boundaries');
 C:=DefaultSprtConfig;J:=SprtConfigJson(C);
 try C:=ReadSprtConfig(J);Check(C.Elo1=5,'Settings round trip');J.Strings['model']:='unknown';Failed:=False;
  try C:=ReadSprtConfig(J);except on E:EConvertError do Failed:=True;end;Check(Failed,'Reject unknown persisted model');
 finally J.Free;end;
end;
procedure Pairing;
var Rows:TComparisonRows;P:TSprtPairs;Openings:TStringList;Failed:Boolean;Fmt:TGameFileFormat;
begin
 Openings:=TStringList.Create;
 try
 Openings.Add('same FEN');Openings.Add('same FEN');SetLength(Rows,5);
 Rows[0].Number:=1;Rows[0].Opening:=1;Rows[0].WhiteKey:='A';Rows[0].BlackKey:='B';Rows[0].Fen:='same FEN';
 Rows[1]:=Rows[0];Rows[1].Number:=2;Rows[1].BlackKey:='C';
 Rows[2]:=Rows[0];Rows[2].Number:=3;Rows[2].Opening:=2;
 Rows[3]:=Rows[0];Rows[3].Number:=4;Rows[3].WhiteKey:='B';Rows[3].BlackKey:='A';
 Rows[4]:=Rows[3];Rows[4].Number:=5;Rows[4].Opening:=2;
 for Fmt:=Low(Fmt) to High(Fmt) do begin
  Rows[0].Outcome:=ParseTournamentResult(TournamentResultText(trWhiteWin,Fmt),Fmt);
  Rows[2].Outcome:=ParseTournamentResult(TournamentResultText(trDraw,Fmt),Fmt);
  Rows[3].Outcome:=Rows[0].Outcome;Rows[4].Outcome:=trUnknown;
  P:=CollectComparisonPairs(Rows,'A','B',Openings,False);
  Check((Length(P)=2) and (P[0].Games[1]=4) and (P[1].Games[0]=3),'Filter scheduled head-to-head membership without grouping equal FEN');
  Check((P[0].Scores[0]=1) and (P[0].Scores[1]=0) and (P[1].Scores[0]=0.5) and (P[1].Scores[1]<0),'Both notation formats normalize candidate results');
  P:=CollectComparisonPairs(Rows,'B','A',Openings,False);Check((P[0].Scores[0]=0) and (P[0].Scores[1]=1),'Candidate inversion');
 end;
 Failed:=False;try P:=CollectComparisonPairs(Rows,'A','B',Openings,True);except on E:EConvertError do Failed:=True;end;Check(Failed,'Strict CLI match still rejects unrelated participants');
 Rows[3].WhiteKey:='A';Rows[3].BlackKey:='B';Failed:=False;
 try P:=CollectComparisonPairs(Rows,'A','B',Openings,False);except on E:EConvertError do Failed:=True;end;Check(Failed,'Reject same-colour pair');
 finally Openings.Free;end;
end;
begin Reference;Sequence;Pairing;WriteLn('SPRT checks passed: ',Checks);end.
