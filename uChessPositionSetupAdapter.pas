unit uChessPositionSetupAdapter;
{$mode objfpc}{$H+}
interface
uses Classes,Graphics,Types,uPositionSetupAdapter,uGameBoardControl,uGamePosition,
 uChessPosition,uChessBoardControl;
type
 TChessPositionSetupAdapter=class(TPositionSetupAdapter)
 private
  FPieces:array[1..64]of ShortInt;
  FSide:TGameSide;
  FRights:string;
  FEp:string;
  FHalfmove,FFullmove:Integer;
  procedure DropImpossibleRights;
 public
  constructor Create; override;
  function IsChessSetup:Boolean; override;
  function CreateBoard(AOwner:TComponent):TGameBoardControl; override;
  procedure LoadFen(const Fen:string); override;
  function DraftFen:string; override;
  function ValidatedFen:string; override;
  procedure Start; override;
  procedure Clear; override;
  function Side:TGameSide; override;
  procedure SetSide(Value:TGameSide); override;
  function PaletteCount:Integer; override;
  function PalettePiece(Index:Integer):Integer; override;
  function PieceName(Index:Integer):string; override;
  function PieceAt(Square:Integer):Integer;
  procedure Toggle(Square,Piece:Integer); override;
  procedure PaintTile(Canvas:TCanvas;const Bounds:TRect;Index,Selected:Integer;DarkColor:TColor); override;
 end;
implementation
uses SysUtils,Math;
type
 TChessSetupBoard=class(TChessBoardControl)
 public Draft:TChessPositionSetupAdapter;
 protected
  function HasDisplayPosition:Boolean; override;
  function DisplaySideToMove:TGameSide; override;
  procedure DrawPiece(Square:Integer;const Cell:TRect); override;
 end;
function TChessSetupBoard.HasDisplayPosition:Boolean;
begin Result:=Draft<>nil;end;
function TChessSetupBoard.DisplaySideToMove:TGameSide;
begin Result:=Draft.Side;end;
procedure TChessSetupBoard.DrawPiece(Square:Integer;const Cell:TRect);
begin PaintChessPiece(Canvas,Draft.PieceAt(Square),Cell);end;
constructor TChessPositionSetupAdapter.Create;
begin inherited Create;Start;end;
function TChessPositionSetupAdapter.IsChessSetup:Boolean;
begin Result:=True;end;
function TChessPositionSetupAdapter.CreateBoard(AOwner:TComponent):TGameBoardControl;
begin Result:=TChessSetupBoard.Create(AOwner);TChessSetupBoard(Result).Draft:=Self;end;
procedure TChessPositionSetupAdapter.LoadFen(const Fen:string);
var P:TChessPosition;Parts:TStringArray;I:Integer;
begin
 P:=TChessPosition.Create;
 try
  // One authoritative validator. Only known-valid canonical metadata is split.
  P.LoadFromFEN(Fen);Parts:=P.ToFEN.Split([' ']);
  for I:=1 to 64 do FPieces[I]:=P.PieceAt(I);
  FSide:=P.SideToMove;FRights:=Parts[2];FEp:=Parts[3];
  FHalfmove:=StrToInt(Parts[4]);FFullmove:=StrToInt(Parts[5]);
 finally P.Free;end;
end;
function TChessPositionSetupAdapter.DraftFen:string;
const Letters='PNBRQK';
var Rank,FileNo,Empty,Piece:Integer;C:Char;
begin
 Result:='';
 for Rank:=7 downto 0 do begin
  Empty:=0;
  for FileNo:=0 to 7 do begin
   Piece:=FPieces[Rank*8+FileNo+1];
   if Piece=0 then Inc(Empty) else begin
    if Empty>0 then begin Result+=IntToStr(Empty);Empty:=0;end;
    C:=Letters[Abs(Piece)];if Piece<0 then C:=LowerCase(C);Result+=C;
   end;
  end;
  if Empty>0 then Result+=IntToStr(Empty);if Rank>0 then Result+='/';
 end;
 if FSide=gsWhite then Result+=' w ' else Result+=' b ';
 Result+=FRights+' '+FEp+' '+IntToStr(FHalfmove)+' '+IntToStr(FFullmove);
