program engine_parameter_scroll_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 Grids,Types,LMessages,LCLType,uEngineEditForm,uChessPosition,uDraughtsPosition,
 uGamePosition,uGameGuiProfile,uTournamentDialog,uEnginesDialog,uDatabaseForm,
 uPdnOpenDialog,uMainForm;
type
 TGridAccess=class(TStringGrid);
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
var F:TEngineEditForm;V:TGameVariant;J:Integer;
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
  end;
  Check(GridsChecked=16,'All eight application grids checked for both games');
 finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
 WriteLn('Application grid scroll checks passed (',Checks,' checks)');
end.
