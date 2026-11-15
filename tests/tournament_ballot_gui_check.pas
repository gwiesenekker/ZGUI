program tournament_ballot_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 StdCtrls,Grids,CheckLst,ExtCtrls,FPJSON,JSONParser,uTournamentDialog,uTournamentStorage,
 uTournamentGridModel,uTournamentBallot,uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,
 uEngineRegistry,uGuiDialogs,uGameSetupTypes,uGameFileReader,uGameTreePdn;
type TStartProbe=class
  Positions:TStringList;
  procedure Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
end;
procedure TStartProbe.Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
begin Positions.Add(Setup.StartingFEN);Game:=nil;end;
var Checks:Integer=0;Directory:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
procedure WriteFile(const Name,Text:string);
var L:TStringList;
begin L:=TStringList.Create;try L.Text:=Text;L.SaveToFile(Name);finally L.Free;end;end;
procedure Click(D:TTournamentDialog;const Name:string);
var B:TButton;
begin B:=TButton(D.FindComponent(Name));Check(B<>nil,'Existing button '+Name);B.Click;Pump;end;
procedure Peers;
var L:TExternalEngineList;D:TExternalEngineDefinition;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try
  for I:=1 to 4 do begin
   D:=TExternalEngineDefinition.Create;D.ExePath:=ExpandFileName(ParamStr(0));D.Arguments:='--peer '+IntToStr(I);
   if I<=2 then begin D.Kind:=eekUci;D.UciId:='Chess '+IntToStr(I);end
   else begin D.Kind:=eekHub;D.HubId:='Draughts '+IntToStr(I);end;
   L.Add(D);
  end;
  SaveExternalEngines(EnginesJsonFileName,L);
 finally L.Free;end;
end;
procedure CheckCountSpace(D:TTournamentDialog);
var L:TLabel;Required:Integer;
begin
 L:=TLabel(D.FindComponent('TournamentBallotCount'));
 Required:=MeasureGuiText('9999 positions',L.Font).cx+MeasureGuiText('MM',L.Font).cx;
 Check(L.Width>=Required,'Count reserves measured space plus margin: width='+IntToStr(L.Width)+' required='+IntToStr(Required));
 Check((L.Left>=0) and (L.Left+L.Width<=L.Parent.ClientWidth),'Reserved count fits inside ballot row');
 Check(MeasureGuiText(L.Caption,L.Font).cx<L.Width,'Loaded count text fits with breathing room');
end;
procedure ForVariant(V:TGameVariant;const Name:string);
var D,Loaded:TTournamentDialog;P:TGamePosition;Fens:TStringList;List:TCheckListBox;
 Grid:TStringGrid;I,Row:Integer;Setup:TGameSetup;FileName,Snapshot,Bad,Identity:string;
 Probe:TStartProbe;Exported:TStringList;
 Data,RecordData:TJSONObject;Games:TJSONArray;Raised:Boolean;Reader:TGameFileReader;
