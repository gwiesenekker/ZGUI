program gui_layout_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,
 Math,ComCtrls,Graphics,ExtCtrls,LCLIntf,LCLType,uGuiLayout,uGuiDialogs,uGamePosition,uChessPosition,
 uDraughtsPosition,uGameGuiProfile,uEngineEditForm,uEnginesDialog,uGameSetupForm,
 uTournamentDialog,uPreferencesForm,uDatabaseForm,uDraughtsPositionSetupForm,uMainForm,
 uPreferences,uManualForm,uPdnOpenDialog,uScoreHistoryForm;
type TErrors=class
  procedure Report(Sender:TObject;E:Exception);
end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('ERROR: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Checks,Failures:Integer;Errors:TErrors;
procedure Check(B:Boolean;const Msg:string);
begin Inc(Checks);if not B then begin Inc(Failures);WriteLn('FAIL: ',Msg);end;end;
procedure Inspect(C:TWinControl;Root:TForm);
var I,J:Integer;Child:TControl;W,H:Integer;Path:string;Choice:TComboBox;
begin
 for I:=0 to C.ControlCount-1 do begin
  Child:=C.Controls[I];if not Child.Visible then Continue;
  Path:=Root.Caption+' font='+IntToStr(Root.Font.Size)+' size='+IntToStr(Root.Width)+'x'+IntToStr(Root.Height)+'/'+C.ClassName+'/'+Child.ClassName+':'+Child.Name;
  if not (C is TScrollBox) and not (C is TPageControl) then begin
   Check((Child.Left>=-2) and (Child.Top>=-2) and
    (Child.Left+Child.Width<=C.ClientWidth+2) and
    (Child.Top+Child.Height<=C.ClientHeight+2),Path+' bounds '+
    IntToStr(Child.Left)+','+IntToStr(Child.Top)+','+IntToStr(Child.Width)+','+IntToStr(Child.Height)+
    ' parent '+IntToStr(C.ClientWidth)+','+IntToStr(C.ClientHeight));
  end;
  if (Child is TLabel) and not TLabel(Child).WordWrap then begin
   W:=MeasureGuiText(TLabel(Child).Caption,Child.Font).cx;
   H:=MeasureGuiText(TLabel(Child).Caption,Child.Font).cy;
   Check((W<=Child.Width+2) and (H<=Child.Height+2),Path+' text clipped '+TLabel(Child).Caption+' width='+IntToStr(Child.Width)+' required='+IntToStr(W)+' min='+IntToStr(Child.Constraints.MinWidth)+' max='+IntToStr(Child.Constraints.MaxWidth));
  end;
  if Child.Name='EngineUsageStatusBar' then begin
   Check((Child is TStatusBar) and (Child.Top+Child.Height=C.ClientHeight) and
    (Child.BorderSpacing.Bottom=0),Path+' native status bar has no external bottom gap');
   Check(Child.Height>=MeasureGuiText(TStatusBar(Child).SimpleText,Child.Font).cy,
    Path+' status bar text fits the active font');
   {$IFDEF LCLGTK2}
   Check(Child.Height<=MeasureGuiText(TStatusBar(Child).SimpleText,Child.Font).cy+
     2*GetSystemMetrics(SM_CYEDGE),
    Path+' GTK status bar uses its measured height without a theme-sized blank strip');
   {$ENDIF}
  end;
  if Child is TGuiNumberEdit then begin
   W:=MeasureGuiText(TGuiNumberEdit(Child).WidthSample,Child.Font).cx;
   Check((Child.Width>=W) and
    (Child.Width<=W+Max(8,MeasureGuiText('M',Child.Font).cx)+2),Path+' numeric width follows sample and font');
   Check((Child.Constraints.MaxWidth>0) and (TEdit(Child).MaxLength=0),
    Path+' numeric presentation is bounded without truncating accepted input');
  end;
  if Child.Name='TournamentStartingFEN' then begin
   W:=MeasureGuiText(TEdit(Child).Text,Child.Font).cx+MeasureGuiText('MM',Child.Font).cx;
   Check(Child.Width>=W,Path+' complete starting FEN plus margin');
   Choice:=TComboBox(Root.FindComponent('TournamentVariant'));
   if Choice<>nil then begin
    Check(Choice.Parent=Child.Parent,Path+' game chooser shares FEN row');
    Check(TControl(Root.FindComponent('TournamentStartingFENLabel')).Left>=Choice.Left+Choice.Width,
     Path+' game chooser precedes Starting FEN label');
    Check(Abs(Choice.Top-Child.Top)<=2,Path+' game chooser aligns with FEN');
    W:=0;for J:=0 to Choice.Items.Count-1 do W:=Max(W,MeasureGuiText(Choice.Items[J],Choice.Font).cx);
    Inc(W,MeasureGuiText('Ag',Choice.Font).cy+MeasureGuiText('MM',Choice.Font).cx);
    Check(Choice.Width<=W+2,Path+' chooser width is measured to its values: '+IntToStr(Choice.Width)+' expected '+IntToStr(W));
    Check(Child.Parent.Parent.Width>=Root.ClientWidth-32,Path+' full-width settings rows');
   end else Check(Child.Parent.Width>=Root.ClientWidth-32,Path+' full-width settings rows');
  end;
  if (C is TRadioGroup) and (Child is TRadioButton) then begin
   Child.GetPreferredSize(W,H,True);
   Check(Child.Height>=H,Path+' native radio button height');
   for J:=0 to I-1 do if C.Controls[J].Visible and (C.Controls[J] is TRadioButton) then
    Check((Child.Top>=C.Controls[J].Top+C.Controls[J].Height) or
      (C.Controls[J].Top>=Child.Top+Child.Height) or
      (Child.Left>=C.Controls[J].Left+C.Controls[J].Width) or
      (C.Controls[J].Left>=Child.Left+Child.Width),Path+' radio buttons do not overlap');
  end;
  if Child is TWinControl then Inspect(TWinControl(Child),Root);
 end;
end;
procedure Test(F:TForm);
var Size,I,Mode,Tab:Integer;Pages:TPageControl;Img:TBitmap;Png:TPortableNetworkGraphic;
begin
 try
  if F is TPreferencesForm then TPreferencesForm(F).StartEdit(DefaultGuiPreferences);
  if GetEnvironmentVariable('ZGUI_LAYOUT_TEST_FONT')<>'' then F.Font.Name:=GetEnvironmentVariable('ZGUI_LAYOUT_TEST_FONT');
  WriteLn('Testing ',F.ClassName);Flush(Output);
  F.Show;for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;
  if F is TTournamentDialog then begin
   Inspect(F,F);
   if ParamStr(2)='--images' then begin
    Img:=F.GetFormImage;Png:=TPortableNetworkGraphic.Create;
    try Png.Assign(Img);Png.SaveToFile('/tmp/tournament-layout-initial.png');finally Png.Free;Img.Free;end;
   end;
  end;
  for Size:=0 to 2 do begin
   if Size=1 then F.Font.Size:=16 else F.Font.Size:=10;
   F.Width:=Max(F.Constraints.MinWidth,1000);F.Height:=Max(F.Constraints.MinHeight,800);
   for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;
   for Mode:=0 to 3 do begin
    case Mode of
     0:begin F.Width:=F.Constraints.MinWidth;F.Height:=F.Constraints.MinHeight;end;
     1:begin F.Width:=Max(1000,F.Constraints.MinWidth);F.Height:=Max(800,F.Constraints.MinHeight);end;
     2:begin F.Width:=Max(1500,F.Constraints.MinWidth);F.Height:=Max(950,F.Constraints.MinHeight);end;
     3:F.WindowState:=wsMaximized;
    end;
    for I:=1 to 5 do begin Application.ProcessMessages;Sleep(5);end;
    Inspect(F,F);
    if F is TPreferencesForm then
      for I:=0 to F.ComponentCount-1 do if F.Components[I] is TPageControl then begin
       Pages:=TPageControl(F.Components[I]);
       for Tab:=0 to Pages.PageCount-1 do begin
        Pages.ActivePageIndex:=Tab;Application.ProcessMessages;Inspect(F,F);
       end;
      end;
    if Mode=3 then F.WindowState:=wsNormal;
   end;
   if (ParamStr(1)='--images') or (ParamStr(2)='--images') then begin
    // Let the native window finish restoring from maximized before capturing it.
    for I:=1 to 5 do begin Application.ProcessMessages;Sleep(5);end;
    Img:=F.GetFormImage;Png:=TPortableNetworkGraphic.Create;
    try Png.Assign(Img);Png.SaveToFile('/tmp/layout-'+F.ClassName+'-'+IntToStr(Size)+'.png');finally Png.Free;Img.Free;end;
   end;
  end;
  if F is TMainForm then begin
   F.Font.Size:=10;F.WindowState:=wsNormal;
   // Simulated laptop work areas; do not change the user's desktop resolution.
   for I:=0 to 1 do begin
    if I=0 then F.SetBounds(0,0,1366,700) else F.SetBounds(0,0,1280,740);
    Application.ProcessMessages;TMainForm(F).RefreshLayout;Application.ProcessMessages;
    Check(F.Height<=700+40*I,'U26 main window fits laptop work-area height');
    Check(F.Width<=1366-86*I,'U26 main window fits laptop work-area width');
    Inspect(F,F);
   end;
  end;
  if F is TTournamentDialog then begin
   TEdit(F.FindComponent('TournamentStartingFEN')).Text:=
     TEdit(F.FindComponent('TournamentStartingFEN')).Text+' 12345678901234567890';
   for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;
   Inspect(F,F);
  end;
  F.AutoAdjustLayout(lapAutoAdjustForDPI,96,144,F.Width,Round(F.Width*1.5));
  for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;Inspect(F,F);
  F.AutoAdjustLayout(lapAutoAdjustForDPI,144,96,F.Width,Round(F.Width/1.5));
  for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;Inspect(F,F);
 finally F.Free;end;
end;
var Chess,Draughts:TGameVariant;I:Integer;
begin
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 try
  if ParamStr(1)='--main-only' then Test(TMainForm.Create(nil))
  else if ParamStr(1)='--tournament-only' then Test(TTournamentDialog.Create(nil,Chess)) else begin
  Test(TGameSetupForm.Create(nil,Chess));
  Test(TEngineEditForm.Create(nil,Draughts));
  Test(TEngineEditForm.Create(nil,Chess));
  Test(TPreferencesForm.Create(nil));
  Test(TEnginesDialog.Create(nil,Chess));
  Test(TTournamentDialog.Create(nil,Chess));
  Test(TTournamentDialog.Create(nil,Draughts));
  Test(TDatabaseForm.Create(nil,Chess));
  Test(TDatabaseForm.Create(nil,Draughts));
  Test(TPositionSetupForm.Create(nil,Chess));
  Test(TPositionSetupForm.Create(nil,Draughts));
  Test(TManualForm.Create(nil));Test(TPdnOpenDialog.Create(nil));
  Test(TScoreHistoryForm.Create(nil));
  Test(TGameSetupForm.Create(nil,Draughts));
  Test(TMainForm.Create(nil));
  end;
 finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
 WriteLn('Layout checks: ',Checks,' checks, ',Failures,' failures');
 if Failures>0 then Halt(1);
end.
