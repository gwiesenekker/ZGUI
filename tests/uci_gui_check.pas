program uci_gui_check;
{$mode objfpc}{$H+}
{$IFNDEF GWDGUI_NONINTERACTIVE_TEST}{$FATAL Build with LPI}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Controls, Classes, SysUtils,
  StdCtrls, Menus, Grids, ExtCtrls, uEngineEditForm, uEngineRegistry,
  uEngineParamsJson, uMainForm, uChessPosition, uChessUciEngine, uGamePosition,
  uGameGuiProfile, uGameTree, uGuiDialogs, uGameTreeSearchRef;
type TErrors=class
  procedure Report(Sender: TObject; E: Exception);
end;
var Checks: Integer=0;
procedure TErrors.Report(Sender: TObject; E: Exception);
begin WriteLn('FAIL: ',E.Message); DumpExceptionBackTrace(Output); Flush(Output); Halt(1); end;
procedure Check(Value: Boolean; const Text: string);
begin Inc(Checks); if not Value then raise Exception.Create(Text); end;
procedure Fake;
var Line,Move,Fen: string; P: TChessPosition; L: TStringList; I,N: Integer;
begin
  P:=TChessPosition.Create; L:=TStringList.Create; Move:='e2e4';
  try
    while not EOF(Input) do begin
      ReadLn(Line);
      if Line='uci' then begin
        if ParamStr(2)='hang' then Continue;
        WriteLn('id name GUI UCI');
        WriteLn('option name hAsH type spin default 16 min 1 max 256');
        WriteLn('option name Style type combo default Solid var Solid var Very Aggressive');
        WriteLn('option name Clear Hash type button');
        WriteLn('option name Ponder type check default true'); WriteLn('uciok');
      end else if Line='isready' then WriteLn('readyok')
      else if Copy(Line,1,9)='position ' then begin
        L.Clear; ExtractStrings([' '],[],PChar(Line),L); N:=L.IndexOf('moves');
        if L[1]='startpos' then P.LoadFromFEN(ChessStartingFEN) else begin
          Fen:=''; for I:=2 to 7 do begin if I>2 then Fen+=' '; Fen+=L[I]; end; P.LoadFromFEN(Fen);
        end;
        if N>=0 then for I:=N+1 to L.Count-1 do P.PlayMove(L[I]);
        if P.LegalMoveCount>0 then Move:=P.LegalMove(0) else Move:='0000';
      end else if Copy(Line,1,3)='go ' then begin
        WriteLn('info depth 1 score cp 10 pv '+Move); Flush(Output); Sleep(40);
        WriteLn('info depth 2 score cp 35 pv '+Move); Flush(Output); Sleep(40);
        WriteLn('info depth 99 score cp 999 upperbound pv '+Move);
        WriteLn('bestmove '+Move);
      end else if Line='quit' then Break;
      Flush(Output);
    end;
  finally L.Free; P.Free; end;
end;
function Button(Form: TForm; const Caption: string): TButton;
var I: Integer;
begin
  for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TButton) and (TButton(Form.Components[I]).Caption=Caption) then Exit(TButton(Form.Components[I]));
  raise Exception.Create('Missing button '+Caption);
end;
function Menu(Form: TMainForm; const Caption: string): TMenuItem;
var I: Integer;
begin
  for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TMenuItem) and (TMenuItem(Form.Components[I]).Caption=Caption) then Exit(TMenuItem(Form.Components[I]));
  raise Exception.Create('Missing menu '+Caption);
end;
procedure Pump(Form: TMainForm=nil);
begin Application.ProcessMessages; if Form<>nil then Form.TestDrainGuiEvents(True); Sleep(5); end;
function GridOf(Form: TForm): TStringGrid;
var I: Integer;
begin
  for I:=0 to Form.ComponentCount-1 do if Form.Components[I] is TStringGrid then Exit(TStringGrid(Form.Components[I]));
  raise Exception.Create('Missing parameter grid');
end;
function Row(Grid: TStringGrid; const Name: string): Integer;
begin
  for Result:=1 to Grid.RowCount-1 do if SameText(Grid.Cells[0,Result],Name) then Exit;
  Result:=-1;
end;
procedure Editor(const Exe: string);
var F: TEngineEditForm; D: TExternalEngineDefinition; P,Q: TEngineParamArray;
  G: TStringGrid; Tick: QWord; Name,IniName: string; Lines: TStringList;