begin
 D:=nil;Loaded:=nil;P:=V.CreatePosition;Fens:=TStringList.Create;
 Probe:=TStartProbe.Create;Probe.Positions:=TStringList.Create;Exported:=TStringList.Create;
 FileName:=Directory+'/'+Name+'.fen';Snapshot:=Directory+'/'+Name+'.json';Bad:=Directory+'/'+Name+'-bad.json';
 try
  P.LoadFromFEN(V.DefaultStartingFEN);P.PlayMove(P.LegalMove(0));Fens.Add(P.ToFEN);
  P.PlayMove(P.LegalMove(0));Fens.Add(P.ToFEN);WriteFile(FileName,Fens.Text);
  D:=TTournamentDialog.Create(nil,V);D.Show;Pump;
  Check(TLabel(D.FindComponent('TournamentBallotCount')).Caption='','No placeholder text before choosing a ballot');
  CheckCountSpace(D);
  List:=nil;
  for I:=0 to D.ComponentCount-1 do if D.Components[I] is TCheckListBox then List:=TCheckListBox(D.Components[I]);
  Check((List<>nil) and (List.Items.Count=2),'Only engines for the selected game offered');
  for I:=0 to List.Items.Count-1 do List.Checked[I]:=True;
  GuiTestFileName:=FileName;GuiTestFileDialogResult:=mrOk;
  try Click(D,'LoadOpeningBallot');finally GuiTestFileDialogResult:=-1;end;
  Check(TLabel(D.FindComponent('TournamentBallotCount')).Caption='2 positions','File chooser reports position count');
  D.Font.Size:=16;D.RefreshLayout;Pump;CheckCountSpace(D);
  D.Font.Size:=10;D.RefreshLayout;Pump;CheckCountSpace(D);
  Check(not TEdit(D.FindComponent('TournamentStartingFEN')).Enabled,'Single FEN cannot override ballot');
  Check(not TRadioGroup(D.FindComponent('TournamentPairingOptions')).Enabled,'Ballot retains double round-robin');
  Click(D,'CreatePairing');Grid:=TStringGrid(D.FindComponent('TournamentPairings'));
  Check((Grid.RowCount=5) and (D.StorageError=''),'Four games created through existing pairing and automatic-save paths: '+D.StorageError);
  Check(not TButton(D.FindComponent('LoadOpeningBallot')).Enabled,'Ballot cannot change beneath existing pairings');
  for Row:=1 to 4 do begin
   Check(D.GameSetupForRow(Row,Setup),'Existing game setup accepts row');
   Check(Setup.StartingFEN=Fens[(Row-1) div 2],'Runner setup receives its own saved position');
  end;
  for I:=0 to 1 do begin
   Check((Grid.Cells[TournamentColWhite,2*I+1]=Grid.Cells[TournamentColBlack,2*I+2]) and
    (Grid.Cells[TournamentColBlack,2*I+1]=Grid.Cells[TournamentColWhite,2*I+2]),'Consecutive games reverse engines');
  end;
  D.OnStartGame:=@Probe.Start;GuiTestConfirmationResult:=mrYes;
  try Click(D,'TournamentPlay');finally GuiTestConfirmationResult:=0;end;
  Check(Probe.Positions.Count=4,'Existing scheduler passes every row through the game-start callback');
  for I:=0 to 3 do Check(Probe.Positions[I]=Fens[I div 2],'Game-start callback receives the correct opening');
  for Row:=1 to 4 do begin
   Grid.Row:=Row;D.SetSelectedResult(V.ResultText(goDraw));
  end;
  D.SaveTournamentToFile(Snapshot);
  Data:=ReadTournamentDocument(Snapshot,GameGuiProfileFor(V).FileFormat);
  try
   Check(Data.Get('storage_version',0)=4,'Ballot save uses version 4, rejected by old readers');
   Games:=TJSONArray(Data.Find('games'));Check(Games.Count=4,'Every opening game saved');
   for I:=0 to 3 do begin
    RecordData:=TJSONObject(Games.Objects[I].Find('record'));
    Check(RecordData.Get('starting_fen','')=Fens[I div 2],'Per-game position persists in existing record');
   end;
   TJSONArray(TJSONObject(Data.Find('opening_ballot')).Find('positions')).Strings[0]:='invalid fen';
   for I:=0 to 1 do TJSONObject(Games.Objects[I].Find('record')).Strings['starting_fen']:='invalid fen';
   WriteFile(Bad,Data.AsJSON);
  finally Data.Free;end;
  Exported.LoadFromFile(D.PdnFileName);
  for I:=0 to 1 do Check(Pos('[FEN "'+Fens[I]+'"]',Exported.Text)>0,'Export headers preserve each distinct starting position');
  Reader:=CreateProfileReader(GameGuiProfileFor(V),V);
  try
   Reader.OpenFile(D.PdnFileName);Check(Reader.Entries.Count=4,'All ballot games exported through existing PGN/PDN projection');
   for I:=0 to 3 do TGameFileEntry(Reader.Entries[I]).Validate;
  finally Reader.Free;end;
  DeleteFile(FileName);FreeAndNil(D);
  Loaded:=TTournamentDialog.Create(nil,V);Loaded.LoadTournamentFromFile(Snapshot);Loaded.Show;Pump;
  Check(Loaded.StorageError='','Saved ballot loads after external FEN file is removed');
  Check(TLabel(Loaded.FindComponent('TournamentBallotCount')).Caption='2 positions','Embedded positions restore ballot UI');
  for Row:=1 to 4 do begin
   Check(Loaded.GameSetupForRow(Row,Setup) and (Setup.StartingFEN=Fens[(Row-1) div 2]),'Resume retains exact opening for each colour');
  end;
  Identity:=Loaded.TournamentIdentity;Raised:=False;
  try Loaded.LoadTournamentFromFile(Bad);except on E:EConvertError do Raised:=True;end;
  Check(Raised and (Loaded.TournamentIdentity=Identity),'Invalid saved FEN rejected before replacing current tournament');
  Raised:=False;try Loaded.ClearOpeningBallot;except on E:EInvalidOperation do Raised:=True;end;
  Check(Raised,'Cannot clear positions referenced by pairings');
  Grid:=TStringGrid(Loaded.FindComponent('TournamentPairings'));Grid.Row:=3;
  Loaded.RescheduleSelectedGame(nil);
  Check(Loaded.GameSetupForRow(3,Setup) and (Setup.StartingFEN=Fens[1]),'Replay uses original second opening');
  GuiTestConfirmationResult:=mrYes;
  try Click(Loaded,'ClearPairing');finally GuiTestConfirmationResult:=0;end;
  Click(Loaded,'ClearOpeningBallot');
  Check(TEdit(Loaded.FindComponent('TournamentStartingFEN')).Enabled,'Clearing ballot restores ordinary single-FEN tournament');
  Check(TLabel(Loaded.FindComponent('TournamentBallotCount')).Caption='','Clearing removes position count');CheckCountSpace(Loaded);
  WriteFile(FileName,Fens.Text);Loaded.LoadBallotFromFile(FileName);
  if V=RegisteredGame(0) then Loaded.ResetForVariant(RegisteredGame(1)) else Loaded.ResetForVariant(RegisteredGame(0));
  Check(TLabel(Loaded.FindComponent('TournamentBallotCount')).Caption='','Switching games clears game-specific ballot state');
 finally Loaded.Free;D.Free;P.Free;Fens.Free;Exported.Free;Probe.Positions.Free;Probe.Free;end;
