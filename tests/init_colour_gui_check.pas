program init_colour_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,
 ExtCtrls,Graphics,ComCtrls,Math,Grids,Types,uEngineEditForm,uEngineRegistry,uEngineParamsJson,
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
procedure FakeHub;
var Line:string;Trace:TStringList;Initialized:Boolean;
begin
 Trace:=TStringList.Create;Initialized:=False;
 try
  while not EOF(Input) do begin
   ReadLn(Line);Trace.Add(Line);Trace.SaveToFile(ParamStr(2));
   if Line='hub' then WriteLn('wait')
   else if Line='init' then begin
    if Initialized then Halt(4);
    Initialized:=True;WriteLn('ready');
   end else if Line='quit' then begin
    if not Initialized then Halt(3);
    Break;
   end;
   Flush(Output);
  end;
 finally Trace.Free;end;
end;
function InitRow(F:TForm;out Grid:TStringGrid):Integer;
var I:Integer;
begin
 Grid:=nil;Result:=-1;
 for I:=0 to F.ComponentCount-1 do if F.Components[I] is TStringGrid then Grid:=TStringGrid(F.Components[I]);
 if Grid=nil then Exit;
 for I:=1 to Grid.RowCount-1 do if Grid.Cells[0,I]='gui-hub-init' then Exit(I);
end;
procedure Click(F:TForm;const Caption:string);
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption=Caption) then begin TButton(F.Components[I]).Click;Exit;end;
 raise Exception.Create('Button missing: '+Caption);
end;
var D:TExternalEngineDefinition;F:TEngineEditForm;M:TMemo;P,Loaded:TEngineParamArray;
 Grid:TStringGrid;Row:Integer;
 Pref:TTestPreferences;Panel:TPanel;C:TCheckBox;Pages:TPageControl;
 Edits:TGamePreferencesEdits;I,J,K,N,Size,W,H:Integer;Errors:TErrors;Bitmap:TBitmap;Trace:TStringList;TraceName:string;
 Ancestor:TWinControl;Location:TPoint;
begin
 if ParamStr(1)='--fake-hub-init' then begin FakeHub;Halt(0);end;
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 D:=TExternalEngineDefinition.Create;F:=nil;Pref:=nil;
 try
  D.ExePath:=ExpandFileName(ParamStr(0));D.Kind:=eekHub;D.InitText:='quit';
  if ParamStr(1)<>'--preferences-only' then begin
   TraceName:=GetTempFileName(GetTempDir,'hubinit');
   D.Arguments:='--fake-hub-init "'+TraceName+'"';
   P:=nil;AddOrUpdateParam(P,'gui-hub-init','string','quit',False);
   AddOrUpdateParam(P,'gui-future-setting','string','preserved',False);
   SaveEngineParamsToJson(EngineParamsFileName(D.ExePath),'hub',P);
   F:=TEngineEditForm.Create(nil,RegisteredGame(1));F.LoadEngine(D);F.Show;Pump;
   M:=TMemo(F.FindComponent('HubInitializationMemo'));Row:=InitRow(F,Grid);
   Check((Row<0) and not M.IsVisible,'Retired gui-hub-init has no Hub editor control');
   Check(not EngineParamShouldSendToHub('gui-hub-init'),'Legacy GUI setting is not an engine option');
   Click(F,'Launch engine');Click(F,'Launched correctly');
   Trace:=TStringList.Create;
   try
    Trace.LoadFromFile(TraceName);N:=0;
    for I:=0 to Trace.Count-1 do if Trace[I]='init' then Inc(N);
    Check((N=1) and (Trace.IndexOf('init')<Trace.IndexOf('quit')),'Editor sends one mandatory init before quitting');
    Check(Pos('gui-hub-init',Trace.Text)=0,'Retired setting is not sent on the Hub wire');
   finally Trace.Free;DeleteFile(TraceName);end;
   LoadEngineParamsFromJson(EngineParamsFileName(D.ExePath),'hub',Loaded);
   Check(EngineParamValue(Loaded,'gui-hub-init','absent')='absent','Saving retires old gui-hub-init metadata');
   Check(EngineParamValue(Loaded,'gui-future-setting','')='preserved','Other GUI metadata survives');
   F.LoadEngine(D);Check(InitRow(F,Grid)<0,'Retired initialization setting does not return on reload');
   D.Kind:=eekUci;D.InitText:='';F.LoadEngine(D);F.Show;Pump;
   Check((InitRow(F,Grid)<0) and not M.IsVisible,'Legacy Hub initialization hidden for UCI');
   Check(Trim(M.Text)='','UCI remains without Hub init command');
   D.InitText:='setoption name Hash value 32';F.LoadEngine(D);
   Check(Trim(M.Text)=D.InitText,'Existing UCI initialization commands preserved');
   D.Kind:=eekDxp;P:=nil;AddOrUpdateParam(P,'gui-engine-type','string','dxp',False);
   SaveEngineParamsToJson(EngineParamsFileName(D.ExePath),'dxp',P);
   F.LoadEngine(D);Pump;Check((InitRow(F,Grid)<0) and not M.IsVisible,'No Hub initialization option for DXP');
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
    Pref.Height:=Pref.Constraints.MinHeight;
    for K:=0 to Pages.PageCount-1 do begin
     Pages.ActivePageIndex:=K;Pump;N:=0;
     for I:=0 to Pref.ComponentCount-1 do begin
      if (Pref.Components[I] is TPanel) and (TPanel(Pref.Components[I]).BevelOuter=bvLowered) and
       TPanel(Pref.Components[I]).IsVisible then begin
       Panel:=TPanel(Pref.Components[I]);Inc(N);
       Ancestor:=Panel.Parent;
       while Ancestor<>nil do begin
        if Ancestor is TScrollBox then TScrollBox(Ancestor).ScrollInView(Panel);
        Ancestor:=Ancestor.Parent;
       end;
       Pump;
       Ancestor:=Panel.Parent;
       while Ancestor<>nil do begin
        if Ancestor is TScrollBox then begin
         Location:=Ancestor.ScreenToClient(Panel.ClientToScreen(Point(0,0)));
         Check((Location.Y>=0) and (Location.Y+Panel.Height<=Ancestor.ClientHeight),
           'Captured preview is completely inside its scroll viewport');
        end;
        Ancestor:=Ancestor.Parent;
       end;
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
