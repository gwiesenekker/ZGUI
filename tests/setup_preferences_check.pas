program setup_preferences_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,StdCtrls,ExtCtrls,
 ComCtrls,Menus,Graphics,Classes,SysUtils,StrUtils,Types,LCLType,LMessages,
 uGamePosition,uChessPosition,uGameGuiProfile,uPositionSetupAdapter,
 uChessPositionSetupAdapter,uDraughtsPositionSetupForm,uGameBoardControl,
 uChessBoardControl,uPreferences,uPreferencesForm,uScoreHistoryControl,uScoreHistoryForm,
 uPvBrowser,uMainForm,uGuiDialogs,Grids,uEngineEditForm,uEnginesDialog,uEngineRegistry,uEngineParamsJson;
type
 TChooser=class(TPreferencesForm)
 public Chosen:TColor;AcceptChoice:Boolean;
 protected function SelectColor(var AColor:TColor):Boolean; override;
 end;
 TReceiver=class
 public Called:Integer;Allow:Boolean;Fen:string;Prefs:TGuiPreferences;
  procedure Setup(Sender:TObject;const AFen:string;var Accepted:Boolean);
  procedure Preferences(Sender:TObject;const Value:TGuiPreferences);
 end;
var Checks:Integer=0;V:TChessVariant;SavedPrefs:TMemoryStream;HadPrefs:Boolean;
procedure Check(Value:Boolean;const Msg:string);
begin Inc(Checks);if not Value then raise Exception.Create(Msg);end;
function TChooser.SelectColor(var AColor:TColor):Boolean;
begin AColor:=Chosen;Result:=AcceptChoice;end;
procedure TReceiver.Setup(Sender:TObject;const AFen:string;var Accepted:Boolean);
begin Inc(Called);Fen:=AFen;Accepted:=Allow;end;
procedure TReceiver.Preferences(Sender:TObject;const Value:TGuiPreferences);
begin Inc(Called);Prefs:=Value;end;
function Button(F:TForm;const Caption:string):TButton;
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption=Caption) then Exit(TButton(F.Components[I]));
 raise Exception.Create('Missing button '+Caption);
end;
function Menu(F:TForm;const Caption:string):TMenuItem;
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TMenuItem) and
  (TMenuItem(F.Components[I]).Caption=Caption) then Exit(TMenuItem(F.Components[I]));
 raise Exception.Create('Missing menu '+Caption);
end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(10);end;end;
procedure ClickSquare(Board:TGameBoardControl;Square:Integer);
var X,Y:Integer;
begin
 for Y:=3 to Board.Height div 4-1 do for X:=3 to Board.Width div 4-1 do
  if Board.SquareAtPoint(X*4,Y*4)=Square then begin
   Board.OnMouseDown(Board,mbLeft,[],X*4,Y*4);Exit;
  end;
 raise Exception.Create('Square not reachable '+IntToStr(Square));
end;
procedure Adapters;
var A:TChessPositionSetupAdapter;Old,Fen:string;I:Integer;Raised:Boolean;
begin
 A:=TChessPositionSetupAdapter.Create;
 try
  Check(A.DraftFen=ChessStartingFEN,'Adapter starts at standard chess FEN');
  Check(A.PaletteCount=12,'Twelve chess pieces');
  for I:=0 to 11 do Check(Abs(A.PalettePiece(I))=I div 2+1,'Piece code for palette entry');
  A.Toggle(2,2);Check(Pos(' KQkq ',A.ValidatedFen)>0,'U14 knight edit retains castling');
  A.Toggle(8,4);Check(Pos(' Qkq ',A.ValidatedFen)>0,'U14 only impossible rook right removed');
  A.Toggle(8,4);Check(Pos(' Qkq ',A.ValidatedFen)>0,'Replacing rook never invents a right');
  A.Toggle(5,6);Check(Pos(' kq ',A.DraftFen)>0,'Missing white king drops white rights only');
  Raised:=False;try A.ValidatedFen;except on E:EConvertError do Raised:=True;end;
  Check(Raised,'Incomplete draft cannot become playable');A.Toggle(5,6);A.ValidatedFen;
  A.LoadFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 37');
  A.SetSide(gsBlack);Check(Pos(' b - - 0 37',A.DraftFen)>0,'Side edit clears EP and preserves fullmove');
  A.LoadFen('4k3/8/8/8/8/8/8/R3K3 b - - 17 37');
  Fen:=A.ValidatedFen;Old:=A.DraftFen;Raised:=False;
  try A.LoadFen('invalid');except on E:EConvertError do Raised:=True;end;
  Check(Raised and (A.DraftFen=Old),'Invalid import leaves draft unchanged');
  A.Toggle(1,4);Check(Pos(' 0 37',A.DraftFen)>0,'Placement resets halfmove and preserves fullmove');
  A.Clear;Check(A.DraftFen='8/8/8/8/8/8/8/8 w - - 0 1','Clear is an explicitly incomplete draft');
  A.Toggle(5,6);A.Toggle(61,-6);Check(A.ValidatedFen<>'','Completed raw draft validates through chess loader');
  A.Toggle(57,1);Raised:=False;try A.ValidatedFen;except on E:EConvertError do Raised:=True;end;
  Check(Raised,'Pawn on rank eight is rejected on Apply');
  A.LoadFen('7k/6Q1/5K2/8/8/8/8/8 b - - 0 1');Check(A.ValidatedFen<>'','Checkmate setup is valid');
  A.LoadFen('7k/5K2/6Q1/8/8/8/8/8 b - - 0 1');Check(A.ValidatedFen<>'','Stalemate setup is valid');
 finally A.Free;end;
