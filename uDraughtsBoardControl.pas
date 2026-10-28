unit uDraughtsBoardControl;
{$mode objfpc}{$H+}
interface
uses Classes, Graphics, Math, SysUtils, uDraughtsBoard, uDraughtsPosition,
  uGamePosition, uGameBoardControl;
type
  TDraughtsBoardControl = class(TGameBoardControl)
  private
    FBoard: TDraughtsBoard; // Legacy setup/database callers still own this board.
    procedure SetBoard(AValue: TDraughtsBoard);
  protected
    procedure PreparePosition; override;
    function BoardDimension: Integer; override;
    function SquareForCell(ARow, ACol: Integer): Integer; override;
    procedure DrawPiece(ASquare: Integer; const ACell: TRect); override;
    procedure DrawCoordinates(ASquare, ARow, ACol: Integer; const ACell: TRect); override;
  public
    procedure SetPosition(APosition: TGamePosition); override;
    property Board: TDraughtsBoard read FBoard write SetBoard;
  end;
implementation
procedure ShrinkRect(var ARect: TRect; DX, DY: Integer);
begin
  Inc(ARect.Left, DX); Inc(ARect.Top, DY);
  Dec(ARect.Right, DX); Dec(ARect.Bottom, DY);
end;
procedure TDraughtsBoardControl.SetBoard(AValue: TDraughtsBoard);
begin
  FBoard := AValue;
  if FBoard = nil then inherited SetPosition(nil);
  Invalidate;
end;
procedure TDraughtsBoardControl.SetPosition(APosition: TGamePosition);
begin
  if (APosition <> nil) and not (APosition is TDraughtsPosition) then
    raise EGamePositionError.Create('Draughts view requires a draughts position');
  FBoard := nil;
  inherited SetPosition(APosition);
end;
procedure TDraughtsBoardControl.PreparePosition;
var P: TDraughtsPosition;
begin
  // The legacy Board is mutable between paints. Refresh one snapshot before
  // drawing so pieces and the side marker always come from the same position.
  if FBoard = nil then Exit;
  if RenderPosition = nil then
  begin
    P := TDraughtsPosition.Create;
    try inherited SetPosition(P); finally P.Free; end;
  end;
  TDraughtsPosition(RenderPosition).AssignBoard(FBoard);
end;
function TDraughtsBoardControl.BoardDimension: Integer;
begin Result := 10; end;
function TDraughtsBoardControl.SquareForCell(ARow, ACol: Integer): Integer;
begin Result := RowColToSquare(ARow, ACol); end;
procedure TDraughtsBoardControl.DrawCoordinates(ASquare, ARow, ACol: Integer; const ACell: TRect);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clWhite;
  Canvas.Font.Size := Max(7, BoardSquareSize div 7);
  Canvas.TextOut(ACell.Left + 4, ACell.Top + 3, IntToStr(ASquare));
  Canvas.Brush.Style := bsSolid;
end;
procedure TDraughtsBoardControl.DrawPiece(ASquare: Integer; const ACell: TRect);
var LPiece: TDraughtsPieceKind; LPieceRect: TRect; LCell: Integer; LText: string;
begin
  LPiece := TDraughtsPosition(RenderPosition).Board[ASquare];
  LCell := BoardSquareSize;
  if LPiece <> pkEmpty then
  begin
          LPieceRect := ACell;
          ShrinkRect(LPieceRect, Max(4, LCell div 8), Max(4, LCell div 8));

          if PieceColor(LPiece) = pcWhite then
          begin
            Canvas.Brush.Color := RGBToColor(245, 241, 229);
            Canvas.Pen.Color := RGBToColor(70, 70, 70);
          end
          else
          begin
            Canvas.Brush.Color := RGBToColor(36, 37, 40);
            Canvas.Pen.Color := RGBToColor(10, 10, 10);
          end;

          Canvas.Ellipse(LPieceRect);
          ShrinkRect(LPieceRect, Max(2, LCell div 12), Max(2, LCell div 12));
          Canvas.Brush.Style := bsClear;
          Canvas.Pen.Color := RGBToColor(150, 132, 104);
          Canvas.Ellipse(LPieceRect);

          if LPiece in [pkWhiteKing, pkBlackKing] then
          begin
            Canvas.Font.Style := [fsBold];
            Canvas.Font.Size := Max(10, LCell div 3);
            if PieceColor(LPiece) = pcWhite then
              Canvas.Font.Color := RGBToColor(50, 50, 50)
            else
              Canvas.Font.Color := RGBToColor(235, 230, 220);
            LText := 'K';
            Canvas.TextOut(
              ACell.Left + (LCell - Canvas.TextWidth(LText)) div 2,
              ACell.Top + (LCell - Canvas.TextHeight(LText)) div 2,
              LText
            );
            Canvas.Font.Style := [];
          end;
          Canvas.Brush.Style := bsSolid;
  end;
end;
end.
