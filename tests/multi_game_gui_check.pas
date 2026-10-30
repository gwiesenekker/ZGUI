program multi_game_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,StdCtrls,
  uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,uEngineRegistry,
  uGameSetupTypes,uGameSetupForm,uGameOrchestrator,uRunningGame,uEngineEditForm,uMainForm,
  uEngineParamsJson,uGameBoardControl,uChessBoardControl,uDraughtsBoardControl,Menus,Controls,Dialogs,
  uChessUciEngine,uDraughtsHubEngine,uDraughtsDxpEngine,uDraughtsEngine,uEngineBase,
  uGameGuiMessages,uAnalyzerRunnerThread,uGuiDialogs,uGameTree,uGameTreeActor,uGameTreePdn,
  uChessPgn,uGameDocumentContext,uGameDatabase,uPreferences,Graphics,Grids,ExtCtrls,
  uTournamentDialog,uTournamentGridModel;
var Chess,Draughts:TGameVariant;Checks:Integer=0;RealEngines:Boolean=False;
procedure Check(Value:Boolean;const Msg:string);
begin Inc(Checks);if not Value then raise Exception.Create(Msg);end;
procedure Peer;
var L,Mode,Move,Fen,Raw,Whites,Blacks:string;P:TGamePosition;Parts:TStringList;I,N:Integer;Active:Boolean;
begin
  Mode:=ParamStr(2);Parts:=TStringList.Create;Active:=False;
  if Mode='uci' then P:=TChessPosition.Create else P:=TDraughtsPosition.Create;
  try
    while not EOF(Input) do begin
      ReadLn(L);
      if L='uci' then begin WriteLn('id name Mixed UCI');WriteLn('uciok');end
      else if L='hub' then begin WriteLn('id name=Mixed version=1');WriteLn('wait');end
      else if L='init' then WriteLn('ready') else if L='isready' then WriteLn('readyok')
      else if Copy(L,1,9)='position ' then begin
        Parts.Clear;ExtractStrings([' '],[],PChar(L),Parts);N:=Parts.IndexOf('moves');
        if Parts[1]='startpos' then P.LoadFromFEN(Chess.DefaultStartingFEN) else begin
          Fen:='';for I:=2 to 7 do begin if I>2 then Fen+=' ';Fen+=Parts[I];end;P.LoadFromFEN(Fen);
        end;
        if N>=0 then for I:=N+1 to Parts.Count-1 do P.PlayMove(Parts[I]);
      end else if Copy(L,1,4)='pos ' then begin
        Raw:=ExtractHubArgument(L,'pos');Whites:='';Blacks:='';
        for I:=2 to Length(Raw) do begin
          if Raw[I] in ['w','W'] then begin if Whites<>'' then Whites+=',';if Raw[I]='W' then Whites+='K';Whites+=IntToStr(I-1);end;
          if Raw[I] in ['b','B'] then begin if Blacks<>'' then Blacks+=',';if Raw[I]='B' then Blacks+='K';Blacks+=IntToStr(I-1);end;
        end;
        P.LoadFromFEN(Raw[1]+':W'+Whites+':B'+Blacks);Parts.Clear;
        Raw:=ExtractHubArgument(L,'moves');ExtractStrings([' '],[],PChar(Raw),Parts);
        for I:=0 to Parts.Count-1 do P.PlayMoveText(Parts[I]);
      end else if Copy(L,1,3)='go ' then begin
        Move:='';if P.LegalMoveCount>0 then Move:=P.LegalMove(0);
        if (Mode='uci') and P.IsLegal('f7g7') then Move:='f7g7';
        Active:=True;
        if Mode='uci' then WriteLn('info depth 8 score cp 42 pv '+Move)
        else WriteLn('info depth=8 score=0.42 pv="'+Move+'"');
        Flush(Output);
        if Pos('analyze',L)=0 then begin
          Sleep(180);
          if Mode='uci' then WriteLn('bestmove '+Move) else WriteLn('done move='+Move);
          Active:=False;
        end;
      end else if L='stop' then begin
        if Active then begin if Mode='uci' then WriteLn('bestmove '+Move) else WriteLn('done move='+Move);Active:=False;end;
      end else if L='quit' then Break;
      Flush(Output);
    end;
  finally P.Free;Parts.Free;end;
