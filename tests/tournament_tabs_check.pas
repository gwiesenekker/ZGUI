program tournament_tabs_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,
  {$IFDEF LCLgtk2}Gtk2,Gtk2Proc,{$ENDIF} Forms,Classes,SysUtils,Controls,
  StdCtrls,ExtCtrls,ComCtrls,CheckLst,Grids,Dialogs,LCLIntf,FPJSON,JSONParser,uMainForm,
  uTournamentHostForm,uTournamentDialog,uTournamentGridModel,uGamePosition,
  uChessPosition,uDraughtsPosition,uGameGuiProfile,uEngineRegistry,uGameSetupTypes,
  uGameOrchestrator,uRunningGame,uDraughtsEngine,uDraughtsHubEngine,uEngineParamsJson,uGuiDialogs,uGameTree;
type TControlAccess=class(TControl);
var Chess,Draughts:TGameVariant;Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
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
        if (Pos('analyze',L)=0) and (ParamStr(3)<>'hold') then begin
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

function Button(F:TForm;const Caption:string):TButton;
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption=Caption) then Exit(TButton(F.Components[I]));
 raise Exception.Create('Button missing: '+Caption);
end;
function Grid(D:TTournamentDialog):TStringGrid;
begin Result:=TStringGrid(D.FindComponent('TournamentPairings'));end;
procedure Pump;
begin Application.ProcessMessages;Sleep(10);end;
function Contents(const Name:string):string;
var L:TStringList;
begin L:=TStringList.Create;try L.LoadFromFile(Name);Result:=L.Text;finally L.Free;end;end;
type TDecisions=class
public
 Answers:array of Integer;Index:Integer;
 procedure Show(Sender:TObject);
end;
type TStarts=class
public
 Original:TTournamentStartGameEvent;
 Owners:TList;
 procedure Start(Sender:TObject;const Setup:TGameSetup;const Prefix:string;out Game:TObject);
end;
procedure TStarts.Start(Sender:TObject;const Setup:TGameSetup;const Prefix:string;out Game:TObject);
begin
 Original(Sender,Setup,Prefix,Game);
 if Game<>nil then Owners.Add(Sender);
end;
procedure TDecisions.Show(Sender:TObject);
begin
 Check(Index<Length(Answers),'No unexpected extra close prompt');
 Check((TForm(Sender).ActiveControl is TButton) and
  (TButton(TForm(Sender).ActiveControl).Caption='Cancel'),'Close defaults to Cancel');
 TForm(Sender).ModalResult:=Answers[Index];Inc(Index);
end;
var Main:TMainForm;Host:TTournamentHostForm;Defs:TExternalEngineList;
    Tabs:array[0..3]of TTournamentDialog;I,J:Integer;Started:QWord;
    Directory,SaveName,Before,Published,Identity:string;D,Other:TTournamentDialog;
    Root:TGameTree;Page:TTabSheet;Rejected,CanClose:Boolean;L:TStringList;
    Decisions:TDecisions;Data:TJSONObject;Combo:TComboBox;Starts:TStarts;
procedure CheckTabReady(H:TTournamentHostForm;D:TTournamentDialog);
begin
 Check((TControlAccess(TControl(H)).AutoSizingLockCount=0) and
  (TControlAccess(TControl(H.Pages)).AutoSizingLockCount=0) and
  (TControlAccess(TControl(D)).AutoSizingLockCount=0),
  'Alignment is resumed before a completed tab returns');
 if H.Visible then Check((D.Parent.ClientWidth>=D.Constraints.MinWidth) and
  (D.Parent.ClientHeight>=D.Constraints.MinHeight),
  'Completed tab has its final measured bounds before pumping events');
 if H.Visible then Check(IsWindowVisible(H.Pages.Handle),
  'Native tab drawing is restored after assembly');
end;
procedure CheckHiddenHost;
var H:TTournamentHostForm;D:TTournamentDialog;
begin
 H:=TTournamentHostForm.Create(Main);
 try
  D:=H.NewTournament(Chess);CheckTabReady(H,D);
  Check(not H.Visible and not IsWindowVisible(H.Handle),
   'Assembling a hidden host does not accidentally show it');
  D:=H.NewTournament(Draughts);CheckTabReady(H,D);
  Check(not H.Visible and not IsWindowVisible(H.Handle),
   'Another hidden tab does not reveal the host');
 finally H.Free;end;
