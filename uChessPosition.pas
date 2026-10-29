unit uChessPosition;

{$mode objfpc}{$H+}

{ Orthodox chess implementation of the existing game boundary. Squares are
  a1=1 .. h8=64; canonical moves are lowercase UCI, presentation is SAN.
  Linking this unit deliberately does NOT replace the default draughts variant.
  No game tree, clocks, GUI or engine lifecycle is implemented here. }

interface

uses Classes, SysUtils, uGamePosition;

const
  ChessStartingFEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

type
  { Positive pieces are White; negative pieces Black. 1=P,2=N,3=B,4=R,5=Q,6=K. }
  TChessState = record
    Board: array[0..63] of ShortInt;
    Turn: TGameSide;
    Castling: Byte; // K=1, Q=2, k=4, q=8
    EnPassant: Integer; // 0-based square, or -1
    Halfmove, Fullmove: Integer;
  end;

  TChessPosition = class(TGamePosition)
  private
    FState: TChessState;
    FMoves: TStringList;
    FMovesValid: Boolean;
    procedure EnsureMoves;
    function SAN(AIndex: Integer; IncludeCheck:Boolean=True): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFEN(const AText: string); override;
    function ToFEN: string; override;
    procedure AssignFrom(ASource: TGamePosition); override;
    function Clone: TGamePosition; override;
    function SideToMove: TGameSide; override;
    function PositionKey: string; override;
    function LegalMoveCount: Integer; override;
    function LegalMove(AIndex: Integer): string; override;
    function IsLegal(const ACanonical: string): Boolean; override;
    function TryParseMove(const AText: string; out ACanonical: string): Boolean; override;
    function SameMove(const A, B: string): Boolean; override;
    procedure PlayMove(const ACanonical: string); override;
    procedure PlayTrustedMove(const ACanonical: string); override;
    function MoveNotation(const ACanonical: string): string; override;
    procedure MoveSquares(const ACanonical: string; out AFrom, ATo: Integer); override;
    function InCheck: Boolean;
    function PieceAt(ASquare: Integer): Integer;
    function HalfmoveClock: Integer;
    // Conservative material proof: False means mating is not ruled out.
    // General dead positions (e.g. locked pawn fortresses) are not solved.
    function HasInsufficientMatingMaterial(ASide: TGameSide): Boolean;
  end;

  TChessVariant = class(TGameVariant)
  public
    function Name: string; override;
    function DefaultStartingFEN: string; override;
    function SideFromFEN(const AFEN: string): TGameSide; override;
    function StartingMoveNumberFromFEN(const AFEN: string): Integer; override;
    function CreatePosition: TGamePosition; override;
    function SameMove(const A, B: string): Boolean; override;
    procedure MoveSquares(const AMove: string; out AFrom, ATo: Integer); override;
    function NormalizeMove(const AMove: string): string; override;
    function CreateRules: TGameRules; override;
    function ResultText(AOutcome: TGameOutcome): string; override;
  end;

  TChessRules = class(TGameRules)
  private
    FHistory: TStringList;
    function Occurrences(const AKey: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset(AStart: TGamePosition); override;
    procedure MovePlayed(ABefore: TGamePosition; const AMove: string;
      AAfter: TGamePosition); override;
    function Outcome(APosition: TGamePosition; out AReason: string): TGameOutcome; override;
    function TimeoutOutcome(APosition: TGamePosition; AExpired: TGameSide;
      var AReason: string): TGameOutcome; override;
  end;

implementation

const
  PieceLetters = 'PNBRQK';
  KnightX: array[0..7] of Integer = (1,2,2,1,-1,-2,-2,-1);
  KnightY: array[0..7] of Integer = (2,1,-1,-2,-2,-1,1,2);
  RayX: array[0..7] of Integer = (1,-1,0,0,1,1,-1,-1);
  RayY: array[0..7] of Integer = (0,0,1,-1,1,-1,1,-1);

function SignFor(ASide: TGameSide): Integer;
begin
  if ASide = gsWhite then Result := 1 else Result := -1;
end;

function OnBoard(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (X < 8) and (Y >= 0) and (Y < 8);
end;

function SquareText(S: Integer): string;
begin
  Result := Chr(Ord('a') + S mod 8) + Chr(Ord('1') + S div 8);
end;

function ParseSquare(const S: string): Integer;
begin
  Result := -1;
  if (Length(S) = 2) and (S[1] in ['a'..'h']) and (S[2] in ['1'..'8']) then
    Result := Ord(S[1])-Ord('a') + 8*(Ord(S[2])-Ord('1'));
end;

function CoordinateMove(const S: string): string;
var T: string;
begin
  Result := '';
  T := Trim(S);
  // B1c3 is rank-disambiguated bishop SAN, not the coordinate b1c3.
  // Canonical lowercase UCI and all-uppercase coordinate input stay unambiguous.
  if (Length(T) = 4) and (T[1] = 'B') and (T[3] in ['a'..'h']) then Exit;
  T := LowerCase(T);
  if not (Length(T) in [4,5]) then Exit;
  if (ParseSquare(Copy(T,1,2)) < 0) or (ParseSquare(Copy(T,3,2)) < 0) then Exit;
  if Copy(T,1,2) = Copy(T,3,2) then Exit;
  if (Length(T) = 5) and not (T[5] in ['q','r','b','n']) then Exit;
  Result := T;
end;

function SANSpelling(const S: string): string;
var Base: string;
begin
  Result := Trim(S); Base := Result;
  if (Base <> '') and (Base[Length(Base)] in ['+','#']) then
    Delete(Base,Length(Base),1);
  if (Base = '0-0') or (Base = '0-0-0') then
    Result := StringReplace(Result,'0','O',[rfReplaceAll]);
end;

function NormalizeChessMove(const Text: string): string;
begin
  Result := CoordinateMove(Text);
  if Result = '' then Result := SANSpelling(Text);
end;

procedure ChessMoveSquares(const Text: string; out AFrom, ATo: Integer);
var M: string;
begin
  AFrom := 0; ATo := 0; M := CoordinateMove(Text);
  if M = '' then Exit;
  AFrom := ParseSquare(Copy(M,1,2))+1; ATo := ParseSquare(Copy(M,3,2))+1;
end;

function KingSquare(const S: TChessState; Side: TGameSide): Integer;
var I: Integer;
begin
  for I := 0 to 63 do
    if S.Board[I] = 6*SignFor(Side) then Exit(I);
  Result := -1;
end;

function Attacked(const S: TChessState; Square: Integer; BySide: TGameSide): Boolean;
var X,Y,NX,NY,I,P,Sign: Integer;
begin
  Result := True;
  X := Square mod 8; Y := Square div 8; Sign := SignFor(BySide);
  for I := -1 to 1 do
    if I <> 0 then
    begin
      NX := X+I; NY := Y-Sign;
      if OnBoard(NX,NY) and (S.Board[NY*8+NX] = Sign) then Exit;
    end;
  for I := 0 to 7 do
  begin
    NX := X+KnightX[I]; NY := Y+KnightY[I];
    if OnBoard(NX,NY) and (S.Board[NY*8+NX] = 2*Sign) then Exit;
    NX := X+RayX[I]; NY := Y+RayY[I];
    if OnBoard(NX,NY) and (S.Board[NY*8+NX] = 6*Sign) then Exit;
    while OnBoard(NX,NY) do
    begin
      P := S.Board[NY*8+NX];
      if P <> 0 then
      begin
        if (P = 5*Sign) or ((I < 4) and (P = 4*Sign)) or
          ((I >= 4) and (P = 3*Sign)) then Exit;
        Break;
      end;
      Inc(NX,RayX[I]); Inc(NY,RayY[I]);
    end;
  end;
  Result := False;
end;

function Checked(const S: TChessState; Side: TGameSide): Boolean;
var K: Integer;
begin
  K := KingSquare(S,Side);
  Result := (K < 0) or Attacked(S,K,OppositeGameSide(Side));
end;

procedure RemoveRookRight(var S: TChessState; Square: Integer);
begin
  case Square of
    0: S.Castling := S.Castling and $FD;
    7: S.Castling := S.Castling and $FE;
    56: S.Castling := S.Castling and $F7;
    63: S.Castling := S.Castling and $FB;
  end;
end;

procedure ApplyMove(var S: TChessState; const M: string);
var F,T,P,C,Sign,RookFrom,RookTo: Integer;
begin
  F := ParseSquare(Copy(M,1,2)); T := ParseSquare(Copy(M,3,2));
  P := S.Board[F]; C := S.Board[T]; Sign := SignFor(S.Turn);
  if (Abs(P) = 1) and (T = S.EnPassant) and (C = 0) then
  begin
    S.Board[T-8*Sign] := 0;
    C := -Sign;
  end;
  S.Board[F] := 0; S.Board[T] := P;
  if Length(M) = 5 then
    S.Board[T] := Pos(UpCase(M[5]),PieceLetters)*Sign;
  if Abs(P) = 6 then
  begin
    if S.Turn = gsWhite then S.Castling := S.Castling and $FC
    else S.Castling := S.Castling and $F3;
    if Abs(T-F) = 2 then
    begin
      if T > F then begin RookFrom := F+3; RookTo := F+1; end
      else begin RookFrom := F-4; RookTo := F-1; end;
      S.Board[RookTo] := S.Board[RookFrom]; S.Board[RookFrom] := 0;
    end;
  end;
  if Abs(P) = 4 then RemoveRookRight(S,F);
  if Abs(C) = 4 then RemoveRookRight(S,T);
  S.EnPassant := -1;
  if (Abs(P) = 1) and (Abs(T-F) = 16) then S.EnPassant := (F+T) div 2;
  if (Abs(P) = 1) or (C <> 0) then S.Halfmove := 0
  else if S.Halfmove < High(Integer) then Inc(S.Halfmove);
  if (S.Turn = gsBlack) and (S.Fullmove < High(Integer)) then Inc(S.Fullmove);
  S.Turn := OppositeGameSide(S.Turn);
end;

procedure GenerateMoves(const S: TChessState; Moves: TStrings);
var F,X,Y,NX,NY,T,P,Sign,I,D,Home: Integer;
    Trial: TChessState;

  procedure Add(Target: Integer; Promotion: Char = #0);
  var M: string; Child: TChessState;
  begin
    if (S.Board[Target]*Sign > 0) or (Abs(S.Board[Target]) = 6) then Exit;
    M := SquareText(F)+SquareText(Target);
    if Promotion <> #0 then M += Promotion;
    Child := S;
    ApplyMove(Child,M);
    if not Checked(Child,S.Turn) then Moves.Add(M);
  end;

  procedure PawnTarget(Target: Integer);
  begin
    if (Target div 8 = 0) or (Target div 8 = 7) then
    begin
      Add(Target,'q'); Add(Target,'r'); Add(Target,'b'); Add(Target,'n');
    end
    else Add(Target);
  end;

  procedure Castle(Right: Byte; Rook,Transit,Destination: Integer);
  var J: Integer;
  begin
    if (S.Castling and Right = 0) or (S.Board[Rook] <> 4*Sign) or Checked(S,S.Turn) then Exit;
    for J := 1 to Abs(Rook-F)-1 do
      if S.Board[F+J*((Rook-F) div Abs(Rook-F))] <> 0 then Exit;
    Trial := S; Trial.Board[F] := 0; Trial.Board[Transit] := 6*Sign;
    if Attacked(Trial,Transit,OppositeGameSide(S.Turn)) then Exit;
    Add(Destination);
  end;

begin
  Moves.Clear; Sign := SignFor(S.Turn);
  for F := 0 to 63 do
  begin
    P := S.Board[F];
    if P*Sign <= 0 then Continue;
    X := F mod 8; Y := F div 8;
    case Abs(P) of
      1: begin
        NY := Y+Sign;
        if not OnBoard(X,NY) then Continue;
        if S.Board[NY*8+X] = 0 then
        begin
          PawnTarget(NY*8+X);
          if ((Sign = 1) and (Y = 1)) or ((Sign = -1) and (Y = 6)) then
            if S.Board[(Y+2*Sign)*8+X] = 0 then Add((Y+2*Sign)*8+X);
        end;
        for D := -1 to 1 do
          if (D <> 0) and OnBoard(X+D,NY) then
          begin
            T := NY*8+X+D;
            if (S.Board[T]*Sign < 0) or
              ((T = S.EnPassant) and (S.Board[T] = 0) and (S.Board[T-8*Sign] = -Sign)) then
              PawnTarget(T);
          end;
      end;
      2: for I := 0 to 7 do
        begin
          NX := X+KnightX[I]; NY := Y+KnightY[I];
          if OnBoard(NX,NY) then Add(NY*8+NX);
        end;
      3,4,5: for I := 0 to 7 do
        begin
          if ((Abs(P) = 3) and (I < 4)) or ((Abs(P) = 4) and (I >= 4)) then Continue;
          NX := X+RayX[I]; NY := Y+RayY[I];
          while OnBoard(NX,NY) do
          begin
            T := NY*8+NX; Add(T);
            if S.Board[T] <> 0 then Break;
            Inc(NX,RayX[I]); Inc(NY,RayY[I]);
          end;
        end;
      6: begin
        for I := 0 to 7 do
        begin
          NX := X+RayX[I]; NY := Y+RayY[I];
          if OnBoard(NX,NY) then Add(NY*8+NX);
        end;
        if S.Turn = gsWhite then Home := 4 else Home := 60;
        if F = Home then
          if S.Turn = gsWhite then
          begin Castle(1,7,5,6); Castle(2,0,3,2); end
          else begin Castle(4,63,61,62); Castle(8,56,59,58); end;
      end;
    end;
  end;
end;

function Placement(const S: TChessState): string;
var X,Y,N,P: Integer; C: Char;
begin
  Result := '';
  for Y := 7 downto 0 do
  begin
    N := 0;
    for X := 0 to 7 do
    begin
      P := S.Board[Y*8+X];
      if P = 0 then Inc(N)
      else
      begin
        if N > 0 then begin Result += IntToStr(N); N := 0; end;
        C := PieceLetters[Abs(P)];
        if P < 0 then C := LowerCase(C);
        Result += C;
      end;
    end;
    if N > 0 then Result += IntToStr(N);
    if Y > 0 then Result += '/';
  end;
end;

function RightsText(Rights: Byte): string;
begin
  Result := '';
  if Rights and 1 <> 0 then Result += 'K';
  if Rights and 2 <> 0 then Result += 'Q';
  if Rights and 4 <> 0 then Result += 'k';
  if Rights and 8 <> 0 then Result += 'q';
  if Result = '' then Result := '-';
end;

function PositionPrefix(const S: TChessState): string;
begin
  Result := Placement(S);
  if S.Turn = gsWhite then Result += ' w ' else Result += ' b ';
  Result += RightsText(S.Castling)+' ';
end;

procedure FenError(const Reason: string);
begin
  raise EConvertError.Create(Reason);
end;

function Fields(const Text: string): TStringArray;
begin
  Result := Text.Split([' ',#9,#10,#13],TStringSplitOptions.ExcludeEmpty);
end;

function ParseFEN(const Text: string): TChessState;
var Parts: TStringArray; I,X,Y,P,Sign,WK,BK,BitValue,EP,OwnCount,OwnPawns: Integer;
    C: Char; Side: TGameSide; SideName: string;
  procedure RequireCastle(Bit:Integer; King, Rook:Integer; PieceSign:Integer;
    const RightName:string);
  begin
    if (Result.Castling and Bit<>0) and
      ((Result.Board[King]<>6*PieceSign) or (Result.Board[Rook]<>4*PieceSign)) then
      FenError('castling right '+RightName+' requires the king on '+SquareText(King)+
        ' and rook on '+SquareText(Rook));
  end;
begin
  FillChar(Result,SizeOf(Result),0); Result.EnPassant := -1;
  Parts := Fields(Text);
  if Length(Parts) <> 6 then FenError('expected six fields');
  X := 0; Y := 7; WK := 0; BK := 0;
  for I := 1 to Length(Parts[0]) do
  begin
    C := Parts[0][I];
    if C = '/' then
    begin
      if X <> 8 then FenError('rank '+IntToStr(Y+1)+' must contain eight squares');
      if Y = 0 then FenError('piece placement must contain eight ranks');
      Dec(Y); X := 0;
    end
    else if C in ['1'..'8'] then
    begin
      Inc(X,Ord(C)-Ord('0'));
      if X > 8 then FenError('rank '+IntToStr(Y+1)+' contains more than eight squares');
      if (I > 1) and (Parts[0][I-1] in ['1'..'8']) then
        FenError('consecutive empty-square digits in rank '+IntToStr(Y+1));
    end
    else
    begin
      P := Pos(UpCase(C),PieceLetters);
      if P = 0 then FenError('unknown piece-placement character "'+C+'"');
      if X >= 8 then FenError('rank '+IntToStr(Y+1)+' contains more than eight squares');
      if C in ['A'..'Z'] then Sign := 1 else Sign := -1;
      if (P = 1) and (Y in [0,7]) then FenError('pawn on back rank at '+SquareText(Y*8+X));
      Result.Board[Y*8+X] := P*Sign;
      if P = 6 then if Sign = 1 then Inc(WK) else Inc(BK);
      Inc(X);
    end;
  end;
  if Y <> 0 then FenError('piece placement must contain eight ranks');
  if X <> 8 then FenError('rank 1 must contain eight squares');
  if WK <> 1 then FenError('White must have exactly one king');
  if BK <> 1 then FenError('Black must have exactly one king');
  if Parts[1] = 'w' then Result.Turn := gsWhite
  else if Parts[1] = 'b' then Result.Turn := gsBlack
  else FenError('side to move must be w or b');
  if Parts[2] <> '-' then
  begin
    for I := 1 to Length(Parts[2]) do
    begin
      BitValue := 0;
      case Parts[2][I] of
        'K': BitValue := 1; 'Q': BitValue := 2;
        'k': BitValue := 4; 'q': BitValue := 8;
      end;
      if BitValue = 0 then FenError('unknown castling right "'+Parts[2][I]+'"');
      if Result.Castling and BitValue <> 0 then FenError('duplicate castling right '+Parts[2][I]);
      Result.Castling := Result.Castling or BitValue;
    end;
  end;
  RequireCastle(1,4,7,1,'K');RequireCastle(2,4,0,1,'Q');
  RequireCastle(4,60,63,-1,'k');RequireCastle(8,60,56,-1,'q');
  for I := 4 to 5 do
  begin
    if I=4 then SideName:='halfmove counter' else SideName:='fullmove number';
    for C in Parts[I] do if not (C in ['0'..'9']) then
      FenError(SideName+' must contain decimal digits only');
  end;
  if not TryStrToInt(Parts[4],Result.Halfmove) or (Result.Halfmove < 0) then
    FenError('halfmove counter must be between 0 and 2147483647');
  if not TryStrToInt(Parts[5],Result.Fullmove) or (Result.Fullmove < 1) then
    FenError('fullmove number must be between 1 and 2147483647');
  if Parts[3] <> '-' then
  begin
    EP := ParseSquare(Parts[3]); Sign := SignFor(Result.Turn);
    if EP < 0 then FenError('en passant target must be a square or -');
    if ((Sign = 1) and (EP div 8 <> 5)) or ((Sign = -1) and (EP div 8 <> 2)) then
      FenError('en passant target must be on rank 6 for White to move or rank 3 for Black');
    if Result.Board[EP] <> 0 then FenError('en passant target '+Parts[3]+' must be empty');
    if Result.Board[EP-8*Sign] <> -Sign then
      FenError('en passant requires an opposing pawn on '+SquareText(EP-8*Sign));
    if Result.Board[EP+8*Sign] <> 0 then
      FenError('en passant pawn starting square '+SquareText(EP+8*Sign)+' must be empty');
    if Result.Halfmove <> 0 then FenError('en passant requires a zero halfmove counter');
    Result.EnPassant := EP;
  end;
  for Side := Low(TGameSide) to High(TGameSide) do
  begin
    OwnCount := 0; OwnPawns := 0;
    for I := 0 to 63 do
      if Result.Board[I]*SignFor(Side) > 0 then
      begin Inc(OwnCount); if Abs(Result.Board[I]) = 1 then Inc(OwnPawns); end;
    if Side=gsWhite then SideName:='White' else SideName:='Black';
    if OwnCount > 16 then FenError(SideName+' has more than 16 pieces');
    if OwnPawns > 8 then FenError(SideName+' has more than eight pawns');
  end;
  // The player who just moved cannot have left their own king in check.
  // This also rejects adjacent kings. Full historical reachability is not proven.
  if Checked(Result,OppositeGameSide(Result.Turn)) then
  begin
    if Result.Turn=gsWhite then SideName:='Black' else SideName:='White';
    FenError(SideName+' (the side not to move) is in check');
  end;
end;

constructor TChessPosition.Create;
begin
  inherited Create;
  FMoves := TStringList.Create;
  FMoves.CaseSensitive := True;
  FState := ParseFEN(ChessStartingFEN);
end;

destructor TChessPosition.Destroy;
begin
  FMoves.Free;
  inherited Destroy;
end;

procedure TChessPosition.LoadFromFEN(const AText: string);
var State: TChessState;
begin
  State := ParseFEN(AText);
  FState := State; FMovesValid := False;
end;

function TChessPosition.ToFEN: string;
begin
  Result := PositionPrefix(FState);
  if FState.EnPassant < 0 then Result += '-' else Result += SquareText(FState.EnPassant);
  Result += ' '+IntToStr(FState.Halfmove)+' '+IntToStr(FState.Fullmove);
end;

procedure TChessPosition.AssignFrom(ASource: TGamePosition);
begin
  if not (ASource is TChessPosition) then
    raise EGamePositionError.Create('Chess position requires a chess source');
  if ASource = Self then Exit;
  FState := TChessPosition(ASource).FState;
  FMovesValid := False;
end;

function TChessPosition.Clone: TGamePosition;
begin
  Result := TChessPosition.Create;
  Result.AssignFrom(Self);
end;

function TChessPosition.SideToMove: TGameSide;
begin Result := FState.Turn; end;

procedure TChessPosition.EnsureMoves;
begin
  if not FMovesValid then
  begin GenerateMoves(FState,FMoves); FMovesValid := True; end;
end;

function TChessPosition.LegalMoveCount: Integer;
begin EnsureMoves; Result := FMoves.Count; end;

function TChessPosition.LegalMove(AIndex: Integer): string;
begin EnsureMoves; Result := FMoves[AIndex]; end;

function TChessPosition.PositionKey: string;
var I,FromSquare,ToSquare: Integer; HasEP: Boolean;
begin
  HasEP := False;
  if FState.EnPassant >= 0 then
  begin
    EnsureMoves;
    for I := 0 to FMoves.Count-1 do
    begin
      FromSquare := ParseSquare(Copy(FMoves[I],1,2));
      ToSquare := ParseSquare(Copy(FMoves[I],3,2));
      if (ToSquare = FState.EnPassant) and (Abs(FState.Board[FromSquare]) = 1) then
        begin HasEP := True; Break; end;
    end;
  end;
  Result := PositionPrefix(FState);
  if HasEP then Result += SquareText(FState.EnPassant) else Result += '-';
end;

function TChessPosition.IsLegal(const ACanonical: string): Boolean;
begin EnsureMoves; Result := FMoves.IndexOf(ACanonical) >= 0; end;

function TChessPosition.SAN(AIndex: Integer; IncludeCheck:Boolean): string;
var M,Other: string; F,T,P,I,OF_: Integer;
    Capture,OtherFound,SameFile,SameRank: Boolean;
    Child: TChessState; Replies: TStringList;
begin
  M := FMoves[AIndex]; F := ParseSquare(Copy(M,1,2)); T := ParseSquare(Copy(M,3,2));
  P := Abs(FState.Board[F]);
  Capture := (FState.Board[T] <> 0) or ((P = 1) and (F mod 8 <> T mod 8));
  if (P = 6) and (Abs(T-F) = 2) then
    if T > F then Result := 'O-O' else Result := 'O-O-O'
  else
  begin
    Result := '';
    if P <> 1 then
    begin
      Result := PieceLetters[P]; OtherFound := False; SameFile := False; SameRank := False;
      for I := 0 to FMoves.Count-1 do
        if I <> AIndex then
        begin
          Other := FMoves[I]; OF_ := ParseSquare(Copy(Other,1,2));
          if (Copy(Other,3,2) = Copy(M,3,2)) and (FState.Board[OF_] = FState.Board[F]) then
          begin
            OtherFound := True;
            SameFile := SameFile or (OF_ mod 8 = F mod 8);
            SameRank := SameRank or (OF_ div 8 = F div 8);
          end;
        end;
      if OtherFound then
        if not SameFile then Result += M[1]
        else if not SameRank then Result += M[2]
        else Result += Copy(M,1,2);
    end
    else if Capture then Result += M[1];
    if Capture then Result += 'x';
    Result += Copy(M,3,2);
    if Length(M) = 5 then Result += '='+UpCase(M[5]);
  end;
  if not IncludeCheck then Exit;
  Child := FState; ApplyMove(Child,M);
  if Checked(Child,Child.Turn) then
  begin
    Replies := TStringList.Create;
    try
      GenerateMoves(Child,Replies);
      if Replies.Count = 0 then Result += '#' else Result += '+';
    finally Replies.Free; end;
  end;
end;

function TChessPosition.TryParseMove(const AText: string; out ACanonical: string): Boolean;
var I,Found,Piece,Target,Last,FromSq,ToSq: Integer; Text,Notation,Base: string;
 HasSuffix,Castle: Boolean;
begin
  ACanonical := ''; EnsureMoves;
  Text := CoordinateMove(AText);
  if Text <> '' then
  begin
    Result := IsLegal(Text);
    if Result then ACanonical := Text;
    Exit;
  end;
  Text := SANSpelling(AText);
  if Text = '' then Exit(False);
  HasSuffix := Text[Length(Text)] in ['+','#'];
  // Filter by the SAN destination/piece before formatting candidates. The
  // existing formatter remains the final authority (including disambiguation).
  Base:=Text;if HasSuffix then Delete(Base,Length(Base),1);
  Castle:=(Base='O-O') or (Base='O-O-O');Piece:=6;Target:=-1;
  if not Castle then begin
    Last:=Length(Base);
    if (Last>=2) and (Base[Last-1]='=') then Dec(Last,2);
    if Last<2 then Exit(False);
    Target:=ParseSquare(Copy(Base,Last-1,2));if Target<0 then Exit(False);
    Piece:=Pos(Base[1],PieceLetters);if Piece=0 then Piece:=1;
  end;
  Found := -1;
  for I := 0 to FMoves.Count-1 do
  begin
    FromSq:=ParseSquare(Copy(FMoves[I],1,2));ToSq:=ParseSquare(Copy(FMoves[I],3,2));
    if Abs(FState.Board[FromSq])<>Piece then Continue;
    if Castle then begin if Abs(ToSq-FromSq)<>2 then Continue;end
    else if ToSq<>Target then Continue;
    Notation := SAN(I,HasSuffix);
    if not HasSuffix and (Notation[Length(Notation)] in ['+','#']) then
      Delete(Notation,Length(Notation),1);
    if Text = Notation then
    begin
      if Found >= 0 then Exit(False);
      Found := I;
    end;
  end;
  Result := Found >= 0;
  if Result then ACanonical := FMoves[Found];
end;

function TChessPosition.SameMove(const A, B: string): Boolean;
var CA,CB: string;
begin
  Result := NormalizeChessMove(A) = NormalizeChessMove(B);
  if not Result and TryParseMove(A,CA) and TryParseMove(B,CB) then Result := CA = CB;
end;

procedure TChessPosition.PlayMove(const ACanonical: string);
begin
  if not IsLegal(ACanonical) then raise EGamePositionError.Create('Illegal move: '+ACanonical);
  ApplyMove(FState,ACanonical); FMovesValid := False;
end;

procedure TChessPosition.PlayTrustedMove(const ACanonical: string);
begin
  // Keep the validated boundary even on trusted replay. This is deliberately
  // conservative until profiling justifies a chess-only fast replay path.
  PlayMove(ACanonical);
end;

function TChessPosition.MoveNotation(const ACanonical: string): string;
var I: Integer;
begin
  EnsureMoves; I := FMoves.IndexOf(ACanonical);
  if I < 0 then raise EGamePositionError.Create('Illegal move: '+ACanonical);
  Result := SAN(I);
end;

procedure TChessPosition.MoveSquares(const ACanonical: string; out AFrom, ATo: Integer);
begin ChessMoveSquares(ACanonical,AFrom,ATo); end;

function TChessPosition.InCheck: Boolean;
begin Result := Checked(FState,FState.Turn); end;

function TChessPosition.PieceAt(ASquare: Integer): Integer;
begin
  if (ASquare < 1) or (ASquare > 64) then raise ERangeError.Create('Chess square out of range');
  Result := FState.Board[ASquare-1];
end;

function TChessPosition.HalfmoveClock: Integer;
begin Result := FState.Halfmove; end;

function TChessPosition.HasInsufficientMatingMaterial(ASide: TGameSide): Boolean;
var I,P,OwnPieces,Knights,Bishops,BishopColour,Colour: Integer;
    AllBishopsSameColour,AnyPawn,AnyKnight,OpponentHelper: Boolean;
begin
  OwnPieces := 0; Knights := 0; Bishops := 0; BishopColour := -1;
  AllBishopsSameColour := True; AnyPawn := False; AnyKnight := False; OpponentHelper := False;
  for I := 0 to 63 do
  begin
    P := Abs(FState.Board[I]);
    if P = 0 then Continue;
    AnyPawn := AnyPawn or (P = 1); AnyKnight := AnyKnight or (P = 2);
    if P = 3 then
    begin
      Colour := (I mod 8 + I div 8) mod 2;
      if BishopColour < 0 then BishopColour := Colour
      else AllBishopsSameColour := AllBishopsSameColour and (Colour = BishopColour);
    end;
    if FState.Board[I]*SignFor(ASide) > 0 then
    begin
      Inc(OwnPieces);
      if P in [1,4,5] then Exit(False);
      if P = 2 then Inc(Knights);
      if P = 3 then Inc(Bishops);
    end
    else if not (P in [5,6]) then OpponentHelper := True;
  end;
  // A second knight can help construct mate; inability to FORCE mate is not
  // insufficient material. Opposing pieces can likewise supply blockers.
  if Knights > 0 then Exit((OwnPieces = 2) and not OpponentHelper);
  if Bishops > 0 then Exit(AllBishopsSameColour and not AnyPawn and not AnyKnight);
  Result := True; // Bare king.
end;

function TChessVariant.Name: string;
begin Result := 'Chess'; end;
function TChessVariant.DefaultStartingFEN: string;
begin Result := ChessStartingFEN; end;
function TChessVariant.CreatePosition: TGamePosition;
begin
  Result := TChessPosition.Create;
  if DefaultStartingFEN <> ChessStartingFEN then
    try Result.LoadFromFEN(DefaultStartingFEN); except Result.Free; raise; end;
end;
function TChessVariant.SideFromFEN(const AFEN: string): TGameSide;
var P: TStringArray;
begin
  P := Fields(AFEN); Result := gsWhite;
  if (Length(P) > 1) and (P[1] = 'b') then Result := gsBlack;
end;
function TChessVariant.StartingMoveNumberFromFEN(const AFEN: string): Integer;
var P: TStringArray;
begin
  P := Fields(AFEN); Result := 1;
  if Length(P) = 6 then Result := StrToIntDef(P[5],1);
  if Result < 1 then Result := 1;
end;
function TChessVariant.NormalizeMove(const AMove: string): string;
begin
  Result := NormalizeChessMove(AMove);
end;
function TChessVariant.SameMove(const A, B: string): Boolean;
begin Result := NormalizeMove(A) = NormalizeMove(B); end;
procedure TChessVariant.MoveSquares(const AMove: string; out AFrom, ATo: Integer);
begin
  ChessMoveSquares(AMove,AFrom,ATo);
end;
function TChessVariant.CreateRules: TGameRules;
begin Result := TChessRules.Create; end;
function TChessVariant.ResultText(AOutcome: TGameOutcome): string;
begin
  case AOutcome of
    goWhiteWins: Result := '1-0'; goBlackWins: Result := '0-1';
    goDraw: Result := '1/2-1/2'; else Result := '*';
  end;
end;

function ChessPosition(APosition: TGamePosition): TChessPosition;
begin
  if not (APosition is TChessPosition) then
    raise EGamePositionError.Create('Chess rules require a chess position');
  Result := TChessPosition(APosition);
end;

constructor TChessRules.Create;
begin inherited Create; FHistory := TStringList.Create; end;
destructor TChessRules.Destroy;
begin FHistory.Free; inherited Destroy; end;
procedure TChessRules.Reset(AStart: TGamePosition);
begin
  ChessPosition(AStart); FHistory.Clear; FHistory.Add(AStart.PositionKey);
end;
procedure TChessRules.MovePlayed(ABefore: TGamePosition; const AMove: string; AAfter: TGamePosition);
begin
  ChessPosition(ABefore); ChessPosition(AAfter);
  // No parallel game history: the existing runner feeds these callbacks.
  // Irreversible moves make earlier repetitions impossible.
  if (ChessPosition(AAfter).HalfmoveClock = 0) then FHistory.Clear;
  FHistory.Add(AAfter.PositionKey);
end;
function TChessRules.Occurrences(const AKey: string): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to FHistory.Count-1 do if FHistory[I] = AKey then Inc(Result);
end;
function TChessRules.Outcome(APosition: TGamePosition; out AReason: string): TGameOutcome;
var P,Child: TChessPosition; I,Repetitions: Integer;
begin
  P := ChessPosition(APosition); AReason := '';
  if P.LegalMoveCount = 0 then
    if P.InCheck then
    begin AReason := 'checkmate'; Exit(WinFor(OppositeGameSide(P.SideToMove))); end
    else begin AReason := 'stalemate'; Exit(goDraw); end;
  if P.HasInsufficientMatingMaterial(gsWhite) and P.HasInsufficientMatingMaterial(gsBlack) then
  begin AReason := 'draw by insufficient mating material'; Exit(goDraw); end;
  if P.HalfmoveClock >= 150 then
  begin AReason := 'draw by 75-move rule'; Exit(goDraw); end;
  Repetitions := Occurrences(P.PositionKey);
  if Repetitions >= 5 then
  begin AReason := 'draw by fivefold repetition'; Exit(goDraw); end;
  if P.HalfmoveClock >= 100 then
  begin AReason := 'draw by 50-move rule (claim accepted)'; Exit(goDraw); end;
  if Repetitions >= 3 then
  begin AReason := 'draw by threefold repetition (claim accepted)'; Exit(goDraw); end;
  // The existing interface automatically accepts available claims. A claim
  // may specify an intended legal move, not just the position already reached.
  Child := TChessPosition(P.Clone);
  try
    for I := 0 to P.LegalMoveCount-1 do
    begin
      Child.AssignFrom(P); Child.PlayTrustedMove(P.LegalMove(I));
      if Occurrences(Child.PositionKey) >= 2 then
      begin AReason := 'draw by intended threefold repetition (claim accepted)'; Exit(goDraw); end;
      if (Child.HalfmoveClock >= 100) and (Child.LegalMoveCount > 0) then
      begin AReason := 'draw by intended 50-move rule (claim accepted)'; Exit(goDraw); end;
    end;
  finally Child.Free; end;
  Result := goOngoing;
end;
function TChessRules.TimeoutOutcome(APosition: TGamePosition; AExpired: TGameSide;
  var AReason: string): TGameOutcome;
var P: TChessPosition;
begin
  P := ChessPosition(APosition);
  if P.LegalMoveCount = 0 then
    if P.InCheck then begin AReason := 'checkmate'; Exit(WinFor(OppositeGameSide(P.SideToMove))); end
    else begin AReason := 'stalemate'; Exit(goDraw); end;
  if P.HasInsufficientMatingMaterial(OppositeGameSide(AExpired)) then
  begin AReason += '; opponent has insufficient mating material'; Result := goDraw; end
  else Result := WinFor(OppositeGameSide(AExpired));
end;

end.
