program uci_gui_check;
{$mode objfpc}{$H+}
{$IFNDEF GWDGUI_NONINTERACTIVE_TEST}{$FATAL Build with LPI}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Controls, Classes, SysUtils,
  StdCtrls, Menus, Grids, ExtCtrls, ComCtrls, uGameTreeView, uEngineEditForm, uEngineRegistry,
  uEngineParamsJson, uMainForm, uChessPosition, uChessUciEngine, uGamePosition,
  uGameGuiProfile, uGameTree, uGuiDialogs, uGameTreeSearchRef,
  uGameSetupForm, uGameSetupTypes, uGameOrchestrator, uRunningGame, uGameBoardControl, Types, Math, uChessPgn, uGameTreePdn, uGameTreeActor, uGameTreeNodeData, uGameNotationView, uPvSnapshot, uGameGuiMessages, uGameFileReader, LCLType;
type TErrors=class
  procedure Report(Sender: TObject; E: Exception);
end;
type TGameAccept=class
  Main: TMainForm;
  Game: TRunningGame;
  procedure Accept(Sender: TObject; const Setup: TGameSetup);
end;
procedure TGameAccept.Accept(Sender: TObject; const Setup: TGameSetup);
begin Game:=Main.StartGameFromSetup(Setup); end;
var Checks: Integer=0;
procedure TErrors.Report(Sender: TObject; E: Exception);
begin WriteLn('FAIL: ',E.Message); DumpExceptionBackTrace(Output); Flush(Output); Halt(1); end;
procedure Check(Value: Boolean; const Text: string);
begin Inc(Checks); if not Value then raise Exception.Create(Text); end;
procedure Fake;
var Line,Move,Fen: string; P: TChessPosition; L: TStringList; I,N: Integer;
  Active,FirstSearch:Boolean;Trace:TextFile;Tracing:Boolean;
begin
  P:=TChessPosition.Create; L:=TStringList.Create; Move:='e2e4';Active:=False;FirstSearch:=True;
  Tracing:=(ParamStr(2)='autoplay') and (ParamStr(3)<>'');
  if Tracing then begin AssignFile(Trace,ParamStr(3));Rewrite(Trace);end;
  try
    while not EOF(Input) do begin
      ReadLn(Line);
      if Tracing then begin WriteLn(Trace,Line);Flush(Trace);end;
      if Line='uci' then begin
        if ParamStr(2)='hang' then Continue;
        if ParamStr(2)='exit-init' then Halt(3);
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
      end else if (Line='stop') and Active then begin
        // Completion of cancelled live analysis must be drained, never played.
        WriteLn('bestmove '+Move);Active:=False;
      end else if Copy(Line,1,3)='go ' then begin
        if ParamStr(2)='autoplay' then begin
          if FirstSearch then begin
            FirstSearch:=False;Active:=True;WriteLn('info depth 2 score cp 35 pv '+Move);
          end else begin
            // Deliberately differ from the cancelled live search's bestmove.
            if P.LegalMoveCount>1 then Move:=P.LegalMove(1);
            Sleep(80);WriteLn('info depth 3 score cp 45 pv '+Move);
            WriteLn('bestmove '+Move);
            WriteLn('info depth 99 score cp 999 pv '+Move);
          end;
          Flush(Output);Continue;
        end;
        if ParamStr(2)='silent' then Continue;
        WriteLn('info depth 1 score cp 10 pv '+Move); Flush(Output);
        if ParamStr(2)='live' then Sleep(650) else Sleep(40);
        WriteLn('info depth 2 score cp 35 time 40 pv '+Move); Flush(Output); Sleep(40);
        WriteLn('info depth 99 score cp 999 upperbound pv '+Move);
        if ParamStr(2)<>'live' then WriteLn('bestmove '+Move);
      end else if Line='quit' then Break;
      Flush(Output);
    end;
  finally if Tracing then CloseFile(Trace);L.Free; P.Free; end;
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
  G: TStringGrid; Tick: QWord; Name,IniName: string; Lines: TStringList;Index:Integer;Failed:Boolean;