end;
procedure ChangeGame(D:TTournamentDialog;Variant:TGameVariant);
var C:TComboBox;Index:Integer;
begin
 C:=TComboBox(D.FindComponent('TournamentVariant'));
 Index:=C.Items.IndexOfObject(Variant);Check(Index>=0,'Target game exists in selector');
 C.SetFocus;
 C.DroppedDown:=True;Pump;
 {$IFDEF LCLgtk2}
 // Use the native signal path: GTK continues accessing its widget after OnChange.
 gtk_combo_box_set_active(PGtkComboBox(GetWidgetInfo(Pointer(C.Handle))^.CoreWidget),Index);
 {$ELSE}
 C.ItemIndex:=Index;C.OnChange(C);
 {$ENDIF}
 C.DroppedDown:=False;
 Pump;
end;
procedure Configure(D:TTournamentDialog;TwoRows:Boolean=False);
var I:Integer;
begin
 if D.Variant=Chess then TEdit(D.FindComponent('TournamentStartingFEN')).Text:='7k/5Q2/6K1/8/8/8/8/8 w - - 0 1'
 else TEdit(D.FindComponent('TournamentStartingFEN')).Text:='W:W32:B27';
 TEdit(D.FindComponent('TournamentMinutes')).Text:='1';
 for I:=0 to D.ComponentCount-1 do if D.Components[I] is TRadioGroup then TRadioGroup(D.Components[I]).ItemIndex:=Ord(TwoRows);
 Button(D,'Create pairing').Click;
 Check(Grid(D).RowCount=2+Ord(TwoRows),'Pairing uses the selected round-robin mode');
end;
procedure RegisterEngines(Hold:Boolean);
var I:Integer;D:TExternalEngineDefinition;
begin
 Defs.Clear;
 for I:=0 to 3 do begin
  D:=TExternalEngineDefinition.Create;D.ExePath:=ExpandFileName(ParamStr(0));
  if I<2 then begin D.Kind:=eekUci;D.UciId:='Chess '+IntToStr(I);D.Arguments:='--peer uci';end
  else begin D.Kind:=eekHub;D.HubId:='Draughts '+IntToStr(I);D.Arguments:='--peer hub';end;
  if Hold then D.Arguments:=D.Arguments+' hold';Defs.Add(D);
 end;
 SaveExternalEngines(EnginesJsonFileName,Defs);
end;
procedure NewFour;
var I:Integer;
begin
 for I:=0 to 3 do begin
  if I<2 then Tabs[I]:=Host.NewTournament(Chess) else Tabs[I]:=Host.NewTournament(Draughts);
  Configure(Tabs[I],(I=0) and (Pos('hold',Defs[0].Arguments)>0));
  if (I=0) and (Grid(Tabs[I]).RowCount=3) then begin
    Grid(Tabs[I]).Row:=1;Tabs[I].SetSelectedResult('1-0');
  end;
 end;
 Check(Host.Count=4,'Two chess and two draughts tournaments have separate tabs');
 for I:=0 to 3 do begin
  Tabs[I].SaveTournamentToFile(Directory+'/tour'+IntToStr(I)+'.json');
  Check(Tabs[I].Owner=Main,'Main-form component owner is preserved');
  for J:=0 to I-1 do begin
   Check(Tabs[J].TournamentIdentity<>Tabs[I].TournamentIdentity,'Tournament IDs are independent');
   Check(Tabs[J].PublicationFileName<>Tabs[I].PublicationFileName,'Publication paths are independent');
  end;
 end;
 GuiTestConfirmationResult:=mrYes;
 try for I:=0 to 3 do Button(Tabs[I],'Play').Click;finally GuiTestConfirmationResult:=0;end;
end;
function RunningGame(D:TTournamentDialog):TRunningGame;
var H:TListBox;I:Integer;G:TRunningGame;
begin
 Result:=nil;H:=TListBox(Main.FindComponent('GameHistoryList'));
 for I:=0 to H.Items.Count-1 do if H.Items.Objects[I] is TRunningGame then begin
  G:=TRunningGame(H.Items.Objects[I]);
  if (G.TournamentOwner=D) and (G.State=gosRunning) and (G.Lifecycle<>rglFinished) then Exit(G);
 end;
end;
procedure WaitStarted(D:TTournamentDialog);
begin
 Started:=GetTickCount64;repeat Pump;until (RunningGame(D)<>nil) or (GetTickCount64-Started>8000);
 Check(RunningGame(D)<>nil,'Tournament reaches a running engine search');
end;
procedure Tick(D:TTournamentDialog);
var I:Integer;
begin
 for I:=0 to D.ComponentCount-1 do if D.Components[I] is TTimer then
  TTimer(D.Components[I]).OnTimer(nil);
