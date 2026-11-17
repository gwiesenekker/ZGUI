unit uSprt;
{$mode objfpc}{$H+}
{ Paired generalized SPRT, logistic Elo, model paired-logistic-v1.
  Independently implemented constrained-multinomial likelihood equations.
  Reference: https://www.cantate.be/Fishtest/support_MLE_multinomial.pdf
  Numerical comparison: official-stockfish/fishtest, stats/LLRcalc.py.
  Empty categories receive 0.001 regularization counts, as in that reference. }
interface
uses SysUtils,FPJSON;
const SprtModel='paired-logistic-v1';
type
 TSprtCounts=array[0..4] of Int64;
 TSprtConfig=record
  CandidateKey,BaselineKey:string;
  Elo0,Elo1,Alpha,Beta:Double;
  Stored,BeforePlay,HasStarted:Boolean;
 end;
 TSprtPair=record
  Opening:Integer;Fen:string;
  Games:array[0..1] of Integer;
  Scores:array[0..1] of Double; // negative = unresolved
 end;
 TSprtPairs=array of TSprtPair;
 TSprtPoint=record Opening:Integer;LLR:Double;end;
 TSprtTrace=array of TSprtPoint;
 TSprtReport=record
  Counts:TSprtCounts;Trace:TSprtTrace;
  Total,Complete,Included,PrefixComplete,WaitingAt,DecisionPair:Integer;
  LLR,Lower,Upper:Double;Decision:string;
 end;
function DefaultSprtConfig:TSprtConfig;
procedure ValidateSprtConfig(const C:TSprtConfig;RequireEngines:Boolean=False);
function SameSprtDesign(const A,B:TSprtConfig):Boolean;
function SprtLogLikelihood(const Counts:TSprtCounts;Elo0,Elo1:Double):Double;
function EvaluateSprt(const C:TSprtConfig;const Pairs:TSprtPairs):TSprtReport;
function SprtConfigJson(const C:TSprtConfig):TJSONObject;
function ReadSprtConfig(Data:TJSONData):TSprtConfig;
function SprtReportJson(const C:TSprtConfig;const R:TSprtReport;Amended:Boolean):TJSONObject;
implementation
uses Math;
function DefaultSprtConfig:TSprtConfig;
begin Result:=Default(TSprtConfig);Result.Elo0:=0;Result.Elo1:=5;Result.Alpha:=0.05;Result.Beta:=0.05;end;
procedure ValidateSprtConfig(const C:TSprtConfig;RequireEngines:Boolean);
begin
 if IsNan(C.Elo0) or IsInfinite(C.Elo0) or IsNan(C.Elo1) or IsInfinite(C.Elo1) or
  (C.Elo0>=C.Elo1) or (C.Elo0< -1000) or (C.Elo1>1000) then
  raise EConvertError.Create('Require -1000 <= Elo H0 < Elo H1 <= 1000 (logistic Elo)');
 if IsNan(C.Alpha) or IsInfinite(C.Alpha) or IsNan(C.Beta) or IsInfinite(C.Beta) or
  (C.Alpha<=0) or (C.Alpha>=1) or (C.Beta<=0) or (C.Beta>=1) or (C.Alpha+C.Beta>=1) then
  raise EConvertError.Create('Alpha and beta must be positive fractions whose sum is below 1');
 if (C.CandidateKey<>'') and (C.CandidateKey=C.BaselineKey) then
  raise EConvertError.Create('Candidate and baseline must be distinct registrations');
 if RequireEngines and ((C.CandidateKey='') or (C.BaselineKey='')) then
  raise EConvertError.Create('Select a candidate and baseline');
end;
function SameSprtDesign(const A,B:TSprtConfig):Boolean;
begin
 Result:=(A.CandidateKey=B.CandidateKey) and (A.BaselineKey=B.BaselineKey) and
  (A.Elo0=B.Elo0) and (A.Elo1=B.Elo1) and (A.Alpha=B.Alpha) and (A.Beta=B.Beta);