end;
procedure DraftDialog;
var D:TPositionSetupForm;R:TReceiver;Edit:TEdit;Board:TGameBoardControl;
 I,J:Integer;Box:TPaintBox;Old:string;Overlap:TRect;
begin
 D:=TPositionSetupForm.Create(nil,DefaultGameVariant);R:=TReceiver.Create;
 try
  D.OnAccepted:=@R.Setup;D.StartSetup(ChessStartingFEN);D.Show;Pump;
  D.Width:=520;D.Height:=420;Pump;Board:=TGameBoardControl(D.FindComponent('SetupBoard'));
  Check(not Board.BoardFlipped,'Setup always uses White orientation');
  for I:=0 to 11 do begin
   Box:=TPaintBox(D.FindComponent('SetupPiece'+IntToStr(I)));
   Check((Box<>nil) and (Box.Width>=20) and (Box.Left>=0) and
    (Box.Top+Box.Height<=Box.Parent.ClientHeight),'Palette fits at minimum size');
   for J:=0 to I-1 do Check(not IntersectRect(Overlap,Box.BoundsRect,
     TPaintBox(D.FindComponent('SetupPiece'+IntToStr(J))).BoundsRect),'Palette tiles do not overlap');
  end;
  D.ScaleBy(3,2);Pump;
  for I:=0 to 11 do begin
   Box:=TPaintBox(D.FindComponent('SetupPiece'+IntToStr(I)));
   Check((Box.Width>=20) and (Box.Left>=0) and (Box.Top+Box.Height<=Box.Parent.ClientHeight),
    'Scaled chess palette fits');
  end;
  Edit:=TEdit(D.FindComponent('SetupFen'));
  Button(D,'Clear').Click;
  for I:=1 to 64 do begin ClickSquare(Board,I);ClickSquare(Board,I);end;
  Check(Edit.Text='8/8/8/8/8/8/8/8 w - - 0 1','All 64 squares editable in an incomplete draft');
  Button(D,'Start').Click;Old:=Edit.Text;
  J:=0;try D.StartSetup('invalid');except on E:EConvertError do J:=1;end;
  Check((J=1) and (Edit.Text=Old),'Invalid initial chess FEN never silently resets draft');
  Edit.Text:='half typed';Old:=Edit.Text;
  GuiTestConfirmationResult:=mrCancel;ClickSquare(Board,17);GuiTestConfirmationResult:=0;
  Check(Edit.Text=Old,'U16 Cancel retains typed FEN');
  ClickSquare(Board,17);Check(Edit.Text=Old,'U16 repeated board edit causes no modal prompt');
  GuiTestConfirmationResult:=mrOk;Button(D,'Paste FEN').Click;GuiTestConfirmationResult:=0;
  Check(Edit.Text=Old,'Invalid explicit import retains text');
  Button(D,'Start').Click;ClickSquare(Board,2);
  Check(Pos(' KQkq ',Edit.Text)>0,'Dialog edit uses U14 rights policy');
  Edit.Text:=' 4k3/8/8/8/8/8/8/R3K3 b - - 17 37 ';
  Old:=Edit.Text;R.Allow:=False;Button(D,'Apply').Click;
  Check(D.Visible and (Edit.Text=Old) and (R.Called=1),'U15 rejection leaves open draft/text');
  Check(R.Fen='4k3/8/8/8/8/8/8/R3K3 b - - 17 37','Apply reads typed FEN and canonicalizes candidate');
  R.Allow:=True;Button(D,'Apply').Click;Check(not D.Visible,'Accepted Apply hides dialog');
  D.Show;Button(D,'Clear').Click;GuiTestConfirmationResult:=mrOk;
  Button(D,'Apply').Click;GuiTestConfirmationResult:=0;
  Check(D.Visible and (R.Called=2),'Invalid draft does not invoke acceptance');
  Button(D,'Cancel').Click;Check(not D.Visible,'Cancel hides without callback');
 finally D.Free;R.Free;end;
