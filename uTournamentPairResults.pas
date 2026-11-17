unit uTournamentPairResults;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,FPJSON,uSprt,uGameTreePdn,uTournamentResults;
type
 TComparisonRow=record
  Number,Opening:Integer;
  Fen,WhiteKey,BlackKey:string;
  Outcome:TTournamentResult;
  Amended:Boolean;
 end;
 TComparisonRows=array of TComparisonRow;
function CandidateScore(Outcome:TTournamentResult;WhiteIsCandidate:Boolean):Double;
function CollectComparisonPairs(const Rows:TComparisonRows;const Candidate,Baseline:string;
 Openings:TStrings;Strict:Boolean):TSprtPairs;
function PairResultsJson(const Pairs:TSprtPairs):TJSONArray;
implementation
function CandidateScore(Outcome:TTournamentResult;WhiteIsCandidate:Boolean):Double;
begin
 if not TournamentResultIsKnown(Outcome) then Exit(-1);
 if Outcome=trDraw then Exit(0.5);
 if ((Outcome=trWhiteWin) and WhiteIsCandidate) or ((Outcome=trBlackWin) and not WhiteIsCandidate) then Exit(1);
 Result:=0;
end;
function CollectComparisonPairs(const Rows:TComparisonRows;const Candidate,Baseline:string;
 Openings:TStrings;Strict:Boolean):TSprtPairs;
var I,P,N,Slot,Matched:Integer;Counts:array of Integer;FirstWhite:array of string;White:Boolean;
begin
 Result:=nil;
 if (Candidate='') or (Baseline='') or (Candidate=Baseline) then raise EConvertError.Create('Select two distinct engines');
 N:=Openings.Count;if N=0 then N:=1;
 SetLength(Result,N);SetLength(Counts,N);SetLength(FirstWhite,N);Matched:=0;
 for I:=0 to High(Rows) do begin
  White:=Rows[I].WhiteKey=Candidate;
  if not ((White and (Rows[I].BlackKey=Baseline)) or
    ((Rows[I].WhiteKey=Baseline) and (Rows[I].BlackKey=Candidate))) then begin
    if Strict then raise EConvertError.Create('MATCH_CHANGED');Continue;
  end;
  Inc(Matched);P:=0;if Openings.Count>0 then P:=Rows[I].Opening-1;
  if (P<0) or (P>=N) or (Counts[P]>=2) then raise EConvertError.Create('Invalid scheduled opening pair');
  Slot:=Counts[P];Inc(Counts[P]);
  if Slot=0 then begin
    Result[P].Opening:=P+1;Result[P].Fen:=Rows[I].Fen;FirstWhite[P]:=Rows[I].WhiteKey;
  end else if (Result[P].Fen<>Rows[I].Fen) or (FirstWhite[P]=Rows[I].WhiteKey) then
    raise EConvertError.Create('Opening pair must share a FEN and reverse colours');
  Result[P].Games[Slot]:=Rows[I].Number;
  Result[P].Scores[Slot]:=CandidateScore(Rows[I].Outcome,White);
 end;
 if Matched=0 then raise EConvertError.Create('No scheduled games for these engines');
 for P:=0 to N-1 do begin
  if Counts[P]<>2 then raise EConvertError.Create('Need two colour-reversed games per scheduled opening');
  if (Openings.Count>0) and (Result[P].Fen<>Openings[P]) then raise EConvertError.Create('Opening pair differs from its ballot entry');
 end;
end;
function PairResultsJson(const Pairs:TSprtPairs):TJSONArray;
var I,S:Integer;Entry:TJSONObject;Games,Scores:TJSONArray;
begin
 Result:=TJSONArray.Create;
 for I:=0 to High(Pairs) do begin
  Entry:=TJSONObject.Create;Result.Add(Entry);Entry.Add('pair',Pairs[I].Opening);Entry.Add('fen',Pairs[I].Fen);
  Games:=TJSONArray.Create;Entry.Add('games',Games);Scores:=TJSONArray.Create;Entry.Add('results',Scores);
  for S:=0 to 1 do begin
   Games.Add(Pairs[I].Games[S]);if Pairs[I].Scores[S]<0 then Scores.Add(TJSONNull.Create) else Scores.Add(Pairs[I].Scores[S]);
  end;
 end;
end;
end.
