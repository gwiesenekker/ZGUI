program engine_parameter_scroll_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 Grids,Types,uEngineEditForm,uChessPosition,uDraughtsPosition,uGamePosition,uGameGuiProfile;
type
 TGridAccess=class(TStringGrid);
 TErrors=class
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
var F:TEngineEditForm;V:TGameVariant;G:TStringGrid;Errors:TErrors;
 I,J,Top,Selected,WidthBefore:Integer;Value:string;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 try
  for J:=0 to RegisteredGameCount-1 do begin
   V:=RegisteredGame(J);F:=TEngineEditForm.Create(nil,V);
   try
    F.LoadEngine(nil);G:=nil;
    for I:=0 to F.ComponentCount-1 do
     if F.Components[I] is TStringGrid then G:=TStringGrid(F.Components[I]);
    Check(G<>nil,'Existing parameter grid exists');
    // No engine process or external configuration: enough rows to scroll.
    G.RowCount:=101;
    for I:=1 to 100 do begin
     G.Cells[0,I]:='parameter-'+IntToStr(I);G.Cells[1,I]:='string';G.Cells[2,I]:='value-'+IntToStr(I);
    end;
    F.Width:=1000;F.Height:=800;F.Show;Pump;
    G.Col:=2;G.Row:=G.FixedRows;G.TopRow:=G.FixedRows;Pump;
    Top:=G.TopRow;Selected:=G.Row;Value:=G.Cells[2,Selected];WidthBefore:=G.ColWidths[0];
    Check(TGridAccess(G).DoMouseWheel([],-120,Point(10,10)),'Down wheel handled');
    Check(G.TopRow>Top,V.Name+': first wheel event immediately scrolls the viewport');
    Check((G.Row=Selected) and (G.Cells[2,Selected]=Value),'Wheel preserves selection and value');
    Top:=G.TopRow;
    Check(TGridAccess(G).DoMouseWheel([],120,Point(10,10)),'Up wheel handled');
    Check(G.TopRow<Top,'First upward wheel immediately scrolls back');
    Check((G.Row=Selected) and (G.ColWidths[0]=WidthBefore),'Wheel preserves selection and measured column width');
    G.TopRow:=G.FixedRows;
    TGridAccess(G).DoMouseWheel([],120,Point(10,10));
    Check(G.TopRow=G.FixedRows,'Up at top stays at top');
    G.TopRow:=G.RowCount-1;Top:=G.TopRow;
    TGridAccess(G).DoMouseWheel([],-120,Point(10,10));
    Check(G.TopRow>=Top,'Down at bottom does not jump backwards');
    WriteLn('PASS: immediate parameter wheel scrolling for ',V.Name);
   finally F.Free;end;
  end;
 finally ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
 WriteLn('Parameter wheel checks passed (',Checks,' checks)');
end.
