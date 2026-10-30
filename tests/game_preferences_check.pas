program game_preferences_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,cwstring,{$ENDIF} Interfaces,Forms,Classes,SysUtils,
  Controls,StdCtrls,Graphics,Dialogs,Menus,FPJSON,JSONParser,
  uPreferences,uPreferencesForm,uNotationStyles,uGuiDialogs,uMainForm,uGameBoardControl,
  uGameGuiProfile,uChessPosition,uDraughtsPosition,uGamePosition;
type
  TReceiver=class
    Count:Integer;
    procedure Accepted(Sender:TObject;const Edits:TGamePreferencesEdits);
  end;
procedure TReceiver.Accepted(Sender:TObject;const Edits:TGamePreferencesEdits);
begin Inc(Count,Length(Edits));SaveGamePreferences(Edits);end;
procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;
function Menu(Main:TMainForm;const Caption:string):TMenuItem;
var I:Integer;
begin
  for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TMenuItem then
    if TMenuItem(Main.Components[I]).Caption=Caption then Exit(TMenuItem(Main.Components[I]));
  raise Exception.Create('Missing menu '+Caption);
end;
var D:TPreferencesForm;R:TReceiver;Edits:TGamePreferencesEdits;
  A,B,Legacy:TGuiPreferences;Lines:TStringList;Data:TJSONData;
  Selector:TComboBox;Bold:TCheckBox;Main:TMainForm;Popout:TGameBoardControl;I,J:Integer;Chess,Draughts:TGameVariant;