end;
procedure PreferenceEditor;
var D:TChooser;R:TReceiver;P,Q:TGuiPreferences;C:TScoreHistoryColor;L:TStringList;
 I:Integer;
begin
 P:=DefaultGuiPreferences;
 for C:=Low(C) to High(C) do P.ScoreHistoryColors[C]:=RGBToColor(10+Ord(C),40,70);
 SaveGuiPreferences(P);LoadGuiPreferences(Q);
 for C:=Low(C) to High(C) do Check(P.ScoreHistoryColors[C]=Q.ScoreHistoryColors[C],'Palette persistence');
 L:=TStringList.Create;
 try
  L.Text:='{"score_history_engine_negative":"invalid","score_history_engine_nonnegative":"#123456"}';
  L.SaveToFile(PreferencesJsonFileName);LoadGuiPreferences(Q);
  Check(Q.ScoreHistoryColors[shcEngineNonnegative]=RGBToColor($12,$34,$56),'Custom colour loads');
  Check(Q.ScoreHistoryColors[shcEngineNegative]=DefaultScoreHistoryColors[shcEngineNegative],'Invalid colour retains default');
  Check(Q.ScoreHistoryColors[shcSelectedPly]=clGray,'Missing colour retains default');
 finally L.Free;end;
 D:=TChooser.Create(nil);R:=TReceiver.Create;
 try
  D.OnAccepted:=@R.Preferences;D.StartEdit(P);
  Check(TTabSheet(D.FindComponent('ScoreHistoryTab')).Caption='Score history','Dedicated preferences tab');
  for C:=Low(C) to High(C) do begin
   Check(TPanel(D.FindComponent('ScoreColorSwatch'+IntToStr(Ord(C)))).Caption='',
    'Score-history swatch contains colour only');
   D.Chosen:=RGBToColor(100+Ord(C),80,90);D.AcceptChoice:=True;
   TButton(D.FindComponent('ScoreColorChoose'+IntToStr(Ord(C)))).Click;
  end;
  D.AcceptChoice:=False;D.Chosen:=clYellow;
  TButton(D.FindComponent('ScoreColorChoose0')).Click;
  Button(D,'Save').Click;
  for C:=Low(C) to High(C) do Check(R.Prefs.ScoreHistoryColors[C]=RGBToColor(100+Ord(C),80,90),'Picker maps to independent score role');
  D.StartEdit(P);D.AcceptChoice:=True;D.Chosen:=clYellow;TButton(D.FindComponent('ScoreColorChoose0')).Click;
  I:=R.Called;Button(D,'Close').Click;Check(R.Called=I,'Cancel does not publish draft');
  D.StartEdit(P);Button(D,'Defaults').Click;Button(D,'Save').Click;
  for C:=Low(C) to High(C) do Check(R.Prefs.ScoreHistoryColors[C]=DefaultScoreHistoryColors[C],'Global Defaults restores palette');
  Check(R.Prefs.MainBoardDarkColor=DefaultGuiPreferences.MainBoardDarkColor,'Defaults still restores other preferences');
 finally D.Free;R.Free;end;
end;
procedure MainIntegration;
var M:TMainForm;D:TPositionSetupForm;F:TPreferencesForm;S,Pop:TScoreHistoryControl;
 I,J:Integer;Old,Typed:string;P:TGuiPreferences;C:TScoreHistoryColor;
 Memo:TMemo;B:TChessBoardControl;Browser:TPvBrowser;Pos:TChessPosition;
 Key:Word;Info:TLabel;SavedHandler:TKeyEvent;SavedClick:TNotifyEvent;
