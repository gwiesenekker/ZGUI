program board_render_fixture;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Controls, Graphics,
  SysUtils, uDraughtsBoard, uDraughtsBoardControl;
type TPaintBoard = class(TDraughtsBoardControl)
  procedure Render(B: TBitmap);
end;
procedure TPaintBoard.Render(B: TBitmap);
begin PaintWindow(B.Canvas.Handle); end;
var F: TForm; B: TPaintBoard; P: TDraughtsBoard; Image: TBitmap; I: Integer;
begin
  RequireDerivedFormResource := False; Application.Initialize;
  F := TForm.CreateNew(nil); P := TDraughtsBoard.Create;
  B := TPaintBoard.Create(F); Image := TBitmap.Create;
  try
    B.Parent := F; B.SetBounds(0,0,520,500); B.Board := P;
    Image.SetSize(520,500);
    ForceDirectories(ParamStr(1));
    for I := 0 to 7 do
    begin
      if I < 4 then P.LoadFromFEN('W:W31-50:B1-20')
      else P.LoadFromFEN('B:WK21,K32:BK6,27,28');
      B.BoardFlipped := Odd(I);
      B.ShowSideToMoveMarker := (I mod 4) >= 2;
      B.PvSourceSquare := 21; B.PvTargetSquare := 26;
      B.HintSourceSquare := 32; B.HintTargetSquare := 23;
      B.LastMoveTargetSquare := 28; B.SetTargetSquares([17,22,27]);
      B.Render(Image);
      Image.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(1))+IntToStr(I)+'.bmp');
    end;
  finally Image.Free; F.Free; P.Free; end;
end.