begin
  Name:=EngineParamsFileName(Exe); IniName:=ChangeFileExt(Exe,'.uci-test.ini');
  P:=nil; AddOrUpdateParam(P,'hash','spin','64',False);
  AddOrUpdateParam(P,'Style','combo','Very Aggressive',False);
  AddOrUpdateParam(P,'Ponder','check','true',False);
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
    Check(G.Cells[2,Row(G,'Ponder')]='true','Discovery runtime false retains saved ponder opt-in');
    Check(FileExists(IniName),'Existing INI preparation reused');
    G.Col:=2; G.Row:=Row(G,'Clear Hash'); G.OnDblClick(G); for Tick:=1 to 10 do Pump;
    Button(F,'Launched correctly').Click;
    LoadEngineParamsFromJson(Name,'uci',Q);
    Check(EngineParamValue(Q,'hash','')='64','UCI values saved');
    Check(EngineParamValue(Q,'Ponder','false')='true','Editor saves the user ponder choice, not managed runtime false');
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
    DeleteFile(Name);D.Arguments:='--fake-uci exit-init';F.LoadEngine(D);Button(F,'Launch engine').Click;
    Tick:=GetTickCount64;
    repeat Pump;until (GetTickCount64-Tick>700);
    Failed:=False;for Index:=0 to F.ComponentCount-1 do
      if (F.Components[Index] is TMemo) and
        (Pos('UCI discovery failed',TMemo(F.Components[Index]).Text)>0) then Failed:=True;
    Check(Failed and (F.Caption='Edit engine'),'Editor reports failed engine discovery and remains usable');
    D.Arguments:='--fake-uci';F.LoadEngine(D);Button(F,'Launch engine').Click;
    Tick:=GetTickCount64;repeat Pump;until (Row(G,'Clear Hash')>0) or (GetTickCount64-Tick>5000);
    Check(Row(G,'Clear Hash')>0,'Discovery succeeds after a failed first launch');
    // Cancel a handshake while the worker waits: no UI-thread discovery loop.
    D.Arguments:='--fake-uci hang'; DeleteFile(Name); F.LoadEngine(D); Button(F,'Launch engine').Click;
    Pump; Tick:=GetTickCount64; Button(F,'Cancel').Click;
    Check(GetTickCount64-Tick<2500,'Cancel interrupts pending discovery promptly');
  finally F.Free; D.Free; Lines.Free; DeleteFile(Name); DeleteFile(IniName); end;