end;
function Button(Form:TForm;const Caption:string):TButton;
var I:Integer;
begin
  for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TButton) and
    (TButton(Form.Components[I]).Caption=Caption) then Exit(TButton(Form.Components[I]));
  raise Exception.Create('Missing button '+Caption);
end;
function Menu(Main:TMainForm;const Caption:string):TMenuItem;
var I:Integer;
begin
  for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TMenuItem then
    if TMenuItem(Main.Components[I]).Caption=Caption then Exit(TMenuItem(Main.Components[I]));
  raise Exception.Create('Missing menu '+Caption);
end;

procedure RegistryAndContexts;
var Candidate:TGameVariant;Rejected:Boolean;Setup:TGameSetup;Game:TRunningGame;
    Dialog:TGameSetupForm;Editor:TEngineEditForm;I:Integer;Kind:TComboBox;
begin
  Check(RegisteredGameCount=2,'Two application-owned games');
  Check((GameForEngineKind(eekUci)=Chess) and (GameForEngineKind(eekHub)=Draughts)
    and (GameForEngineKind(eekDxp)=Draughts),'Protocols map to registered variants');
  Check((GameVariantById('chess')=Chess) and (GameVariantById('draughts')=Draughts),'Stable game IDs');
  Rejected:=False;
  try TGameTree.Create(nil).Free;except on E:EGamePositionError do Rejected:=True;end;
  Check(Rejected,'Trees reject missing variants instead of consulting startup selection');
  Setup:=Default(TGameSetup);Rejected:=False;
  try GameSetupVariant(Setup);except on E:EGamePositionError do Rejected:=True;end;
  Check(Rejected,'Setups reject missing variants');
  RegisterDefaultGameVariant(nil);Rejected:=False;
  try DefaultGameVariant;except on E:EGamePositionError do Rejected:=True;end;
  RegisterDefaultGameVariant(Chess);
  Check(Rejected,'Linked game units do not install implicit defaults');
  Candidate:=TChessVariant.Create;Rejected:=False;
  try try RegisterGame(Candidate,ChessGuiProfile);except on E:EGamePositionError do Rejected:=True;end;
    Check(Rejected,'Duplicate registration rejected');finally Candidate.Free;end;
  Setup:=Default(TGameSetup);Setup.Variant:=Draughts;Setup.StartingFEN:=Draughts.DefaultStartingFEN;
  Setup.TimeControl:=DraughtsGuiProfile.DefaultClock;
  ValidateGameSetup(Setup,Draughts,DraughtsGuiProfile.EngineKinds);
  Game:=TRunningGame.Create(1,'Draughts',nil,pkHuman,pkHuman,'','','White','Black',nil,Setup);
  try Check(Game.GameTree.Variant=Draughts,'Running tree gets explicit variant despite chess process default');
    Game.AssignSetupTo(Setup);Check(Setup.Variant=Draughts,'Replay setup retains variant');
  finally Game.Free;end;
  Dialog:=TGameSetupForm.Create(nil,Draughts);Editor:=TEngineEditForm.Create(nil,Draughts);
  try
    Check(Dialog.Variant=Draughts,'Dialog has explicit target game');Editor.LoadEngine(nil);Kind:=nil;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TComboBox then
      if TComboBox(Editor.Components[I]).Items.IndexOf('UCI')>=0 then Kind:=TComboBox(Editor.Components[I]);
    Check((Kind<>nil) and SameText(Kind.Text,'hub'),'Draughts editor defaults to Hub while process starts as chess');
  finally Editor.Free;Dialog.Free;end;
