program main_readability_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 StdCtrls,Math,uMainForm,uGameNotationView,uGamePosition,uChessPosition,
 uDraughtsPosition,uGameGuiProfile,uGuiDialogs;
type TErrors=class
 procedure Report(Sender:TObject;E:Exception);
end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
const LongChessFEN='r3k2r/p1ppqpb1/bn2pnp1/2pP4/1p2P3/2N2N2/PPQBBPPP/R3K2R w KQkq - 0 1';
var Main:TMainForm;Fen:TEdit;Moves:TGameNotationView;Errors:TErrors;
 I,J,Size,Mode,Required:Integer;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));Main:=nil;
 try
  Main:=TMainForm.Create(nil);Main.Show;Pump;
  Fen:=TEdit(Main.FindComponent('MainFenEdit'));Moves:=TGameNotationView(Main.FindComponent('GameMoveMemo'));
  Check((Fen<>nil) and (Moves<>nil),'Existing FEN and notation controls present');
  for J:=0 to 1 do begin
   Main.SelectGameVariant(RegisteredGame(J));Pump;
   // Exercise the visible empty-game marker without changing any game tree.
   Moves.Lines.Text:='*';Moves.TopLine:=1;
   for Size:=0 to 1 do begin
    Main.Font.Size:=10+6*Size;Moves.Font.Size:=10+6*Size;Main.RefreshLayout;Pump;
    for Mode:=0 to 1 do begin
     if Mode=0 then begin Main.Width:=Main.Constraints.MinWidth;Main.Height:=Main.Constraints.MinHeight;end
     else begin Main.Width:=Max(1040,Main.Constraints.MinWidth);Main.Height:=Max(760,Main.Constraints.MinHeight);end;
     Pump;
     Required:=MeasureGuiText(Fen.Text,Fen.Font).cx+MeasureGuiText('MM',Fen.Font).cx;
     Check(Fen.Width>=Required,'Full FEN fits with a margin');
     Check(Moves.LinesInWindow>=10,'Notation shows at least ten lines');
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
 finally Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
end.
