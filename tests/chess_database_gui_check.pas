program chess_database_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,StdCtrls,ExtCtrls,Menus,
 Grids,Graphics,Classes,SysUtils,Types,SQLite3Conn,SQLDB,uGamePosition,uChessPosition,uDraughtsPosition,
 uChessBoardControl,uGameBoardControl,uDatabaseForm,uMainForm,uGuiDialogs,uPdnOpenDialog,
 uGameTree,uPreferences,uGameGuiProfile,uDraughtsPositionSetupForm;
var Checks:Integer=0;V:TChessVariant;Main:TMainForm;F:TDatabaseForm;Browser:TPdnOpenDialog;
 Games,Results:TStringGrid;Board:TGameBoardControl;FenEdit:TEdit;Data:TStringList;
 Name,DbName,Before:string;I,ColumnGrowth,WindowGrowth:Integer;RootId:Int64;Setup:TPositionSetupForm;SetupFen:TEdit;OwnedDatabase:TDatabaseForm;Bounds:array of TRect;C:TControl;TextCanvas:TControlCanvas;
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
procedure DoubleClickCell(Grid:TStringGrid;Col,Row:Integer);
var R:TRect;
begin
 Check(Assigned(Grid.OnDblClick),'Continuation double-click is connected');
 R:=Grid.CellRect(Col,Row);
 Mouse.CursorPos:=Grid.ClientToScreen(Point(R.Left+4,R.Top+4));
 Grid.OnDblClick(Grid);
end;
function MoveRow(Grid:TStringGrid;const Move:string):Integer;
var I:Integer;
begin
 for I:=1 to Grid.RowCount-1 do if Grid.Cells[0,I]=Move then Exit(I);
 raise Exception.Create('Missing continuation '+Move);
end;
procedure ExecuteDatabaseSql(const Name,Sql:string);
var Connection:TSQLite3Connection;Transaction:TSQLTransaction;
begin
 Connection:=TSQLite3Connection.Create(nil);Transaction:=TSQLTransaction.Create(nil);
 try
  Connection.Transaction:=Transaction;Connection.DatabaseName:=Name;Connection.Open;
  Connection.ExecuteDirect(Sql);Transaction.Commit;Connection.Close;
 finally Transaction.Free;Connection.Free;end;
end;
type TContinuationImportProbe=class
 Grid:TStringGrid;Board:TGameBoardControl;Before:string;Called:Boolean;
 procedure Run(Data:PtrInt);
end;
procedure TContinuationImportProbe.Run(Data:PtrInt);
begin
 Called:=True;Check(Application.ModalLevel>0,'Import is busy for continuation probe');
 DoubleClickCell(Grid,0,1);Check(Board.Position.ToFEN=Before,'Import ignores continuation activation');
