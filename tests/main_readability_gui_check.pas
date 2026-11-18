program main_readability_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,uGuiLayoutTestWatch,Forms,Classes,SysUtils,Controls,
 StdCtrls,Grids,Math,uMainForm,uGameNotationView,uGamePosition,uChessPosition,
 uDraughtsPosition,uGameGuiProfile,uGuiDialogs;
type TErrors=class
 procedure Report(Sender:TObject;E:Exception);
end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Checks:Integer=0;LayoutWatch:TGuiLayoutTestWatch;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin LayoutWatch.Step('');Application.ProcessMessages;Sleep(5);end;end;
procedure CheckMctsRows(Main:TMainForm);
var Grid:TStringGrid;I:Integer;C:TControl;
begin
 Grid:=nil;
 for I:=0 to Main.ComponentCount-1 do
  if Main.Components[I] is TStringGrid then
   if TStringGrid(Main.Components[I]).Cells[0,0]='nshootouts' then Grid:=TStringGrid(Main.Components[I]);
 Check(Grid<>nil,'Existing MCTS statistics grid present');
 Check((Grid.RowCount=8) and (Grid.Cells[0,7]='lcb-ucb'),'All eight MCTS statistics rows retained');
 Check((Grid.TopRow=0) and (Grid.GridHeight<=Grid.ClientHeight),
  'All MCTS rows fit without scrolling: required='+IntToStr(Grid.GridHeight)+' viewport='+IntToStr(Grid.ClientHeight));
 C:=Grid;
 while C.Parent<>nil do begin
  Check((C.Top>=0) and (C.Top+C.Height<=C.Parent.ClientHeight),'MCTS grid is not clipped by '+C.Parent.ClassName);
  C:=C.Parent;
 end;
end;
const LongChessFEN='r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1';
var Main:TMainForm;Fen:TEdit;Moves:TGameNotationView;Errors:TErrors;
 I,J,Size,Mode,Required:Integer;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 LayoutWatch:=TGuiLayoutTestWatch.Create;Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));Main:=nil;
 try
  Main:=TMainForm.Create(nil);
  Main.Show;Pump;
  // Measure a fresh form before font stress, using the application's default fonts.
  for J:=0 to 1 do begin
   LayoutWatch.Step('default-font '+RegisteredGame(J).Name);
   Main.SelectGameVariant(RegisteredGame(J));Pump;Main.SetBounds(0,0,1000,650);Pump;
   WriteLn('U26 default ',RegisteredGame(J).Name,': system_font=',Screen.SystemFont.Name,' system_size=',Screen.SystemFont.Size,
    ' form_font=',Main.Font.Name,' size=',Main.Font.Size,
    ' height=',Main.Height,' minimum=',Main.Constraints.MinHeight);Flush(Output);
   Check(Main.Height<=700,'U26 default-font main window fits laptop work area');
  end;
  if GetEnvironmentVariable('ZGUI_LAYOUT_TEST_FONT')<>'' then Main.Font.Name:=GetEnvironmentVariable('ZGUI_LAYOUT_TEST_FONT');
  Main.Show;Pump;CheckMctsRows(Main);
  Fen:=TEdit(Main.FindComponent('MainFenEdit'));Moves:=TGameNotationView(Main.FindComponent('GameMoveMemo'));
  Check((Fen<>nil) and (Moves<>nil),'Existing FEN and notation controls present');
  for J:=0 to 1 do begin
   Main.SelectGameVariant(RegisteredGame(J));Pump;CheckMctsRows(Main);
   // Exercise the visible empty-game marker without changing any game tree.
   Moves.Lines.Text:='*';Moves.TopLine:=1;
   for Size:=0 to 1 do begin
    Main.Font.Size:=10+6*Size;Moves.Font.Size:=10+6*Size;Main.RefreshLayout;Pump;
    for Mode:=0 to 1 do begin
     if Mode=0 then begin Main.Width:=Main.Constraints.MinWidth;Main.Height:=650;end
     else begin Main.Width:=Max(1040,Main.Constraints.MinWidth);Main.Height:=Max(1100,Main.Constraints.MinHeight);end;
     Pump;CheckMctsRows(Main);
     Required:=MeasureGuiText(Fen.Text,Fen.Font).cx+MeasureGuiText('MM',Fen.Font).cx;
     Check(Fen.Width>=Required,'Full FEN fits with a margin');
     if Mode=1 then Check(Moves.LinesInWindow>=10,'Notation shows ten lines when space permits')
     else Check(Moves.LinesInWindow>=3,'Notation retains a usable three-line minimum');
     Check((Moves.Top>=0) and (Moves.Top+Moves.Height<=Moves.Parent.ClientHeight),'Notation fits its parent');
     Check((Pos('*',Moves.Lines.Text)>0) and (Moves.TopLine=1),'Standalone game result remains in notation');
    end;
   end;
  end;
  Main.SelectGameVariant(RegisteredGame(0));Main.LoadStandaloneFen(LongChessFEN);Pump;
  Check(Fen.Text=LongChessFEN,'Existing FEN display follows browsed position');
  Check(Fen.Width>=MeasureGuiText(LongChessFEN,Fen.Font).cx+MeasureGuiText('MM',Fen.Font).cx,
   'Longer current FEN automatically receives enough width');
  WriteLn('Main FEN / notation readability checks passed (',Checks,' checks)');
 finally Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;LayoutWatch.Free;end;
end.