end;
procedure Pump;
begin Application.ProcessMessages;Sleep(10);end;
procedure MixedViews;
var Main:TMainForm;ChessTree,DraughtsTree:Pointer;Setup:TGameSetup;A,B:TRunningGame;
    History:TListBox;Tick:QWord;I:Integer;
begin
  Main:=TMainForm.Create(nil);
  try
    Main.Show;Pump;ChessTree:=Main.ActiveGameTree;
    Check(Main.FindComponent('MainBoard') is TChessBoardControl,'Initial chess board');
    Main.LoadStandaloneFen('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
    Main.SelectGameVariant(Draughts);Pump;DraughtsTree:=Main.ActiveGameTree;
    Check(Main.FindComponent('MainBoard') is TDraughtsBoardControl,'Draughts board replaces chess view');
    Main.LoadStandaloneFen('W:W32:B27');
    Main.SelectGameVariant(Chess);Pump;
    Check((Pointer(Main.ActiveGameTree)=ChessTree) and (Main.ActiveGameTree.StartingFEN='4k3/8/8/8/8/8/8/R3K3 b - - 0 37'),
      'Chess standalone survives switching');
    Main.SelectGameVariant(Draughts);Pump;
    Check((Pointer(Main.ActiveGameTree)=DraughtsTree) and (Main.ActiveGameTree.StartingFEN='W:W32:B27'),
      'Draughts standalone survives switching');
    Setup:=Default(TGameSetup);Setup.Variant:=Chess;Setup.StartingFEN:=Chess.DefaultStartingFEN;
    Setup.TimeControl:=ChessGuiProfile.DefaultClock;A:=Main.StartGameFromSetup(Setup);
    Setup.Variant:=Draughts;Setup.StartingFEN:=Draughts.DefaultStartingFEN;
    Setup.TimeControl:=DraughtsGuiProfile.DefaultClock;B:=Main.StartGameFromSetup(Setup);
    Tick:=GetTickCount64;
    repeat Pump;Main.TestDrainGuiEvents(True);until ((A.State=gosRunning) and (B.State=gosRunning)) or (GetTickCount64-Tick>5000);
    Check((A.State=gosRunning) and (B.State=gosRunning),'Chess and draughts games run together');
    History:=TListBox(Main.FindComponent('GameHistoryList'));
    for I:=0 to 3 do begin
      if Odd(I) then History.ItemIndex:=History.Items.IndexOfObject(A) else History.ItemIndex:=History.Items.IndexOfObject(B);
      History.OnClick(History);Pump;
      if Odd(I) then Check(Main.ActiveGameTree.Variant=Chess,'Select running chess game')
      else Check(Main.ActiveGameTree.Variant=Draughts,'Select running draughts game');
    end;
    Main.MarkGameStopped(A,'test');Main.MarkGameStopped(B,'test');
    Tick:=GetTickCount64;repeat Pump;Main.TestDrainGuiEvents(True);until
      ((A.Lifecycle=rglFinished) and (B.Lifecycle=rglFinished)) or (GetTickCount64-Tick>5000);
    Check((A.Lifecycle=rglFinished) and (B.Lifecycle=rglFinished),'Both game workers finish');
  finally Main.Free;end;
end;

procedure PreferencesAndFiles;
var A,B,Legacy:TGuiPreferences;Db:TGameDatabase;Name:string;Lines:TStringList;V:TGameVariant;Rejected:Boolean;
begin
  A:=DefaultGuiPreferences;A.MainBoardLightColor:=clRed;A.EvaluationMaxScore:=7;A.NotationFontSize:=14;
  SaveGuiPreferences(A,'chess');B:=DefaultGuiPreferences;B.MainBoardLightColor:=clBlue;B.EvaluationMaxScore:=20;
  B.NotationFontSize:=14;SaveGuiPreferences(B,'draughts');LoadGuiPreferences(A,'chess');LoadGuiPreferences(B,'draughts');
  LoadGuiPreferences(Legacy);
  Check((A.MainBoardLightColor=clRed) and (B.MainBoardLightColor=clBlue),'Per-game board colours stay independent');
  Check((A.EvaluationMaxScore=7) and (B.EvaluationMaxScore=20),'Per-game evaluation range stays independent');
  Check(Legacy.MainBoardLightColor=DefaultGuiPreferences.MainBoardLightColor,'Legacy keys remain migration defaults');
  RememberGamePreference('draughts');Check(LastGamePreference='draughts','Startup remembers last game');RememberGamePreference('chess');
  Name:=GetTempFileName(GetTempDir,'mdb');DeleteFile(Name);
  Db:=TGameDatabase.Create(gffPgn);
  try Db.CreateDatabase(Name);Db.Close;Check(DatabaseFileVariant(Name,Chess)=Chess,'Chess database classified by strict preflight');finally Db.Free;DeleteFile(Name);end;
  Db:=TGameDatabase.Create(gffPdn);
  try Db.CreateDatabase(Name);Db.Close;Check(DatabaseFileVariant(Name,Chess)=Draughts,'Draughts database classified by strict preflight');finally Db.Free;DeleteFile(Name);end;
  Lines:=TStringList.Create;
  try
    Lines.Text:='Not a database';Lines.SaveToFile(Name);Rejected:=False;
    try V:=DatabaseFileVariant(Name,Chess);except on E:Exception do Rejected:=True;end;
    Check(Rejected,'Foreign database rejected');
    Lines.Text:='[Event "Ambiguous without FEN"] 1.e4 *';Lines.SaveToFile(Name);
    Check(GameFileCandidate(Name,Chess)=nil,'Unknown extension without game metadata requires explicit choice');
    Lines.Text:='[FEN "W:W32:B27"] *';Lines.SaveToFile(Name);
    Check(GameFileCandidate(Name,Chess)=Draughts,'Draughts FEN gives file candidate');
  finally Lines.Free;DeleteFile(Name);end;
end;

procedure EnginesAndSessions;
var Main:TMainForm;Engines:TExternalEngineList;Defs:array[0..5]of TExternalEngineDefinition;
    I,J:Integer;Setup:TGameSetup;A,B:TRunningGame;Tick:QWord;History:TListBox;
    CA,HA,NewCA:TAnalyzerRunnerThread;Busy:TStringList;Stale:TAnalyzerLogGuiMessage;CanClose:Boolean;
    Text,Name:string;Lines:TStringList;Actor:TGameTreeActor;Expected:TGameTree;
  procedure Drain;
  begin Pump;Main.TestDrainGuiEvents(True);end;
  procedure OpenAnnotator(Def:TExternalEngineDefinition);
  var Item:TMenuItem;Popup:TPopupMenu;K:Integer;Started:QWord;
  begin
    Item:=Menu(Main,'Open Annotator');Popup:=TPopupMenu(Item.GetParentMenu);Popup.OnPopup(Popup);
    for K:=0 to Item.Count-1 do if Item.Items[K].Hint=EngineIdentityKey(Def) then begin Item.Items[K].Click;Break;end;
    Started:=GetTickCount64;
    repeat Drain;until (Main.ActiveGameTree.Root.AnnotatorPV<>'') or (GetTickCount64-Started>5000);
    Check(Main.ActiveGameTree.Root.AnnotatorPV<>'','Context annotator produces a scored PV');
  end;
  procedure SaveReload(Game:TRunningGame;const ResultText:string);
  begin
    History.ItemIndex:=History.Items.IndexOfObject(Game);History.OnClick(History);Drain;
    Name:=GetTempFileName(GetTempDir,'mix');GuiTestFileName:=Name;GuiTestFileDialogResult:=1;
    try
      if Game.GameTree.Variant=Chess then Menu(Main,'&Save PGN...').Click else Menu(Main,'&Save PDN...').Click;
      Lines.LoadFromFile(Name);Text:=Lines.Text;
      Check(Pos('[Result "'+ResultText+'"]',Text)>0,'Save uses the selected game result');
      if Game.GameTree.Variant=Chess then begin
        Actor:=TGameTreeActor.Create(TGameTree.Create(Chess),True);
        try ImportChessPgn(Text,Actor,nil);Check(Actor.GameTree.MainlineCount=1,'Mixed chess Save reloads');finally Actor.Free;end;
      end else Check(Pos('32x21',Text)>0,'Mixed draughts Save uses draughts moves');
    finally GuiTestFileDialogResult:=-1;DeleteFile(Name);end;
  end;
  procedure Tournaments;
  var C,D:TTournamentDialog;K:Integer;CT,DT:TStringGrid;Started:QWord;CanQuit:Boolean;
      CFile,DFile:string;Before:string;
    function OpenTournament(V:TGameVariant):TTournamentDialog;
    var K:Integer;
    begin
      Main.SelectGameVariant(V);Button(Main,'Tournament...').Click;
      for K:=0 to Main.ComponentCount-1 do if Main.Components[K] is TTournamentDialog then
        if TTournamentDialog(Main.Components[K]).Variant=V then Exit(TTournamentDialog(Main.Components[K]));
      raise Exception.Create('Missing tournament context');
    end;
    procedure Configure(T:TTournamentDialog;const Root:string);
    var K:Integer;
    begin
      TEdit(T.FindComponent('TournamentStartingFEN')).Text:=Root;
      TEdit(T.FindComponent('TournamentMinutes')).Text:='0.03';
      for K:=0 to T.ComponentCount-1 do if T.Components[K] is TRadioGroup then TRadioGroup(T.Components[K]).ItemIndex:=1;
      Button(T,'Create pairing').Click;
    end;
  begin
    C:=OpenTournament(Chess);D:=OpenTournament(Draughts);
    Configure(C,'7k/5Q2/6K1/8/8/8/8/8 w - - 0 1');Configure(D,'W:W32:B27');
    CT:=TStringGrid(C.FindComponent('TournamentPairings'));DT:=TStringGrid(D.FindComponent('TournamentPairings'));
    Check((CT.RowCount=3) and (DT.RowCount=3),'Each tournament filters its own two playing engines');
    CFile:=GetTempFileName(GetTempDir,'ct');DFile:=GetTempFileName(GetTempDir,'dt');
    try
      C.SaveTournamentToFile(CFile);D.SaveTournamentToFile(DFile);
      Check((TournamentFileVariant(CFile,Chess)=Chess) and (TournamentFileVariant(DFile,Chess)=Draughts),
        'Tournament metadata selects its own variant');
      GuiTestConfirmationResult:=mrYes;
      try Button(C,'Play').Click;Button(D,'Play').Click;finally GuiTestConfirmationResult:=0;end;
      Check(C.IsRunning and D.IsRunning,'Both tournament schedulers run together');
      GuiTestConfirmationResult:=mrCancel;
      try Main.OnCloseQuery(Main,CanQuit);finally GuiTestConfirmationResult:=0;end;
      Check(not CanQuit and C.IsRunning and D.IsRunning,'Cancel application close retains both tournament schedulers');
      D.Hide;Main.SelectGameVariant(Chess);Started:=GetTickCount64;
      repeat Drain;until (not C.IsRunning and not D.IsRunning) or (GetTickCount64-Started>12000);
      Check(not C.IsRunning and not D.IsRunning,'Interleaved tournaments finish while one window is hidden');
      for K:=1 to 2 do begin
        Check(CT.Cells[TournamentColResult,K]<>'*','Chess standings receive their completed games');
        Check(DT.Cells[TournamentColResult,K]<>'*','Draughts standings receive their completed games');
      end;
      Lines.LoadFromFile(C.PdnFileName);Check(Pos('[Result "1-0"]',Lines.Text)>0,'Chess tournament publishes PGN');
      Lines.LoadFromFile(D.PdnFileName);Check(Pos('32x21',Lines.Text)>0,'Draughts tournament publishes PDN');
      Lines.LoadFromFile(DFile);Before:=Lines.Text;C.SaveTournamentToFile(CFile);Lines.LoadFromFile(DFile);
      Check(Lines.Text=Before,'Saving chess tournament does not rewrite draughts tournament');
    finally
      DeleteFile(C.PdnFileName);DeleteFile(D.PdnFileName);DeleteFile(CFile);DeleteFile(DFile);
    end;
  end;
begin
  Engines:=TExternalEngineList.Create;Busy:=TStringList.Create;Lines:=TStringList.Create;
  for I:=0 to 5 do begin
    Defs[I]:=TExternalEngineDefinition.Create;Defs[I].ExePath:=ExpandFileName(ParamStr(0));
    if I in [0,1,4] then begin Defs[I].Kind:=eekUci;Defs[I].UciId:='Chess '+IntToStr(I);Defs[I].Arguments:='--peer uci';end
    else begin Defs[I].Kind:=eekHub;Defs[I].HubId:='Draughts '+IntToStr(I);Defs[I].Arguments:='--peer hub';end;
    if RealEngines then begin
      J:=I+1;if I=4 then J:=1 else if I=5 then J:=4;
      Defs[I].ExePath:=ExpandFileName(ParamStr(J));Defs[I].ExecutableName:=ExtractFileName(Defs[I].ExePath);
      if Defs[I].Kind=eekHub then Defs[I].Arguments:='hub' else Defs[I].Arguments:='';
    end;
    Engines.Add(Defs[I]);
  end;
  SaveExternalEngines(EnginesJsonFileName,Engines);Main:=TMainForm.Create(nil);
  try
    Main.Show;Drain;History:=TListBox(Main.FindComponent('GameHistoryList'));
    Setup:=Default(TGameSetup);Setup.Variant:=Chess;Setup.StartingFEN:='7k/5Q2/6K1/8/8/8/8/8 w - - 0 37';
    Setup.TimeControl:=ChessGuiProfile.DefaultClock;Setup.TimeControl.MinutesPerPeriod:=0.03;Setup.TimeControl.IncrementSeconds:=0;Setup.WhitePlayer:=pkRegistered;Setup.BlackPlayer:=pkRegistered;
    Setup.WhiteEngine:=Defs[0];Setup.BlackEngine:=Defs[1];A:=Main.StartGameFromSetup(Setup);
    Setup.Variant:=Draughts;Setup.StartingFEN:='W:W32:B27';Setup.TimeControl:=DraughtsGuiProfile.DefaultClock;
    Setup.TimeControl.MinutesPerPeriod:=0.03;Setup.TimeControl.IncrementSeconds:=0;
    Setup.WhiteEngine:=Defs[2];Setup.BlackEngine:=Defs[3];B:=Main.StartGameFromSetup(Setup);
    Tick:=GetTickCount64;J:=0;
    repeat
      if Odd(J) then History.ItemIndex:=History.Items.IndexOfObject(A) else History.ItemIndex:=History.Items.IndexOfObject(B);
      History.OnClick(History);Drain;Inc(J);
    until ((A.Lifecycle=rglFinished) and (B.Lifecycle=rglFinished)) or (GetTickCount64-Tick>8000);
    Check((A.GameTree.ResultText='1-0') and (B.GameTree.ResultText='2-0'),'Concurrent engine games finish in correct results');
    Check((A.GameTree.MainlineCount=1) and (B.GameTree.MainlineCount=1),'Concurrent game trees contain only their own moves');
    SaveReload(A,'1-0');SaveReload(B,'1-0'); // Existing PDN export normalises 2-0 to 1-0.
    Main.SelectGameVariant(Chess);OpenAnnotator(Defs[4]);CA:=Main.TestAnalyzerRunner;
    Stale:=TAnalyzerLogGuiMessage.Create('old-session-must-not-appear',CA);
    Main.SelectGameVariant(Draughts);OpenAnnotator(Defs[5]);HA:=Main.TestAnalyzerRunner;
    Main.CollectBusyEngineKeys(Busy);Check(Busy.Count=2,'Both loaded annotator slots reserve engines');
    Main.TestGuiEventQueue.Post(TAnalyzerLogGuiMessage.Create('chess-hidden-log',CA));Drain;
    Check(Pos('chess-hidden-log',TMemo(Main.FindComponent('AnnotatorLogMemo')).Text)=0,'Hidden chess log stays out of draughts panel');
    Main.SelectGameVariant(Chess);Drain;
    Check(Main.TestAnalyzerRunner=CA,'Returning to chess retains the loaded annotator runner');
    Check(Pos('chess-hidden-log',TMemo(Main.FindComponent('AnnotatorLogMemo')).Text)>0,'Chess panel restores its own log');
    HA.PostShutdown;Tick:=GetTickCount64;
    repeat Drain;Main.CollectBusyEngineKeys(Busy);until (Busy.Count=1) or (GetTickCount64-Tick>5000);
    Check((Main.TestAnalyzerRunner=CA) and (Busy.Count=1),'Hidden slot finish releases only its own runner and reservation');
    Menu(Main,'Close Annotator').Click;Tick:=GetTickCount64;
    repeat Drain;until (Main.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
    OpenAnnotator(Defs[4]);NewCA:=Main.TestAnalyzerRunner;Check(NewCA.SessionId<>Stale.SessionId,'Restart allocates a new session generation');
    Main.TestGuiEventQueue.Post(Stale);Drain;
    Check(Pos('old-session-must-not-appear',TMemo(Main.FindComponent('AnnotatorLogMemo')).Text)=0,'Retired session message cannot affect replacement');
    Main.SelectGameVariant(Draughts);OpenAnnotator(Defs[5]);HA:=Main.TestAnalyzerRunner;
    GuiTestConfirmationResult:=mrCancel;try Main.OnCloseQuery(Main,CanClose);finally GuiTestConfirmationResult:=0;end;
    Check(not CanClose,'Cancel protects both standalone documents');
    Check(Main.TestAnalyzerRunner=HA,'Cancel retains the visible annotator');Main.SelectGameVariant(Chess);Drain;
    Check(Main.TestAnalyzerRunner=NewCA,'Cancel retains the hidden annotator');
    Menu(Main,'Close Annotator').Click;Main.SelectGameVariant(Draughts);Menu(Main,'Close Annotator').Click;
    Tick:=GetTickCount64;repeat Drain;Main.CollectBusyEngineKeys(Busy);until (Busy.Count=0) or (GetTickCount64-Tick>5000);
    // Remove the two analysis-only test registrations from the tournament lists.
    Engines.Delete(5);Engines.Delete(4);SaveExternalEngines(EnginesJsonFileName,Engines);
    Tournaments;
  finally Main.Free;Engines.Free;Busy.Free;Lines.Free;DeleteFile(EnginesJsonFileName);end;
end;

begin
  if ParamStr(1)='--peer' then begin
    Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;try Peer;finally Chess.Free;Draughts.Free;end;Halt;
  end;
  RealEngines:=ParamCount=4;
  RequireDerivedFormResource:=False;Application.Initialize;Application.ShowMainForm:=False;Application.CaptureExceptions:=False;
  Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
  RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
  try WriteLn('Registry');Flush(Output);RegistryAndContexts;
    WriteLn('Preferences/files');Flush(Output);PreferencesAndFiles;
    WriteLn('Views');Flush(Output);MixedViews;
    WriteLn('Engines/sessions');Flush(Output);EnginesAndSessions;WriteLn('Multi-game checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
