program engine_parameter_scroll_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 Grids,Types,LMessages,LCLType,StdCtrls,ExtCtrls,uEngineRegistry,uRunningGame,
 uGameSetupTypes,uGameTreeActor,uGameTreeBuilder,uGameOrchestrator,uEngineEditForm,uChessPosition,uDraughtsPosition,
 uGamePosition,uGameGuiProfile,uTournamentDialog,uEnginesDialog,uDatabaseForm,
 uPdnOpenDialog,uMainForm,uGuiDialogs;
type
 TGridAccess=class(TStringGrid);
 TStartProbe=class
 public Games:TList;Main:TMainForm;
  constructor Create;
  destructor Destroy;override;
  procedure Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
 end;
 TErrors=class
  procedure Report(Sender:TObject;E:Exception);
 end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Checks,GridsChecked:Integer;Errors:TErrors;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
procedure Scroll(G:TStringGrid;Horizontal:Boolean;Code,Position:Integer);
var M:TLMScroll;
begin
 FillChar(M,SizeOf(M),0);
 if Horizontal then M.Msg:=LM_HSCROLL else M.Msg:=LM_VSCROLL;
 M.ScrollCode:=Code;M.Pos:=Position;G.Dispatch(M);
end;
procedure TestEngineHints(G:TStringGrid);
const Path1='C:\Chess engines\échecs\Stockfish\stockfish-windows-x86-64.exe';
      Path2='D:\External engines\ZZZZZZ4\engine.exe';
var R:TRect;W:Integer;Fill:Boolean;
 procedure Hover(Col,Row:Integer;const Expected:string);
 begin
  R:=G.CellRect(Col,Row);
  TGridAccess(G).ShowCellHintWindow(Point(R.Left+4,R.Top+4));
  Check(G.Hint=Expected,'Engine cell hover supplies full expected hint');
 end;
begin
 Check(G.ShowHint and (goCellHints in G.Options),'Explicit data-cell hints enabled');
 Check(Assigned(G.OnGetCellHint),'Engine data-cell hint handler assigned');
 G.Cells[0,1]:=Path1;G.Cells[0,2]:=Path2;
 W:=G.ColWidths[0];Fill:=G.AutoFillColumns;G.AutoFillColumns:=False;
 try
  G.ColWidths[0]:=120;Hover(0,1,Path1);Hover(0,2,Path2);
  G.ColWidths[0]:=2000;Hover(0,1,Path1);
  Hover(0,0,'');
  G.Cells[0,2]:='';Hover(0,2,'');
 finally G.ColWidths[0]:=W;G.AutoFillColumns:=Fill;Application.CancelHint;end;
end;
procedure TestGrid(G:TStringGrid;const Context:string);
var I,Top,Selected,Column,WidthBefore:Integer;Value:string;Key:Word;P:TPoint;
begin
 Inc(GridsChecked);
 Check(G.MouseWheelOption=mwGrid,Context+': wheel scrolls the viewport');
 Check(goThumbTracking in G.Options,Context+': live thumb tracking enabled');
 // Synthetic rows only: no engine launch, files, pairings or database changes.
 G.RowCount:=301;
 for I:=G.FixedRows to G.RowCount-1 do
  G.Cells[G.FixedCols,I]:='row-'+IntToStr(I);
 if Pos('TEnginesDialog/',Context)=1 then TestEngineHints(G);
 G.Col:=G.FixedCols;G.Row:=G.FixedRows;G.TopRow:=G.FixedRows;Pump;
 Top:=G.TopRow;Selected:=G.Row;Column:=G.Col;
 Value:=G.Cells[Column,Selected];WidthBefore:=G.ColWidths[0];
 Check(TGridAccess(G).DoMouseWheel([],-120,Point(10,10)),Context+': down wheel handled');
 Check(G.TopRow>Top,Context+': first wheel event immediately scrolls');
 Check((G.Row=Selected) and (G.Col=Column) and (G.Cells[Column,Selected]=Value),Context+': wheel preserves selection and data');
 Top:=G.TopRow;
 Check(TGridAccess(G).DoMouseWheel([],120,Point(10,10)),Context+': up wheel handled');
 Check(G.TopRow<Top,Context+': first up wheel immediately scrolls back');
 Check((G.Row=Selected) and (G.ColWidths[0]=WidthBefore),Context+': wheel preserves row and measured widths');
 G.TopRow:=G.FixedRows;
 TGridAccess(G).DoMouseWheel([],120,Point(10,10));
 Check(G.TopRow=G.FixedRows,Context+': up at top stays at top');
 G.TopRow:=G.RowCount-1;Top:=G.TopRow;
 TGridAccess(G).DoMouseWheel([],-120,Point(10,10));
 Check(G.TopRow>=Top,Context+': down at bottom does not jump backwards');
 G.TopRow:=G.FixedRows;
 Scroll(G,False,SB_LINEDOWN,0);
 Check(G.TopRow>G.FixedRows,Context+': vertical scrollbar arrow scrolls immediately');
 Scroll(G,False,SB_PAGEUP,0);
 Check(G.TopRow=G.FixedRows,Context+': scrollbar page up returns to top');
 Scroll(G,False,SB_PAGEDOWN,0);
 Check(G.TopRow>G.FixedRows,Context+': scrollbar page down scrolls immediately');
 G.TopRow:=G.FixedRows;
 Scroll(G,False,SB_THUMBTRACK,500);
 Check(TGridAccess(G).GetPxTopLeft.Y>0,Context+': vertical thumb scrolls before release');
 Check((G.Row=Selected) and (G.Col=Column),Context+': scrollbar navigation preserves selected cell');
 // Force horizontal overflow, independent of the installed engine/database data.
 G.AutoFillColumns:=False;
 for I:=G.FixedCols to G.ColCount-1 do G.ColWidths[I]:=1200;
 G.LeftCol:=G.FixedCols;Pump;P:=TGridAccess(G).GetPxTopLeft;
 TGridAccess(G).DoMouseWheel([ssCtrl],-120,Point(10,10));
 Check(TGridAccess(G).GetPxTopLeft.X>P.X,Context+': horizontal wheel scrolls immediately');
 Scroll(G,True,SB_THUMBPOSITION,0);
 Scroll(G,True,SB_THUMBTRACK,300);
 Check(TGridAccess(G).GetPxTopLeft.X>0,Context+': horizontal thumb scrolls before release');
 Check((G.Row=Selected) and (G.Col=Column),Context+': horizontal scrolling preserves selection');
 // Keyboard navigation must still select rows normally.
 G.TopRow:=G.FixedRows;G.LeftCol:=G.FixedCols;G.Row:=G.FixedRows;
 Key:=VK_DOWN;TGridAccess(G).KeyDown(Key,[]);
 Check(G.Row=G.FixedRows+1,Context+': keyboard down still selects the next row');
 WriteLn('PASS: ',Context);
