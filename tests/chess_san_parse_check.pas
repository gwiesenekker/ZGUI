program chess_san_parse_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uChessPosition;
// Independent reference: enumerate every formatted legal move, as the original
// parser did. The optimized parser must accept exactly this set of spellings.
var P:TChessPosition;V:TChessVariant;Moves,Accepted:TStringList;
    I,J,Game,Ply,Checks,Positions:Integer;Seed:QWord;S,Base,Before:string;
function Pick(Limit:Integer):Integer;
begin Seed:=(Seed*1664525+1013904223) and $FFFFFFFF;Result:=Seed mod QWord(Limit);end;
procedure Probe(const Text:string);
var Expected,Actual,Normalized:string;Found,Want:Boolean;N:Integer;
begin
 Inc(Checks);Normalized:=V.NormalizeMove(Text);Expected:='';
 N:=Accepted.IndexOfName(Normalized);Want:=N>=0;
 if Want then Expected:=Accepted.ValueFromIndex[N];
 Found:=P.TryParseMove(Text,Actual);
 if (Found<>Want) or (Actual<>Expected) then
  raise Exception.CreateFmt('SAN mismatch for "%s" in %s: expected %s, got %s',
   [Text,P.ToFEN,Expected,Actual]);
end;
procedure Position;
const Junk='abcdefgh12345678KQRBNPx=O-+#09!?';
var N,K:Integer;
begin
 Inc(Positions);P.CopyLegalMovesTo(Moves);Accepted.Clear;Before:=P.ToFEN;
 for N:=0 to Moves.Count-1 do begin
  // Use tab as separator: promotion SAN itself contains '='.
  Accepted.Add(Moves[N]+#9+Moves[N]);
  S:=P.MoveNotation(Moves[N]);Accepted.Add(S+#9+Moves[N]);
  if S[Length(S)] in ['+','#'] then begin
   Delete(S,Length(S),1);Accepted.Add(S+#9+Moves[N]);
  end;
 end;
 for N:=0 to Moves.Count-1 do begin
  S:=P.MoveNotation(Moves[N]);Base:=S;
  if Base[Length(Base)] in ['+','#'] then Delete(Base,Length(Base),1);
  Probe(Moves[N]);Probe(UpperCase(Moves[N]));Probe(S);Probe(Base);
  Probe(Base+'+');Probe(Base+'#');Probe(Base+'++');Probe(Base+'!');
  Probe(' '+S+' ');Probe('x'+Base);
  if Pos('O-O',S)=1 then Probe(StringReplace(S,'O','0',[rfReplaceAll]));
 end;
 for N:=1 to 24 do begin
  S:='';for K:=1 to Pick(9) do S+=Junk[1+Pick(Length(Junk))];Probe(S);
 end;
 if P.ToFEN<>Before then raise Exception.Create('Parsing changed position');
end;
begin
 P:=TChessPosition.Create;V:=TChessVariant.Create;Moves:=TStringList.Create;
 Accepted:=TStringList.Create;Accepted.NameValueSeparator:=#9;
 Accepted.CaseSensitive:=True;
 try
  Seed:=20261029;Checks:=0;Positions:=0;
  // Explicit castles, EP, promotions, file/rank/full disambiguation and mate.
  for I:=0 to 6 do begin
   case I of
    0: Before:='r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
    1: Before:='4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2';
    2: Before:='1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1';
    3: Before:='4k3/8/8/8/8/8/1p6/4K3 b - - 0 37';
    4: Before:='4k3/8/8/8/8/1N6/8/1N2KN2 w - - 0 1';
    5: Before:='4k3/8/8/B7/8/8/8/BN5K w - - 0 1';
    6: Before:='7k/5Q2/6K1/8/8/8/8/8 w - - 0 1';
   end;
   P.LoadFromFEN(Before);Position;
  end;
  for Game:=1 to 12 do begin
   P.LoadFromFEN(ChessStartingFEN);
   for Ply:=1 to 80 do begin
    Position;if Moves.Count=0 then Break;
    J:=Pick(Moves.Count);P.PlayMove(Moves[J]);
   end;
  end;
  WriteLn('SAN parser equivalence passed: ',Checks,' spellings, ',Positions,' positions');
 finally Accepted.Free;Moves.Free;V.Free;P.Free;end;
end.