end;
function SprtLogLikelihood(const Counts:TSprtCounts;Elo0,Elo1:Double):Double;
var I,J:Integer;Mean0,Mean1,L0,L1:Double;Weights:array[0..4] of Double;
 function Profile(Mean:Double):Double;
 var K,Iteration:Integer;Left,Right,Lambda,Sum,D:Double;
 begin
  // The secular function is monotone decreasing between its two endpoint poles.
  Left:=-1/(1-Mean);Right:=1/Mean;
  for Iteration:=1 to 120 do begin
   Lambda:=(Left+Right)/2;Sum:=0;
   for K:=0 to 4 do begin D:=K/4-Mean;Sum:=Sum+Weights[K]*D/(1+Lambda*D);end;
   if Sum>0 then Left:=Lambda else Right:=Lambda;
   if Right-Left<1e-13 then Break;
  end;
  Lambda:=(Left+Right)/2;Result:=0;
  for K:=0 to 4 do Result:=Result-Weights[K]*Ln(1+Lambda*(K/4-Mean));
 end;
begin
 J:=0;
 for I:=0 to 4 do begin
  if Counts[I]<0 then raise EConvertError.Create('Negative SPRT count');
  if Counts[I]>0 then begin Weights[I]:=Counts[I];Inc(J);end else Weights[I]:=0.001;
 end;
 if J=0 then Exit(0);
 Mean0:=1/(1+Power(10,-Elo0/400));Mean1:=1/(1+Power(10,-Elo1/400));
 L0:=Profile(Mean0);L1:=Profile(Mean1);Result:=L1-L0;
 if IsNan(Result) or IsInfinite(Result) then raise EConvertError.Create('SPRT numerical calculation failed');
end;
function EvaluateSprt(const C:TSprtConfig;const Pairs:TSprtPairs):TSprtReport;
var I,Bin:Integer;PrefixOpen:Boolean;
begin
 ValidateSprtConfig(C,True);Result:=Default(TSprtReport);
 Result.Total:=Length(Pairs);Result.Decision:='continue';
 // Subtract logs to avoid overflowing ratios for small but valid error rates.
 Result.Lower:=Ln(C.Beta)-Ln(1-C.Alpha);Result.Upper:=Ln(1-C.Beta)-Ln(C.Alpha);
 PrefixOpen:=True;
 for I:=0 to High(Pairs) do begin
  if (Pairs[I].Opening<1) or ((I>0) and (Pairs[I].Opening<=Pairs[I-1].Opening)) then
    raise EConvertError.Create('SPRT pairs must be in scheduled order');
  for Bin:=0 to 1 do
   if IsNan(Pairs[I].Scores[Bin]) or IsInfinite(Pairs[I].Scores[Bin]) or
    ((Pairs[I].Scores[Bin]>=0) and (Pairs[I].Scores[Bin]<>0) and
     (Pairs[I].Scores[Bin]<>0.5) and (Pairs[I].Scores[Bin]<>1)) then
     raise EConvertError.Create('SPRT scores must be 0, 0.5, 1 or unresolved');
  if (Pairs[I].Scores[0]>=0) and (Pairs[I].Scores[1]>=0) then begin
   Inc(Result.Complete);if PrefixOpen then Inc(Result.PrefixComplete);
  end else begin
   if PrefixOpen then Result.WaitingAt:=Pairs[I].Opening;
   PrefixOpen:=False;
  end;
 end;
 for I:=0 to Result.PrefixComplete-1 do begin
  Bin:=Round(2*(Pairs[I].Scores[0]+Pairs[I].Scores[1]));
  if (Bin<0) or (Bin>4) then raise EConvertError.Create('Invalid paired score');
  Inc(Result.Counts[Bin]);Inc(Result.Included);
  Result.LLR:=SprtLogLikelihood(Result.Counts,C.Elo0,C.Elo1);
  SetLength(Result.Trace,Result.Included);Result.Trace[Result.Included-1].Opening:=Pairs[I].Opening;
  Result.Trace[Result.Included-1].LLR:=Result.LLR;
  if Result.LLR<=Result.Lower then Result.Decision:='h0'
  else if Result.LLR>=Result.Upper then Result.Decision:='h1';
  if Result.Decision<>'continue' then begin Result.DecisionPair:=Pairs[I].Opening;Break;end;
 end;