end;
procedure RealBallot(const Name:string);
var D:TTournamentDialog;Fens:TStringList;I:Integer;List:TCheckListBox;
 Grid:TStringGrid;Setup:TGameSetup;Data:TJSONObject;
begin
 Fens:=TStringList.Create;D:=TTournamentDialog.Create(nil,RegisteredGame(1));
 try
  LoadOpeningBallot(Name,RegisteredGame(1),Fens);D.LoadBallotFromFile(Name);D.Show;Pump;
  List:=nil;for I:=0 to D.ComponentCount-1 do if D.Components[I] is TCheckListBox then List:=TCheckListBox(D.Components[I]);
  for I:=0 to List.Items.Count-1 do List.Checked[I]:=True;
  Click(D,'CreatePairing');Grid:=TStringGrid(D.FindComponent('TournamentPairings'));CheckCountSpace(D);
  Check(Grid.RowCount=1+2*Fens.Count,'Actual ballot creates exactly two rows per entry');
  for I:=1 to 2*Fens.Count do
   Check(D.GameSetupForRow(I,Setup) and (Setup.StartingFEN=Fens[(I-1) div 2]),'Every actual ballot row reaches the normal setup path');
  D.SaveTournamentToFile(Directory+'/real-ballot.json');
  Data:=ReadTournamentDocument(Directory+'/real-ballot.json',gffPdn);
  try Check(TJSONArray(Data.Find('games')).Count=2*Fens.Count,'Actual ballot snapshot contains every game');finally Data.Free;end;
  WriteLn('Actual GUI ballot: ',Fens.Count,' positions, ',Grid.RowCount-1,' rows');
 finally D.Free;Fens.Free;end;
end;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));Directory:=ExtractFilePath(ExpandFileName(ParamStr(0)))+'ballot-fixtures';ForceDirectories(Directory);
 try Peers;ForVariant(RegisteredGame(0),'chess');ForVariant(RegisteredGame(1),'draughts');
  if ParamCount>0 then RealBallot(ParamStr(1));
 finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
 WriteLn('Tournament ballot GUI checks passed (',Checks,' checks)');
end.
