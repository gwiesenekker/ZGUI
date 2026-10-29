program chess_database_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,StdCtrls,ExtCtrls,Menus,
 Grids,Graphics,Classes,SysUtils,Types,uGamePosition,uChessPosition,uDraughtsPosition,
 uChessBoardControl,uGameBoardControl,uDatabaseForm,uMainForm,uGuiDialogs,uPdnOpenDialog,
 uGameTree,uPreferences,uGameGuiProfile,uDraughtsPositionSetupForm;
var Checks:Integer=0;V:TChessVariant;Main:TMainForm;F:TDatabaseForm;Browser:TPdnOpenDialog;
 Games,Results:TStringGrid;Board:TGameBoardControl;FenEdit:TEdit;Data:TStringList;
 Name,DbName,Before:string;I,ColumnGrowth:Integer;RootId:Int64;Setup:TPositionSetupForm;SetupFen:TEdit;OwnedDatabase:TDatabaseForm;Bounds:array of TRect;C:TControl;TextCanvas:TControlCanvas;
procedure Check(B:Boolean;const Text:string);
begin Inc(Checks);if not B then raise Exception.Create(Text);end;
procedure Button(Form:TForm;const Text:string);
var I:Integer;
begin
 for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TButton) and
   (TButton(Form.Components[I]).Caption=Text) then begin TButton(Form.Components[I]).Click;Exit;end;
 raise Exception.Create('Missing button '+Text);
end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
function Menu(Form:TForm;const Text:string):TMenuItem;
var I:Integer;
begin
 for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TMenuItem) and
   (TMenuItem(Form.Components[I]).Caption=Text) then Exit(TMenuItem(Form.Components[I]));
 raise Exception.Create('Missing menu '+Text);
