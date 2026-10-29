program chess_position_check;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, uGamePosition, uChessPosition, uDraughtsPosition,
  uGameTree, uGameTreeActor, uGameOrchestrator, uGameSetupTypes;

var Checks: Integer = 0;

procedure Check(Value: Boolean; const MessageText: string);
begin
  Inc(Checks);
  if not Value then raise Exception.Create(MessageText);
end;

procedure CheckMove(P: TChessPosition; const Move,Notation: string);
var Canonical,Before: string;
begin
  Before := P.ToFEN;
  Check(P.IsLegal(Move), 'Expected legal move '+Move+' in '+Before);
  Check(P.MoveNotation(Move) = Notation, 'SAN '+Move+': '+P.MoveNotation(Move)+' expected '+Notation);
  Check(P.TryParseMove(Notation,Canonical) and (Canonical = Move),'SAN roundtrip '+Notation);
  Check(P.ToFEN = Before,'Notation must not change the position');
end;

procedure CheckFEN;
var P: TChessPosition; V: TChessVariant; Before: string;

  procedure Bad(const Text: string);
  begin
    Before := P.ToFEN;
    try
      P.LoadFromFEN(Text);
      raise Exception.Create('Accepted bad FEN '+Text);
    except on E: EConvertError do ; end;
    Check(P.ToFEN = Before,'Rejected FEN is transactional');
    Check(P.IsLegal('e2e4'),'Rejected FEN does not invalidate legal move cache');
  end;

begin
  P := TChessPosition.Create; V := TChessVariant.Create;
  try
    Check(DefaultGameVariant = DraughtsVariant,'Chess must not replace default draughts');
    Check(V.NormalizeMove(' 0.25 ') = '0.25','Non-move normalization only trims');
    Check(V.NormalizeMove(' B1c3 ') = 'B1c3','SAN bishop spelling preserved');
    Check(P.ToFEN = ChessStartingFEN,'Initial FEN');
    Check(P.PieceAt(1) = 4,'a1 numbering'); Check(P.PieceAt(64) = -4,'h8 numbering');
    Bad('8/8/8/8/8/8/8/8 w - - 0 1');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 1 junk');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - +0 1');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 2147483648');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 0');
    Bad('4k3/8/8/8/8/8/8/4K3 w KK - 0 1');
    Bad('r3k2r/8/8/8/8/8/8/R3K2R w KK - 0 1');
    Bad('r3k2r/8/8/8/8/8/8/R3K2R w A - 0 1');
    Bad('4k3/8/8/8/8/8/8/4K3 w - e6 0 1');
    Bad('4k3/8/8/8/3pP3/8/8/4K3 b - e3 1 1');
    Bad('4k3/8/8/8/3pP3/8/8/4K3 b - e6 0 1');
    Bad('4k3/8/8/8/8/8/4k3/4K3 w - - 0 1');
    Bad('4k3/8/8/8/8/8/8/4K2P w - - 0 1');
    Bad('4k3/8/8/8/8/8/8/K3R3 w - - 0 1'); // side that just moved is in check
  finally V.Free; P.Free; end;
end;

procedure CheckFENDiagnostics;
var P:TChessPosition; Before,Move,MessageText:string; Rejected:Boolean;
  procedure Bad(const Text,Reason:string);
  begin
    Before:=P.ToFEN;
    Check(P.TryParseMove('e4',Move),'Prime legal move cache before FEN rejection');
    Rejected:=False;MessageText:='';
    try P.LoadFromFEN(Text);except on E:EConvertError do
      begin Rejected:=True;MessageText:=E.Message;end;end;
    Check(Rejected,'Reject FEN: '+Text);
    Check(Pos('Invalid',MessageText)=0,'Caller supplies FEN diagnostic prefix');
    Check(Pos(Reason,MessageText)>0,'Expected '+Reason+'; got '+MessageText);
    Check(P.ToFEN=Before,'Diagnostic failure preserves position');
    Check(P.TryParseMove('e4',Move) and (Move='e2e4'),'Diagnostic failure preserves cached moves');
  end;