end;
procedure CheckFairness(Variant:TGameVariant);
var K,N:Integer;T:TTimer;
begin
 Starts.Owners.Clear;
 Host.OnStartGame:=@Starts.Start;
 for K:=0 to 2 do begin
  Tabs[K]:=Host.NewTournament(Variant);Configure(Tabs[K],True);
  for N:=0 to Tabs[K].ComponentCount-1 do
   if Tabs[K].Components[N] is TTimer then begin T:=TTimer(Tabs[K].Components[N]);T.Enabled:=False;end;
 end;
 GuiTestConfirmationResult:=mrYes;
 try
  for K:=0 to 2 do begin
   Button(Tabs[K],'Play').Click;
   for N:=0 to Tabs[K].ComponentCount-1 do
    if Tabs[K].Components[N] is TTimer then TTimer(Tabs[K].Components[N]).Enabled:=False;
  end;
 finally GuiTestConfirmationResult:=0;end;
 Started:=GetTickCount64;
 repeat
  Pump;
  // Deliberately give the newest tournament the first scheduling opportunity.
  for K:=2 downto 0 do Tick(Tabs[K]);
 until (Starts.Owners.Count=6) or (GetTickCount64-Started>20000);
 Check(Starts.Owners.Count=6,Variant.Name+': all six competing games start');
 for K:=0 to 5 do Check(TObject(Starts.Owners[K])=Tabs[K mod 3],
  Variant.Name+': oldest waiting tournament gets the next complete engine pair');
 Host.OnStartGame:=Starts.Original;
end;
procedure DiscardAll;
begin
 GuiTestConfirmationResult:=mrNo;
 try Check(Host.PrepareCloseAll and Host.FinishCloseAll,'Discard explicitly closes remaining tournament tabs');
 finally GuiTestConfirmationResult:=0;end;
 Check(Host.Count=0,'Closed host has no hidden tournament sessions');
