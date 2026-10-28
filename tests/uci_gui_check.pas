program uci_gui_check;
{$mode objfpc}{$H+}
{$IFNDEF GWDGUI_NONINTERACTIVE_TEST}{$FATAL Build with LPI}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Controls, Classes, SysUtils,
  StdCtrls, Menus, Grids, ExtCtrls, uEngineEditForm, uEngineRegistry,
  uEngineParamsJson, uMainForm, uChessPosition, uChessUciEngine, uGamePosition,
  uGameGuiProfile, uGameTree, uGuiDialogs, uGameTreeSearchRef,
  uGameSetupForm, uGameSetupTypes, uGameOrchestrator, uRunningGame, uGameBoardControl, Types, Math, uChessPgn, uGameTreePdn, uGameTreeActor;
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
        if ParamStr(2)='silent' then Continue;
        WriteLn('info depth 1 score cp 10 pv '+Move); Flush(Output);
        if ParamStr(2)='live' then Sleep(650) else Sleep(40);
        WriteLn('info depth 2 score cp 35 time 40 pv '+Move); Flush(Output); Sleep(40);
        WriteLn('info depth 99 score cp 999 upperbound pv '+Move);
        if ParamStr(2)<>'live' then WriteLn('bestmove '+Move);
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
    Check(F.ActiveGameTree.Root.ChildCount=0,'Analysis never adds moves or variations');
    Check(not Button(F,'Auto Play').Enabled,'Auto Play remains disabled for chess');
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
    Games(ExpandFileName(ParamStr(0)));
    if ParamStr(1)<>'' then begin RealAnalysis(ParamStr(1)); Games(ExpandFileName(ParamStr(1)),True); end;
    WriteLn('UCI GUI checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(nil); V.Free; Errors.Free; end;
end.
