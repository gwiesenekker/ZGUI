unit uDraughtsPositionSetupAdapter;
{$mode objfpc}{$H+}
interface
uses Classes,Graphics,Types,uPositionSetupAdapter,uGameBoardControl,uGamePosition,
 uDraughtsBoard,uDraughtsBoardControl;
type
 TDraughtsPositionSetupAdapter=class(TPositionSetupAdapter)
 private FBoard:TDraughtsBoard;
 public
  constructor Create; override;
  destructor Destroy; override;
  function CreateBoard(AOwner:TComponent):TGameBoardControl; override;
  procedure LoadFen(const Fen:string); override;
  function DraftFen:string; override;
  procedure Start; override;
  procedure Clear; override;
  function Side:TGameSide; override;
  procedure SetSide(Value:TGameSide); override;
  function PaletteCount:Integer; override;
  function PalettePiece(Index:Integer):Integer; override;
  function PieceName(Index:Integer):string; override;
  procedure Toggle(Square,Piece:Integer); override;
  procedure PaintTile(Canvas:TCanvas;const Bounds:TRect;Index,Selected:Integer;DarkColor:TColor); override;
 end;
implementation
uses Math;
procedure ShrinkRect(var R:TRect;X,Y:Integer);
begin Inc(R.Left,X);Inc(R.Top,Y);Dec(R.Right,X);Dec(R.Bottom,Y);end;
constructor TDraughtsPositionSetupAdapter.Create;
begin inherited Create;FBoard:=TDraughtsBoard.Create;end;
destructor TDraughtsPositionSetupAdapter.Destroy;
begin FBoard.Free;inherited Destroy;end;
function TDraughtsPositionSetupAdapter.CreateBoard(AOwner:TComponent):TGameBoardControl;
begin Result:=TDraughtsBoardControl.Create(AOwner);TDraughtsBoardControl(Result).Board:=FBoard;end;
procedure TDraughtsPositionSetupAdapter.LoadFen(const Fen:string);
begin FBoard.LoadFromFEN(Fen);end;
function TDraughtsPositionSetupAdapter.DraftFen:string;
begin Result:=FBoard.CurrentFEN;end;
procedure TDraughtsPositionSetupAdapter.Start;
begin FBoard.SetBeginPosition;end;
procedure TDraughtsPositionSetupAdapter.Clear;
begin FBoard.Clear;end;
function TDraughtsPositionSetupAdapter.Side:TGameSide;
begin if FBoard.SideToMove=dsBlack then Result:=gsBlack else Result:=gsWhite;end;
procedure TDraughtsPositionSetupAdapter.SetSide(Value:TGameSide);
begin if Value=gsBlack then FBoard.SideToMove:=dsBlack else FBoard.SideToMove:=dsWhite;end;
function TDraughtsPositionSetupAdapter.PaletteCount:Integer;
begin Result:=4;end;
function TDraughtsPositionSetupAdapter.PalettePiece(Index:Integer):Integer;
begin
 case Index of 0:Result:=Ord(pkWhiteMan);1:Result:=Ord(pkWhiteKing);
 2:Result:=Ord(pkBlackMan);3:Result:=Ord(pkBlackKing);else Result:=Ord(pkWhiteMan);end;
end;
function TDraughtsPositionSetupAdapter.PieceName(Index:Integer):string;
const Names:array[0..3]of string=('White man','White king','Black man','Black king');
begin Result:=Names[Index];end;
procedure TDraughtsPositionSetupAdapter.Toggle(Square,Piece:Integer);
begin if FBoard[Square]=TDraughtsPieceKind(Piece) then FBoard[Square]:=pkEmpty
 else FBoard[Square]:=TDraughtsPieceKind(Piece);end;
procedure TDraughtsPositionSetupAdapter.PaintTile(Canvas:TCanvas;const Bounds:TRect;
 Index,Selected:Integer;DarkColor:TColor);
var CellSize:Integer;Piece:TDraughtsPieceKind;PieceRect:TRect;TextValue:string;
begin
  CellSize := Min(Bounds.Width, Bounds.Height);
  Piece := TDraughtsPieceKind(PalettePiece(Index));
  Canvas.Brush.Color := DarkColor;
  Canvas.FillRect(Bounds);

  Canvas.Pen.Color := clGray;
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(Bounds);
  Canvas.Brush.Style := bsSolid;

  PieceRect := Rect((Bounds.Width - CellSize) div 2, (Bounds.Height - CellSize) div 2,
    (Bounds.Width + CellSize) div 2, (Bounds.Height + CellSize) div 2);
  ShrinkRect(PieceRect, Max(4, CellSize div 8), Max(4, CellSize div 8));
  if PieceColor(Piece) = pcWhite then
  begin
    Canvas.Brush.Color := RGBToColor(245, 241, 229);
    Canvas.Pen.Color := RGBToColor(70, 70, 70);
  end
  else
  begin
    Canvas.Brush.Color := RGBToColor(36, 37, 40);
    Canvas.Pen.Color := RGBToColor(10, 10, 10);
  end;
  Canvas.Ellipse(PieceRect);
  ShrinkRect(PieceRect, Max(2, CellSize div 12), Max(2, CellSize div 12));
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := RGBToColor(150, 132, 104);
  Canvas.Ellipse(PieceRect);
  Canvas.Brush.Style := bsSolid;

  if Piece in [pkWhiteKing, pkBlackKing] then
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Size := Max(10, CellSize div 3);
    if PieceColor(Piece) = pcWhite then
      Canvas.Font.Color := RGBToColor(50, 50, 50)
    else
      Canvas.Font.Color := RGBToColor(235, 230, 220);
    TextValue := 'K';
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut((Bounds.Width - Canvas.TextWidth(TextValue)) div 2,
      (Bounds.Height - Canvas.TextHeight(TextValue)) div 2, TextValue);
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
  end;

  if Piece = TDraughtsPieceKind(Selected) then
  begin
    Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Width := 4;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(Bounds);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsSolid;
  end;
end;


end.