end;
function TChessPositionSetupAdapter.ValidatedFen:string;
var P:TChessPosition;
begin P:=TChessPosition.Create;try P.LoadFromFEN(DraftFen);Result:=P.ToFEN;finally P.Free;end;end;
procedure TChessPositionSetupAdapter.Start;
begin LoadFen(ChessStartingFEN);end;
procedure TChessPositionSetupAdapter.Clear;
begin FillChar(FPieces,SizeOf(FPieces),0);FSide:=gsWhite;FRights:='-';FEp:='-';FHalfmove:=0;FFullmove:=1;end;
function TChessPositionSetupAdapter.Side:TGameSide;
begin Result:=FSide;end;
procedure TChessPositionSetupAdapter.SetSide(Value:TGameSide);
begin if Value<>FSide then FEp:='-';FSide:=Value;end;
function TChessPositionSetupAdapter.PaletteCount:Integer;
begin Result:=12;end;
function TChessPositionSetupAdapter.PalettePiece(Index:Integer):Integer;
begin Result:=Index div 2+1;if Odd(Index) then Result:=-Result;end;
function TChessPositionSetupAdapter.PieceName(Index:Integer):string;
const Names:array[0..5]of string=('pawn','knight','bishop','rook','queen','king');
begin if Odd(Index) then Result:='Black ' else Result:='White ';Result+=Names[Index div 2];end;
function TChessPositionSetupAdapter.PieceAt(Square:Integer):Integer;
begin if (Square<1) or (Square>64) then raise ERangeError.Create('Chess square out of range');Result:=FPieces[Square];end;
procedure TChessPositionSetupAdapter.DropImpossibleRights;
var C:Char;Keep:Boolean;NewRights:string;
begin
 NewRights:='';
 for C in FRights do begin
  case C of
   'K':Keep:=(FPieces[5]=6) and (FPieces[8]=4);
   'Q':Keep:=(FPieces[5]=6) and (FPieces[1]=4);
   'k':Keep:=(FPieces[61]=-6) and (FPieces[64]=-4);
   'q':Keep:=(FPieces[61]=-6) and (FPieces[57]=-4);
  else Keep:=False;end;
  if Keep then NewRights+=C;
 end;
 if NewRights='' then NewRights:='-';FRights:=NewRights;
end;
procedure TChessPositionSetupAdapter.Toggle(Square,Piece:Integer);
begin
 if (Square<1) or (Square>64) or (Abs(Piece)<1) or (Abs(Piece)>6) then
  raise ERangeError.Create('Invalid setup square or piece');
 if FPieces[Square]=Piece then FPieces[Square]:=0 else FPieces[Square]:=Piece;
 DropImpossibleRights;FEp:='-';FHalfmove:=0;
end;
procedure TChessPositionSetupAdapter.PaintTile(Canvas:TCanvas;const Bounds:TRect;
 Index,Selected:Integer;DarkColor:TColor);
begin
 Canvas.Brush.Color:=DarkColor;Canvas.FillRect(Bounds);
 Canvas.Pen.Color:=clGray;Canvas.Brush.Style:=bsClear;Canvas.Rectangle(Bounds);
 Canvas.Brush.Style:=bsSolid;
 PaintChessPiece(Canvas,PalettePiece(Index),Bounds);
 if PalettePiece(Index)=Selected then begin
  Canvas.Pen.Color:=clHighlight;Canvas.Pen.Width:=4;Canvas.Brush.Style:=bsClear;
  Canvas.Rectangle(Bounds);Canvas.Pen.Width:=1;Canvas.Brush.Style:=bsSolid;
 end;
end;
end.