begin
  Name:=EngineParamsFileName(Exe); IniName:=ChangeFileExt(Exe,'.uci-test.ini');
  P:=nil; AddOrUpdateParam(P,'hash','spin','64',False);
  AddOrUpdateParam(P,'Style','combo','Very Aggressive',False);
  SaveEngineParamsToJson(Name,'uci',P);
  P:=nil; AddOrUpdateParam(P,'legacy','string','preserved',False); SaveEngineParamsToJson(Name,'hub',P);
  D:=TExternalEngineDefinition.Create; D.Kind:=eekUci; D.ExePath:=Exe; D.Arguments:='--fake-uci';
  D.UciId:='Saved GUI UCI'; D.IniFileName:=IniName; D.IniContent:='retained=ini';
  F:=TEngineEditForm.Create(nil); Lines:=TStringList.Create;
  try
    F.LoadEngine(D); G:=GridOf(F); Tick:=GetTickCount64; Button(F,'Launch engine').Click;
    Check(GetTickCount64-Tick<200,'Discovery returns immediately');
    repeat Pump; until (Row(G,'Clear Hash')>0) or (GetTickCount64-Tick>5000);
    Check(Row(G,'Clear Hash')>0,'Asynchronous option discovery updates existing grid');
    Check(G.Cells[2,Row(G,'hAsH')]='64','Discovery retains saved spin value');
    Check(G.Cells[2,Row(G,'Style')]='Very Aggressive','Discovery retains saved combo value');
    Check(FileExists(IniName),'Existing INI preparation reused');
    G.Col:=2; G.Row:=Row(G,'Clear Hash'); G.OnDblClick(G); for Tick:=1 to 10 do Pump;
    Button(F,'Launched correctly').Click;
    LoadEngineParamsFromJson(Name,'uci',Q);
    Check(EngineParamValue(Q,'hash','')='64','UCI values saved');
    Check(EngineParamValue(Q,'gui-uci-id','')='Saved GUI UCI','Discovery preserves custom identity');
    Check(EngineParamValue(Q,'gui-uci-init','bad')='','UCI init remains empty');
    Check(EngineParamValue(Q,EngineLaunchArgumentParamName(eekUci),'')='--fake-uci','UCI arguments saved separately');
    Check(EngineParamValue(Q,'gui-ini-content','')<>'','INI editor content persists');
    Check(EngineParamValue(Q,'Clear Hash','bad')='','Buttons not persisted as press commands');
    Check(Q[0].Name<>'','Saved option array exists');
    P:=nil; LoadEngineParamsFromJson(Name,'hub',P); Check(EngineParamValue(P,'legacy','')='preserved','Hub section preserved');
    for Tick:=0 to High(Q) do if SameText(Q[Tick].Name,'hAsH') then Check((Q[Tick].MinValue='1') and (Q[Tick].MaxValue='256'),'Spin bounds persist');
    // Reopen and reject invalid values before changing the saved file.
    F.LoadEngine(D); G:=GridOf(F); Lines.LoadFromFile(Name); G.Cells[2,Row(G,'hAsH')]:='9999';
    GuiTestConfirmationResult:=mrOk;
    try Button(F,'Launched correctly').Click; finally GuiTestConfirmationResult:=0; end;
    Check(Pos('hAsH',GuiTestLastConfirmationText)>0,'Invalid spin is reported');
    LoadEngineParamsFromJson(Name,'uci',P); Check(EngineParamValue(P,'hash','')='64','Invalid spin cannot overwrite saved configuration');
    // Cancel a handshake while the worker waits: no UI-thread discovery loop.
    D.Arguments:='--fake-uci hang'; DeleteFile(Name); F.LoadEngine(D); Button(F,'Launch engine').Click;
    Pump; Tick:=GetTickCount64; Button(F,'Cancel').Click;
    Check(GetTickCount64-Tick<2500,'Cancel interrupts pending discovery promptly');
  finally F.Free; D.Free; Lines.Free; DeleteFile(Name); DeleteFile(IniName); end;
end;
procedure Analysis(const Exe: string);
var F: TMainForm; Engines: TExternalEngineList; D: TExternalEngineDefinition;
  Item: TMenuItem; Popup: TPopupMenu; Tick: QWord; Keys: TStringList; S: TGameTreeSearchRef; Fen: string;