begin
  RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
  Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
  RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
  Lines:=TStringList.Create;D:=nil;R:=nil;Main:=nil;
  try
    Lines.Text:='{"notation_font_name":"Courier New","notation_font_size":13,"main_board_light":"#123456","custom":17,"last_game":"chess"}';
    Lines.SaveToFile(PreferencesJsonFileName);
    LoadGuiPreferences(Legacy);
    A:=Legacy;A.NotationFontSize:=19;A.MainBoardLightColor:=clRed;
    A.ScoreHistoryColors[shcSelectedPly]:=clGreen;A.EvaluationMaxScore:=7;
    SaveGuiPreferences(A,'chess');LoadGuiPreferences(B,'draughts');
    Check(SameGuiPreferences(B,Legacy),'Root-only fallback remains unchanged for draughts');
    LoadGuiPreferences(B,'chess');Check(SameGuiPreferences(A,B),'All appearance fields round trip');
    Lines.LoadFromFile(PreferencesJsonFileName);Data:=GetJSON(Lines.Text);
    try
      Check(TJSONObject(Data).Get('custom',0)=17,'Unknown root key retained');
      Check(TJSONObject(Data).Get('notation_font_size',0)=13,'Legacy font retained');
      Check(TJSONObject(Data).Get('last_game','')='chess','Last game retained');
    finally Data.Free;end;
    SetLength(Edits,2);Edits[0].GameId:='chess';Edits[0].Preferences:=A;
    Edits[1].GameId:='draughts';Edits[1].Preferences:=Legacy;
    R:=TReceiver.Create;D:=TPreferencesForm.Create(nil);D.OnGamesAccepted:=@R.Accepted;
    D.StartGameEdits(Edits,'chess');D.Show;Application.ProcessMessages;
    Selector:=TComboBox(D.FindComponent('PreferencesGameSelector'));
    Bold:=TCheckBox(D.FindComponent('NotationBold0'));Bold.Checked:=not Bold.Checked;
    Selector.ItemIndex:=1;Selector.OnChange(Selector);
    Bold.Checked:=not Bold.Checked;
    Selector.ItemIndex:=0;Selector.OnChange(Selector);
    Check(Bold.Checked<>A.NotationStyles[TNotationStyle(0)].Bold,'Chess draft survives section changes');
    TButton(D.FindComponent('PreferencesApply')).Click;
    Check(R.Count=2,'One Save accepts both changed sections');
    LoadGuiPreferences(A,'chess');LoadGuiPreferences(B,'draughts');
    Check(A.NotationStyles[TNotationStyle(0)].Bold<>Edits[0].Preferences.NotationStyles[TNotationStyle(0)].Bold,'Chess draft saved');
    Check(B.NotationStyles[TNotationStyle(0)].Bold<>Edits[1].Preferences.NotationStyles[TNotationStyle(0)].Bold,'Draughts draft saved');
    Bold.Checked:=not Bold.Checked;Selector.ItemIndex:=1;Selector.OnChange(Selector);
    TButton(D.FindComponent('PreferencesDefaults')).Click;
    GuiTestConfirmationResult:=mrCancel;D.Close;
    Check(D.Visible,'Close Cancel retains draft window');
    Selector.ItemIndex:=0;Selector.OnChange(Selector);
    Check(Bold.Checked<>A.NotationStyles[TNotationStyle(0)].Bold,'Close Cancel retains other draft');
    GuiTestConfirmationResult:=mrYes;D.Close;Check(not D.Visible,'Discard closes editor');
    LoadGuiPreferences(Legacy,'chess');Check(SameGuiPreferences(A,Legacy),'Discard does not save');
    FreeAndNil(D);
    // Exact U22: open in chess, switch main window to draughts, then Save.
    Main:=TMainForm.Create(nil);Main.Show;Application.ProcessMessages;
    Main.SelectGameVariant(Chess);Menu(Main,'&Preferences...').Click;
    for I:=0 to Main.ComponentCount-1 do
      if Main.Components[I] is TPreferencesForm then D:=TPreferencesForm(Main.Components[I]);
    Check(D<>nil,'Main window owns preferences editor');
    Bold:=TCheckBox(D.FindComponent('NotationBold0'));Bold.Checked:=not Bold.Checked;
    Main.SelectGameVariant(Draughts);
    TButton(D.FindComponent('PreferencesApply')).Click;
    LoadGuiPreferences(Legacy,'draughts');Check(SameGuiPreferences(B,Legacy),'U22 leaves draughts preferences unchanged');
    LoadGuiPreferences(Legacy,'chess');Check(Legacy.NotationStyles[TNotationStyle(0)].Bold<>A.NotationStyles[TNotationStyle(0)].Bold,'U22 saves explicit chess layer');
    // A visible chess popout must retain its old theme while chess is inactive.
    Main.SelectGameVariant(Chess);Menu(Main,'Pop out mini-board').Click;
    Popout:=nil;
    for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TForm then
      if TForm(Main.Components[I]).Caption='Mini-board' then
        for J:=0 to TForm(Main.Components[I]).ComponentCount-1 do
          if TForm(Main.Components[I]).Components[J] is TGameBoardControl then
            Popout:=TGameBoardControl(TForm(Main.Components[I]).Components[J]);
    Check(Popout<>nil,'Chess popout created');
    Check(Popout.BoardLightColor=clRed,'Chess popout starts with chess colour');
    TButton(D.FindComponent('PreferencesDefaults')).Click;
    Main.SelectGameVariant(Draughts);
    TButton(D.FindComponent('PreferencesApply')).Click;
    Check(Popout.BoardLightColor=clRed,'Inactive chess popout is not repainted on Save');
    Check(TGameBoardControl(Main.FindComponent('MainBoard')).BoardLightColor=B.MainBoardLightColor,
      'Saving chess defaults preserves active draughts board');
    Main.SelectGameVariant(Chess);
    Check(Popout.BoardLightColor=DefaultGuiPreferences.MainBoardLightColor,
      'Chess popout adopts saved defaults on activation');
    D:=nil;FreeAndNil(Main);
    WriteLn('PASS: separate game preferences, migration, drafts, close and U22');
  finally D.Free;Main.Free;R.Free;Lines.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