end;
constructor TStartProbe.Create;
begin inherited Create;Games:=TList.Create;Main:=TMainForm.Create(nil);end;
destructor TStartProbe.Destroy;
var I:Integer;
begin
 for I:=0 to Games.Count-1 do TRunningGame(Games[I]).MarkFinished;
 Main.Free;Games.Free;inherited Destroy;
end;
procedure TStartProbe.Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
begin
 Game:=TRunningGame.Create(Games.Count+1,Title,nil,Setup.WhitePlayer,Setup.BlackPlayer,
   '','','White','Black',nil,Setup);
 Games.Add(Game);Main.TestRegisterGame(TRunningGame(Game));
end;
procedure TournamentViewport(V:TGameVariant;Pairing,FontSize:Integer);
var D:TTournamentDialog;P:TStartProbe;Engines:TExternalEngineList;E:TExternalEngineDefinition;
 G:TStringGrid;Timer:TTimer;Play:TButton;Saved:TMemoryStream;Had:Boolean;
 I,Top,Last:Integer;Id:TGUID;Directory,FileName:string;Search:TSearchRec;
 C:TGameTreeCommand;Game:TRunningGame;
begin
 D:=nil;P:=TStartProbe.Create;Engines:=TExternalEngineList.Create;Saved:=TMemoryStream.Create;
 Had:=FileExists(EnginesJsonFileName);if Had then Saved.LoadFromFile(EnginesJsonFileName);
 CreateGUID(Id);Directory:=GetTempDir+'tournament-view-'+GUIDToString(Id);ForceDirectories(Directory);
 FileName:=Directory+'/tournament.json';
 try
  for I:=1 to 8 do begin
   E:=TExternalEngineDefinition.Create;
   if GameVariantId(V)='chess' then E.Kind:=eekUci else E.Kind:=eekHub;
   E.ExePath:=ExpandFileName(ParamStr(0));E.UciId:='Viewport '+IntToStr(I);E.HubId:=E.UciId;Engines.Add(E);
  end;
  SaveExternalEngines(EnginesJsonFileName,Engines);D:=TTournamentDialog.Create(P.Main,V);
  D.Font.Size:=FontSize;D.Width:=1100;D.Height:=900;D.Show;Pump;
  Timer:=nil;Play:=nil;
  for I:=0 to D.ComponentCount-1 do begin
   if D.Components[I] is TRadioGroup then TRadioGroup(D.Components[I]).ItemIndex:=Pairing;
   if D.Components[I] is TTimer then Timer:=TTimer(D.Components[I]);
   if (D.Components[I] is TButton) and (TButton(D.Components[I]).Caption='Play') then Play:=TButton(D.Components[I]);
  end;
  Check((Timer<>nil) and (Play<>nil),'Tournament Play/timer controls exist');
  TEdit(D.FindComponent('TournamentConcurrentGames')).Text:='2';
  D.OnStartGame:=@P.Start;TButton(D.FindComponent('CreatePairing')).Click;
  D.SaveTournamentToFile(FileName);G:=TStringGrid(D.FindComponent('TournamentPairings'));Last:=G.RowCount-1;
  Check(Last>=28,'Round-robin schedule has enough rows to scroll');
  G.Row:=1;G.TopRow:=1;Top:=G.TopRow;
  if FontSize=16 then begin
   if Pairing=0 then G.TopRow:=Last
   else Scroll(G,False,SB_THUMBTRACK,G.DefaultRowHeight div 2);
  end;
  GuiTestConfirmationResult:=mrYes;
  try Play.Click;finally GuiTestConfirmationResult:=0;end;
  Timer.Enabled:=False;
  Check((P.Games.Count=1) and (G.Row=1) and (G.TopRow=Top),'Play keeps the first row visible');
  Check(G.CellRect(G.Col,1).Top>=G.CellRect(G.Col,0).Bottom,'Play fully reveals a hidden/partly clipped selected first row');
  Sleep(1100);Timer.OnTimer(Timer);Timer.Enabled:=False;
  Check((P.Games.Count=2) and (G.Row=2),'Second concurrent game is selected');
  Check(G.TopRow=Top,'Selecting a visible round-robin row must not scroll row one away');
  Check(G.IsCellVisible(G.Col,1),'First row remains visible after starting row two');
  // Exercise following a new start that really is outside the viewport.
  for I:=3 to Last-1 do G.Cells[5,I]:='Skipped fixture';
  Game:=TRunningGame(P.Games[0]);
  C:=Game.GameTreeActor.CreateSetHeaderCommand(GameTreeHeaderInput('complete','Viewport',
   'White','Black',V.ResultText(goWhiteWins),V.DefaultStartingFEN,False,DefaultTimeControl,gosGameOver));
  try Game.GameTreeActor.ExecuteCommand(C);Check(C.Accepted,'Fixture completion accepted');finally C.Free;end;
  Game.MarkFinished;D.GameStopped(Game);Timer.Enabled:=False;
  Sleep(1100);Timer.OnTimer(Timer);Timer.Enabled:=False;
  Check((P.Games.Count=3) and (G.Row=Last),'Offscreen pending game still starts and is selected');
  Check(G.IsCellVisible(G.Col,Last) and (G.TopRow>Top),'Offscreen started row is brought into view');
  // Scrolling while no further start is possible must stay under user control.
  G.TopRow:=1;Timer.OnTimer(Timer);Timer.Enabled:=False;
  Check(G.TopRow=1,'Idle scheduling tick preserves a manually scrolled viewport');
  WriteLn('PASS: tournament viewport ',V.Name,' pairing=',Pairing,' font=',FontSize);
 finally
  D.Free;P.Free;Engines.Free;
  if Had then Saved.SaveToFile(EnginesJsonFileName) else DeleteFile(EnginesJsonFileName);Saved.Free;
  if FindFirst(Directory+'/*',faAnyFile,Search)=0 then begin
   repeat if (Search.Name<>'.') and (Search.Name<>'..') then DeleteFile(Directory+'/'+Search.Name);until FindNext(Search)<>0;
   FindClose(Search);end;RemoveDir(Directory);
 end;