end;
procedure CheckContinuationBrowsing;
var Form:TDatabaseForm;Moves,GameList:TStringGrid;B:TGameBoardControl;Edit:TEdit;
 Search:TButton;FileName,DatabaseName,OtherName,OldFen,TreeText,OriginalFen:string;
 Text:TStringList;Expected:TGamePosition;I,Scenario:Integer;Raised:Boolean;TreeId,NodeId:Int64;
 Probe:TContinuationImportProbe;Dialog:TPositionSetupForm;Draft:TEdit;
 const StartWithCounters='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 19 37';
 procedure LocateControls;
 var I:Integer;
 begin
  Moves:=nil;B:=nil;Edit:=nil;Search:=nil;GameList:=nil;
  for I:=0 to Form.ComponentCount-1 do begin
   if Form.Components[I] is TGameBoardControl then B:=TGameBoardControl(Form.Components[I]);
   if Form.Components[I] is TStringGrid then
    if TStringGrid(Form.Components[I]).ColCount=5 then Moves:=TStringGrid(Form.Components[I])
    else GameList:=TStringGrid(Form.Components[I]);
   if (Form.Components[I] is TButton) and (TButton(Form.Components[I]).Caption='Search') then Search:=TButton(Form.Components[I]);
  end;
  for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TEdit) and
    (TEdit(Form.Components[I]).Text=B.Position.ToFEN) then Edit:=TEdit(Form.Components[I]);
  Check((Moves<>nil) and (Edit<>nil) and (Search<>nil),'Existing browsing controls found');
 end;
 procedure FindPosition(const Fen:string);
 begin Form.SetSearchFEN(Fen);Form.SearchCurrentPosition;Expected.LoadFromFEN(Fen);end;
 procedure Advance(const San,Canonical:string);
 begin
  DoubleClickCell(Moves,1,MoveRow(Moves,San));Expected.PlayMove(Canonical);
  Check((B.Position.ToFEN=Expected.ToFEN) and (Edit.Text=Expected.ToFEN),'Continuation updates exact board and FEN: '+San);
 end;
 procedure Unchanged(const Reason:string);
 begin DoubleClickCell(Moves,0,1);Check((B.Position.ToFEN=OldFen) and (Edit.Text=OriginalFen),Reason);end;
 begin
  FileName:=GetTempFileName(GetTempDir,'zdbbrowse');DatabaseName:=FileName+'.db';OtherName:=FileName+'.other';
  Form:=TDatabaseForm.Create(nil,DefaultGameVariant);Text:=TStringList.Create;Expected:=TChessPosition.Create;Probe:=TContinuationImportProbe.Create;
  TreeId:=Main.ActiveGameTree.Root.NodeId;NodeId:=Main.ActiveGameTree.MainlineNode[1].NodeId;TreeText:=Main.CurrentGameTreePdnText('');
  try
   Form.Show;Pump;LocateControls;
   Text.Text:='[Event "Main"] 1.e4 e5 2.Nf3 Nc6 *'+#10+'[Event "Other"] 1.d4 d5 *'+#10+
    '[SetUp "1"] [FEN "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"] 1.O-O O-O-O *'+#10+
    '[SetUp "1"] [FEN "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"] 1.a8=Q+ Kf7 *'+#10+
    '[SetUp "1"] [FEN "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"] 2.exd6 Kd7 *'+#10+
    '[SetUp "1"] [FEN "4k3/8/8/8/8/8/8/R3K3 b - - 0 37"] 37...Ke7 38.Ra2 *';
   Text.SaveToFile(FileName);Form.CreateDatabase(DatabaseName);Form.ImportPdnFile(FileName);
   FindPosition(ChessStartingFEN);Moves.Row:=MoveRow(Moves,'e4');OldFen:=B.Position.ToFEN;
   DoubleClickCell(Moves,0,0);Check(B.Position.ToFEN=OldFen,'Header does not execute previously selected row');
   Search.Enabled:=False;DoubleClickCell(Moves,0,MoveRow(Moves,'e4'));Search.Enabled:=True;
   Check(B.Position.ToFEN=OldFen,'Search busy guard leaves position unchanged');
   Advance('e4','e2e4');Check((Moves.RowCount=2) and (Moves.Cells[0,1]='e5') and (GameList.RowCount=2),'First move searches opponent continuation and matching game');
   Advance('e5','e7e5');Check(Moves.Cells[0,1]='Nf3','Second move searches next continuation');
   Advance('Nf3','g1f3');Advance('Nc6','b8c6');Check((Moves.Cells[0,1]='') and (GameList.RowCount=2),'Terminal position has matching game without continuation');
   OldFen:=B.Position.ToFEN;OriginalFen:=Edit.Text;Unchanged('Empty continuation does nothing');
   FindPosition('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');Advance('O-O','e1g1');Advance('O-O-O','e8c8');
   FindPosition('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');Advance('a8=Q+','a7a8q');
   FindPosition('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');Advance('exd6','e5d6');
   FindPosition('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');Advance('Ke7','e8e7');
   // A changed counter FEN has the same key and still permits e4: legality alone is insufficient.
   for Scenario:=0 to 2 do begin
    FindPosition(ChessStartingFEN);OldFen:=B.Position.ToFEN;
    if Scenario=0 then Edit.Text:=StartWithCounters
    else if Scenario=1 then Edit.Text:='invalid FEN'
    else begin Form.SetSearchFEN(StartWithCounters);OldFen:=B.Position.ToFEN;end;
    OriginalFen:=Edit.Text;Unchanged('Stale results cannot execute after edited/set FEN');
   end;
   FindPosition(ChessStartingFEN);Menu(Form,'Setup position...').Click;Pump;Dialog:=nil;Draft:=nil;
   for I:=0 to Form.ComponentCount-1 do if Form.Components[I] is TPositionSetupForm then Dialog:=TPositionSetupForm(Form.Components[I]);
   for I:=0 to Dialog.ComponentCount-1 do if Dialog.Components[I] is TEdit then Draft:=TEdit(Dialog.Components[I]);
   Draft.Text:=StartWithCounters;Button(Dialog,'Apply');OldFen:=B.Position.ToFEN;OriginalFen:=Edit.Text;
   Unchanged('Setup invalidates the old continuation position');Form.SearchCurrentPosition;Expected.LoadFromFEN(StartWithCounters);Advance('e4','e2e4');
   // Searching replaces result objects, but displayed SAN is not the canonical move source.
   FindPosition(ChessStartingFEN);Moves.Cells[0,MoveRow(Moves,'e4')]:='display text only';
   DoubleClickCell(Moves,0,MoveRow(Moves,'display text only'));Expected.PlayMove('e2e4');
   Check(B.Position.ToFEN=Expected.ToFEN,'Activation uses canonical result rather than displayed cell');
   FindPosition(ChessStartingFEN);Probe.Grid:=Moves;Probe.Board:=B;Probe.Before:=B.Position.ToFEN;
   Application.QueueAsyncCall(@Probe.Run,0);Form.ImportPdnFile(FileName);Check(Probe.Called,'Busy import probe ran');
   OldFen:=B.Position.ToFEN;OriginalFen:=Edit.Text;Unchanged('Imported collection requires fresh search before activation');
   FindPosition(ChessStartingFEN);Raised:=False;
   try Form.OpenDatabase(FileName);except on E:Exception do Raised:=True;end;
   Check(Raised,'Invalid database open rejected');Advance('e4','e2e4');
   FindPosition(ChessStartingFEN);Form.CreateDatabase(OtherName);OldFen:=B.Position.ToFEN;OriginalFen:=Edit.Text;
   Unchanged('Database create invalidates prior continuation association');
   Form.OpenDatabase(DatabaseName);Unchanged('Database open invalidates prior continuation association');
   FindPosition(ChessStartingFEN);Form.SetSearchFEN('4k3/8/8/8/8/8/8/4K3 w - - 0 1');
   Check(Moves.Cells[0,1]='','Changed board clears continuations that are now illegal');
   Form.CreateDatabase(OtherName+'.stale');
   Check(FileExists(OtherName+'.stale') and (Moves.Cells[0,1]=''),'Create succeeds after changed-board search results');
   Form.OpenDatabase(DatabaseName);FindPosition(ChessStartingFEN);
   Form.SetSearchFEN('4k3/8/8/8/8/8/8/4K3 w - - 0 1');Form.OpenDatabase(OtherName);
   Check((Pos(ExtractFileName(OtherName),Form.Caption)>0) and (Moves.Cells[0,1]=''),'Open succeeds after changed-board search results');
   Form.OpenDatabase(DatabaseName);FindPosition(ChessStartingFEN);
   ExecuteDatabaseSql(DatabaseName,'update continuations set next_move=''a1a9'' where next_move=''e2e4''');
   try
    Form.SearchCurrentPosition;
    Check(MoveRow(Moves,'a1a9 (?)')>0,'Invalid stored continuation has an explicit display marker');
    OldFen:=B.Position.ToFEN;DoubleClickCell(Moves,0,MoveRow(Moves,'a1a9 (?)'));
    Check(B.Position.ToFEN=OldFen,'Invalid displayed continuation cannot execute');
   finally ExecuteDatabaseSql(DatabaseName,'update continuations set next_move=''e2e4'' where next_move=''a1a9''');end;
   FindPosition(ChessStartingFEN);
   ExecuteDatabaseSql(DatabaseName,'alter table positions rename to unavailable_positions');
   try
    Advance('e4','e2e4');OldFen:=B.Position.ToFEN;OriginalFen:=Edit.Text;
    Unchanged('Failed search does not reactivate stale continuation rows');
   finally
    // Release the failed connection before repairing this deliberately changed schema.
    Form.Free;Form:=nil;
    ExecuteDatabaseSql(DatabaseName,'alter table unavailable_positions rename to positions');
   end;
   Form:=TDatabaseForm.Create(nil,DefaultGameVariant);Form.Show;Pump;LocateControls;
   Form.OpenDatabase(DatabaseName);FindPosition(ChessStartingFEN);Advance('e4','e2e4');
   Check((Main.ActiveGameTree.Root.NodeId=TreeId) and (Main.ActiveGameTree.MainlineNode[1].NodeId=NodeId) and
     (Main.CurrentGameTreePdnText('')=TreeText),'Database browsing preserves main game nodes, moves and annotations');
   // The same handler uses the existing draughts position adapter.
   Form.Free;Form:=nil;Expected.Free;Expected:=nil;RegisterDefaultGameVariant(DraughtsVariant);
   Form:=TDatabaseForm.Create(nil,DefaultGameVariant);Form.Show;Pump;LocateControls;Expected:=TDraughtsPosition.Create;
   Text.Text:='1.32-28 18-23 2.37-32 *';Text.SaveToFile(FileName);
   Form.CreateDatabase(DatabaseName+'.draughts');Form.ImportPdnFile(FileName);FindPosition(Expected.ToFEN);
   Advance('32-28','32-28');Check(Moves.Cells[0,1]='18-23','Draughts searches next continuation');Advance('18-23','18-23');
  finally
   Application.RemoveAsyncCalls(Probe);Probe.Free;Expected.Free;Form.Free;RegisterDefaultGameVariant(V);Text.Free;
   DeleteFile(FileName);DeleteFile(DatabaseName);DeleteFile(OtherName);DeleteFile(OtherName+'.stale');DeleteFile(DatabaseName+'.draughts');DeleteFile(ChangeFileExt(FileName,'.import.log'));
  end;
 end;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 V:=TChessVariant.Create;Name:=GetTempFileName(GetTempDir,'zdbgui');DbName:=Name+'.db';Data:=TStringList.Create;
 Main:=nil;F:=nil;
 try
  // Same control geometry except the explicitly requested wider chess FEN column.
  RegisterDefaultGameVariant(DraughtsVariant);F:=TDatabaseForm.Create(nil,DefaultGameVariant);F.Show;Pump;
  SetLength(Bounds,F.ComponentCount);
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TControl then Bounds[I]:=TControl(F.Components[I]).BoundsRect;
  F.Free;F:=nil;RegisterDefaultGameVariant(V);F:=TDatabaseForm.Create(nil,DefaultGameVariant);F.Show;Pump;
  Check(F.ComponentCount=Length(Bounds),'Existing component count');
  Board:=nil;
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TGameBoardControl then
   Board:=TGameBoardControl(F.Components[I]);
  WindowGrowth:=F.Width-900;ColumnGrowth:=0;
  for I:=0 to F.ComponentCount-1 do if F.Components[I]=Board.Parent then
   ColumnGrowth:=Board.Parent.Width-(Bounds[I].Right-Bounds[I].Left);
  for I:=0 to F.ComponentCount-1 do if F.Components[I] is TControl then begin
   C:=TControl(F.Components[I]);
   if C=Board.Parent then begin Inc(Bounds[I].Left,WindowGrowth-ColumnGrowth);Inc(Bounds[I].Right,WindowGrowth);end
   else if C.Parent=Board.Parent then Inc(Bounds[I].Right,ColumnGrowth)
   else if (C is TStringGrid) and (TStringGrid(C).ColCount=5) then Inc(Bounds[I].Right,WindowGrowth-ColumnGrowth)
   else if C.Align in [alTop,alBottom,alClient] then Inc(Bounds[I].Right,WindowGrowth);
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
  Check(Results.ClientWidth>=420,Format('Continuation client=%d window=%d column=%d sum=%d',[Results.ClientWidth,F.Width,FenEdit.Parent.Width,Results.ColWidths[0]+Results.ColWidths[1]+Results.ColWidths[2]+Results.ColWidths[3]+Results.ColWidths[4]]));
  F.Hide;FenEdit.Font.Size:=18;F.Show;Pump;
  TextCanvas:=TControlCanvas.Create;
  try
   TextCanvas.Control:=FenEdit;TextCanvas.Font.Assign(FenEdit.Font);
   Check(TextCanvas.TextWidth('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e3 99 99')+24<=FenEdit.ClientWidth,'Large edit font sizes the full representative FEN');
  finally TextCanvas.Free;end;
  Check(Results.ClientWidth>=420,'Font-dependent width retains continuation columns');
  F.Hide;FenEdit.ParentFont:=True;F.Show;Pump;
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
  Check(F.Width>=900,'Database default window fits its content');
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
  CheckContinuationBrowsing;
  WriteLn('Chess database GUI checks passed (',Checks,' checks)');
 finally
  GuiTestConfirmationResult:=mrNo;GuiTestFileDialogResult:=0;
  if Main<>nil then Main.Free;F.Free;RegisterDefaultGameVariant(DraughtsVariant);V.Free;Data.Free;
  DeleteFile(DbName);DeleteFile(DbName+'.created');DeleteFile(Name);DeleteFile(ChangeFileExt(Name,'.import.log'));
 end;
end.