begin
 P:=DefaultGuiPreferences;SaveGuiPreferences(P);M:=TMainForm.Create(nil);D:=nil;S:=nil;
 try
  M.Show;Pump;M.LoadStandaloneFen('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
  Old:=M.ActiveGameTree.StartingFEN;Menu(M,'Setup position...').Click;
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TPositionSetupForm then D:=TPositionSetupForm(M.Components[I]);
  Check(D<>nil,'Existing main-window setup path enabled');
  Typed:=' 4k3/8/8/8/8/8/8/R3K3 w - - 0 38 ';
  TEdit(D.FindComponent('SetupFen')).Text:=Typed;
  GuiTestConfirmationResult:=mrCancel;Button(D,'Apply').Click;GuiTestConfirmationResult:=0;
  Check(D.Visible and (TEdit(D.FindComponent('SetupFen')).Text=Typed) and
   (M.ActiveGameTree.StartingFEN=Old),'U15 main replacement Cancel keeps tree and typed draft');
  GuiTestConfirmationResult:=mrYes;GuiTestFileDialogResult:=1;GuiTestFileName:=GetTempDir(False)+'zgui-setup-review/missing/save.pgn';
  try Button(D,'Apply').Click;finally GuiTestConfirmationResult:=0;GuiTestFileDialogResult:=-1;end;
  Check(D.Visible and (TEdit(D.FindComponent('SetupFen')).Text=Typed) and
   (M.ActiveGameTree.StartingFEN=Old),'U15 failed save keeps tree and typed draft');
  GuiTestConfirmationResult:=mrNo;Button(D,'Apply').Click;GuiTestConfirmationResult:=0;
  Check(not D.Visible and (M.ActiveGameTree.StartingFEN=Trim(Typed)),'Accepted draft uses existing tree replacement');
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TScoreHistoryControl then S:=TScoreHistoryControl(M.Components[I]);
  Check(S<>nil,'Existing embedded score history');S.PopupMenu.Items[0].Click;
  F:=nil;Menu(M,'&Preferences...').Click;
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TPreferencesForm then F:=TPreferencesForm(M.Components[I]);
  Check(F<>nil,'Existing Preferences path');
  // Deliver via the existing callback, keeping the score signature unchanged.
  for C:=Low(C) to High(C) do P.ScoreHistoryColors[C]:=RGBToColor(7,31+Ord(C),67);
  Old:=S.AnnotationsText;F.StartEdit(P);Button(F,'Save').Click;
  for C:=Low(C) to High(C) do Check(S.ScoreColors[C]=P.ScoreHistoryColors[C],'Main palette updates outside score signature');
  Check(S.AnnotationsText=Old,'Colour update does not reparse or change scores');
  Pop:=nil;
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TScoreHistoryForm then
   for J:=0 to TScoreHistoryForm(M.Components[I]).ComponentCount-1 do
    if TScoreHistoryForm(M.Components[I]).Components[J] is TScoreHistoryControl then
     Pop:=TScoreHistoryControl(TScoreHistoryForm(M.Components[I]).Components[J]);
  Check(Pop<>nil,'Existing popout');
  for C:=Low(C) to High(C) do Check(Pop.ScoreColors[C]=P.ScoreHistoryColors[C],'Open popout palette updates immediately');
  // Use actual LCL widget key dispatch: Application handlers and parent
  // KeyPreview execute before the memo. No direct browser OnKeyDown call.
  for I:=0 to 1 do begin
   if I=0 then Memo:=TMemo(M.FindComponent('EnginePvMemo')) else Memo:=TMemo(M.FindComponent('AnnotatorPvMemo'));
   B:=TChessBoardControl.Create(M);B.Parent:=M;B.Visible:=False;Info:=TLabel.Create(M);
   SavedHandler:=Memo.OnKeyDown;SavedClick:=Memo.OnClick;Browser:=TPvBrowser.Create(V,B,Info,Memo);Pos:=TChessPosition.Create;
   try
    Browser.SetData(Pos,0,ChessStartingFEN,'e2e4 e7e5','0','1','1');
    Memo.SetFocus;Check(M.ActiveControl=Memo,'PV memo has real focus');
    Key:=VK_LEFT;Memo.Perform(CN_KEYDOWN,Key,0);
    Browser.SetData(Pos,0,ChessStartingFEN,'d2d4','0','2','2');
    Check(PosEx('newer PV pending',Info.Caption)>0,'PV is frozen before Escape');
    Memo.Perform(CN_KEYDOWN,VK_ESCAPE,0);
    Check(PosEx('newer PV pending',Info.Caption)=0,'Escape passes form key preview to focused PV');
    Check(PosEx('d4',Memo.Text)>0,'Escape applies newest pending PV');
   finally Pos.Free;Browser.Free;Memo.OnKeyDown:=SavedHandler;Memo.OnClick:=SavedClick;B.Free;Info.Free;end;
  end;
 finally M.Free;end;
 M:=TMainForm.Create(nil);
 try
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TScoreHistoryControl then S:=TScoreHistoryControl(M.Components[I]);
  S.PopupMenu.Items[0].Click;Pop:=nil;
  for I:=0 to M.ComponentCount-1 do if M.Components[I] is TScoreHistoryForm then
   for J:=0 to TScoreHistoryForm(M.Components[I]).ComponentCount-1 do
    if TScoreHistoryForm(M.Components[I]).Components[J] is TScoreHistoryControl then Pop:=TScoreHistoryControl(TScoreHistoryForm(M.Components[I]).Components[J]);
  for C:=Low(C) to High(C) do Check(Pop.ScoreColors[C]=P.ScoreHistoryColors[C],'New popout inherits saved palette');
 finally M.Free;end;
end;
procedure CheckMeasuredColumn(Grid:TStringGrid;Col:Integer);
var BodyWidth,HeaderWidth,Margin:Integer;Column:TGridColumn;
begin
  if Col<Grid.FixedCols then begin
    BodyWidth:=MeasureGuiText(Grid.Cols[Col].Text,Grid.Font).cx;
    HeaderWidth:=MeasureGuiText(Grid.Cells[Col,0],Grid.TitleFont).cx;
  end else begin
    Column:=Grid.Columns[Col-Grid.FixedCols];
    BodyWidth:=MeasureGuiText(Grid.Cols[Col].Text,Column.Font).cx;
    HeaderWidth:=MeasureGuiText(Column.Title.Caption,Column.Title.Font).cx;
  end;
  if HeaderWidth>BodyWidth then BodyWidth:=HeaderWidth;
  Margin:=MeasureGuiText('MM',Grid.Font).cx;
  Check(Grid.ColWidths[Col]>=BodyWidth+Margin,'Column fits actual title and cell fonts plus margin');
end;

procedure EnginesDialogSizes;
var Engines:TExternalEngineList;D:TExternalEngineDefinition;Form:TEnginesDialog;
    Grid:TStringGrid;Saved:TMemoryStream;HadRegistry:Boolean;I,J,Col,OldPathWidth:Integer;
    HintText:string;
begin
  Saved:=TMemoryStream.Create;Engines:=TExternalEngineList.Create;Form:=nil;
  HadRegistry:=FileExists(EnginesJsonFileName);
  if HadRegistry then Saved.LoadFromFile(EnginesJsonFileName);
  try
    for I:=1 to 35 do begin
      D:=TExternalEngineDefinition.Create;D.Kind:=eekUci;
      D.ExePath:='/a/very/long/directory/which/should/not/determine/the/window/width/engine'+IntToStr(I)+'.exe';
      D.UciId:='Engine '+IntToStr(I);D.DxpId:='';Engines.Add(D);
    end;
    SaveExternalEngines(EnginesJsonFileName,Engines);Form:=TEnginesDialog.Create(nil,DefaultGameVariant);Grid:=nil;
    for I:=0 to Form.ComponentCount-1 do if Form.Components[I] is TStringGrid then Grid:=TStringGrid(Form.Components[I]);
    Check(Grid<>nil,'Engines list grid exists');Form.Show;Pump;
    Check((Grid.Cells[3,0]='') and (Grid.Columns[3].Title.Caption='DXP id'),
      'DXP header is stored separately from empty cell data');
    Grid.Columns[3].Title.Font.Size:=18;Grid.Columns[3].Title.Font.Style:=[fsBold];
    for J:=0 to 2 do begin
      Form.Font.Size:=8+5*J;Pump;
      Check((Grid.ColCount=4) and (Grid.FixedCols=0) and (Grid.RowCount=36),
        'Engines list retains four columns and all registrations');
      for Col:=1 to 3 do CheckMeasuredColumn(Grid,Col);
      Check((Grid.ColWidths[0]>0) and (Grid.GridWidth<=Grid.ClientWidth) and
        (Grid.ClientWidth-Grid.GridWidth<=4),'Path fills remaining width with vertical scrolling');
      OldPathWidth:=Grid.ColWidths[0];Form.Width:=Form.Width+150;Pump;
      Check(Grid.ColWidths[0]>OldPathWidth,'Path column expands with dialog');
      Form.Width:=Form.Width-150;Pump;
      Check(Grid.ColWidths[0]=OldPathWidth,'Path column shrinks with dialog');
      Check((goRowSelect in Grid.Options) and not (goEditing in Grid.Options) and
        (Grid.OnDblClick<>nil),'Existing row selection and edit action remain');
      Check(Grid.ShowHint and Assigned(Grid.OnGetCellHint),'Engine cell hints enabled');
      HintText:='';Grid.OnGetCellHint(Grid,0,1,HintText);
      Check(HintText=Engines[0].ExePath,'Clipped paths expose full text in hints');
      Check((Grid.Cells[0,1]=Engines[0].ExePath) and (Grid.Cells[2,1]=Engines[0].UciId),
        'Layout keeps complete path and identity data');
    end;
    FreeAndNil(Form);Engines.Clear;SaveExternalEngines(EnginesJsonFileName,Engines);
    Form:=TEnginesDialog.Create(nil,DefaultGameVariant);Form.Font.Size:=18;Form.Show;Pump;Grid:=nil;
    for I:=0 to Form.ComponentCount-1 do if Form.Components[I] is TStringGrid then Grid:=TStringGrid(Form.Components[I]);
    Check(Grid<>nil,'Empty engines list grid exists');
    for Col:=1 to 3 do CheckMeasuredColumn(Grid,Col);
    Check(Grid.GridWidth<=Grid.ClientWidth,'Empty list titles keep the grid within client width');
  finally
    Form.Free;Engines.Free;
    if HadRegistry then Saved.SaveToFile(EnginesJsonFileName) else DeleteFile(EnginesJsonFileName);
    Saved.Free;
  end;
end;

procedure MeasuredDialogSizes;
var Font:TFont;Bitmap:TBitmap;One,Two,Multi:TSize;I,J,Col,OldValueWidth:Integer;
    Main:TMainForm;Log:TMemo;Editor:TEngineEditForm;Grid:TStringGrid;
    Definition:TExternalEngineDefinition;Params:TEngineParamArray;Name,ParamFile,LongName:string;
begin
  Font:=TFont.Create;Bitmap:=TBitmap.Create;Main:=nil;Editor:=nil;
  Definition:=TExternalEngineDefinition.Create;
  Name:=GetTempFileName(GetTempDir,'zsz');ParamFile:=EngineParamsFileName(Name);
  try
    Font.Name:='DejaVu Sans';Font.Size:=11;Bitmap.Canvas.Font.Assign(Font);
    One:=MeasureGuiText('Ag',Font);Two:=MeasureGuiText('Ag'+#10,Font);
    Check((One.cx=Bitmap.Canvas.TextWidth('Ag')) and
      (Two.cy=2*Bitmap.Canvas.TextHeight('Ag')),'Text/font helper includes a trailing empty line');
    Multi:=MeasureGuiText('Long option name'+#13#10+'i',Font);
    Check((Multi.cx=Bitmap.Canvas.TextWidth('Long option name')) and
      (Multi.cy=Two.cy),'Text/font helper uses longest explicit line and accepts CRLF');
    Multi:=MeasureGuiText('Ag'+#13+'Ag',Font);Check(Multi.cy=Two.cy,'Text/font helper accepts CR-only lines');
    Multi:=MeasureGuiText('',Font);Check((Multi.cx=0) and (Multi.cy=0),'Empty text has zero extent');
    Main:=TMainForm.Create(nil);Main.Show;Pump;Log:=nil;
    for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TMemo then
      if Pos('Annotator closed',TMemo(Main.Components[I]).Text)>0 then Log:=TMemo(Main.Components[I]);
    Check(Log<>nil,'Annotator status memo exists');
    for J:=0 to 2 do begin
      Main.Font.Size:=8+5*J;Main.Width:=Main.Width+1;Pump;
      Bitmap.Canvas.Font.Assign(Log.Font);
      Check(Log.ClientHeight>=2*Bitmap.Canvas.TextHeight('Ag'),'Annotator log retains two readable text lines');
      Check(Log.Height>=TMemo(Main.FindComponent('AnnotatorPvMemo')).Height,'Annotator log is at least the No PV height');
      Check(Log.Top+Log.Height<=Log.Parent.ClientHeight,'Annotator log stays inside its allocated panel');
    end;
    Definition.Kind:=eekUci;Definition.ExePath:=Name;
    LongName:='An unusually long engine parameter name used to check measured column width';
    Params:=nil;AddOrUpdateParam(Params,LongName,'string','value',False);
    SaveEngineParamsToJson(ParamFile,'uci',Params);Editor:=TEngineEditForm.Create(nil,DefaultGameVariant);
    Editor.Font.Size:=16;Editor.LoadEngine(Definition);Grid:=nil;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TStringGrid then Grid:=TStringGrid(Editor.Components[I]);
    Check(Grid<>nil,'Engine parameter grid exists');Bitmap.Canvas.Font.Assign(Grid.Font);
    Check(Grid.ColWidths[0]>Bitmap.Canvas.TextWidth(LongName),'Parameter name column measures longest value plus margin');
    Params:=nil;
    for I:=1 to 40 do AddOrUpdateParam(Params,'option'+IntToStr(I),'long_parameter_type','editable value',False);
    SaveEngineParamsToJson(ParamFile,'uci',Params);
    Editor.Width:=1400;Editor.Show;Pump;
    for J:=0 to 2 do begin
      Editor.Font.Size:=8+5*J;Editor.LoadEngine(Definition);Pump;
      Check((Grid.ColCount=3) and (Grid.FixedCols=1),'Filling columns preserves three columns and the fixed name column');
      for Col:=0 to 1 do CheckMeasuredColumn(Grid,Col);
      Check((Grid.ColWidths[2]>0) and (Grid.GridWidth<=Grid.ClientWidth) and
        (Grid.ClientWidth-Grid.GridWidth<=4),'Value column fills remaining usable client width with vertical scrolling');
      OldValueWidth:=Grid.ColWidths[2];Editor.Width:=Editor.Width-150;Pump;
      Check((Grid.ColWidths[2]<OldValueWidth) and (Grid.GridWidth<=Grid.ClientWidth),
        'Value column shrinks with dialog without horizontal overflow');
      Grid.Row:=1;Grid.Col:=2;Grid.EditorMode:=True;Pump;
      Check((Grid.LeftCol=Grid.FixedCols) and (Grid.CellRect(2,1).Right<=Grid.ClientWidth),
        'Editing the value keeps all columns visible');
      Grid.Cells[2,1]:='changed value';Grid.EditorMode:=False;
      Check(Grid.Cells[2,1]='changed value','Value remains editable with filling columns');
      Editor.Width:=1400;Pump;
      Check(Grid.ColWidths[2]=OldValueWidth,'Value column expands when dialog width is restored');
    end;
  finally Editor.Free;Main.Free;Definition.Free;Bitmap.Free;Font.Free;DeleteFile(ParamFile);DeleteFile(Name);end;
end;

begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 SavedPrefs:=TMemoryStream.Create;HadPrefs:=FileExists(PreferencesJsonFileName);
 if HadPrefs then SavedPrefs.LoadFromFile(PreferencesJsonFileName);
 V:=TChessVariant.Create;RegisterDefaultGameVariant(V);RegisterGameGuiProfile(V,ChessGuiProfile);
 try Adapters;DraftDialog;PreferenceEditor;MainIntegration;MeasuredDialogSizes;EnginesDialogSizes;
  WriteLn('Setup and score preferences checks passed (',Checks,' checks)');
 finally
  RegisterDefaultGameVariant(nil);V.Free;
  if HadPrefs then SavedPrefs.SaveToFile(PreferencesJsonFileName) else DeleteFile(PreferencesJsonFileName);
  SavedPrefs.Free;
 end;
end.