end;
procedure TestForm(F:TForm);
var I,Found:Integer;
begin
 try
  F.Width:=1000;F.Height:=800;F.Show;Pump;Found:=0;
  for I:=0 to F.ComponentCount-1 do
   if F.Components[I] is TStringGrid then begin
    Inc(Found);TestGrid(TStringGrid(F.Components[I]),F.ClassName+'/'+IntToStr(Found));
   end;
  Check(Found>0,F.ClassName+': existing grid found');
 finally F.Free;end;
end;
var F:TEngineEditForm;V:TGameVariant;J,Pairing,Size:Integer;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 try
  for J:=0 to RegisteredGameCount-1 do begin
   V:=RegisteredGame(J);RegisterDefaultGameVariant(V);
   F:=TEngineEditForm.Create(nil,V);F.LoadEngine(nil);TestForm(F);
   TestForm(TTournamentDialog.Create(nil,V));
   TestForm(TEnginesDialog.Create(nil,V));
   TestForm(TDatabaseForm.Create(nil,V));
   TestForm(TPdnOpenDialog.Create(nil));
   TestForm(TMainForm.Create(nil));
   for Pairing:=0 to 1 do for Size:=0 to 1 do TournamentViewport(V,Pairing,10+6*Size);
  end;
  Check(GridsChecked=16,'All eight application grids checked for both games');
 finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
 WriteLn('Application grid scroll checks passed (',Checks,' checks)');
end.
