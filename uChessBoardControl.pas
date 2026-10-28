unit uChessBoardControl;
{$mode objfpc}{$H+}
{ Original chess vector artwork, distributed under the project's GPLv3 licence.
  Drawn in normalized cell coordinates: no system chess glyphs or external assets. }
interface
uses Classes, Graphics, Math, SysUtils, Types, uGamePosition, uChessPosition,
  uGameBoardControl;
type
  TChessBoardControl = class(TGameBoardControl)
  protected
    function BoardDimension: Integer; override;
    function SquareForCell(ARow, ACol: Integer): Integer; override;
    procedure DrawPiece(ASquare: Integer; const ACell: TRect); override;
    procedure DrawCoordinates(ASquare, ARow, ACol: Integer; const ACell: TRect); override;
  public
    procedure SetPosition(APosition: TGamePosition); override;
  end;
implementation
function TChessBoardControl.BoardDimension: Integer;
begin Result := 8; end;
function TChessBoardControl.SquareForCell(ARow, ACol: Integer): Integer;
begin Result := (7-ARow)*8+ACol+1; end;
procedure TChessBoardControl.SetPosition(APosition: TGamePosition);
begin
  if (APosition <> nil) and not (APosition is TChessPosition) then
    raise EGamePositionError.Create('Chess view requires a chess position');
  inherited SetPosition(APosition);
end;
procedure TChessBoardControl.DrawCoordinates(ASquare, ARow, ACol: Integer; const ACell: TRect);
var LText: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clWhite;
  Canvas.Font.Size := Max(6,BoardSquareSize div 7);
  if ACol = 0 then Canvas.TextOut(ACell.Left+2,ACell.Top+1,IntToStr((ASquare-1) div 8+1));
  if ARow = 7 then
  begin
    LText := Chr(Ord('a')+(ASquare-1) mod 8);
    Canvas.TextOut(ACell.Right-Canvas.TextWidth(LText)-2,ACell.Bottom-Canvas.TextHeight(LText)-1,LText);
  end;
  Canvas.Brush.Style := bsSolid;
end;
procedure TChessBoardControl.DrawPiece(ASquare: Integer; const ACell: TRect);
var Piece,Size_: Integer; Fill,Edge: TColor;
  function Pt(X,Y: Integer): TPoint;
  begin Result := Point(ACell.Left+X*Size_ div 100,ACell.Top+Y*Size_ div 100); end;
  procedure Ellipse(X1,Y1,X2,Y2: Integer);
  var A,B: TPoint;
  begin A:=Pt(X1,Y1); B:=Pt(X2,Y2); Canvas.Ellipse(A.X,A.Y,B.X,B.Y); end;
  procedure Box(X1,Y1,X2,Y2: Integer);
  var A,B: TPoint;
  begin A:=Pt(X1,Y1); B:=Pt(X2,Y2); Canvas.Rectangle(A.X,A.Y,B.X,B.Y); end;
  procedure Poly(const XY: array of Integer);
  var Points: array of TPoint; I: Integer;
  begin
    SetLength(Points,Length(XY) div 2);
    for I:=0 to High(Points) do Points[I]:=Pt(XY[2*I],XY[2*I+1]);
    Canvas.Polygon(Points);
  end;
  procedure Line(X1,Y1,X2,Y2: Integer);
  var A,B: TPoint;
  begin A:=Pt(X1,Y1); B:=Pt(X2,Y2); Canvas.Line(A.X,A.Y,B.X,B.Y); end;
begin
  Piece := TChessPosition(RenderPosition).PieceAt(ASquare);
  if Piece=0 then Exit;
  Size_ := ACell.Right-ACell.Left;
  if Piece>0 then begin Fill:=RGBToColor(245,241,229); Edge:=RGBToColor(45,45,45); end
  else begin Fill:=RGBToColor(36,37,40); Edge:=RGBToColor(220,212,194); end;
  Canvas.Brush.Color:=Fill; Canvas.Pen.Color:=Edge;
  Canvas.Pen.Width:=Max(1,Size_ div 45);
  case Abs(Piece) of
    1: begin
      Poly([42,40,58,40,62,62,71,76,29,76,38,62]);
      Ellipse(36,18,64,46);
    end;
    2: begin
      Poly([29,74,35,61,44,49,28,50,23,43,35,27,47,22,47,13,
        59,21,69,34,73,53,68,74]);
      Canvas.Brush.Color:=Edge; Ellipse(43,31,49,37); Canvas.Brush.Color:=Fill;
      Line(29,43,38,42);
    end;
    3: begin
      Poly([44,43,56,43,61,65,71,76,29,76,39,65]);
      Poly([50,15,64,31,63,42,50,49,37,42,36,31]);
      Line(53,24,44,36);
    end;
    4: begin
      Poly([32,37,68,37,64,70,72,76,28,76,36,70]);
      Poly([28,20,39,20,39,29,45,29,45,20,55,20,55,29,61,29,
        61,20,72,20,72,41,28,41]);
    end;
    5: begin
      Poly([29,28,43,42,50,23,57,42,71,28,63,66,70,76,30,76,37,66]);
      Ellipse(23,20,35,32); Ellipse(44,15,56,27); Ellipse(65,20,77,32);
      Line(36,61,64,61);
    end;
    6: begin
      Poly([35,38,65,38,61,66,71,76,29,76,39,66]);
      Box(38,30,62,46); Box(46,12,54,35); Box(37,20,63,27);
    end;
  end;
  Poly([29,75,71,75,76,85,24,85]);
  Canvas.Pen.Width:=1;
end;
end.