end;
function SprtConfigJson(const C:TSprtConfig):TJSONObject;
begin
 Result:=TJSONObject.Create;Result.Add('version',1);Result.Add('model',SprtModel);
 Result.Add('candidate',C.CandidateKey);Result.Add('baseline',C.BaselineKey);
 Result.Add('elo0',C.Elo0);Result.Add('elo1',C.Elo1);Result.Add('alpha',C.Alpha);Result.Add('beta',C.Beta);
 Result.Add('before_play',C.BeforePlay);Result.Add('has_started',C.HasStarted);Result.Add('stored',C.Stored);
end;
function ReadSprtConfig(Data:TJSONData):TSprtConfig;
var J:TJSONObject;I:Integer;V:TJSONData;
const Names:array[0..10] of string=('version','model','candidate','baseline','elo0','elo1','alpha','beta','before_play','has_started','stored');
begin
 Result:=DefaultSprtConfig;if Data=nil then Exit;
 if Data.JSONType<>jtObject then raise EConvertError.Create('Invalid SPRT view metadata');J:=TJSONObject(Data);
 for I:=0 to High(Names) do begin
  V:=J.Find(Names[I]);if V=nil then raise EConvertError.Create('Missing SPRT field '+Names[I]);
  if (I=0) and (V.JSONType<>jtNumber) or (I in [1,2,3]) and (V.JSONType<>jtString) or
   (I in [4,5,6,7]) and (V.JSONType<>jtNumber) or (I in [8,9,10]) and (V.JSONType<>jtBoolean) then
   raise EConvertError.Create('Invalid SPRT field '+Names[I]);
 end;
 if (J.Get('version',0.0)<>1) or (J.Get('model','')<>SprtModel) then raise EConvertError.Create('Unsupported SPRT model/version');
 Result.CandidateKey:=J.Get('candidate','');Result.BaselineKey:=J.Get('baseline','');
 Result.Elo0:=J.Get('elo0',0.0);Result.Elo1:=J.Get('elo1',5.0);Result.Alpha:=J.Get('alpha',0.05);Result.Beta:=J.Get('beta',0.05);
 Result.BeforePlay:=J.Get('before_play',False);Result.HasStarted:=J.Get('has_started',False);Result.Stored:=J.Get('stored',True);
 ValidateSprtConfig(Result,False);
end;
function SprtReportJson(const C:TSprtConfig;const R:TSprtReport;Amended:Boolean):TJSONObject;
var Counts:TJSONArray;I:Integer;Mode:string;
begin
 Result:=TJSONObject.Create;Result.Add('available',True);Result.Add('model',SprtModel);
 Mode:='exploratory';if C.BeforePlay then Mode:='configured_before_play';if Amended then Mode:='amended';
 Result.Add('mode',Mode);Result.Add('candidate_key',C.CandidateKey);Result.Add('baseline_key',C.BaselineKey);
 Result.Add('elo0',C.Elo0);Result.Add('elo1',C.Elo1);Result.Add('alpha',C.Alpha);Result.Add('beta',C.Beta);
 Counts:=TJSONArray.Create;for I:=0 to 4 do Counts.Add(R.Counts[I]);Result.Add('counts',Counts);
 Result.Add('pairs_total',R.Total);Result.Add('pairs_complete',R.Complete);Result.Add('pairs_included',R.Included);
 Result.Add('prefix_complete',R.PrefixComplete);Result.Add('waiting_at_pair',R.WaitingAt);
 Result.Add('later_complete',R.Complete-R.Included);Result.Add('llr',R.LLR);Result.Add('lower_bound',R.Lower);Result.Add('upper_bound',R.Upper);
 Result.Add('decision',R.Decision);Result.Add('decision_pair',R.DecisionPair);Result.Add('automatic_stop',False);
end;
end.
