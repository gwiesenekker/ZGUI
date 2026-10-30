program setup_score_render_fixture;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,Graphics,Classes,SysUtils,
 ExtCtrls,StdCtrls,uGamePosition,uDraughtsPosition,uDraughtsPositionSetupForm,
 uGameGuiProfile,uScoreHistoryControl,uChessBoardControl,uChessPosition;
type
 TScorePaint=class(TScoreHistoryControl)
  procedure Render(B:TBitmap);
 end;
 TChessPaint=class(TChessBoardControl)
  procedure Render(B:TBitmap);
 end;
procedure TScorePaint.Render(B:TBitmap);
begin HandleNeeded;PaintWindow(B.Canvas.Handle);B.Canvas.Pixels[0,0]:=B.Canvas.Pixels[0,0];end;
procedure TChessPaint.Render(B:TBitmap);
begin HandleNeeded;PaintWindow(B.Canvas.Handle);B.Canvas.Pixels[0,0]:=B.Canvas.Pixels[0,0];end;
var Setup:TPositionSetupForm;F:TForm;S:TScorePaint;C:TChessPaint;P:TChessPosition;
 B:TBitmap;I,J:Integer;OutDir:string;
procedure Save(const Name:string);
begin B.SaveToFile(OutDir+Name+'.bmp');end;
begin
  RegisterDefaultGameVariant(DraughtsVariant);
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 OutDir:=IncludeTrailingPathDelimiter(ParamStr(1));ForceDirectories(OutDir);
 B:=TBitmap.Create;Setup:=TPositionSetupForm.Create(nil,DefaultGameVariant);F:=TForm.CreateNew(nil);
 S:=TScorePaint.Create(F);S.Parent:=F;C:=TChessPaint.Create(F);C.Parent:=F;P:=TChessPosition.Create;
 try
  Setup.StartSetup('B:WK21,K32:BK6,27,28');Setup.Show;Application.ProcessMessages;
  for I:=0 to 1 do begin
   if I=1 then begin Setup.Width:=520;Setup.Height:=420;end;
   Setup.Realign;
   for J:=1 to 20 do begin Application.ProcessMessages;Sleep(10);end;
   Setup.Repaint;
   B.SetSize(Setup.ClientWidth,Setup.ClientHeight);Setup.PaintTo(B.Canvas,0,0);
   B.Canvas.Pixels[0,0]:=B.Canvas.Pixels[0,0];Save('draughts-setup-'+IntToStr(I));
  end;
  Setup.Hide;
  S.SetBounds(0,0,700,220);S.PlyCount:=8;S.CurrentPly:=4;S.ShowEvaluationBar:=True;
  // A missing point and both signs exercise every existing colour role.
  S.AnnotationsText:='engine=1.25; annotator=0.5'+LineEnding+
    'engine=-2; annotator=-1'+LineEnding+LineEnding+'engine=0.0'+LineEnding+
    'annotator=-0.5'+LineEnding+'engine=-1; annotator=2'+LineEnding;
  for I:=0 to 1 do begin
   if I=0 then S.DisplayMode:=shdmGraph else S.DisplayMode:=shdmBars;
   B.SetSize(S.Width,S.Height);S.Render(B);Save('score-'+IntToStr(I));
  end;
  C.SetBounds(0,0,520,500);C.ShowSideToMoveMarker:=True;
  for I:=0 to 3 do begin
   if I<2 then P.LoadFromFEN(ChessStartingFEN)
   else P.LoadFromFEN('r3k2r/1P6/8/3pP3/8/8/4p3/R3K2R w KQkq d6 0 37');
   C.SetPosition(P);C.BoardFlipped:=Odd(I);
   C.PvSourceSquare:=5;C.PvTargetSquare:=7;C.HintSourceSquare:=37;C.HintTargetSquare:=44;
   C.SetTargetSquares([17,22,27]);B.SetSize(C.Width,C.Height);C.Render(B);Save('chess-'+IntToStr(I));
  end;
 finally P.Free;F.Free;Setup.Free;B.Free;end;
end.