end;
procedure Analysis(const Exe: string);
var F: TMainForm; Engines: TExternalEngineList; D: TExternalEngineDefinition;
  Item: TMenuItem; Popup: TPopupMenu; Tick: QWord; Keys: TStringList; S: TGameTreeSearchRef; Fen: string;
  Info: TLabel;
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
    Info:=TLabel(F.FindComponent('AnnotatorPvInfoLabel'));
    Check((Info<>nil) and (Info.Align=alTop),'Annotator uses the existing PV information header above its moves');
    Check((Pos('score 0.35',Info.Caption)>0) and (Pos('time ',Info.Caption)>0),'Annotator score and time are visible in the header');
    // Stay on the position beyond the default one-second search + stop allowance.
    Tick:=GetTickCount64;repeat Pump(F);until GetTickCount64-Tick>2800;
    Check((F.TestAnalyzerRunner<>nil) and (F.ActiveGameTree.Root.AnnotatorScore='0.35') and
      (F.ActiveGameTree.Root.AnnotatorPV<>''),'Completed timed annotator stays loaded and retains score/PV');
    Check(F.ActiveGameTree.Root.ChildCount=0,'Analysis never adds moves or variations');
    Check(not Button(F,'Auto Play').Enabled,'Waiting game keeps Auto Play disabled');
    Check(not Menu(F,'Open MCTS annotator').Enabled,'MCTS remains disabled for chess');
    F.CollectBusyEngineKeys(Keys); Check(Keys.Count=1,'Existing reservation tracks UCI annotator');
    S:=F.TestAnalysis.Search;
    Fen:='4k3/8/8/8/8/8/8/R3K3 b - - 0 37'; F.LoadStandaloneFen(Fen);
    Tick:=GetTickCount64;
    repeat Pump(F); until (F.ActiveGameTree.Root.AnnotatorScore='-0.35') or (GetTickCount64-Tick>5000);
    Check(F.ActiveGameTree.Root.AnnotatorScore='-0.35','New Black root uses current context and White score');
    Check(Pos('score -0.35',Info.Caption)>0,'Header follows the current annotator position');
    Check(not SameGameTreeSearchRef(S,F.TestAnalysis.Search),'Position transition gets a new search reference');
    Check(F.ActiveGameTree.Root.ChildCount=0,'Navigation analysis preserves topology');
    Popup.OnPopup(Popup); Menu(F,'Close Annotator').Click; Tick:=GetTickCount64;
    repeat Pump(F); until (F.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
    Check(F.TestAnalyzerRunner=nil,'Existing runner shuts down UCI cleanly');
    Check(Pos('score ',Info.Caption)=0,'Closing annotator clears stale header values');
    Keys.Clear; F.CollectBusyEngineKeys(Keys); Check(Keys.Count=0,'Shutdown releases existing reservation');
  finally F.Free; Engines.Free; Keys.Free; DeleteFile(EnginesJsonFileName); end;
end;
procedure AutoPlay(const Exe:string);
var F:TMainForm;Engines:TExternalEngineList;D:TExternalEngineDefinition;
  Item:TMenuItem;Popup:TPopupMenu;Tick:QWord;K:Word;P:TChessPosition;
  Expected,Found,Wire,Trace,BeforeResult:string;Lines:TStringList;
  OldSearch:TGameTreeSearchRef;Changed:Boolean;A:TGameTreeActor;C:TGameTreeCommand;Data:TGameTreeNodeData;
  Memo:TGameNotationView;BeforeCount:Integer;Late:TGameTreeSearchRef;Snapshot:TPvSnapshot;CanClose:Boolean;
  Options:TGameTreePdnRenderOptions;Exported:string;Render:TGameTreePdnRenderResult;
  procedure CheckOriginDisplay;
  var View:TTreeView;I:Integer;Text,Original:string;
  begin
    View:=TTreeView.Create(nil);A:=TGameTreeActor.Create(F.ActiveGameTree,False);
    Original:=F.ActiveGameTree.MainlineNode[1].OriginText;
    try
      PopulateGameTreeView(View,F.ActiveGameTree);Text:='';
      for I:=0 to View.Items.Count-1 do Text+=View.Items[I].Text+LineEnding;
      Check(Pos('Auto Play: Auto Play UCI',Text)>0,'Tree details show readable annotator name');
      Data:=F.ActiveGameTree.MainlineNode[1].NodeData;
      Data.OriginText:='Auto Play: uci|c:\engines\stockfish.exe|stockfish.exe|cfg2:old';
      C:=A.CreateRestoreNodeDataCommand(F.ActiveGameTree.MainlineNode[1].NodeId,Data);
      try A.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;
      PopulateGameTreeView(View,F.ActiveGameTree);Text:='';
      for I:=0 to View.Items.Count-1 do Text+=View.Items[I].Text+LineEnding;
      Check((Pos('Auto Play: stockfish',Text)>0) and (Pos('cfg2:',Text)=0) and
        (Pos('c:\engines',Text)=0),'Legacy origin displays engine filename without registry details');
      Options:=DefaultGameTreePdnRenderOptions;
      RenderGameTreeMovesToPdn(F.ActiveGameTree,Options,Render);
      Check(Pos('Auto Play:',Render.Text)=0,
        'Legacy origins also stay out of move notation');
      Check(F.ActiveGameTree.MainlineNode[1].OriginText=Data.OriginText,
        'Rendering preserves original legacy provenance');
      Data.OriginText:=Original;
      C:=A.CreateRestoreNodeDataCommand(F.ActiveGameTree.MainlineNode[1].NodeId,Data);
      try A.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;
    finally A.Free;View.Free;end;
  end;
  procedure StartStopped(const Fen:string);
  var Setup:TGameSetup;Game:TRunningGame;Started:QWord;
  begin
    Setup:=Default(TGameSetup);Setup.StartingFEN:=Fen;Setup.TimeControl:=ChessGuiProfile.DefaultClock;
    Game:=F.StartGameFromSetup(Setup);Started:=GetTickCount64;
    repeat Pump(F);until (Game.Lifecycle=rglRunning) or (Game.Lifecycle=rglFinished) or
      (GetTickCount64-Started>5000);
    if Game.State=gosRunning then
      Check(not Button(F,'Auto Play').Enabled,'A running game disables chess Auto Play');
    F.MarkGameStopped(Game,'Auto Play fixture');Started:=GetTickCount64;
    repeat Pump(F);until (Game.Lifecycle=rglFinished) or (GetTickCount64-Started>5000);
    Check(Game.Lifecycle=rglFinished,'Auto Play fixture is a stopped game');
  end;
  procedure Escape;
  begin K:=VK_ESCAPE;F.OnKeyDown(F,K,[]);Pump(F);Check(K=0,'Escape is consumed');end;
  function MemoContains(const Text:string):Boolean;
  var I:Integer;
  begin
    Result:=False;
    for I:=0 to F.ComponentCount-1 do
      if (F.Components[I] is TMemo) and (Pos(Text,TMemo(F.Components[I]).Text)>0) then Exit(True);
  end;
begin
  Engines:=TExternalEngineList.Create;Lines:=TStringList.Create;P:=TChessPosition.Create;
  Trace:=GetTempFileName(GetTempDir,'uap');DeleteFile(Trace);
  D:=TExternalEngineDefinition.Create;D.Kind:=eekUci;D.ExePath:=Exe;D.UciId:='Auto Play UCI';
  D.Arguments:='--fake-uci autoplay "'+Trace+'"';Engines.Add(D);
  SaveExternalEngines(EnginesJsonFileName,Engines);F:=TMainForm.Create(nil);
  try
    StartStopped(ChessStartingFEN);
    Check(not Button(F,'Auto Play').Enabled,'No annotator disables chess Auto Play');
    Item:=Menu(F,'Open Annotator');Popup:=TPopupMenu(Item.GetParentMenu);Popup.OnPopup(Popup);Item.Items[0].Click;
    Tick:=GetTickCount64;
    repeat Pump(F);until (F.ActiveGameTree.Root.AnnotatorPV<>'') or (GetTickCount64-Tick>5000);
    Check(F.ActiveGameTree.Root.AnnotatorPV<>'','Live UCI analysis before Auto Play');
    OldSearch:=F.TestAnalysis.Search;BeforeResult:=F.ActiveGameTree.ResultText;
    A:=TGameTreeActor.Create(F.ActiveGameTree,False);
    try
      Data:=F.ActiveGameTree.Root.NodeData;Data.AnnotatorPVDepth:='40';Data.AnnotatorScore:='0.90';
      Data.EngineScore:='0.80';Data.EnginePV:='a2a3';Data.AutoPlayPV:='h2h3';
      C:=A.CreateRestoreNodeDataCommand(F.ActiveGameTree.Root.NodeId,Data);
      try A.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;
    finally A.Free;end;
    Expected:=P.LegalMove(1);Button(F,'Auto Play').Click;Tick:=GetTickCount64;
    repeat Pump(F);until (F.ActiveGameTree.MainlineCount>=2) or (GetTickCount64-Tick>5000);
    Check(F.ActiveGameTree.MainlineCount>=2,'Auto Play appends real mainline moves');
    Check(F.ActiveGameTree.MainlineNode[1].MoveText=Expected,'One-shot bestmove becomes a real move');
    Check((F.ActiveGameTree.Root.AutoPlayPV='h2h3') and (F.ActiveGameTree.ResultText=BeforeResult),
      'New Auto Play preserves the result and legacy analysis line');
    Check((F.ActiveGameTree.Root.AnnotatorPVDepth='40') and
      (F.ActiveGameTree.MainlineNode[1].AnnotatorPVDepth='3'),'Auto Play protects deeper stored analysis and stores new source analysis');
    Check((F.ActiveGameTree.Root.EngineScore='0.80') and
      (F.ActiveGameTree.MainlineNode[1].AnnotatorScore='-0.45'),'Game-engine fields stay intact and post-bestmove info is ignored');
    Check(F.ActiveGameTree.MainlineNode[1].OriginText='Auto Play: Auto Play UCI',
      'New nodes carry readable Auto Play provenance');
    Options:=DefaultGameTreePdnRenderOptions;
    RenderGameTreeMovesToPdn(F.ActiveGameTree,Options,Render);
    Check((Pos('Auto Play:',Render.Text)=0) and (Pos('A: ',Render.Text)>0),
      'Move notation retains evaluation without repeated Auto Play origin');
    Lines.Clear;F.ActiveGameTree.CopyMainlineMovesTo(Lines);P.LoadFromFEN(ChessStartingFEN);
    for K:=0 to Lines.Count-1 do P.PlayMove(Lines[K]);
    Check(TGameBoardControl(F.FindComponent('MainBoard')).Position.ToFEN=P.ToFEN,
      'Auto Play displays the real current node');
    Lines.LoadFromFile(Trace);Wire:=Lines.Text;
    Check(Button(F,'Stop').Enabled,'Active Auto Play exposes an enabled Stop button');
    Late:=F.TestAutoPlay.Search;
    Button(F,'Stop').Click;Found:=IntToStr(F.ActiveGameTree.MainlineCount);Tick:=GetTickCount64;
    Snapshot:=TPvSnapshot.Create;Snapshot.SetDataWithSearch(P,F.ActiveGameTree.MainlineCount,P.LegalMove(0),
      '9.99','99','1',Late,True);
    F.TestGuiEventQueue.Post(TAnalyzerSnapshotGuiMessage.Create(Snapshot));
    repeat Pump(F);until (not SameGameTreeSearchRef(OldSearch,F.TestAnalysis.Search)) or (GetTickCount64-Tick>5000);
    for K:=1 to 70 do Pump(F);
    Check(IntToStr(F.ActiveGameTree.MainlineCount)=Found,'Late cancelled reply cannot extend stopped Auto Play');
    Check(Button(F,'Auto Play').Enabled,'Stop restores chess Auto Play button');
    Check(F.ActiveGameTree.FindNodeById(Late.NodeId).AnnotatorScore<>'9.99',
      'A cancelled Auto Play snapshot cannot overwrite any node');
    CheckOriginDisplay;
    BeforeCount:=F.ActiveGameTree.MainlineCount;A:=TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True);
    try
      Options:=DefaultGameTreePdnRenderOptions;Options.FileFormat:=gffPgn;Options.LosslessPgn:=True;
      ImportChessPgn(GameTreeToPdnTextEx(F.ActiveGameTree,Options,'auto-play'),A,nil);
      Check((A.GameTree.MainlineCount=BeforeCount) and (A.GameTree.Root.AutoPlayPV='h2h3') and
        (A.GameTree.MainlineNode[1].OriginText=F.ActiveGameTree.MainlineNode[1].OriginText),
        'Lossless PGN preserves real moves, provenance and legacy Auto Play data');
      Options:=DefaultGameTreePdnRenderOptions;Options.FileFormat:=gffPgn;Options.LosslessPgn:=False;
      Exported:=GameTreeToPdnTextEx(F.ActiveGameTree,Options,'auto-play');ImportChessPgn(Exported,A,nil);
      Check((A.GameTree.MainlineCount=BeforeCount) and (A.GameTree.Root.EngineScore<>''),
        'Ordinary PGN retains the real moves and conventional score annotations');
    finally A.Free;end;
    GuiTestConfirmationResult:=mrCancel;
    try F.OnCloseQuery(F,CanClose);finally GuiTestConfirmationResult:=0;end;
    Check(not CanClose,'Existing save/discard protection protects the changed Auto Play game');
    Lines.LoadFromFile(Trace);
    Check(Pos('go movetime 1000',Lines.Text)>0,'Auto Play uses configured UCI movetime');
    Check(Pos('go movetime 1000',Copy(Lines.Text,Length(Wire)+1,MaxInt))>0,'Timed annotation resumes after Auto Play');
    // Starting from a real node, navigation cancels the pending Auto Play request.
    Button(F,'Auto Play').Click;Memo:=TGameNotationView(F.FindComponent('GameMoveMemo'));
    K:=VK_LEFT;Memo.OnKeyDown(Memo,K,[]);BeforeCount:=F.ActiveGameTree.MainlineCount;
    for K:=1 to 40 do Pump(F);
    Check(Button(F,'Auto Play').Enabled and (F.ActiveGameTree.MainlineCount=BeforeCount),
      'Navigating away stops Auto Play and rejects the late move');
    // An already drawn position must not send a think-once request.
    Popup.OnPopup(Popup);Menu(F,'Close Annotator').Click;Tick:=GetTickCount64;
    repeat Pump(F);until (F.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
    F.LoadStandaloneFen('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1');
    // A stopped custom-position fixture; a real game would already be gosGameOver.
    F.ActiveGameTree.SetGameState(gosStopped,Changed);
    Popup.OnPopup(Popup);Item.Items[0].Click;Tick:=GetTickCount64;
    repeat Pump(F);until (F.ActiveGameTree.Root.AnnotatorPV<>'') or (GetTickCount64-Tick>5000);
    Check(Button(F,'Auto Play').Enabled,'Stopped custom position enables Auto Play with annotator');
    BeforeResult:=F.ActiveGameTree.ResultText;
    Button(F,'Auto Play').Click;for K:=1 to 30 do Pump(F);
    Check(MemoContains('Auto Play stopped; reason=draw by insufficient mating material'),'Chess Auto Play shows its rule-based stop reason');
    Check((F.ActiveGameTree.Root.AutoPlayPV='') and (F.ActiveGameTree.Root.ChildCount=0) and
      (F.ActiveGameTree.ResultText=BeforeResult),'Already drawn Auto Play keeps the game result and topology unchanged');
    Popup.OnPopup(Popup);Menu(F,'Close Annotator').Click;
  finally F.Free;P.Free;Lines.Free;Engines.Free;DeleteFile(Trace);DeleteFile(EnginesJsonFileName);end;
end;
procedure Games(const Exe: string; RealEngine: Boolean=False);
var F: TMainForm; Dialog: TGameSetupForm; D: TExternalEngineDefinition; Engines: TExternalEngineList;
  Capture: TGameAccept; Edits: array[0..3] of TEdit; Combos: array[0..2] of TComboBox;
  I,N,M,CountBefore: Integer; Rejected: Boolean; BadDefinition: TExternalEngineDefinition; Tick: QWord; Setup: TGameSetup; B: TGameBoardControl; P: TPoint;
  WR,BR,WU,BU,Before: Double; LogInput: TRunningSnapshotLogInput; Keys: TStringList; A: TGameTreeActor; Text: string;
  function SquarePoint(Square: Integer): TPoint;
  var X,Y,Step: Integer;
  begin
    Step:=Max(1,B.BoardSquareSize div 2); Y:=0;
    while Y<B.ClientHeight do begin X:=0; while X<B.ClientWidth do begin
      if B.SquareAtPoint(X,Y)=Square then Exit(Point(X,Y)); Inc(X,Step);
    end; Inc(Y,Step); end;
    raise Exception.Create('Missing board square');
  end;
  procedure WaitPlies(Count: Integer);
  begin
    Tick:=GetTickCount64;
    repeat Pump(F); until (Capture.Game.GameTree.MainlineCount>=Count) or (GetTickCount64-Tick>8000);
    if Capture.Game.GameTree.MainlineCount<Count then begin Capture.Game.SnapshotLogInput(LogInput); WriteLn(LogInput.LogLinesText); Flush(Output); end;
    Check(Capture.Game.GameTree.MainlineCount>=Count,'Clocked GUI game receives expected moves; actual='+IntToStr(Capture.Game.GameTree.MainlineCount)+' state='+OrchestratorStateToString(Capture.Game.State)+' error='+Capture.Game.LastErrorText);
  end;
begin
  Engines:=TExternalEngineList.Create; Keys:=TStringList.Create;
  D:=TExternalEngineDefinition.Create; D.Kind:=eekUci; D.ExePath:=Exe; D.UciId:='Game UCI';
  if not RealEngine then D.Arguments:='--fake-uci'; Engines.Add(D);
  if not RealEngine then begin D:=TExternalEngineDefinition.Create; D.Kind:=eekHub; D.ExePath:=Exe; D.HubId:='Not Chess'; Engines.Add(D); end;
  SaveExternalEngines(EnginesJsonFileName,Engines);
  F:=TMainForm.Create(nil); Dialog:=TGameSetupForm.Create(F); Capture:=TGameAccept.Create; Capture.Main:=F;
  try
    Setup:=Default(TGameSetup); Setup.StartingFEN:=ChessStartingFEN; Setup.TimeControl:=ChessGuiProfile.DefaultClock;
    BadDefinition:=TExternalEngineDefinition.Create;
    try
      BadDefinition.Kind:=eekHub; BadDefinition.ExePath:=Exe;
      Setup.WhitePlayer:=pkRegistered; Setup.WhiteEngine:=BadDefinition;
      CountBefore:=TListBox(F.FindComponent('GameHistoryList')).Items.Count; Rejected:=False;
      try F.StartGameFromSetup(Setup); except on E:EConvertError do Rejected:=True; end;
      Check(Rejected,'Programmatic game start rejects wrong protocol');
      Check(TListBox(F.FindComponent('GameHistoryList')).Items.Count=CountBefore,'Rejected programmatic setup leaves no game/reservation');
    finally BadDefinition.Free; end;
    Dialog.OnAccepted:=@Capture.Accept; N:=0; M:=0;
    for I:=0 to Dialog.ComponentCount-1 do begin
      if Dialog.Components[I] is TEdit then begin Edits[N]:=TEdit(Dialog.Components[I]); Inc(N); end;
      if Dialog.Components[I] is TComboBox then begin Combos[M]:=TComboBox(Dialog.Components[I]); Inc(M); end;
    end;
    Check((N=4) and (M=3),'Existing New game fields/layout retained');
    Check(Edits[0].Text=ChessStartingFEN,'New game defaults to chess FEN');
    Check((Edits[1].Text='0') and (Edits[2].Text='5') and (Edits[3].Text='3'),'Chess GUI profile defaults to 5+3 sudden death');
    Dialog.Show; Pump(F); Check((Combos[0].Items.Count=2) and (Combos[1].Items.Count=2),'New game filters unsupported engines');
    Edits[2].Text:='unreadable'; GuiTestConfirmationResult:=mrOk;
    try Button(Dialog,'OK').Click; finally GuiTestConfirmationResult:=0; end;
    Check((Capture.Game=nil) and Dialog.Visible,'Unreadable time leaves dialog open without a game');
    Edits[2].Text:='0.05'; Edits[3].Text:='0.1'; Combos[1].ItemIndex:=1; Button(Dialog,'OK').Click;
    Check(Capture.Game<>nil,'Existing New game callback starts clocked chess');
    Tick:=GetTickCount64; repeat Pump(F); until ((Capture.Game.Lifecycle=rglRunning) and (Capture.Game.State=gosRunning)) or (GetTickCount64-Tick>5000);
    B:=TGameBoardControl(F.FindComponent('MainBoard'));
    P:=SquarePoint(13); B.OnMouseDown(B,mbLeft,[],P.X,P.Y);
    P:=SquarePoint(29); B.OnMouseDown(B,mbLeft,[],P.X,P.Y);
    WaitPlies(2); Check(Capture.Game.GameTree.MainlineNode[1].MoveText='e2e4','Human board input uses existing runner');
    Check(Capture.Game.GameTree.MainlineNode[2].HasClockInfo,'GUI game move retains clock data');
    F.CollectBusyEngineKeys(Keys); Check(Keys.Count=1,'Clocked game uses existing reservation');
    F.MarkGameStopped(Capture.Game,'GUI acceptance stop'); Tick:=GetTickCount64;
    repeat Pump(F); until (Capture.Game.Lifecycle=rglFinished) or (GetTickCount64-Tick>5000);
    Check((Capture.Game.Lifecycle=rglFinished) and (Capture.Game.GameTree.ResultText='*'),'Stop preserves unfinished GUI result');
    Keys.Clear; F.CollectBusyEngineKeys(Keys); Check(Keys.Count=0,'Finished game releases reservation');
    Text:=F.CurrentGameTreePdnText('test'); A:=TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True);
    try ImportChessPgn(Text,A,nil); Check(A.GameTree.MainlineCount=2,'Clocked game PGN reloads through existing adapter'); Check(A.GameTree.MainlineNode[2].HasClockInfo,'Clock annotations survive PGN reload'); finally A.Free; end;
    // Engine-as-White exercises a different player mapping through the same path.
    Setup:=Default(TGameSetup); Setup.StartingFEN:=ChessStartingFEN; Setup.TimeControl:=ChessGuiProfile.DefaultClock;
    Setup.TimeControl.MinutesPerPeriod:=0.05; Setup.TimeControl.IncrementSeconds:=0.1;
    Setup.WhitePlayer:=pkRegistered; Setup.WhiteEngine:=Engines[0]; Capture.Game:=F.StartGameFromSetup(Setup); WaitPlies(1);
    F.MarkGameStopped(Capture.Game,'done'); Tick:=GetTickCount64;
    repeat Pump(F); until (Capture.Game.Lifecycle=rglFinished) or (GetTickCount64-Tick>5000);
    Check(Capture.Game.Lifecycle=rglFinished,'Engine-as-White shuts down');
    if not RealEngine then begin
      // A quiet search must count down without engine info callbacks.
      Engines[0].Arguments:='--fake-uci silent'; Setup.WhiteEngine:=Engines[0]; Capture.Game:=F.StartGameFromSetup(Setup);
      Tick:=GetTickCount64; repeat Pump(F); until ((Capture.Game.Lifecycle=rglRunning) and (Capture.Game.State=gosRunning)) or (GetTickCount64-Tick>5000);
      Capture.Game.ProjectClocks(WR,BR,WU,BU); Before:=WR;
      for I:=1 to 25 do Pump(F); Capture.Game.ProjectClocks(WR,BR,WU,BU);
      Check((WR<Before-0.05) and (BU=0),'Quiet engine clock projects through existing snapshots');
      F.MarkGameStopped(Capture.Game,'quiet stop'); Tick:=GetTickCount64;
      repeat Pump(F); until (Capture.Game.Lifecycle=rglFinished) or (GetTickCount64-Tick>5000);
      Check((Capture.Game.Lifecycle=rglFinished) and (Capture.Game.GameTree.ResultText='*'),'Stop during quiet search is not a flag');
      Engines[0].Arguments:='--fake-uci live'; Capture.Game:=F.StartGameFromSetup(Setup); Tick:=GetTickCount64;
      repeat Pump(F); until (Capture.Game.GameTree.Root.EnginePVDepth='2') or (GetTickCount64-Tick>2500);
      Check((Capture.Game.GameTree.Root.EnginePVDepth='2') and (Capture.Game.GameTree.MainlineCount=0),'Live UCI info reaches existing game tree with raw stdout hidden');
      F.MarkGameStopped(Capture.Game,'live stop'); Tick:=GetTickCount64;
      repeat Pump(F); until (Capture.Game.Lifecycle=rglFinished) or (GetTickCount64-Tick>5000);
      Check(Capture.Game.Lifecycle=rglFinished,'Live-only search cancels cleanly');
    end;
    D:=TExternalEngineDefinition.Create; D.Assign(Engines[0]); D.UciId:='Second game UCI';
    if not RealEngine then begin Engines[0].Arguments:='--fake-uci'; D.Arguments:='--fake-uci'; end;
    Engines.Add(D); SaveExternalEngines(EnginesJsonFileName,Engines);
    Setup.BlackPlayer:=pkRegistered; Setup.BlackEngine:=D; Capture.Game:=F.StartGameFromSetup(Setup); WaitPlies(4);
    Keys.Clear; F.CollectBusyEngineKeys(Keys); Check(Keys.Count=2,'Two registered engines use the existing runner and reservation set');
    F.MarkGameStopped(Capture.Game,'match test done'); Tick:=GetTickCount64;
    repeat Pump(F); until (Capture.Game.Lifecycle=rglFinished) or (GetTickCount64-Tick>5000);
    Check(Capture.Game.Lifecycle=rglFinished,'Two-engine game joins both workers');
  finally Dialog.Free; Capture.Free; F.Free; Engines.Free; Keys.Free; DeleteFile(EnginesJsonFileName); end;