end;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 V:=TChessVariant.Create;Name:=GetTempFileName(GetTempDir,'zdbgui');DbName:=Name+'.db';Data:=TStringList.Create;
 Main:=nil;F:=nil;
 try
  // Same control geometry except the explicitly requested wider chess FEN column.
  RegisterDefaultGameVariant(DraughtsVariant);F:=TDatabaseForm.Create(nil);F.Show;Pump;
  SetLength(Bounds,F.ComponentCount);
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TControl then Bounds[I]:=TControl(F.Components[I]).BoundsRect;
  F.Free;F:=nil;RegisterDefaultGameVariant(V);F:=TDatabaseForm.Create(nil);F.Show;Pump;
  Check(F.ComponentCount=Length(Bounds),'Existing component count');
  Board:=nil;
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TGameBoardControl then
   Board:=TGameBoardControl(F.Components[I]);
  ColumnGrowth:=0;
  for I:=0 to F.ComponentCount-1 do if F.Components[I]=Board.Parent then
   ColumnGrowth:=Board.Parent.Width-(Bounds[I].Right-Bounds[I].Left);
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TControl then begin
   C:=TControl(F.Components[I]);
   if C=Board.Parent then Dec(Bounds[I].Left,ColumnGrowth)
   else if C.Parent=Board.Parent then Inc(Bounds[I].Right,ColumnGrowth)
   else if (C is TStringGrid) and (TStringGrid(C).ColCount=5) then Dec(Bounds[I].Right,ColumnGrowth);
   Check(EqualRect(Bounds[I],C.BoundsRect),'Only requested column width affects bounds '+IntToStr(I));
  end;
  Board:=nil;Games:=nil;Results:=nil;FenEdit:=nil;
  for I:=0 to F.ComponentCount-1 do begin
   if F.Components[I] is TGameBoardControl then Board:=TGameBoardControl(F.Components[I]);
   if F.Components[I] is TStringGrid then
    if TStringGrid(F.Components[I]).ColCount=7 then Games:=TStringGrid(F.Components[I]) else Results:=TStringGrid(F.Components[I]);
   if (F.Components[I] is TEdit) and (TEdit(F.Components[I]).Text=ChessStartingFEN) then FenEdit:=TEdit(F.Components[I]);
  end;
  Check(Board is TChessBoardControl,'Existing board factory supplies chess');Check(FenEdit<>nil,'Existing FEN field supplies chess');
  TextCanvas:=TControlCanvas.Create;
  try
   TextCanvas.Control:=FenEdit;TextCanvas.Font.Assign(FenEdit.Font);
   Check(TextCanvas.TextWidth(FenEdit.Text)+16<=FenEdit.ClientWidth,Format('Complete starting FEN fits: text=%d, client=%d',[TextCanvas.TextWidth(FenEdit.Text),FenEdit.ClientWidth]));
  finally TextCanvas.Free;end;
  Check(Results.ClientWidth>=420,'Default continuation grid retains room for its columns');
  Check(Menu(F,'Import PGN...')<>nil,'Existing import action uses PGN');
  Data.Text:='[Event "First"] 1.e4 {note} e5 (1...c5 $5) *'+#10+'[Event "Second"] 1.d4 d5 *';Data.SaveToFile(Name);
  F.CreateDatabase(DbName);F.ImportPdnFile(Name);Pump;
  Check(Games.RowCount=3,'Existing worker/progress import completes');
  F.SetSearchFEN(ChessStartingFEN);F.SearchCurrentPosition;
  Check(Results.RowCount=3,'Existing continuation grid populated');
  Check(((Results.Cells[0,1]='e4') and (Results.Cells[0,2]='d4')) or
    ((Results.Cells[0,2]='e4') and (Results.Cells[0,1]='d4')),'Continuation grid displays SAN');
  Main:=TMainForm.Create(nil);Main.Show;Pump;
  GuiTestFileDialogResult:=1;GuiTestFileName:=Name;Menu(Main,'&Open PGN...').Click;
  Browser:=nil;for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TPdnOpenDialog then Browser:=TPdnOpenDialog(Main.Components[I]);
  Check(Browser<>nil,'Existing file-selection callback available');
  F.OnFileGameSelected:=Browser.OnFileGameSelected;
  Games.Row:=1;GuiTestConfirmationResult:=mrNo;Games.OnDblClick(Games);Pump;
  Check((Main.ActiveGameTree.MainlineCount=2) and (Main.ActiveGameTree.BranchCount=1),'Database selection uses existing main tree path');
  Check(Main.ActiveGameTree.MainlineNode[1].CommentText='note','Full PGN comments preserved');
  RootId:=Main.ActiveGameTree.Root.NodeId;Before:=Main.ActiveGameTree.StartingFEN;
  Games.Row:=2;GuiTestConfirmationResult:=mrCancel;Games.OnDblClick(Games);
  Check(Main.ActiveGameTree.Root.NodeId=RootId,'Cancelled database replacement keeps tree identity');
  GuiTestConfirmationResult:=mrYes;GuiTestFileDialogResult:=0;Games.OnDblClick(Games);
  Check(Main.ActiveGameTree.Root.NodeId=RootId,'Cancelled Save keeps database replacement tree');
  GuiTestFileDialogResult:=1;GuiTestFileName:=Name+'/missing/save.pgn';Games.OnDblClick(Games);
  Check(Main.ActiveGameTree.Root.NodeId=RootId,'Failed Save keeps database replacement tree');
  GuiTestConfirmationResult:=mrNo;Games.OnDblClick(Games);Check(Main.ActiveGameTree.EventName='Second','Discard loads selected database game');
  Menu(F,'Setup position...').Click;Pump;
  Check(F.Width=900,'Existing database window layout retained');
  Setup:=nil;for I:=0 to F.ComponentCount-1 do if F.Components[I] is TPositionSetupForm then Setup:=TPositionSetupForm(F.Components[I]);
  Check(Setup<>nil,'Existing setup dialog reused');SetupFen:=nil;
  for I:=0 to Setup.ComponentCount-1 do if Setup.Components[I] is TEdit then SetupFen:=TEdit(Setup.Components[I]);
  SetupFen.Text:='4k3/8/8/8/8/8/8/4K3 w - - 0 37';Button(Setup,'Apply');Pump;
  Check(not Setup.Visible,'Valid database setup accepted');
  Check(Board.Position.ToFEN=SetupFen.Text,'Setup updates the database search board');
  Menu(F,'Setup position...').Click;Pump;SetupFen.Text:='8/8/8/8/8/8/8/4K3 w - - 0 1';
  Before:=Board.Position.ToFEN;Button(Setup,'Apply');
  Check(Setup.Visible and (Board.Position.ToFEN=Before),'Invalid setup keeps dialog and search position');Button(Setup,'Cancel');
  // Use the real main-window Open database action and its wired selection path.
  GuiTestFileName:=DbName;GuiTestFileDialogResult:=1;Menu(Main,'&Open database...').Click;Pump;
  Check(GuiTestFileTitle='Open database','Existing main database action reused');
  OwnedDatabase:=nil;
  for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TDatabaseForm then
   OwnedDatabase:=TDatabaseForm(Main.Components[I]);
  Check((OwnedDatabase<>nil) and Assigned(OwnedDatabase.OnFileGameSelected),'Main wires existing file-game selection');
  Main.LoadStandaloneFen(ChessStartingFEN);RootId:=Main.ActiveGameTree.Root.NodeId;
  Menu(Main,'Search position in database').Click;Pump;
  for I:=0 to OwnedDatabase.ComponentCount-1 do
   if OwnedDatabase.Components[I] is TGameBoardControl then
    Check(TGameBoardControl(OwnedDatabase.Components[I]).Position.ToFEN=ChessStartingFEN,'Automatic database search follows displayed position');
  Check((Main.ActiveGameTree.Root.NodeId=RootId) and (Main.ActiveGameTree.MainlineCount=0),'Automatic database search keeps game tree unchanged');
  for I:=0 to OwnedDatabase.ComponentCount-1 do
   if (OwnedDatabase.Components[I] is TStringGrid) and
    (TStringGrid(OwnedDatabase.Components[I]).ColCount=7) then Games:=TStringGrid(OwnedDatabase.Components[I]);
  Games.Row:=1;GuiTestConfirmationResult:=mrNo;Games.OnDblClick(Games);Pump;
  Check((Main.ActiveGameTree.MainlineCount=2) and (Main.ActiveGameTree.BranchCount=1),'Actual main database callback loads complete game');
  RootId:=Main.ActiveGameTree.Root.NodeId;
  GuiTestFileName:=DbName+'.created';Menu(Main,'&Create database...').Click;Pump;
  Check((GuiTestFileTitle='Create database') and FileExists(GuiTestFileName),'Existing main create action creates chess database');
  Check(Main.ActiveGameTree.Root.NodeId=RootId,'Creating database preserves current game tree');
  WriteLn('Chess database GUI checks passed (',Checks,' checks)');
 finally
  GuiTestConfirmationResult:=mrNo;GuiTestFileDialogResult:=0;
  if Main<>nil then Main.Free;F.Free;RegisterDefaultGameVariant(DraughtsVariant);V.Free;Data.Free;
  DeleteFile(DbName);DeleteFile(DbName+'.created');DeleteFile(Name);DeleteFile(ChangeFileExt(Name,'.import.log'));
 end;
end.