end;
begin
 if ParamStr(1)='--peer' then begin
  Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
  try Peer;finally Chess.Free;Draughts.Free;end;Halt;
 end;
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 Chess:=RegisteredGame(0);Draughts:=RegisteredGame(1);RegisterDefaultGameVariant(Chess);
 Directory:=GetTempFileName(GetTempDir,'tabs');DeleteFile(Directory);ForceDirectories(Directory);
 Starts:=TStarts.Create;Starts.Owners:=TList.Create;
 Defs:=TExternalEngineList.Create;L:=TStringList.Create;Decisions:=TDecisions.Create;Main:=nil;
 try
  RegisterEngines(False);Main:=TMainForm.Create(nil);Main.Show;Pump;
  Button(Main,'Tournament...').Click;Host:=Main.TournamentHost;Check(Host.Count=1,'First open creates one tab');
  CheckHiddenHost;
  Starts.Original:=Host.OnStartGame;
  D:=Host.Dialogs[0];CheckTabReady(Host,D);Check(Host.ShowForVariant(Chess)=D,'Reopen selects existing same-game tab');
  Page:=Host.Pages.ActivePage;Identity:=D.TournamentIdentity;
  ChangeGame(D,Draughts);D:=Host.Dialogs[0];
  Check(Host.Visible and D.Visible,'Changing Chess to Draughts keeps tournament visible');
  Check((Host.Count=1) and (Host.Pages.ActivePage=Page) and (D.Variant=Draughts),
    'Native selector replaces settings inside the same tab');
  Check(D.TournamentIdentity<>Identity,'Native game switch receives a fresh identity');
  ChangeGame(D,Chess);D:=Host.Dialogs[0];
  Check(Host.Visible and D.Visible and (D.Variant=Chess),'Reverse native switch keeps tournament visible');
  Check(Host.CloseTournament(D),'An empty tab closes directly');
  D:=Host.NewTournament(Chess);D.TournamentName:='Edited draft';
  GuiTestConfirmationResult:=mrCancel;
  try Check(not Host.CloseTournament(D),'Edited empty settings are protected by Cancel');
  finally GuiTestConfirmationResult:=0;end;
  DiscardAll;
  Root:=Main.ActiveGameTree;NewFour;
  Check((Pos('Waiting for engine ',Grid(Tabs[1]).Cells[TournamentColReason,1])=1) and
    (Pos(Tabs[0].TournamentName,Grid(Tabs[1]).Cells[TournamentColReason,1])>0),
    'Shared chess engine wait identifies engine and owning tournament');
  Started:=GetTickCount64;
  repeat
   Pump;Rejected:=False;for I:=0 to 3 do Rejected:=Rejected or Tabs[I].IsRunning;
  until not Rejected or (GetTickCount64-Started>16000);
  Check(not Rejected,'Shared registrations eventually finish all four tournaments');
  for I:=0 to 3 do Check(Grid(Tabs[I]).Cells[TournamentColResult,1]<>'*','Each tournament receives its own result');
  Check(Main.ActiveGameTree=Root,'Background starts and completions preserve main document');
  DiscardAll;
  CheckFairness(Chess);DiscardAll;CheckFairness(Draughts);DiscardAll;
  RegisterEngines(True);NewFour;WaitStarted(Tabs[0]);WaitStarted(Tabs[2]);
  GuiTestConfirmationResult:=mrCancel;
  try Check(not Host.CloseTournament(Tabs[0]),'Cancel retains running tab');finally GuiTestConfirmationResult:=0;end;
  Check((Host.Count=4) and Tabs[0].IsRunning and Tabs[2].IsRunning,'Cancel does not stop either game');
  GuiTestConfirmationResult:=mrYes;GuiTestFileDialogResult:=0;
  try Check(not Host.CloseTournament(Tabs[0]),'Cancelled Save destination leaves tournament running');
  finally GuiTestConfirmationResult:=0;GuiTestFileDialogResult:=-1;end;
  Check(Tabs[0].IsRunning,'File-dialog cancellation sends no stop');
  SetLength(Decisions.Answers,2);Decisions.Answers[0]:=mrNo;Decisions.Answers[1]:=mrCancel;Decisions.Index:=0;
  GuiTestConfirmationOnShow:=@Decisions.Show;
  try Check(not Host.PrepareCloseAll,'Later Cancel abandons every close plan');
  finally GuiTestConfirmationOnShow:=nil;end;
  Check((Decisions.Index=2) and Tabs[0].IsRunning and Tabs[2].IsRunning,'Prepare-all cancellation stops nothing');
  SaveName:=Directory+'/closed.json';D:=Tabs[0];Identity:=D.TournamentIdentity;
  GuiTestConfirmationResult:=mrYes;GuiTestFileDialogResult:=1;GuiTestFileName:=SaveName;
  try Check(Host.CloseTournament(D),'Save stops, captures and closes one running tournament');
  finally GuiTestConfirmationResult:=0;GuiTestFileDialogResult:=-1;end;
  Check((Host.Count=3) and Tabs[1].IsRunning and Tabs[2].IsRunning and Tabs[3].IsRunning,
    'Closing one tab keeps the other three schedulers running');
  Before:=Contents(SaveName);Check(Pos('Stopped: tournament closed',Before)>0,'Saved row records explicit close-stop reason');
  Check(Pos('"result":"*"',StringReplace(Before,' ','',[rfReplaceAll]))>0,'Close-stopped result remains unfinished');
  D:=Host.OpenFile(SaveName,Chess);Check(D.TournamentIdentity=Identity,'Reopen retains saved tournament identity');
  Check(Grid(D).Cells[TournamentColResult,1]='1-0','Reopen keeps completed pairing result');
  Check(Host.OpenFile(SaveName,Chess)=D,'Opening same tournament again selects its tab');
  Check(Host.Count=4,'Reopening existing file does not duplicate its tab');
  // Release the shared engine so the saved stopped row can resume.
  GuiTestConfirmationResult:=mrNo;
  try Check(Host.CloseTournament(Tabs[1]),'Other shared tournament can close independently');
  finally GuiTestConfirmationResult:=0;end;
  GuiTestConfirmationResult:=mrYes;try Button(D,'Play').Click;finally GuiTestConfirmationResult:=0;end;
  WaitStarted(D);Check(D.IsRunning,'Only stopped/unplayed row resumes on Play');
  Check(Grid(D).Cells[TournamentColResult,1]='1-0','Resume does not replay a completed pairing');
  DiscardAll;
  RegisterEngines(False);D:=Host.NewTournament(Chess);Configure(D);
  SaveName:=Directory+'/ownership.json';D.SaveTournamentToFile(SaveName);Before:=Contents(SaveName);
  Other:=Host.NewTournament(Chess);Configure(Other);Rejected:=False;
  try Other.SaveTournamentToFile(SaveName);except on E:EInvalidOperation do Rejected:=True;end;
  Check(Rejected and (Contents(SaveName)=Before),'Save As rejects another tab file without changing bytes');
  Published:=D.PublicationFileName;Data:=TJSONObject(GetJSON(Before));
  try
   Data.Strings['tournament_id']:='different-id';Data.Strings['pdn_file_name']:=Published;
   L.Text:=Data.AsJSON;L.SaveToFile(Directory+'/conflict.json');
  finally Data.Free;end;
  Rejected:=False;
  try Host.OpenFile(Directory+'/conflict.json',Chess);except on E:EInvalidOperation do Rejected:=True;end;
  Check(Rejected,'A foreign session cannot claim an open publication file');
  D.TournamentName:='Same name';Other.TournamentName:='Same name';Pump;
  Check(Host.Pages.Pages[0].Caption<>Host.Pages.Pages[1].Caption,'Duplicate names have distinct visible labels');
  Page:=Host.Pages.ActivePage;Identity:=Other.TournamentIdentity;
  GuiTestConfirmationResult:=mrCancel;
  try ChangeGame(Other,Draughts);finally GuiTestConfirmationResult:=0;end;
  Check((Host.Count=2) and (Other.Variant=Chess),'Cancelled game switch preserves current tab and pairings');
  GuiTestConfirmationResult:=mrNo;
  try ChangeGame(Other,Draughts);finally GuiTestConfirmationResult:=0;end;
  Other:=Host.Dialogs[1];
  Check((Host.Count=2) and (Host.Pages.ActivePage=Page) and (Other.Variant=Draughts),
    'Game switch updates the same tab, not a new tab');
  Check((Other.TournamentName='Same name') and (Other.TournamentIdentity<>Identity),
    'Game switch keeps the name but gives incompatible data a fresh identity');
  Check(TEdit(Other.FindComponent('TournamentStartingFEN')).Text=Draughts.DefaultStartingFEN,
    'In-place game switch uses target-game defaults');
  Check(D.Variant=Chess,'Switching one tab leaves the other game intact');
  // A failed final Save leaves stopped tabs open and their prior files intact.
  ForceDirectories(Directory+'/directory-target');GuiTestConfirmationResult:=mrYes;
  GuiTestFileDialogResult:=1;GuiTestFileName:=Directory+'/directory-target';
  try Check(not Host.CloseTournament(D),'Failed final Save retains the tab');
  finally GuiTestConfirmationResult:=0;GuiTestFileDialogResult:=-1;end;
  Check(Host.Count=2,'Save failure does not silently discard a tab');
  Check(D.SaveFileName=SaveName,'Failed Save As retains the previous authoritative path');
  Data:=TJSONObject(GetJSON(Contents(SaveName)));
  try Check(Data.Get('tournament_id','')=D.TournamentIdentity,'Existing autosaved state remains readable after failed Save As');
  finally Data.Free;end;
  DiscardAll;
  Host.Font.Size:=18;D:=Host.NewTournament(Chess);CheckTabReady(Host,D);Pump;
  Check(D.Font.Size=18,'New tab inherits the host font');
  Check((D.Parent.ClientWidth>=D.Constraints.MinWidth) and
    (D.Parent.ClientHeight>=D.Constraints.MinHeight),'Host accommodates measured child minimums');
  Other:=Host.NewTournament(Draughts);Pump;
  Check(Host.ShowForVariant(Chess)=D,'Reopening main game selects its last-used tab');
  D.Close;Pump;
  Check((Host.Count=1) and (Host.Dialogs[0]=Other),'Child close routes through tab removal');
  Host.Pages.OnCloseTabClicked(Host.Pages.ActivePage);Pump;
  Check(Host.Count=0,'Tab X removes its session rather than hiding it');
  Host.Font.Size:=10;
  D:=Host.NewTournament(Chess);D.OnContextRequested(D,Draughts,'');
  Check(Host.Dialogs[0]=D,'A game request keeps its sender alive until the native event returns');
  Check(Host.CloseTournament(D),'A tab with a queued game switch can close safely');Pump;
  Check(Host.Count=0,'A queued switch cannot recreate a closed tab');
  D:=Host.NewTournament(Chess);Configure(D);
  Other:=Host.NewTournament(Draughts);Configure(Other);
  GuiTestConfirmationResult:=mrCancel;CanClose:=True;
  try Main.OnCloseQuery(Main,CanClose);finally GuiTestConfirmationResult:=0;end;
  Check(not CanClose and (Host.Count=2),'Application Close protects all tournament tabs');
  GuiTestConfirmationResult:=mrNo;CanClose:=False;
  try Host.OnCloseQuery(Host,CanClose);finally GuiTestConfirmationResult:=0;end;
  Check(CanClose and (Host.Count=0),'Host Close retires every session after decisions');
  WriteLn('Tournament tabs checks passed (',Checks,' checks)');
 finally
  GuiTestConfirmationOnShow:=nil;GuiTestConfirmationResult:=0;GuiTestFileDialogResult:=-1;
  Main.Free;Defs.Free;L.Free;Decisions.Free;Starts.Owners.Free;Starts.Free;DeleteFile(EnginesJsonFileName);
  RegisterDefaultGameVariant(nil);ClearRegisteredGames;
 end;
end.