begin
  P:=TChessPosition.Create;
  try
    Bad('8/8/8/8/8/8/8/8 w - - 0','six fields');
    Bad('7/8/8/8/8/8/8/8 w - - 0 1','rank 8 must contain eight');
    Bad('8/8/8/8/8/8/8/8/8 w - - 0 1','eight ranks');
    Bad('8/8/8/8/8/8/8 w - - 0 1','eight ranks');
    Bad('8P/8/8/8/8/8/8/8 w - - 0 1','rank 8 contains more');
    Bad('88/8/8/8/8/8/8/8 w - - 0 1','rank 8 contains more');
    Bad('44/8/8/8/8/8/8/8 w - - 0 1','consecutive');
    Bad('X7/8/8/8/8/8/8/8 w - - 0 1','unknown piece');
    Bad('4k3/8/8/8/8/8/8/4K2 w - - 0 1','rank 1 must contain eight');
    Bad('8/8/8/8/8/8/8/4K3 w - - 0 1','Black must have exactly one king');
    Bad('4k3/8/8/8/8/8/8/8 w - - 0 1','White must have exactly one king');
    Bad('4k3/8/8/8/8/8/8/3KK3 w - - 0 1','White must have exactly one king');
    Bad('3kk3/8/8/8/8/8/8/4K3 w - - 0 1','Black must have exactly one king');
    Bad('4k2P/8/8/8/8/8/8/4K3 w - - 0 1','pawn on back rank at h8');
    Bad('4k3/8/8/8/8/8/8/p3K3 w - - 0 1','pawn on back rank at a1');
    Bad('4k3/8/8/8/8/8/8/4K3 x - - 0 1','side to move');
    Bad('4k3/8/8/8/8/8/8/4K3 w A - 0 1','unknown castling right');
    Bad('4k3/8/8/8/8/8/8/4K3 w KK - 0 1','duplicate castling right K');
    Bad('4k3/8/8/8/8/8/8/4K3 w K - 0 1','king on e1 and rook on h1');
    Bad('4k3/8/8/8/8/8/8/4K3 w Q - 0 1','king on e1 and rook on a1');
    Bad('4k3/8/8/8/8/8/8/4K3 w k - 0 1','king on e8 and rook on h8');
    Bad('4k3/8/8/8/8/8/8/4K3 w q - 0 1','king on e8 and rook on a8');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - -1 1','halfmove counter must contain decimal');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 +1','fullmove number must contain decimal');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 2147483648 1','halfmove counter must be between');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 2147483648','fullmove number must be between');
    Bad('4k3/8/8/8/8/8/8/4K3 w - - 0 0','fullmove number must be between');
    Bad('4k3/8/8/8/8/8/8/4K3 w - z6 0 1','target must be a square');
    Bad('4k3/8/8/8/8/8/8/4K3 w - e3 0 1','target must be on rank 6');
    Bad('4k3/8/4N3/4p3/8/8/8/4K3 w - e6 0 1','target e6 must be empty');
    Bad('4k3/8/8/8/8/8/8/4K3 w - e6 0 1','opposing pawn on e5');
    Bad('4k3/4n3/8/4p3/8/8/8/4K3 w - e6 0 1','starting square e7 must be empty');
    Bad('4k3/8/8/4p3/8/8/8/4K3 w - e6 1 1','zero halfmove counter');
    Bad('rnbqkbnr/pppppppp/8/8/8/Q7/PPPPPPPP/RNBQKBNR w KQkq - 0 1','White has more than 16');
    Bad('4k3/8/8/8/8/PP6/PPPPPPP1/4K3 w - - 0 1','White has more than eight pawns');
    Bad('rnbqkbnr/pppppppp/q7/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1','Black has more than 16');
    Bad('4k3/ppppppp1/pp6/8/8/8/8/4K3 w - - 0 1','Black has more than eight pawns');
    Bad('4k3/8/8/8/8/8/8/K3R3 w - - 0 1','Black (the side not to move) is in check');
    Bad('k3r3/8/8/8/8/8/8/4K3 b - - 0 1','White (the side not to move) is in check');
  finally P.Free;end;