begin
  Engines:=TExternalEngineList.Create; Keys:=TStringList.Create;
  D:=TExternalEngineDefinition.Create; D.Kind:=eekUci; D.ExePath:=Exe; D.UciId:='GUI UCI'; D.Arguments:='--fake-uci'; Engines.Add(D);
  D:=TExternalEngineDefinition.Create; D.Kind:=eekHub; D.ExePath:=Exe; D.HubId:='Not Chess'; Engines.Add(D);
  SaveExternalEngines(EnginesJsonFileName,Engines); F:=TMainForm.Create(nil);
  try
    Item:=Menu(F,'Open Annotator'); Popup:=TPopupMenu(Item.GetParentMenu); Popup.OnPopup(Popup);
    Check(Item.Count=1,'Chess picker contains UCI and excludes Hub'); Item.Items[0].Click;
    Tick:=GetTickCount64;
    repeat Pump(F); until (F.ActiveGameTree.Root.AnnotatorPVDepth='2') or (GetTickCount64-Tick>5000);
    Check(F.ActiveGameTree.Root.AnnotatorPVDepth='2','Same PV with new depth reaches existing tree/GUI');
    Check(F.ActiveGameTree.Root.AnnotatorScore='0.35','Exact White score reaches existing annotator');
    Check(F.ActiveGameTree.Root.ChildCount=0,'Analysis never adds moves or variations');
    Check(not Button(F,'Auto Play').Enabled,'Auto Play remains disabled for chess');
    Check(not Menu(F,'Open MCTS annotator').Enabled,'MCTS remains disabled for chess');
    F.CollectBusyEngineKeys(Keys); Check(Keys.Count=1,'Existing reservation tracks UCI annotator');
    S:=F.TestAnalysis.Search;
    Fen:='4k3/8/8/8/8/8/8/R3K3 b - - 0 37'; F.LoadStandaloneFen(Fen);
    Tick:=GetTickCount64;
    repeat Pump(F); until (F.ActiveGameTree.Root.AnnotatorScore='-0.35') or (GetTickCount64-Tick>5000);
    Check(F.ActiveGameTree.Root.AnnotatorScore='-0.35','New Black root uses current context and White score');
    Check(not SameGameTreeSearchRef(S,F.TestAnalysis.Search),'Position transition gets a new search reference');
    Check(F.ActiveGameTree.Root.ChildCount=0,'Navigation analysis preserves topology');
    Popup.OnPopup(Popup); Menu(F,'Close Annotator').Click; Tick:=GetTickCount64;
    repeat Pump(F); until (F.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
    Check(F.TestAnalyzerRunner=nil,'Existing runner shuts down UCI cleanly');
    Keys.Clear; F.CollectBusyEngineKeys(Keys); Check(Keys.Count=0,'Shutdown releases existing reservation');
  finally F.Free; Engines.Free; Keys.Free; DeleteFile(EnginesJsonFileName); end;
end;
procedure RealAnalysis(const Path: string);
var F: TMainForm; Engines: TExternalEngineList; D: TExternalEngineDefinition;
  Item: TMenuItem; Popup: TPopupMenu; Tick: QWord;
  procedure WaitForPV;
  begin
    Tick:=GetTickCount64;
    repeat Pump(F); until (F.ActiveGameTree.Root.AnnotatorPV<>'') or (GetTickCount64-Tick>8000);
    Check((F.ActiveGameTree.Root.AnnotatorPV<>'') and (F.ActiveGameTree.Root.AnnotatorScore<>''),'Stockfish reaches existing GUI analysis');
    Check(F.ActiveGameTree.Root.ChildCount=0,'Stockfish analysis preserves topology');
  end;
begin
  Engines:=TExternalEngineList.Create;
  D:=TExternalEngineDefinition.Create; D.Kind:=eekUci; D.ExePath:=ExpandFileName(Path); D.UciId:='Stockfish test'; Engines.Add(D);
  SaveExternalEngines(EnginesJsonFileName,Engines); F:=TMainForm.Create(nil);
  try
    Item:=Menu(F,'Open Annotator'); Popup:=TPopupMenu(Item.GetParentMenu); Popup.OnPopup(Popup); Item.Items[0].Click;
    WaitForPV;
    F.LoadStandaloneFen('4k3/8/8/8/8/8/8/R3K3 b - - 0 37'); WaitForPV;
    Popup.OnPopup(Popup); Menu(F,'Close Annotator').Click; Tick:=GetTickCount64;
    repeat Pump(F); until (F.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
    Check(F.TestAnalyzerRunner=nil,'Stockfish closes through existing GUI runner');
  finally F.Free; Engines.Free; DeleteFile(EnginesJsonFileName); end;
end;
var V: TChessVariant; Errors: TErrors;
begin
  if ParamStr(1)='--fake-uci' then begin Fake; Halt; end;
  Application.Initialize; Application.ShowMainForm:=False; Errors:=TErrors.Create; Application.OnException:=@Errors.Report; V:=TChessVariant.Create;
  RegisterDefaultGameVariant(V); RegisterGameGuiProfile(V,ChessGuiProfile);
  try Editor(ExpandFileName(ParamStr(0))); Analysis(ExpandFileName(ParamStr(0)));
    if ParamStr(1)<>'' then RealAnalysis(ParamStr(1));
    WriteLn('UCI GUI checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(nil); V.Free; Errors.Free; end;
end.
