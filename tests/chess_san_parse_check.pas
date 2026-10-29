program chess_san_parse_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uChessPosition;
// Independent reference: expand formatter-produced legal moves into the
// documented input aliases. Conflicting aliases must remain ambiguous.
var P:TChessPosition;V:TChessVariant;Moves,Accepted:TStringList;
    I,J,Game,Ply,Checks,Positions:Integer;Seed:QWord;S,Base,Before:string;
function Pick(Limit:Integer):Integer;
begin Seed:=(Seed*1664525+1013904223) and $FFFFFFFF;Result:=Seed mod QWord(Limit);end;
procedure Probe(const Text:string);
var Expected,Actual,Normalized:string;Found,Want:Boolean;N:Integer;
begin
 Inc(Checks);Normalized:=V.NormalizeMove(Text);Expected:='';
 N:=Accepted.IndexOf(Normalized);Want:=(N>=0) and (Accepted.Objects[N]<>nil);
 if Want then Expected:=Moves[PtrUInt(Accepted.Objects[N])-1];
 Found:=P.TryParseMove(Text,Actual);
 if (Found<>Want) or (Actual<>Expected) then
  raise Exception.CreateFmt('SAN mismatch for "%s" in %s: expected %s, got %s',
   [Text,P.ToFEN,Expected,Actual]);
end;
procedure Alias(const Text:string;MoveIndex:Integer);
var Key:string;I:Integer;
begin
 Key:=V.NormalizeMove(Text);I:=Accepted.IndexOf(Key);
 if I<0 then Accepted.AddObject(Key,TObject(PtrUInt(MoveIndex+1)))
 else if Accepted.Objects[I]<>TObject(PtrUInt(MoveIndex+1)) then Accepted.Objects[I]:=nil;
end;
procedure Spellings(const Base:string;MoveIndex:Integer);
begin Alias(Base,MoveIndex);Alias(Base+'+',MoveIndex);Alias(Base+'#',MoveIndex);end;
procedure Position;
const Junk='abcdefgh12345678KQRBNPx=O-+#09!?';Letters='PNBRQK';
var N,K,Piece,Source,CaptureMode,PromotionMode:Integer;M,Prefix,Marker,Dest,Promotion,Notation,PieceLetter:string;
 Capture:Boolean;Disambiguation:array[0..3] of string;
begin
 Inc(Positions);P.CopyLegalMovesTo(Moves);Accepted.Clear;Before:=P.ToFEN;
 for N:=0 to Moves.Count-1 do begin
  M:=Moves[N];Notation:=P.MoveNotation(M);Base:=Notation;
  if Base[Length(Base)] in ['+','#'] then Delete(Base,Length(Base),1);
  Alias(M,N);Spellings(M,N);Spellings(Copy(M,1,2)+'-'+Copy(M,3,Length(M)),N);
  Spellings(Base,N);
  if Pos('O-O',Base)=1 then Continue;
  Piece:=Abs(P.PieceAt(Ord(M[1])-Ord('a')+1+8*(Ord(M[2])-Ord('1'))));
  Capture:=Pos('x',Notation)>0;Dest:=Copy(M,3,2);
  Disambiguation[0]:='';Disambiguation[1]:=M[1];Disambiguation[2]:=M[2];Disambiguation[3]:=Copy(M,1,2);
  for Source:=0 to 3 do begin
   if (Piece=1) and Capture and (Source in [0,2]) then Continue;
   for CaptureMode:=0 to Ord(Capture) do begin
    Marker:='';if CaptureMode=1 then Marker:='x';
    for PromotionMode:=0 to Ord(Length(M)=5) do begin
     Promotion:='';
     if Length(M)=5 then begin
      Promotion:=UpCase(M[5]);if PromotionMode=0 then Promotion:='='+Promotion;
     end;
     PieceLetter:='';if Piece<>1 then PieceLetter:=Letters[Piece];
     Prefix:=PieceLetter+Disambiguation[Source]+Marker;
     Spellings(Prefix+Dest+Promotion,N);
     if Piece in [2,4,5,6] then Spellings(LowerCase(PieceLetter)+Disambiguation[Source]+Marker+Dest+Promotion,N);
    end;
   end;
  end;
 end;
 for N:=0 to Accepted.Count-1 do Probe(Accepted[N]);
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
 Accepted:=TStringList.Create;Accepted.Sorted:=True;
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
