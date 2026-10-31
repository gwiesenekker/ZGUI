program init_colour_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,
 ExtCtrls,Graphics,ComCtrls,Math,uEngineEditForm,uEngineRegistry,uEngineParamsJson,
 uPreferencesForm,uPreferences,uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,uGuiDialogs;
type
 TTestPreferences=class(TPreferencesForm)
 protected function SelectColor(var AColor:TColor):Boolean; override;
 end;
 TErrors=class
  procedure Report(Sender:TObject;E:Exception);
 end;
function TTestPreferences.SelectColor(var AColor:TColor):Boolean;
begin AColor:=clLime;Result:=True;end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
procedure Click(F:TForm;const Caption:string);
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption=Caption) then begin TButton(F.Components[I]).Click;Exit;end;
 raise Exception.Create('Button missing: '+Caption);
end;
var D:TExternalEngineDefinition;F:TEngineEditForm;M:TMemo;P,Loaded:TEngineParamArray;
 Pref:TTestPreferences;Panel:TPanel;C:TCheckBox;Pages:TPageControl;
 Edits:TGamePreferencesEdits;I,J,K,N,Size,W,H:Integer;Errors:TErrors;Bitmap:TBitmap;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 D:=TExternalEngineDefinition.Create;F:=nil;Pref:=nil;
 try
  D.ExePath:=ExpandFileName(ParamStr(0));D.Kind:=eekHub;D.InitText:='';
  if ParamStr(1)<>'--preferences-only' then begin
  P:=nil;AddOrUpdateParam(P,'gui-hub-init','string','',False);
  SaveEngineParamsToJson(EngineParamsFileName(D.ExePath),'hub',P);
  F:=TEngineEditForm.Create(nil,RegisteredGame(1));F.LoadEngine(D);F.Show;Pump;
  M:=TMemo(F.FindComponent('HubInitializationMemo'));
  Check((M<>nil) and M.IsVisible,'Existing initialization memo visible for Hub');
  Check(Trim(M.Text)='init','Saved blank Hub init defaults to init');
  M.Text:='set-param name=threads value=1'+LineEnding+'init';
  Click(F,'Launched correctly');
  LoadEngineParamsFromJson(EngineParamsFileName(D.ExePath),'hub',Loaded);
  Check(Trim(EngineParamValue(Loaded,'gui-hub-init',''))=Trim(M.Text),'Custom initialization persists');
  F.LoadEngine(D);Check(Pos('set-param',M.Text)=1,'Custom initialization reloads');
  M.Clear;Click(F,'Launched correctly');
  LoadEngineParamsFromJson(EngineParamsFileName(D.ExePath),'hub',Loaded);
  Check(Trim(EngineParamValue(Loaded,'gui-hub-init',''))='init','Saving cleared Hub init restores default');
  D.Kind:=eekUci;D.InitText:='';F.LoadEngine(D);F.Show;Pump;
  Check(not M.IsVisible,'Hub initialization hidden for UCI');
  Check(Trim(M.Text)='','UCI remains without Hub init command');
  D.Kind:=eekDxp;P:=nil;AddOrUpdateParam(P,'gui-engine-type','string','dxp',False);
  SaveEngineParamsToJson(EngineParamsFileName(D.ExePath),'dxp',P);
  F.LoadEngine(D);Pump;Check(not M.IsVisible,'Hub initialization hidden for DXP');
  FreeAndNil(F);
  end;
  SetLength(Edits,2);
  Edits[0].GameId:='chess';Edits[1].GameId:='draughts';
  for J:=0 to 1 do Edits[J].Preferences:=DefaultGuiPreferences;
  Pref:=TTestPreferences.Create(nil);Pref.StartGameEdits(Edits,'chess');Pref.Show;Pump;
  Pages:=nil;
  for I:=0 to Pref.ComponentCount-1 do if Pref.Components[I] is TPageControl then Pages:=TPageControl(Pref.Components[I]);
  Check(Pages<>nil,'Preferences pages exist');
  for J:=0 to 1 do begin
   for I:=0 to Pref.ComponentCount-1 do if (Pref.Components[I] is TComboBox) and
    (TComboBox(Pref.Components[I]).Name='PreferencesGameSelector') then begin
     TComboBox(Pref.Components[I]).ItemIndex:=J;TComboBox(Pref.Components[I]).OnChange(Pref.Components[I]);
    end;
   for Size:=0 to 1 do begin
    if Size=0 then Pref.Font.Size:=10 else Pref.Font.Size:=16;
    for K:=0 to Pages.PageCount-1 do begin
     Pages.ActivePageIndex:=K;Pump;N:=0;
     for I:=0 to Pref.ComponentCount-1 do begin
      if (Pref.Components[I] is TPanel) and (TPanel(Pref.Components[I]).BevelOuter=bvLowered) and
       TPanel(Pref.Components[I]).IsVisible then begin
       Panel:=TPanel(Pref.Components[I]);Inc(N);
       Check((Panel.Width>=20) and (Panel.Height>=16),'Colour preview has usable dimensions');
       Check((Panel.Caption='') and not Panel.ParentBackground,'Colour preview paints its own colour without text');
       Bitmap:=TBitmap.Create;
       try
        Bitmap.SetSize(Panel.Width,Panel.Height);Panel.PaintTo(Bitmap.Canvas,0,0);
        Check(ColorToRGB(Bitmap.Canvas.Pixels[Panel.Width div 2,Panel.Height div 2])=ColorToRGB(Panel.Color),'Preview pixels show the configured colour');
       finally Bitmap.Free;end;
      end;
      if (Pref.Components[I] is TCheckBox) and (TCheckBox(Pref.Components[I]).Caption='Italic') then begin
       C:=TCheckBox(Pref.Components[I]);W:=0;H:=0;C.GetPreferredSize(W,H,True);
       Check(C.Width>=W+Max(4,MeasureGuiText('M',C.Font).cx div 2),'Italic label has native width plus padding');
      end;
     end;
     if Pages.ActivePage.Caption<>'Evaluation' then Check(N>0,'Colour previews present on colour/notation pages');
    end;
   end;
   Panel:=TPanel(Pref.FindComponent('ScoreColorSwatch0'));
   Check(Panel.Color=Edits[J].Preferences.ScoreHistoryColors[shcEngineNonnegative],'Game selection restores its configured preview colour');
   for I:=0 to Pref.ComponentCount-1 do
    if (Pref.Components[I] is TButton) and (TButton(Pref.Components[I]).Name='ScoreColorChoose0') then
     TButton(Pref.Components[I]).Click;
   Check(Panel.Color=clLime,'Chosen colour immediately updates the preview');
  end;
  FreeAndNil(Pref);
  WriteLn('Hub init / colour preview checks passed (',Checks,' checks)');
 finally
  Pref.Free;F.Free;DeleteFile(EngineParamsFileName(D.ExePath));D.Free;
  ClearRegisteredGames;Application.OnException:=nil;Errors.Free;
 end;
end.
