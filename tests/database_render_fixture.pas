program database_render_fixture;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,Graphics,Classes,SysUtils,uDatabaseForm, uGamePosition, uDraughtsPosition;
var F:TDatabaseForm;B:TBitmap;I,J:Integer;OutDir:string;
begin
  RegisterDefaultGameVariant(DraughtsVariant);
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 OutDir:=IncludeTrailingPathDelimiter(ParamStr(1));ForceDirectories(OutDir);
 F:=TDatabaseForm.Create(nil,DefaultGameVariant);B:=TBitmap.Create;
 try
  F.Show;
  for I:=0 to 1 do begin
   if I=1 then begin F.Width:=680;F.Height:=420;end;
   F.Realign;for J:=1 to 20 do begin Application.ProcessMessages;Sleep(10);end;
   F.Repaint;B.SetSize(F.ClientWidth,F.ClientHeight);F.PaintTo(B.Canvas,0,0);
   B.Canvas.Pixels[0,0]:=B.Canvas.Pixels[0,0];B.SaveToFile(OutDir+IntToStr(I)+'.bmp');
  end;
 finally B.Free;F.Free;end;
end.