end;

procedure CheckSpecialMoves;
var P,Q: TChessPosition; Before,Canonical,Key: string; Moves: TStringList;
begin
  P := TChessPosition.Create; Q := TChessPosition.Create; Moves := TStringList.Create;
  try
    P.PlayMoveText('e4');
    Check(P.ToFEN = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1','Double pawn FEN');
    Q.LoadFromFEN('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
    Check(P.PositionKey = Q.PositionKey,'Uncapturable EP excluded from key');
    P.PlayMoveText('Nf6');
    Check(Copy(P.ToFEN,Length(P.ToFEN)-4,5) = '- 1 2','Black move increments fullmove, clears EP');
    Before := P.ToFEN;
    try P.PlayMove('e2e5'); Check(False,'Illegal move raises'); except on E: EGamePositionError do ; end;
    Check(P.ToFEN = Before,'Illegal move leaves all FEN fields unchanged');
    P.LoadFromFEN('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    CheckMove(P,'e1g1','O-O'); CheckMove(P,'e1c1','O-O-O');
    Check(P.TryParseMove('0-0',Canonical) and (Canonical = 'e1g1'),'Castling zero spelling');
    P.PlayMoveText('O-O');
    Check(P.ToFEN = 'r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1','Castle moves rook and clears only own rights');
    P.PlayMoveText('O-O-O');
    Check(P.ToFEN = '2kr3r/8/8/8/8/8/8/R4RK1 w - - 2 2','Black queenside castling');
    P.LoadFromFEN('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    P.PlayMove('a1a8');
    Check(Pos(' b Kk ',P.ToFEN) > 0,'Rook move/capture clear both queenside rights');
    P.LoadFromFEN('r3kr1r/8/8/8/8/8/8/R3K2R w KQ - 0 1');
    Check(not P.IsLegal('e1g1') and P.IsLegal('e1c1'),'Cannot castle through attacked f1');
    P.LoadFromFEN('r3k1rr/8/8/8/8/8/8/R3K2R w KQ - 0 1');
    Check(not P.IsLegal('e1g1'),'Cannot castle into attacked g1');
    P.LoadFromFEN('r3k2r/8/8/8/8/8/4r3/R3K2R w KQ - 0 1');
    Check(not P.IsLegal('e1g1') and not P.IsLegal('e1c1'),'Cannot castle out of check');
    P.LoadFromFEN('r3k2r/8/8/8/8/8/8/RN2K2R w KQ - 0 1');
    Check(not P.IsLegal('e1c1'),'Queenside castling requires b1 empty');
    P.LoadFromFEN('r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1');
    Check(not P.IsLegal('e1g1'),'No inferred castling rights');
    P.LoadFromFEN('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');
    CheckMove(P,'e5d6','exd6'); Key := P.PositionKey;
    Q.LoadFromFEN('4k3/8/8/3pP3/8/8/8/4K3 w - - 0 2');
    Check(Key <> Q.PositionKey,'Legal EP belongs to repetition identity');
    P.PlayMove('e5d6');
    Check(P.ToFEN = '4k3/8/3P4/8/8/8/8/4K3 b - - 0 2','EP removes passed pawn');
    P.LoadFromFEN('k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');
    Check(not P.IsLegal('e5d6'),'Pinned EP cannot expose king');
    Q.LoadFromFEN('k3r3/8/8/3pP3/8/8/8/4K3 w - - 0 2');
    Check(P.PositionKey = Q.PositionKey,'Pinned EP excluded from key');
    P.LoadFromFEN('8/8/8/r4pPK/8/8/8/k7 w - f6 0 2');
    Check(not P.IsLegal('g5f6'),'EP cannot uncover horizontal rook check');
    P.LoadFromFEN('4k3/8/8/3pP3/4K3/8/8/8 w - d6 0 2');
    Check(P.InCheck and P.IsLegal('e5d6'),'EP can remove checking pawn');
    P.LoadFromFEN('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
    P.MovesBetween(49,57,Moves); Check(Moves.Count = 4,'Four promotion choices');
    CheckMove(P,'a7a8q','a8=Q+'); CheckMove(P,'a7a8n','a8=N');
    Check(not P.IsLegal('a7a8'),'Promotion piece required');
    Check(not P.TryParseMove('a8',Canonical),'Omitted promotion rejected');
    P.PlayMoveText('a8=N'); Check(P.PieceAt(57) = 2,'Knight underpromotion');
    P.LoadFromFEN('1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1');
    CheckMove(P,'a7b8r','axb8=R+');
    P.LoadFromFEN('4k3/8/8/8/8/8/1p6/4K3 b - - 0 37');
    CheckMove(P,'b2b1q','b1=Q+');
    P.PlayMove('b2b1q'); Check(P.PieceAt(2) = -5,'Black promotion');
  finally Moves.Free; Q.Free; P.Free; end;
end;

procedure CheckSAN;
var P: TChessPosition; M: string;
begin
  P := TChessPosition.Create;
  try
    CheckMove(P,'g1f3','Nf3');
    Check(not P.TryParseMove('e4#',M),'False mate suffix rejected');
    Check(not P.TryParseMove('e4+',M),'False check suffix rejected');
    Check(P.TryParseMove(' E2E4 ',M) and (M = 'e2e4'),'Coordinate spelling normalization');
    P.LoadFromFEN('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1');
    CheckMove(P,'b1d2','Nbd2'); CheckMove(P,'f1d2','Nfd2');
    Check(not P.TryParseMove('Nd2',M),'Ambiguous SAN rejected');
    P.LoadFromFEN('4k3/8/8/8/8/R7/8/R3K3 w - - 0 1');
    CheckMove(P,'a1a2','R1a2'); CheckMove(P,'a3a2','R3a2');
    P.LoadFromFEN('4k3/8/8/8/8/1N6/8/1N2KN2 w - - 0 1');
    CheckMove(P,'b1d2','Nb1d2');
    P.LoadFromFEN('4k3/8/8/B7/8/8/8/BN5K w - - 0 1');
    CheckMove(P,'a1c3','B1c3'); CheckMove(P,'a5c3','B5c3');
    CheckMove(P,'b1c3','Nc3');
    P.LoadFromFEN('k3r3/8/8/8/8/8/4N3/4K1N1 w - - 0 1');
    CheckMove(P,'g1f3','Nf3'); // pinned knight must not cause disambiguation
    P.LoadFromFEN('4k3/8/8/8/8/8/4B3/K3R3 w - - 0 1');
    CheckMove(P,'e2d3','Bd3+');
    P.LoadFromFEN('7k/5Q2/6K1/8/8/8/8/8 w - - 0 1');
    CheckMove(P,'f7g7','Qg7#');
    Check(P.TryParseMove('Qg7',M) and (M = 'f7g7'),'Check/mate suffix may be omitted');
  finally P.Free; end;
end;

procedure CheckRules;
var P,Before: TChessPosition; R: TChessRules; Reason,Key: string; I: Integer;
    V: TChessVariant;

  procedure Load(const FEN: string);
  begin P.LoadFromFEN(FEN); R.Reset(P); end;
  procedure Move(const Text: string);
  var Canonical: string;
  begin
    Before.AssignFrom(P); Canonical := P.PlayMoveText(Text);
    R.MovePlayed(Before,Canonical,P);
  end;
  procedure Expect(Outcome: TGameOutcome; const Text: string);
  begin
    Check(R.Outcome(P,Reason) = Outcome,'Outcome '+Text+': '+Reason);
    if Text <> '' then Check(Pos(Text,Reason) > 0,'Reason expected '+Text+', got '+Reason);
  end;
  procedure Material(const FEN: string; White,Black: Boolean);
  begin
    Load(FEN);
    Check(P.HasInsufficientMatingMaterial(gsWhite) = White,'White insufficient '+FEN);
    Check(P.HasInsufficientMatingMaterial(gsBlack) = Black,'Black insufficient '+FEN);
  end;
  procedure Timeout(Expired: TGameSide; Expected: TGameOutcome);
  var Original,TimedFEN: string;
  begin
    Original := P.ToFEN; TimedFEN := Original;
    if Expired = gsWhite then TimedFEN := StringReplace(TimedFEN,' b ',' w ',[])
    else TimedFEN := StringReplace(TimedFEN,' w ',' b ',[]);
    P.LoadFromFEN(TimedFEN);
    Reason := 'flag';
    Check(R.TimeoutOutcome(P,Expired,Reason) = Expected,'Timeout '+P.ToFEN);
    P.LoadFromFEN(Original);
  end;

begin
  P := TChessPosition.Create; Before := TChessPosition.Create;
  R := TChessRules.Create; V := TChessVariant.Create;
  try
    R.Reset(P); Expect(goOngoing,'');
    Check(V.ResultText(goWhiteWins) = '1-0','White result');
    Check(V.ResultText(goBlackWins) = '0-1','Black result');
    Check(V.ResultText(goDraw) = '1/2-1/2','Draw result');
    Check(V.ResultText(goOngoing) = '*','Ongoing result');
    Load(ChessStartingFEN); Move('f3'); Move('e5'); Move('g4'); Move('Qh4#');
    Expect(goBlackWins,'checkmate');
    Load('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'); Expect(goDraw,'stalemate');
    Load('7k/6Q1/6K1/8/8/8/8/8 b - - 150 1'); Expect(goWhiteWins,'checkmate');
    Load('7k/6Q1/6K1/8/8/8/8/8 b - - 100 1'); Expect(goWhiteWins,'checkmate');
    Load('7k/8/6K1/8/8/8/8/R7 w - - 100 1'); Expect(goDraw,'50-move');
    Load('7k/8/6K1/8/8/8/8/R7 w - - 150 1'); Expect(goDraw,'75-move');
    Load('7k/8/6K1/8/8/8/8/R7 w - - 99 1'); Expect(goDraw,'intended 50-move');
    Load('8/8/8/8/8/2kb4/r7/K7 w - - 99 1');
    Check(P.LegalMoveCount = 1,'Only move is capture'); Expect(goOngoing,'');
    Move('Kxa2'); Check(P.HalfmoveClock = 0,'Capture resets halfmove');
    Load(ChessStartingFEN); Move('e4'); Check(P.HalfmoveClock = 0,'Pawn move resets halfmove');
    Load(ChessStartingFEN);
    Move('Nf3'); Move('Nf6'); Move('Ng1'); Move('Ng8'); Expect(goOngoing,'');
    Move('Nf3'); Move('Nf6'); Expect(goOngoing,'');
    Move('Ng1'); Expect(goDraw,'intended threefold');
    Move('Ng8'); Expect(goDraw,'threefold');
    for I := 1 to 2 do begin Move('Nf3'); Move('Nf6'); Move('Ng1'); Move('Ng8'); end;
    Expect(goDraw,'fivefold');
    R.Reset(P); Expect(goOngoing,''); // Reset does not import position history
    Load('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'); Key := P.PositionKey;
    Move('Rh2'); Move('Rh7'); Move('Rh1'); Move('Rh8');
    Check(P.PositionKey <> Key,'Castling rights distinguish repetition');
    Material('4k3/8/8/8/8/8/8/4K3 w - - 0 1',True,True); Expect(goDraw,'material');
    Material('4k3/8/8/8/8/8/8/3NK3 w - - 0 1',True,True); Expect(goDraw,'material');
    Material('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1',True,True); Expect(goDraw,'material');
    Material('4k3/8/8/8/8/8/8/2NNK3 w - - 0 1',False,True); Expect(goOngoing,'');
    Timeout(gsBlack,goWhiteWins); Timeout(gsWhite,goDraw);
    Material('2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1',False,False); // opposite colours
    Material('4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1',True,True); Expect(goDraw,'material');
    Material('4k3/8/8/8/8/8/8/2BNK3 w - - 0 1',False,True);
    Material('3nk3/8/8/8/8/8/8/2B1K3 w - - 0 1',False,False);
    Material('4k3/8/8/8/8/8/8/2B1K1b1 w - - 0 1',True,True);
    Material('4k3/8/8/8/8/8/8/3QK3 w - - 0 1',False,True);
    Timeout(gsWhite,goDraw); Timeout(gsBlack,goWhiteWins);
    Material('4k1n1/8/8/8/8/8/8/3QK3 w - - 0 1',False,True);
    Timeout(gsWhite,goDraw); // opposing queen alone cannot assist a lone knight
    Material('4k1n1/8/8/8/8/8/P7/4K3 w - - 0 1',False,False);
    Timeout(gsWhite,goBlackWins); // opposing pawn CAN assist
  finally V.Free; R.Free; Before.Free; P.Free; end;
end;

procedure CheckSharedCore;
var V: TChessVariant; Tree: TGameTree; Actor: TGameTreeActor; C: TGameTreeCommand;
    Node: Int64; P: TGamePosition; G: TGameOrchestrator; I: Integer;
    Control: TTimeControl;
const Moves: array[0..3] of string = ('f2f3','e7e5','g2g4','d8h4');
begin
  V := TChessVariant.Create; Tree := TGameTree.Create(V);
  Actor := TGameTreeActor.Create(Tree,False); P := V.CreatePosition;
  G := TGameOrchestrator.Create(V);
  try
    for I := 0 to 3 do
    begin
      C := Actor.CreateAppendMainlineMoveCommand(Moves[I],gmsHuman);
      try Actor.ExecuteCommand(C); Check(C.Accepted,'Existing actor accepts chess: '+C.ErrorText);
        Node := C.CreatedNodeId;
      finally C.Free; end;
    end;
    Check(Tree.TryBuildPositionAtNode(Tree.FindNodeById(Node),P),'Existing tree replays chess');
    Check(TChessPosition(P).InCheck and (P.LegalMoveCount = 0),'Replayed mate');
    Tree.SetHeader('Chess','W','B','*','4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
    Check(Tree.Root.SideToMove = gsBlack,'Tree uses chess starting side');
    Check(V.StartingMoveNumberFromFEN(Tree.StartingFEN) = 37,'Chess fullmove metadata');
    G.NewGame(ChessStartingFEN);
    for I := 0 to 3 do G.PlayMove(Moves[I],G.CurrentSide,0,'human');
    Check(G.State = gosGameOver,'Existing orchestrator ends chess game');
    Check(G.GameResult = '0-1','Existing orchestrator uses chess result');
    Control := G.TimeControl; Control.MinutesPerPeriod := 0.001;
    G.TimeControl := Control;
    G.NewGame('4k3/8/8/8/8/8/8/3QK3 w - - 0 37');
    G.PlayMove('e1f1',gsWhite,1,'human');
    Check((G.State = gosGameOver) and (G.GameResult = '1/2-1/2'),
      'Existing clock path uses chess timeout draw with bare opponent king');
    G.NewGame('4k3/8/8/8/8/8/8/3QK3 b - - 0 37');
    G.PlayMove('e8f8',gsBlack,1,'human');
    Check((G.State = gosGameOver) and (G.GameResult = '1-0'),
      'Existing clock path uses chess timeout win with opposing queen');
    Check(DefaultGameVariant = DraughtsVariant,'Shared core injection leaves default unchanged');
  finally G.Free; P.Free; Actor.Free; Tree.Free; V.Free; end;
end;

begin
  CheckFEN;
  CheckFENDiagnostics;
  CheckSpecialMoves;
  CheckSAN;
  CheckRules;
  CheckSharedCore;
  WriteLn('Chess position and rules checks passed (',Checks,' checks)');
end.