end;
procedure RealAnalysis(const Path: string);
var F: TMainForm; Engines: TExternalEngineList; D: TExternalEngineDefinition;
  Item: TMenuItem; Popup: TPopupMenu; Tick: QWord;Changed:Boolean;
  procedure CheckAutoPlay(const Fen,Reason:string;ExpectMoves:Boolean);
  var Started:QWord;Found:Boolean;I:Integer;
  begin
    Popup.OnPopup(Popup);Menu(F,'Close Annotator').Click;Started:=GetTickCount64;
    repeat Pump(F);until (F.TestAnalyzerRunner=nil) or (GetTickCount64-Started>5000);
    F.LoadStandaloneFen(Fen);F.ActiveGameTree.SetGameState(gosStopped,Changed);
    Popup.OnPopup(Popup);Item.Items[0].Click;
    Check(Button(F,'Auto Play').Enabled,'Stockfish Auto Play enabled for stopped position');
    Button(F,'Auto Play').Click;Started:=GetTickCount64;
    repeat
      Pump(F);Found:=False;
      for I:=0 to F.ComponentCount-1 do
        if (F.Components[I] is TMemo) and
          (Pos('Auto Play stopped; reason='+Reason,TMemo(F.Components[I]).Text)>0) then Found:=True;
    until Found or (GetTickCount64-Started>15000);
    Check(Found,'Stockfish Auto Play stop: '+Reason);
    Check((F.ActiveGameTree.MainlineCount>0)=ExpectMoves,'Stockfish Auto Play expected real moves');
    Check((F.ActiveGameTree.Root.AutoPlayPV='') and (F.ActiveGameTree.ResultText='*'),
      'Stockfish Auto Play preserves result without creating a virtual line');
  end;
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
    CheckAutoPlay('7k/5Q2/6K1/8/8/8/8/8 w - - 0 1','checkmate',True);
    CheckAutoPlay('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1','draw by insufficient mating material',False);
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
    AutoPlay(ExpandFileName(ParamStr(0)));Games(ExpandFileName(ParamStr(0)));
    if ParamStr(1)<>'' then begin RealAnalysis(ParamStr(1)); Games(ExpandFileName(ParamStr(1)),True); end;
    WriteLn('UCI GUI checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(nil); V.Free; Errors.Free; end;
end.
