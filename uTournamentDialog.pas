unit uTournamentDialog;

{$mode objfpc}{$H+}

interface

uses
  CheckLst, uGuiLayout, Classes, Contnrs, Controls, ExtCtrls, Forms, Grids, StdCtrls, SysUtils,
  Menus, SyncObjs, Types, uEngineRegistry, uGameSetupTypes, uTournamentGameRecord,
  uGameGuiProfile,uGamePosition,uGameOrchestrator;

type
  TTournamentRunningGame = class
  public
    Active: Boolean;
    PendingCapture: Boolean;
    CaptureError: string;
    GameId: Integer;
    Row: Integer;
  end;

  TTournamentContextEvent=procedure(Sender:TObject;Variant:TGameVariant;const FileName:string) of object;
  TTournamentTargetsEvent=procedure(Sender:TObject;const JsonFile,Publication,Identity:string) of object;
  TTournamentStartGameEvent = procedure(Sender: TObject; const ASetup: TGameSetup;
    const ATitlePrefix: string; out AGame: TObject) of object;
  TTournamentSelectGameEvent = procedure(Sender: TObject; AGame: TObject) of object;

  TTournamentDialog = class(TGuiLayoutForm)
  private
    FOnContextRequested:TTournamentContextEvent;
    FOnTargets:TTournamentTargetsEvent;
    FOnTitleChanged:TNotifyEvent;
    FCloseStopped:Boolean;
    FGameCombo:TComboBox;
    procedure NameChanged(Sender:TObject);
    function GetTournamentName:string;
    procedure SetTournamentName(const Value:string);
    procedure GameContextChanged(Sender:TObject);
    procedure StartingFENChanged(Sender:TObject);
  private
    FVariant:TGameVariant;
    FProfile:TGameGuiProfile;
    FAcceptedTournamentSignature: string;
    FInitialSettingsSignature: string;
    FBlackEngines: TStringList;
    FClosing: Boolean;
    FCrossTableGrid: TStringGrid;
    FEngineCheckList: TCheckListBox;
    FEngines: TExternalEngineList;
    FFileName: string;
    FPdnFileName: string;
    FPdnFileOwned: Boolean;
    FPdnPublishedHash: string;
    FVerifiedPdnFingerprint: string;
    FStorageNotice: string;
    FTournamentId: string;
    FStorageError: string;
    FGrid: TStringGrid;
    FConcurrentGamesEdit: TEdit;
    FIncrementEdit: TEdit;
    FIncrementModeCombo: TComboBox;
    FInvalidationPanel: TPanel;
    FLoadingTournament: Boolean;
    FLastGameStartTick: QWord;
    FMinutesEdit: TEdit; // Quantity in the selected display unit.
    FTimeUnitCombo: TComboBox;
    FStopButton: TButton;
    FRefereeStopPending: Boolean;
    FMovesEdit: TEdit;
    FOnSelectGame: TTournamentSelectGameEvent;
    FOnStartGame: TTournamentStartGameEvent;
    FPdnWriteLock: TCriticalSection;
    FRoundRobinGroup: TRadioGroup;
    FRunning: Boolean;
    FRunningGames: TList;
    FGameRecords: TObjectList;
    FLegacyPdnFileName: string;
    FStartStopButton: TButton;
    FStartingFENEdit: TEdit;
    FTimer: TTimer;
    FTournamentNameEdit: TEdit;
    FWhiteEngines: TStringList;
    function ReadSettings:TTimeControl;
    function ConfirmSharedExecutables:Boolean;
    function GameFileExtension:string;
    procedure AddLabelledEdit(AParent: TWinControl; const ACaption: string;
      AEdit: TEdit; var ATop: Integer);
    procedure AdjustPairingGridColumnWidths;
    procedure ApplyInvalidatingChange(Sender: TObject);
    function GameRecord(ARow: Integer): TTournamentGameRecord;
    procedure CaptureTournamentGame(ARunningGame: TTournamentRunningGame;
      AGame: TObject);
    procedure WritePdnProjection;
    procedure ClearPairingsClick(Sender: TObject);
    procedure ClearStaleRunningReasons;
    procedure AutoSaveTournament;
    procedure SaveTournamentSnapshot(const AFileName: string);
    procedure EnsureStoragePaths;
    function StartNewTournamentStorage: Boolean;
    procedure ClearTournamentGameRefs;
    procedure CollectPairingRows(AWhiteEngines, ABlackEngines,
      AResults: TStrings);
    procedure CollectRoundRows(ARounds: TStrings);
    procedure CollectSelectedEngines(AEngines: TStrings);
    procedure ConfigurePairingGridColumns;
    procedure CreatePairingClick(Sender: TObject);
    function DisplayNameForEngine(AEngine: TExternalEngineDefinition): string;
    function EngineByDisplayName(const AName: string): TExternalEngineDefinition;
    function EngineKeyForName(const AName: string): string;
    function EngineForRow(ARow: Integer; White: Boolean): TExternalEngineDefinition;
    function ActiveRunningGameCount: Integer;
    function FindNextUnplayedRow: Integer;
    function FindTournamentGameByRow(ARow: Integer): TTournamentRunningGame;
    function HasNonByeResults: Boolean;
    function MaxConcurrentGames: Integer;
    procedure HighlightRow(ARow: Integer);
    procedure InvalidateTournamentResults(Sender: TObject);
    function IsRowRunning(ARow: Integer): Boolean;
    function IsRowStartable(ARow: Integer; ABusyEngineKeys: TStrings): Boolean;
    procedure LoadClick(Sender: TObject);
    function PendingInvalidatingChange: Boolean;
    procedure PairingGridDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure PairingGridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PopulateEngines;
    procedure RevertInvalidatingChange(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SetSelectedResultClick(Sender: TObject);
    procedure StartStopClick(Sender: TObject);
    procedure RefereeStopClick(Sender: TObject);
    procedure StartPendingGames;
    procedure LeaveEngineQueue;
    procedure StartFailure(ARow: Integer; const AReason: string);
    procedure StopRunningGames(const AReason:string='Tournament stopped');
    procedure TimerTick(Sender: TObject);
    function TournamentSignature: string;
    function SettingsSignature: string;
    procedure UpdateButtons;
    procedure UpdateCrossTable;
  protected
    function CaptureGamePdn(AGame: TObject): string; virtual;
  public
    procedure RefreshLayout; override;
    procedure ResetForVariant(AVariant:TGameVariant);
    procedure LoadTournamentFromFile(const AFileName: string);
    procedure SaveTournamentToFile(const AFileName: string);
    procedure SetSelectedResult(const AResultText: string);
    function GameSetupForRow(ARow: Integer; out ASetup: TGameSetup): Boolean;
    procedure RescheduleSelectedGame(Sender: TObject);
    function PdnFileName: string;
    property SaveFileName: string read FFileName;
    property StorageError: string read FStorageError;
    procedure BeginShutdown;
    constructor Create(AOwner:TComponent;AVariant:TGameVariant); reintroduce;
    property Variant:TGameVariant read FVariant;
    destructor Destroy; override;
    procedure GameStopped(AGame: TObject);
    procedure GameRemoved(AGame: TObject);
    procedure RegisterRunningGame(ARow: Integer; AGame: TObject);
    procedure AcceptInitialSettings;
    function HasTournamentData: Boolean;
    function IsRunning: Boolean;
    function SaveTournamentWithDialog: Boolean;
    function ChooseSaveFileName(out FileName:string):Boolean;
    procedure StopForClose;
    function DrainClose:Boolean;
    property TournamentName:string read GetTournamentName write SetTournamentName;
    property TournamentIdentity:string read FTournamentId;
    property PublicationFileName:string read FPdnFileName;
    property OnTargets:TTournamentTargetsEvent read FOnTargets write FOnTargets;
    property OnTitleChanged:TNotifyEvent read FOnTitleChanged write FOnTitleChanged;
    property OnContextRequested:TTournamentContextEvent read FOnContextRequested write FOnContextRequested;
    property OnSelectGame: TTournamentSelectGameEvent read FOnSelectGame write FOnSelectGame;
    property OnStartGame: TTournamentStartGameEvent read FOnStartGame write FOnStartGame;
  end;

implementation

uses
  uGameDocumentContext, Dialogs, SHA1, FPJSON, Graphics, JSONParser, Math, LazFileUtils,
  uGuiDialogs, uMainForm, uRunningGame, uTournamentGridModel, uTournamentModel,
  uTournamentPairing, uTournamentResults, uTournamentTypes, uTournamentStorage,
  uAtomicFile, uGameTreePdn, uDraughtsPdn, LazLoggerBase, uTournamentEngineQueue;

procedure DrawGridText(AGrid: TStringGrid; ACol, ARow: Integer;
  const ARect: TRect);
var
  TextRect: TRect;
begin
  AGrid.Canvas.FillRect(ARect);
  TextRect := ARect;
  InflateRect(TextRect, -4, -2);
  AGrid.Canvas.TextRect(TextRect, TextRect.Left,
    TextRect.Top + Max(0, (TextRect.Height -
    AGrid.Canvas.TextHeight(AGrid.Cells[ACol, ARow])) div 2),
    AGrid.Cells[ACol, ARow]);
end;

function TournamentReasonIsTransient(const AReason: string): Boolean;
begin
  Result := SameText(Trim(AReason), 'Running') or
    SameText(Trim(AReason), 'Stopping') or SameText(Trim(AReason),'Waiting for a free engine') or
    (Copy(AReason,1,19)='Waiting for engine ') or SameText(Trim(AReason),'Stopped: tournament closed');
end;

const
  TournamentLaunchStaggerMs = 1000;

function TournamentEngineEndText(AGame:TRunningGame):string;
var Reason,Actor,Code:string;
begin
  Reason:=AGame.EngineEndReasonText;Actor:=AGame.EngineEndActorText;
  Code:=AGame.EngineEndCodeText;
  if Reason='' then Reason:=AGame.GameEndReasonText;
  if Reason='' then Reason:='Engine ended game';
  Reason:=UpperCase(Copy(Reason,1,1))+Copy(Reason,2,MaxInt);Result:=Reason;
  if Actor<>'' then begin
    if SameText(Reason,'Draw claimed') then Result:=Actor+' claimed draw'
    else if SameText(Reason,'Win claimed') then Result:=Actor+' claimed win'
    else if SameText(Reason,'Resigned') then Result:=Actor+' resigned'
    else if Copy(Reason,1,Length('Engine ended game'))='Engine ended game' then
      Result:=Actor+' ended game'+Copy(Reason,Length('Engine ended game')+1,MaxInt)
    else Result:=Actor+': '+Reason;
  end;
  if (Code<>'') and (Pos(Code,Result)=0) then Result+=' ('+Code+')';
end;

function TournamentRuleEndText(const AReason:string):string;
var Reason:string;
begin
  Reason:=Trim(AReason);
  if Copy(LowerCase(Reason),1,8)='draw by ' then
    Result:='Orchestrator declared '+LowerCase(Copy(Reason,1,1))+Copy(Reason,2,MaxInt)
  else if SameText(Reason,'stalemate') then Result:='Orchestrator declared draw by stalemate'
  else if SameText(Reason,'checkmate') then Result:='Orchestrator declared checkmate'
  else Result:='Orchestrator: '+UpperCase(Copy(Reason,1,1))+Copy(Reason,2,MaxInt);
end;

function TournamentPlayedReason(const AReason:string):string;
var P:Integer;
begin
  Result:=Trim(AReason);P:=Pos('. Referee declared ',Result);
  if P=0 then P:=Pos('. Referee set result to ',Result);
  if P=0 then P:=Pos('. Operator set result to ',Result);
  if P>0 then Result:=Copy(Result,1,P-1)
  else if (Pos('Referee declared ',Result)=1) or (Pos('Referee set result to ',Result)=1) or
    (Pos('Operator set result to ',Result)=1) or SameText(Result,'Manual result') then Result:='';
end;

function TournamentRefereeReason(const AReason,AResult:string;AFormat:TGameFileFormat):string;
begin
  Result:=TournamentPlayedReason(AReason);
  if Result<>'' then Result+='. ';
  case ParseTournamentResult(AResult,AFormat) of
    trWhiteWin:Result+='Referee declared win for White';
    trBlackWin:Result+='Referee declared win for Black';
    trDraw:Result+='Referee declared draw';
  else Result+='Referee declared unfinished game';end;
end;

procedure ApplyTournamentGameResultToRow(AGrid: TStringGrid; ARow: Integer;
  AGame: TRunningGame; AFormat:TGameFileFormat);
var
  ResultText: string;
begin
  if (AGrid = nil) or (AGame = nil) or (ARow <= 0) or
    (ARow >= AGrid.RowCount) then
    Exit;

  ResultText := AGame.ResultText;
  AGrid.Cells[TournamentColResult, ARow] := ResultText;
  if AGame.State = gosError then
    AGrid.Cells[TournamentColReason, ARow] := AGame.LastErrorText
  else if (AGame.EngineEndReasonText <> '') or (AGame.EngineEndActorText<>'') or
    (AGame.EngineEndCodeText<>'') then
    AGrid.Cells[TournamentColReason, ARow] := TournamentEngineEndText(AGame)
  else if AGame.GameEndReasonText<>'' then
    AGrid.Cells[TournamentColReason, ARow] := TournamentRuleEndText(AGame.GameEndReasonText)
  else if ResultText = '*' then
    AGrid.Cells[TournamentColReason, ARow] := 'Unknown result'
  else if ParseTournamentResult(ResultText,AFormat)=trDraw then
    AGrid.Cells[TournamentColReason, ARow] := 'Draw'
  else
    AGrid.Cells[TournamentColReason, ARow] := 'Game finished';
end;

function TournamentRunningGameFor(AOwner: TComponent;
  ARunningGame: TTournamentRunningGame): TRunningGame;
begin
  Result := nil;
  if (ARunningGame = nil) or not (AOwner is TMainForm) then
    Exit;
  Result := TMainForm(AOwner).FindGameById(ARunningGame.GameId);
end;

function SafeFileNameText(const AText: string): string;
var
  I: Integer;
begin
  Result := Trim(AText);
  if Result = '' then
    Result := 'Tournament';
  for I := 1 to Length(Result) do
    if Result[I] in ['/', '\', ':', '*', '?', '"', '<', '>', '|'] then
      Result[I] := '_';
end;

constructor TTournamentDialog.Create(AOwner:TComponent;AVariant:TGameVariant);
var
  ButtonPanel: TPanel;
  ContentPanel: TPanel;
  CreateButton: TButton;
  ClearButton: TButton;
  CrossTablePanel: TPanel;
  EnginePanel: TPanel;
  GridPanel: TPanel;
  LabelControl: TLabel;
  LoadButton: TButton;
  PairingPanel: TPanel;
  PairingPopup: TPopupMenu;
  PanelButton: TButton;
  PanelLabel: TLabel;
  PopupItem: TMenuItem;
  SaveButton: TButton;
  Splitter: TSplitter;
  TopPos: Integer;
  Id: TGUID;
  GameIndex:Integer;
  NameLabel,FenLabel,MovesLabel,MinutesLabel,IncrementLabel,ConcurrentLabel,TimeLabel:TLabel;
  SettingsColumn,FenRow,PairingActions:TPanel;
begin
  inherited Create(AOwner);
  DisableAlign;
  try
  if AVariant=nil then raise EGamePositionError.Create('Missing dialog game variant');
  FVariant:=AVariant;
  FProfile:=GameGuiProfileFor(FVariant);
  if CreateGUID(Id) <> 0 then
    raise EInOutError.Create('Could not create a tournament identity');
  FTournamentId := GUIDToString(Id);

  Caption := 'Tournament';
  Position := poDesigned;
  Width := 980;
  Height := 680;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 520;

  FWhiteEngines := TStringList.Create;
  FBlackEngines := TStringList.Create;
  FEngines := TExternalEngineList.Create;
  FRunningGames := TList.Create;
  FGameRecords := TObjectList.Create(True);
  FPdnWriteLock := TCriticalSection.Create;

  ButtonPanel := TPanel.Create(Self);
  ButtonPanel.Parent := Self;
  ButtonPanel.Align := alTop;
  ButtonPanel.Height := 180;
  ButtonPanel.BevelOuter := bvNone;
  ButtonPanel.BorderSpacing.Around := 8;

  TopPos := 4;
  FTournamentNameEdit := TEdit.Create(Self);
  FTournamentNameEdit.Name := 'TournamentName';
  FTournamentNameEdit.OnChange:=@NameChanged;
  FTournamentNameEdit.Text := 'Tournament';
  AddLabelledEdit(ButtonPanel, 'Tournament name', FTournamentNameEdit, TopPos);

  FStartingFENEdit := TEdit.Create(Self);
  FStartingFENEdit.Name := 'TournamentStartingFEN';
  FStartingFENEdit.Text := FVariant.DefaultStartingFEN;
  FStartingFENEdit.OnChange := @StartingFENChanged;
  AddLabelledEdit(ButtonPanel, 'Starting FEN', FStartingFENEdit, TopPos);

  FMovesEdit := TGuiNumberEdit.Create(Self);
  TGuiNumberEdit(FMovesEdit).WidthSample:='999';
  FMovesEdit.Name:='TournamentMoves';FMovesEdit.Text := IntToStr(FProfile.DefaultClock.MovesPerPeriod);
  FMovesEdit.OnChange := @InvalidateTournamentResults;
  FMovesEdit.SetBounds(0, 132, 86, 24);
  FMovesEdit.Parent := ButtonPanel;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := ButtonPanel;
  LabelControl.SetBounds(0, 114, 86, 18);
  LabelControl.Caption := 'moves in';MovesLabel:=LabelControl;

  FMinutesEdit := TGuiNumberEdit.Create(Self);
  TGuiNumberEdit(FMinutesEdit).WidthSample:='999.99';
  FMinutesEdit.Name:='TournamentMinutes';FMinutesEdit.Text := FloatToStr(FProfile.DefaultClock.MinutesPerPeriod);
  FMinutesEdit.OnChange := @InvalidateTournamentResults;
  FMinutesEdit.SetBounds(96, 132, 86, 24);
  FMinutesEdit.Parent := ButtonPanel;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := ButtonPanel;
  LabelControl.SetBounds(96, 114, 86, 18);
  LabelControl.Caption := 'with';MinutesLabel:=LabelControl;

  FIncrementEdit := TGuiNumberEdit.Create(Self);
  TGuiNumberEdit(FIncrementEdit).WidthSample:='999.99';
  FIncrementEdit.Name:='TournamentIncrement';FIncrementEdit.Text := FloatToStr(FProfile.DefaultClock.IncrementSeconds);
  FIncrementEdit.OnChange := @InvalidateTournamentResults;
  FIncrementEdit.SetBounds(192, 132, 86, 24);
  FIncrementEdit.Parent := ButtonPanel;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := ButtonPanel;
  LabelControl.SetBounds(192, 114, 86, 18);
  LabelControl.Caption := 'second increment';IncrementLabel:=LabelControl;

  TimeLabel:=TLabel.Create(Self);TimeLabel.Caption:='Time control:';
  TimeLabel.Name:='TournamentTimeControlLabel';TimeLabel.Parent:=ButtonPanel;
  FTimeUnitCombo:=TComboBox.Create(Self);FTimeUnitCombo.Parent:=ButtonPanel;
  FTimeUnitCombo.Name:='TournamentTimeUnit';FTimeUnitCombo.Style:=csDropDownList;
  FTimeUnitCombo.Items.Add('minutes');FTimeUnitCombo.Items.Add('seconds');
  FTimeUnitCombo.ItemIndex:=0;FTimeUnitCombo.OnChange:=@InvalidateTournamentResults;

  FIncrementModeCombo := TComboBox.Create(Self);
  FIncrementModeCombo.Name:='TournamentIncrementMode';
  FIncrementModeCombo.Parent := ButtonPanel;
  FIncrementModeCombo.SetBounds(288, 132, 140, 24);
  FIncrementModeCombo.Style := csDropDownList;
  FIncrementModeCombo.Items.Add('From start');
  FIncrementModeCombo.Items.Add('After move limit');
  FIncrementModeCombo.ItemIndex := 0;
  FIncrementModeCombo.OnChange := @InvalidateTournamentResults;

  FConcurrentGamesEdit := TGuiNumberEdit.Create(Self);
  TGuiNumberEdit(FConcurrentGamesEdit).WidthSample:='999';
  FConcurrentGamesEdit.Name:='TournamentConcurrentGames';FConcurrentGamesEdit.Text := '1';
  FConcurrentGamesEdit.SetBounds(640, 98, 120, 24);
  FConcurrentGamesEdit.Parent := ButtonPanel;
  LabelControl := TLabel.Create(Self);
  LabelControl.Parent := ButtonPanel;
  LabelControl.SetBounds(640, 82, 120, 18);
  LabelControl.Caption := 'Concurrent games';ConcurrentLabel:=LabelControl;

  FRoundRobinGroup := TRadioGroup.Create(Self);
  FRoundRobinGroup.Parent := ButtonPanel;
  FRoundRobinGroup.SetBounds(442, 10, 180, 92);
  FRoundRobinGroup.Caption := 'Pairing';
  FRoundRobinGroup.Items.Add('Single round-robin');
  FRoundRobinGroup.Items.Add('Double round-robin');
  FRoundRobinGroup.Items.Add('Swiss');
  FRoundRobinGroup.ItemIndex := TournamentPairingIndexSingleRoundRobin;
  FRoundRobinGroup.OnClick := @InvalidateTournamentResults;

  CreateButton := TButton.Create(Self);
  CreateButton.Name := 'CreatePairing';
  CreateButton.Parent := ButtonPanel;
  CreateButton.SetBounds(640, 16, 120, 28);
  CreateButton.Caption := 'Create pairing';
  CreateButton.OnClick := @CreatePairingClick;

  FStartStopButton := TButton.Create(Self);
  FStartStopButton.Parent := ButtonPanel;
  FStartStopButton.SetBounds(640, 52, 120, 28);
  FStartStopButton.Name:='TournamentPlay';
  FStartStopButton.Caption := 'Play';
  FStartStopButton.OnClick := @StartStopClick;

  FStopButton:=TButton.Create(Self);FStopButton.Parent:=ButtonPanel;
  FStopButton.Name:='TournamentStop';FStopButton.Caption:='Stop';
  FStopButton.OnClick:=@RefereeStopClick;

  ClearButton := TButton.Create(Self);
  ClearButton.Name := 'ClearPairing';
  ClearButton.Parent := ButtonPanel;
  ClearButton.SetBounds(770, 16, 120, 28);
  ClearButton.Caption := 'Clear pairing';
  ClearButton.OnClick := @ClearPairingsClick;

  SaveButton := TButton.Create(Self);
  SaveButton.Name:='SaveTournament';
  SaveButton.Parent := ButtonPanel;
  SaveButton.SetBounds(770, 52, 56, 28);
  SaveButton.Caption := 'Save...';
  SaveButton.OnClick := @SaveClick;

  LoadButton := TButton.Create(Self);
  LoadButton.Name := 'LoadTournament';
  LoadButton.Parent := ButtonPanel;
  LoadButton.SetBounds(834, 52, 56, 28);
  LoadButton.Caption := 'Load...';
  LoadButton.OnClick := @LoadClick;
  if RegisteredGameCount>1 then begin
    FGameCombo:=TComboBox.Create(Self);FGameCombo.Parent:=ButtonPanel;FGameCombo.Name:='TournamentVariant';
    FGameCombo.SetBounds(640,110,250,28);FGameCombo.Style:=csDropDownList;
    for GameIndex:=0 to RegisteredGameCount-1 do begin
      FGameCombo.Items.AddObject(RegisteredGame(GameIndex).Name,RegisteredGame(GameIndex));
      if RegisteredGame(GameIndex)=FVariant then FGameCombo.ItemIndex:=GameIndex;
    end;
    FGameCombo.OnChange:=@GameContextChanged;
  end;


  FInvalidationPanel := TPanel.Create(Self);
  FInvalidationPanel.Name := 'TournamentSettingsChanged';
  FInvalidationPanel.Parent := Self;
  FInvalidationPanel.Align := alTop;
  FInvalidationPanel.Height := 40;
  FInvalidationPanel.BevelOuter := bvNone;
  FInvalidationPanel.BorderSpacing.Around := 6;
  FInvalidationPanel.Visible := False;

  PanelLabel := TLabel.Create(Self);
  PanelLabel.Parent := FInvalidationPanel;
  PanelLabel.Align := alClient;
  PanelLabel.Layout := tlCenter;
  PanelLabel.Caption := 'Tournament settings changed. Apply to clear current results, or revert.';

  PanelButton := TButton.Create(Self);
  PanelButton.Parent := FInvalidationPanel;
  PanelButton.Align := alRight;
  PanelButton.Width := 110;
  PanelButton.Caption := 'Revert';
  PanelButton.OnClick := @RevertInvalidatingChange;

  PanelButton := TButton.Create(Self);
  PanelButton.Parent := FInvalidationPanel;
  PanelButton.Align := alRight;
  PanelButton.Width := 110;
  PanelButton.BorderSpacing.Right := 8;
  PanelButton.Name := 'ApplyTournamentChanges';
  PanelButton.Caption := 'Apply change';
  PanelButton.OnClick := @ApplyInvalidatingChange;

  ContentPanel := TPanel.Create(Self);
  ContentPanel.Parent := Self;
  ContentPanel.Align := alClient;
  ContentPanel.BevelOuter := bvNone;

  EnginePanel := TPanel.Create(Self);
  EnginePanel.Parent := ContentPanel;
  EnginePanel.Align := alLeft;
  EnginePanel.Width := 270;
  EnginePanel.BevelOuter := bvNone;
  EnginePanel.BorderSpacing.Around := 8;

  FEngineCheckList := TCheckListBox.Create(Self);
  FEngineCheckList.Name := 'TournamentEngines';
  FEngineCheckList.Parent := EnginePanel;
  FEngineCheckList.Align := alClient;

  GridPanel := TPanel.Create(Self);
  GridPanel.Parent := ContentPanel;
  GridPanel.Align := alClient;
  GridPanel.BevelOuter := bvNone;
  GridPanel.BorderSpacing.Around := 8;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := GridPanel;
  Splitter.Align := alTop;
  Splitter.Height := 8;
  Splitter.ResizeAnchor := akTop;

  CrossTablePanel := TPanel.Create(Self);
  CrossTablePanel.Parent := GridPanel;
  CrossTablePanel.Align := alTop;
  CrossTablePanel.Height := 150;
  CrossTablePanel.BevelOuter := bvNone;

  FCrossTableGrid := TStringGrid.Create(Self);
  FCrossTableGrid.MouseWheelOption := mwGrid;
  FCrossTableGrid.Options := FCrossTableGrid.Options + [goThumbTracking];
  FCrossTableGrid.Parent := CrossTablePanel;
  FCrossTableGrid.Align := alClient;
  FCrossTableGrid.ColCount := 4;
  FCrossTableGrid.RowCount := 2;
  FCrossTableGrid.FixedRows := 1;
  FCrossTableGrid.Options := FCrossTableGrid.Options - [goEditing] +
    [goColSizing, goRowSelect];

  PairingPanel := TPanel.Create(Self);
  PairingPanel.Parent := GridPanel;
  PairingPanel.Align := alClient;
  PairingPanel.BevelOuter := bvNone;

  FGrid := TStringGrid.Create(Self);
  FGrid.MouseWheelOption := mwGrid;
  FGrid.Options := FGrid.Options + [goThumbTracking];
  FGrid.Name := 'TournamentPairings';
  FGrid.Parent := PairingPanel;
  FGrid.Align := alClient;
  FGrid.ColCount := 6;
  FGrid.RowCount := 2;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.Options := FGrid.Options + [goColSizing] - [goEditing, goRowSelect];
  FGrid.OnDrawCell := @PairingGridDrawCell;
  FGrid.OnMouseDown := @PairingGridMouseDown;
  PairingPopup := TPopupMenu.Create(Self);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := '*';
  PopupItem.OnClick := @SetSelectedResultClick;
  PairingPopup.Items.Add(PopupItem);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := TournamentResultText(trWhiteWin,FProfile.FileFormat);
  PopupItem.OnClick := @SetSelectedResultClick;
  PairingPopup.Items.Add(PopupItem);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := TournamentResultText(trDraw,FProfile.FileFormat);
  PopupItem.OnClick := @SetSelectedResultClick;
  PairingPopup.Items.Add(PopupItem);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := TournamentResultText(trBlackWin,FProfile.FileFormat);
  PopupItem.OnClick := @SetSelectedResultClick;
  PairingPopup.Items.Add(PopupItem);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := '-';
  PairingPopup.Items.Add(PopupItem);
  PopupItem := TMenuItem.Create(Self);
  PopupItem.Caption := 'Reschedule selected game';
  PopupItem.OnClick := @RescheduleSelectedGame;
  PairingPopup.Items.Add(PopupItem);
  FGrid.PopupMenu := PairingPopup;
  FGrid.Cells[TournamentColGame, 0] := 'Game';
  FGrid.Cells[TournamentColRound, 0] := 'Round';
  FGrid.Cells[TournamentColWhite, 0] := 'White';
  FGrid.Cells[TournamentColBlack, 0] := 'Black';
  FGrid.Cells[TournamentColResult, 0] := 'Result';
  FGrid.Cells[TournamentColReason, 0] := 'Reason';
  FGrid.ColWidths[TournamentColGame] := 54;
  FGrid.ColWidths[TournamentColRound] := 54;
  FGrid.ColWidths[TournamentColWhite] := 260;
  FGrid.ColWidths[TournamentColBlack] := 260;
  FGrid.ColWidths[TournamentColResult] := 80;
  FGrid.ColWidths[TournamentColReason] := 180;
  ConfigurePairingGridColumns;
  AdjustPairingGridColumnWidths;

  ClearTournamentPairingGrid(FGrid);
  PopulateEngines;
  AdjustPairingGridColumnWidths;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 250;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
  FAcceptedTournamentSignature := TournamentSignature;
  AcceptInitialSettings;
  NameLabel:=TLabel(ButtonPanel.Controls[0]);FenLabel:=TLabel(ButtonPanel.Controls[2]);
  FenLabel.Name:='TournamentStartingFENLabel';
  SettingsColumn:=TPanel.Create(Self);SettingsColumn.Parent:=ButtonPanel;
  SettingsColumn.BevelOuter:=bvNone;SettingsColumn.Align:=alTop;
  SettingsColumn.AutoSize:=True;SettingsColumn.Top:=0;
  with LayoutFields(SettingsColumn,[NameLabel,FTournamentNameEdit]) do Top:=0;
  if FGameCombo<>nil then
    FenRow:=LayoutRow(SettingsColumn,[FGameCombo,FenLabel,FStartingFENEdit],2)
  else FenRow:=LayoutRow(SettingsColumn,[FenLabel,FStartingFENEdit],1);
  FenRow.Top:=1;
  PairingActions:=LayoutStack(ButtonPanel);
  with LayoutRow(PairingActions,[CreateButton]) do Top:=0;
  with LayoutRow(PairingActions,[ClearButton]) do Top:=1;
  FRoundRobinGroup.Name:='TournamentPairingOptions';FRoundRobinGroup.AutoSize:=True;
  with LayoutFlow(ButtonPanel,[FRoundRobinGroup,PairingActions]) do Top:=1;
  with LayoutRow(ButtonPanel,[TimeLabel,FMovesEdit,MovesLabel,FMinutesEdit,FTimeUnitCombo,
    MinutesLabel,FIncrementEdit,IncrementLabel,FIncrementModeCombo]) do Top:=2;
  with LayoutRow(ButtonPanel,[FStartStopButton,ConcurrentLabel,FConcurrentGamesEdit,
    FStopButton,SaveButton,LoadButton]) do Top:=3;
  ButtonPanel.AutoSize:=True;
  UpdateButtons;
  EnableAutoLayout;
  finally EnableAlign;end;
end;

procedure TTournamentDialog.StartingFENChanged(Sender:TObject);
begin
  InvalidateTournamentResults(Sender);
  InvalidateLayout;
end;

procedure TTournamentDialog.RefreshLayout;
const ChessFenSample='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e3 99 999';
var FieldWidth,ContentWidth,GameWidth,I:Integer;Fields:TWinControl;
begin
  inherited RefreshLayout;
  if FStartingFENEdit=nil then Exit;
  FieldWidth:=MeasureGuiText(FStartingFENEdit.Text,FStartingFENEdit.Font).cx;
  if GameVariantId(FVariant)='chess' then
    FieldWidth:=Max(FieldWidth,MeasureGuiText(ChessFenSample,FStartingFENEdit.Font).cx);
  Inc(FieldWidth,MeasureGuiText('MM',FStartingFENEdit.Font).cx);
  FStartingFENEdit.Constraints.MinWidth:=FieldWidth;
  Fields:=FStartingFENEdit.Parent;
  ContentWidth:=FieldWidth;
  if FGameCombo<>nil then begin
    GameWidth:=0;
    for I:=0 to FGameCombo.Items.Count-1 do
      GameWidth:=Max(GameWidth,MeasureGuiText(FGameCombo.Items[I],FGameCombo.Font).cx);
    Inc(GameWidth,MeasureGuiText('Ag',FGameCombo.Font).cy+MeasureGuiText('MM',FGameCombo.Font).cx);
    FGameCombo.Constraints.MaxWidth:=0;
    FGameCombo.Constraints.MinWidth:=GameWidth;
    FGameCombo.Constraints.MaxWidth:=GameWidth;
    Inc(ContentWidth,FGameCombo.Constraints.MinWidth);
  end;
  for I:=0 to Fields.ControlCount-1 do
    if Fields.Controls[I] is TLabel then
      Inc(ContentWidth,MeasureGuiText(TLabel(Fields.Controls[I]).Caption,Fields.Controls[I].Font).cx);
  Inc(ContentWidth,(Fields.ControlCount-1)*Fields.ChildSizing.HorizontalSpacing);
  Fields.Constraints.MinWidth:=ContentWidth;
  Fields.Parent.Constraints.MinWidth:=ContentWidth;
  RefreshMinimum;
end;

procedure TTournamentDialog.ResetForVariant(AVariant:TGameVariant);
var Profile:TGameGuiProfile;Id:TGUID;
begin
  if AVariant=nil then raise EGamePositionError.Create('Missing dialog game variant');
  if IsRunning then raise EInvalidOperation.Create('Stop tournament before changing game');
  Profile:=GameGuiProfileFor(AVariant);
  if CreateGUID(Id)<>0 then raise EInOutError.Create('Could not create a tournament identity');
  LeaveEngineQueue;
  DisableAlign;FGrid.BeginUpdate;FCrossTableGrid.BeginUpdate;
  FLoadingTournament:=True;
  try
    FTimer.Enabled:=False;FRunning:=False;FClosing:=False;
    FCloseStopped:=False;FRefereeStopPending:=False;FLastGameStartTick:=0;
    ClearTournamentGameRefs;FWhiteEngines.Clear;FBlackEngines.Clear;
    FFileName:='';FPdnFileName:='';FPdnFileOwned:=False;
    FPdnPublishedHash:='';FVerifiedPdnFingerprint:='';FLegacyPdnFileName:='';
    FStorageNotice:='';FStorageError:='';FTournamentId:=GUIDToString(Id);
    FVariant:=AVariant;FProfile:=Profile;
    FStartingFENEdit.Text:=FVariant.DefaultStartingFEN;
    FMovesEdit.Text:=IntToStr(FProfile.DefaultClock.MovesPerPeriod);
    FMinutesEdit.Text:=FloatToStr(FProfile.DefaultClock.MinutesPerPeriod);
    FTimeUnitCombo.ItemIndex:=0;
    FIncrementEdit.Text:=FloatToStr(FProfile.DefaultClock.IncrementSeconds);
    if FProfile.DefaultClock.IncrementMode=cimAfterMoveLimit then FIncrementModeCombo.ItemIndex:=1
    else FIncrementModeCombo.ItemIndex:=0;
    FConcurrentGamesEdit.Text:='1';FRoundRobinGroup.ItemIndex:=0;
    if FGameCombo<>nil then FGameCombo.ItemIndex:=FGameCombo.Items.IndexOfObject(FVariant);
    ClearTournamentPairingGrid(FGrid);PopulateEngines;
    FGrid.PopupMenu.Items[1].Caption:=TournamentResultText(trWhiteWin,FProfile.FileFormat);
    FGrid.PopupMenu.Items[2].Caption:=TournamentResultText(trDraw,FProfile.FileFormat);
    FGrid.PopupMenu.Items[3].Caption:=TournamentResultText(trBlackWin,FProfile.FileFormat);
    FAcceptedTournamentSignature:=TournamentSignature;
    FInvalidationPanel.Visible:=False;AcceptInitialSettings;
    AdjustPairingGridColumnWidths;UpdateCrossTable;
  finally
    FLoadingTournament:=False;
    FCrossTableGrid.EndUpdate;FGrid.EndUpdate;EnableAlign;
  end;
  RefreshLayout;UpdateButtons;
  if Assigned(FOnTitleChanged) then FOnTitleChanged(Self);
end;

function TTournamentDialog.GetTournamentName:string;
begin Result:=FTournamentNameEdit.Text;end;
procedure TTournamentDialog.SetTournamentName(const Value:string);
begin FTournamentNameEdit.Text:=Value;end;
procedure TTournamentDialog.NameChanged(Sender:TObject);
begin if Assigned(FOnTitleChanged) then FOnTitleChanged(Self);end;

procedure TTournamentDialog.StopForClose;
begin
  FCloseStopped:=True;FRunning:=False;
  StopRunningGames;FTimer.Enabled:=ActiveRunningGameCount>0;UpdateButtons;
end;

function TTournamentDialog.DrainClose:Boolean;
var I:Integer;
begin
  while ActiveRunningGameCount>0 do begin
    if not (Owner is TMainForm) then Exit(False);
    TMainForm(Owner).DrainTournamentClose;
    TimerTick(nil);
  end;
  // Do not drop an unrecorded final game on a Save-and-close operation.
  for I:=0 to FRunningGames.Count-1 do
    if TTournamentRunningGame(FRunningGames[I]).PendingCapture then Exit(False);
  Result:=True;
end;

procedure TTournamentDialog.LeaveEngineQueue;
begin
  if (Owner is TMainForm) and (TMainForm(Owner).TournamentEngineQueue <> nil) then
    TMainForm(Owner).TournamentEngineQueue.RemoveOwner(Self);
end;

procedure TTournamentDialog.BeginShutdown;
begin
  LeaveEngineQueue;
  FClosing := True;
  FRunning := False;
  if FTimer <> nil then
    FTimer.Enabled := False;
end;

function TTournamentDialog.SettingsSignature: string;
var Selected: TStringList;
begin
  Selected := TStringList.Create;
  try
    CollectSelectedEngines(Selected);
    Result := TournamentSignature + '|' + FTournamentNameEdit.Text + '|' +
      FConcurrentGamesEdit.Text + '|' + Selected.Text;
  finally Selected.Free; end;
end;

procedure TTournamentDialog.AcceptInitialSettings;
begin
  FInitialSettingsSignature := SettingsSignature;
end;

function TTournamentDialog.HasTournamentData: Boolean;
begin
  Result := (Trim(FFileName) <> '') or
    (not TournamentPairingGridIsEmpty(FGrid)) or
    HasNonByeResults or (SettingsSignature <> FInitialSettingsSignature);
end;

function TTournamentDialog.IsRunning: Boolean;
begin
  Result := FRunning or (ActiveRunningGameCount > 0);
end;

function TTournamentDialog.SaveTournamentWithDialog: Boolean;
var SaveName:string;
begin
  Result:=ChooseSaveFileName(SaveName);
  if Result then SaveTournamentToFile(SaveName);
end;

function TTournamentDialog.ChooseSaveFileName(out FileName:string):Boolean;
var
  Dialog: TSaveDialog;
begin
  Result := False;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Title := 'Save tournament';
    Dialog.Filter := 'Tournament files (*.json)|*.json|All files (*.*)|*.*';
    Dialog.DefaultExt := 'json';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if FFileName <> '' then
      Dialog.FileName := FFileName
    else
      Dialog.FileName := SafeFileNameText(FTournamentNameEdit.Text) + '.json';
    if not ExecuteGuiFileDialog(Dialog) then Exit;
    FileName:=ExpandFileName(Dialog.FileName);
    if Assigned(FOnTargets) then FOnTargets(Self,FileName,FPdnFileName,FTournamentId);
    Result := True;
  finally
    Dialog.Free;
  end;
end;

destructor TTournamentDialog.Destroy;
begin
  BeginShutdown;
  StopRunningGames;
  while FRunningGames.Count > 0 do
  begin
    TTournamentRunningGame(FRunningGames[0]).Free;
    FRunningGames.Delete(0);
  end;
  FRunningGames.Free;
  FGameRecords.Free;
  FPdnWriteLock.Free;
  FEngines.Free;
  FBlackEngines.Free;
  FWhiteEngines.Free;
  inherited Destroy;
end;

procedure TTournamentDialog.ClearTournamentGameRefs;
begin
  FGameRecords.Clear;
  if FRunningGames = nil then
    Exit;
  while FRunningGames.Count > 0 do
  begin
    TTournamentRunningGame(FRunningGames[0]).Free;
    FRunningGames.Delete(0);
  end;
end;

function TTournamentDialog.GameFileExtension:string;
begin Result:='.'+FProfile.FileExtension;end;

function TTournamentDialog.ReadSettings:TTimeControl;
var Setup:TGameSetup;
begin
  Result:=FProfile.DefaultClock;
  if not TryStrToInt(Trim(FMovesEdit.Text),Result.MovesPerPeriod) then
    raise EConvertError.Create('Moves must be a nonnegative integer');
  if not TryStrToFloat(Trim(FMinutesEdit.Text),Result.MinutesPerPeriod) then
    raise EConvertError.Create('Time must be a positive finite number');
  if FTimeUnitCombo.ItemIndex=1 then Result.MinutesPerPeriod:=Result.MinutesPerPeriod/60;
  if not TryStrToFloat(Trim(FIncrementEdit.Text),Result.IncrementSeconds) then
    raise EConvertError.Create('Increment must be a nonnegative finite number');
  if FIncrementModeCombo.ItemIndex=1 then Result.IncrementMode:=cimAfterMoveLimit
  else Result.IncrementMode:=cimFromStart;
  Setup:=Default(TGameSetup);Setup.Variant:=FVariant;Setup.WhitePlayer:=pkHuman;Setup.BlackPlayer:=pkHuman;
  Setup.TimeControl:=Result;Setup.StartingFEN:=Trim(FStartingFENEdit.Text);
  if Setup.StartingFEN='' then Setup.StartingFEN:=FVariant.DefaultStartingFEN;
  ValidateGameSetup(Setup,FVariant,FProfile.EngineKinds);
end;

function TTournamentDialog.ConfirmSharedExecutables:Boolean;
var Seen,Keys:TStringList;Row:Integer;
 function Participant(D:TExternalEngineDefinition):Boolean;
 var Path,Key:string;
 begin
  Result:=True;if D=nil then Exit;
  Key:=EngineIdentityKey(D);if Keys.IndexOf(Key)>=0 then Exit;
  Keys.Add(Key);Path:=ExpandFileName(D.ExePath);
  if Seen.IndexOf(Path)>=0 then Exit(False);
  Seen.Add(Path);
 end;
begin
  Result:=True;if FProfile.FileFormat<>gffPgn then Exit;
  Seen:=TStringList.Create;Keys:=TStringList.Create;
  try
    Seen.CaseSensitive:={$IFDEF MSWINDOWS}False{$ELSE}True{$ENDIF};
    // The current pairing rows are authoritative, even if the checklist was
    // edited in preparation for a later round.
    for Row:=1 to FGrid.RowCount-1 do
      if TournamentGridHasPairingAtRow(FGrid,Row) then
        if not Participant(EngineForRow(Row,True)) or
          not Participant(EngineForRow(Row,False)) then begin
          Result:=ShowGuiConfirmationDialog(Self,'Tournament',
            'Two participants use the same executable and share one UCI options file.'+LineEnding+
            'They cannot use different saved settings. Use separate executable paths for that comparison.'+LineEnding+
            'Continue with the shared settings?', 'Continue','',mrCancel)=mrYes;
          Exit;
        end;
  finally Keys.Free;Seen.Free;end;
end;

procedure TTournamentDialog.AddLabelledEdit(AParent: TWinControl;
  const ACaption: string; AEdit: TEdit; var ATop: Integer);
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := AParent;
  LLabel.SetBounds(0, ATop, 420, 20);
  LLabel.Caption := ACaption;
  Inc(ATop, 20);
  AEdit.Parent := AParent;
  AEdit.SetBounds(0, ATop, 420, 24);
  Inc(ATop, 34);
end;

procedure TTournamentDialog.AdjustPairingGridColumnWidths;
var
  EngineTextWidth: Integer;
  I: Integer;
  Row: Integer;

  function TextWidth(const AText: string; AMinWidth: Integer): Integer;
  begin
    Result := Max(AMinWidth, FGrid.Canvas.TextWidth(AText) + 28);
  end;

begin
  if FGrid = nil then
    Exit;

  FGrid.Canvas.Font.Assign(FGrid.Font);
  EngineTextWidth := TextWidth('Widest player name', 260);
  if FEngineCheckList <> nil then
    for I := 0 to FEngineCheckList.Items.Count - 1 do
      EngineTextWidth := Max(EngineTextWidth,
        TextWidth(FEngineCheckList.Items[I], 260));
  for Row := 1 to FGrid.RowCount - 1 do
  begin
    EngineTextWidth := Max(EngineTextWidth,
      TextWidth(FGrid.Cells[TournamentColWhite, Row], 260));
    EngineTextWidth := Max(EngineTextWidth,
      TextWidth(FGrid.Cells[TournamentColBlack, Row], 260));
  end;

  FGrid.ColWidths[TournamentColGame] := TextWidth('Game 9999', 70);
  FGrid.ColWidths[TournamentColRound] := TextWidth('Round 999', 76);
  FGrid.ColWidths[TournamentColWhite] := EngineTextWidth;
  FGrid.ColWidths[TournamentColBlack] := EngineTextWidth;
  FGrid.ColWidths[TournamentColResult] := TextWidth('Result 0-2', 92);
  FGrid.ColWidths[TournamentColReason] := TextWidth('Unknown result', 180);

  if FGrid.Columns.Count >= FGrid.ColCount then
    for I := 0 to FGrid.ColCount - 1 do
      FGrid.Columns[I].Width := FGrid.ColWidths[I];

  // The grid scrolls horizontally when necessary; long engine names must not
  // force the whole tournament window beyond the monitor's available width.

end;

function TTournamentDialog.DisplayNameForEngine(
  AEngine: TExternalEngineDefinition): string;
var
  I: Integer;
begin
  Result := '';
  if AEngine = nil then
    Exit;

  for I := 0 to FEngines.Count - 1 do
    if FEngines[I] = AEngine then
      Exit(EnginePickerDisplayName(AEngine, I + 1));

  Result := EnginePickerDisplayName(AEngine, 0);
end;

function TTournamentDialog.StartNewTournamentStorage: Boolean;
var
  Id: TGUID;
  NewId, NewFileName, BaseName: string;
  I: Integer;
  HasRecords: Boolean;
begin
  Result := False;
  // Results may exist only in memory after a failed save. Keep them until the
  // current tournament has been saved successfully instead of discarding them.
  if IsRunning or (FStorageError <> '') then Exit;
  HasRecords := False;
  for I := 0 to FGameRecords.Count - 1 do
    if TTournamentGameRecord(FGameRecords[I]).HasRecord or
      (TTournamentGameRecord(FGameRecords[I]).Attempt > 1) then
    begin HasRecords := True; Break; end;
  if not HasRecords then Exit(True);
  repeat
    if CreateGUID(Id) <> 0 then
      raise EInOutError.Create('Could not create a tournament identity');
    NewId := GUIDToString(Id);
    NewFileName := '';
    if FFileName <> '' then
    begin
      BaseName := ExtractFilePath(ExpandFileName(FFileName)) +
        SafeFileNameText(FTournamentNameEdit.Text) + '.' + NewId;
      NewFileName := BaseName + '.json';
    end;
  until (NewFileName = '') or
    (not FileExists(NewFileName) and not DirectoryExists(NewFileName) and
     not FileExists(ChangeFileExt(NewFileName, GameFileExtension)) and
     not DirectoryExists(ChangeFileExt(NewFileName, GameFileExtension)));
  FTournamentId := NewId;
  FFileName := NewFileName;
  FPdnFileName := '';
  FPdnFileOwned := False;
  FPdnPublishedHash := '';
  FVerifiedPdnFingerprint := '';
  FStorageNotice := '';
  FLegacyPdnFileName := '';
  Result := True;
end;

procedure TTournamentDialog.EnsureStoragePaths;
var
  DirectoryName: string;
begin
  if FFileName = '' then
  begin
    DirectoryName := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'tournaments';
    if not ForceDirectories(DirectoryName) then
      raise EInOutError.Create('Could not create tournament recovery directory');
    FFileName := IncludeTrailingPathDelimiter(DirectoryName) +
      SafeFileNameText(FTournamentNameEdit.Text) + '.' + FTournamentId + '.json';
  end;
  if FPdnFileName = '' then
    FPdnFileName := ChangeFileExt(ExpandFileName(FFileName), GameFileExtension);
  if not FPdnFileOwned then
    FPdnFileName := UnusedTournamentPdnPath(FPdnFileName,FProfile.FileFormat);
  if Assigned(FOnTargets) then FOnTargets(Self,FFileName,FPdnFileName,FTournamentId);
end;

function TTournamentDialog.PdnFileName: string;
begin
  EnsureStoragePaths;
  Result := FPdnFileName;
end;

procedure TTournamentDialog.AutoSaveTournament;
begin
  if FLoadingTournament then Exit;
  FStorageError := '';
  try
    ReadSettings;MaxConcurrentGames;
    EnsureStoragePaths;
    try
      WritePdnProjection;
    finally
      // JSON remains authoritative even when publication of its PDN fails.
      SaveTournamentSnapshot(FFileName);
    end;
  except
    on E: Exception do
    begin
      FStorageError := E.Message;
      FRunning := False;
      LeaveEngineQueue;
      if FTimer <> nil then
        FTimer.Enabled := ActiveRunningGameCount > 0;
    end;
  end;
  if not FClosing then
    UpdateButtons;
end;

function TTournamentDialog.GameRecord(ARow: Integer): TTournamentGameRecord;
begin
  if (ARow < 1) or (ARow >= FGrid.RowCount) then
    raise ERangeError.Create('Tournament row is outside the pairing grid');
  while FGameRecords.Count < ARow do
    FGameRecords.Add(TTournamentGameRecord.Create);
  Result := TTournamentGameRecord(FGameRecords[ARow - 1]);
end;

function TTournamentDialog.CaptureGamePdn(AGame: TObject): string;
var Options:TGameTreePdnRenderOptions;
begin
  Options:=DefaultGameTreePdnRenderOptions;Options.FileFormat:=FProfile.FileFormat;
  Options.LosslessPgn:=FProfile.FileFormat=gffPgn;
  Result := GameTreeToPdnTextEx(TRunningGame(AGame).GameTree,Options);
end;

procedure TTournamentDialog.CaptureTournamentGame(
  ARunningGame: TTournamentRunningGame; AGame: TObject);
begin
  if (ARunningGame = nil) or not (AGame is TRunningGame) then Exit;
  try
    if FProfile.FileFormat=gffPgn then GameRecord(ARunningGame.Row).StartDate:=FormatDateTime('yyyy.mm.dd',TRunningGame(AGame).StartedAt);
    GameRecord(ARunningGame.Row).RecordPlayedGame(CaptureGamePdn(AGame),
      TRunningGame(AGame).ResultText);
    ARunningGame.PendingCapture := False;
    ARunningGame.CaptureError := '';
  except
    on E: Exception do
    begin
      ARunningGame.Active := False;
      ARunningGame.PendingCapture := True;
      ARunningGame.CaptureError := 'Could not capture finished game: ' + E.Message;
      GameRecord(ARunningGame.Row).RecordCaptureFailure(TRunningGame(AGame).ResultText,
        ARunningGame.CaptureError);
      FGrid.Cells[TournamentColReason, ARunningGame.Row] := 'Capture failed: ' + ARunningGame.CaptureError;
      FRunning := False;
    end;
  end;
end;

procedure TTournamentDialog.WritePdnProjection;
var
  Row: Integer;
  PdnText, PublishedText, ActualHash, Fingerprint: string;
  Output: TStringStream;
  OwnedContent: Boolean;
begin
  Output := TStringStream.Create('');
  try
    for Row := 1 to FGrid.RowCount - 1 do
      if TournamentGridHasPairingAtRow(FGrid, Row) and
        not SameText(FGrid.Cells[TournamentColReason, Row], 'Bye') then
        Output.WriteString(GameRecord(Row).RenderGame(FProfile.FileFormat,FTournamentId,
          FTournamentNameEdit.Text, FGrid.Cells[TournamentColRound, Row],
          FGrid.Cells[TournamentColGame, Row], FGrid.Cells[TournamentColWhite, Row],
          FGrid.Cells[TournamentColBlack, Row], FStartingFENEdit.Text) + LineEnding);
    PdnText := Output.DataString;
  finally
    Output.Free;
  end;
  if (Trim(PdnText) = '') and
    (not FPdnFileOwned or not FileExists(FPdnFileName)) then
    Exit;
  FPdnWriteLock.Acquire;
  try
    PublishedText := Trim(PdnText) + LineEnding;
    if FPdnFileOwned then
    begin
      OwnedContent := False;
      if FileExists(FPdnFileName) then
      begin
        ActualHash := SHA1Print(SHA1File(FPdnFileName));
        Fingerprint := FPdnFileName + '|' + ActualHash;
        if FPdnPublishedHash = '' then
        begin
          // Older snapshots had no fingerprint. Exact projection equality plus
          // the tournament identity safely establishes the first fingerprint.
          OwnedContent := (ActualHash = SHA1Print(SHA1String(PublishedText))) and
            TournamentPdnMatchesId(FPdnFileName, FTournamentId,FProfile.FileFormat);
        end
        else
          OwnedContent := (ActualHash = FPdnPublishedHash) and
            ((FVerifiedPdnFingerprint = Fingerprint) or
             TournamentPdnMatchesId(FPdnFileName, FTournamentId,FProfile.FileFormat));
      end;
      if not OwnedContent then
      begin
        if FPdnPublishedHash = '' then
          FStorageNotice := 'Preserved unverified prior '+FProfile.FormatName+': ' + ExtractFileName(FPdnFileName)
        else
          FStorageNotice := 'Preserved changed '+FProfile.FormatName+': ' + ExtractFileName(FPdnFileName);
        FLegacyPdnFileName := FPdnFileName;
        FPdnFileOwned := False;
        FPdnPublishedHash := '';
        FPdnFileName := UnusedTournamentPdnPath(FPdnFileName,FProfile.FileFormat);
      end;
    end;
    WriteTextFileAtomically(FPdnFileName, PublishedText, FPdnFileOwned);
    FPdnPublishedHash := SHA1Print(SHA1String(PublishedText));
    FPdnFileOwned := True;
    FVerifiedPdnFingerprint := FPdnFileName + '|' + FPdnPublishedHash;
  finally
    FPdnWriteLock.Release;
  end;
end;

procedure TTournamentDialog.PopulateEngines;
var
  I: Integer;
begin
  FEngineCheckList.Items.BeginUpdate;
  try
  FEngineCheckList.Clear;
  LoadExternalEngines(EnginesJsonFileName, FEngines);
  for I := 0 to FEngines.Count - 1 do
  begin
    if not (FEngines[I].Kind in FProfile.EngineKinds) then Continue;
    FEngineCheckList.Items.AddObject(DisplayNameForEngine(FEngines[I]),
      FEngines[I]);
    FEngineCheckList.Checked[FEngineCheckList.Items.Count-1] := True;
  end;
  finally FEngineCheckList.Items.EndUpdate;end;
end;

function TTournamentDialog.EngineByDisplayName(
  const AName: string): TExternalEngineDefinition;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FEngines.Count - 1 do
    if SameText(EnginePickerDisplayName(FEngines[I], I + 1), AName) then
      Exit(FEngines[I]);
end;

function TTournamentDialog.EngineForRow(ARow: Integer; White: Boolean): TExternalEngineDefinition;
var Key: string; Col: Integer; RecordData: TTournamentGameRecord;
begin
  Result := nil;
  RecordData := GameRecord(ARow);
  if White then begin Key := RecordData.WhiteEngineKey; Col := TournamentColWhite; end
  else begin Key := RecordData.BlackEngineKey; Col := TournamentColBlack; end;
  if Key = '' then
  begin
    Result := EngineByDisplayName(FGrid.Cells[Col, ARow]);
    if Result <> nil then
      if White then RecordData.WhiteEngineKey := EngineIdentityKey(Result)
      else RecordData.BlackEngineKey := EngineIdentityKey(Result);
    Exit;
  end;
  Result := FindEngineByIdentityKey(FEngines, Key);
  if Result <> nil then
    if White then RecordData.WhiteEngineKey := EngineIdentityKey(Result)
    else RecordData.BlackEngineKey := EngineIdentityKey(Result);
end;

function TTournamentDialog.EngineKeyForName(const AName: string): string;
var
  Engine: TExternalEngineDefinition;
begin
  Result := '';
  Engine := EngineByDisplayName(AName);
  if Engine <> nil then
    Result := EngineIdentityKey(Engine);
end;

procedure TTournamentDialog.CollectSelectedEngines(AEngines: TStrings);
begin
  CollectSelectedTournamentEngineNames(FEngineCheckList, AEngines);
end;

procedure TTournamentDialog.ConfigurePairingGridColumns;
  function AddColumn(const ATitle: string; AWidth: Integer;
    AReadOnly: Boolean): TGridColumn;
  begin
    Result := FGrid.Columns.Add;
    Result.Title.Caption := ATitle;
    Result.Width := AWidth;
    Result.ReadOnly := AReadOnly;
  end;

begin
  FGrid.Columns.Clear;
  AddColumn('Game', FGrid.ColWidths[TournamentColGame], True);
  AddColumn('Round', FGrid.ColWidths[TournamentColRound], True);
  AddColumn('White', FGrid.ColWidths[TournamentColWhite], True);
  AddColumn('Black', FGrid.ColWidths[TournamentColBlack], True);
  AddColumn('Result', FGrid.ColWidths[TournamentColResult], True);
  AddColumn('Reason', FGrid.ColWidths[TournamentColReason], True);

  FGrid.Cells[TournamentColGame, 0] := 'Game';
  FGrid.Cells[TournamentColRound, 0] := 'Round';
  FGrid.Cells[TournamentColWhite, 0] := 'White';
  FGrid.Cells[TournamentColBlack, 0] := 'Black';
  FGrid.Cells[TournamentColResult, 0] := 'Result';
  FGrid.Cells[TournamentColReason, 0] := 'Reason';
end;

procedure TTournamentDialog.CollectPairingRows(AWhiteEngines, ABlackEngines,
  AResults: TStrings);
begin
  CollectTournamentPairingRows(FGrid, AWhiteEngines, ABlackEngines, AResults);
end;

procedure TTournamentDialog.CollectRoundRows(ARounds: TStrings);
begin
  CollectTournamentRoundRows(FGrid, ARounds);
end;

procedure TTournamentDialog.CreatePairingClick(Sender: TObject);
var
  BlackEngines: TStringList;
  Engines: TStringList;
  PairingRound: TTournamentPairingRound;
  Results: TStringList;
  Rounds: TStringList;
  WhiteEngines: TStringList;
begin
  if IsRunning or (FStorageError <> '') then
    Exit;
  if PendingInvalidatingChange then
    Exit;
  try ReadSettings;MaxConcurrentGames;
  except on E:Exception do begin ShowGuiOkDialog(Self,'Tournament',E.Message);Exit;end;end;
  Engines := TStringList.Create;
  WhiteEngines := TStringList.Create;
  BlackEngines := TStringList.Create;
  Results := TStringList.Create;
  Rounds := TStringList.Create;
  try
    CollectSelectedEngines(Engines);
    if Engines.Count < 2 then
    begin
      ShowGuiOkDialog(Self, 'Tournament', 'Select at least two engines.');
      Exit;
    end;
    CollectPairingRows(WhiteEngines, BlackEngines, Results);
    CollectRoundRows(Rounds);
    if TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) and
      not TournamentAllResultsKnown(WhiteEngines, BlackEngines, Results,FProfile.FileFormat) then
    begin
      ShowGuiOkDialog(Self, 'Tournament',
        'Finish the current Swiss round first.');
      Exit;
    end;

    PairingRound := BuildTournamentPairingRound(
      TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex),
      TournamentRoundRobinIndexIsDouble(FRoundRobinGroup.ItemIndex), Engines,
      WhiteEngines, BlackEngines, Results, Rounds,FProfile.FileFormat);
    if PairingRound.HasRepeat and
      (ShowGuiConfirmationDialog(Self, 'Tournament',
      'The proposed Swiss round includes repeated opponents.' +
      LineEnding + 'Continue with repeated pairing?', 'Continue', '',
      mrCancel) <> mrYes) then
      Exit;
    if not TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) then
    begin
      if not StartNewTournamentStorage then Exit;
      ClearTournamentGameRefs;
      ClearTournamentPairingGrid(FGrid);
    end;
    ApplyTournamentPairingRoundToGrid(FGrid, PairingRound,FProfile.FileFormat);
    FAcceptedTournamentSignature := TournamentSignature;
    if FInvalidationPanel <> nil then
      FInvalidationPanel.Visible := False;
    AdjustPairingGridColumnWidths;
    UpdateCrossTable;
  finally
    Rounds.Free;
    Results.Free;
    BlackEngines.Free;
    WhiteEngines.Free;
    Engines.Free;
  end;
  AutoSaveTournament;
end;

procedure TTournamentDialog.ClearPairingsClick(Sender: TObject);
begin
  if IsRunning or (FStorageError <> '') then
    Exit;
  if FRunning then
    Exit;
  if HasNonByeResults and
    (ShowGuiConfirmationDialog(Self, 'Clear pairing',
    'Start a new tournament without these pairings? Saved tournament files will be kept.', 'Yes',
    'No', mrNo) <> mrYes) then
    Exit;
  if not StartNewTournamentStorage then Exit;
  ClearTournamentGameRefs;
  ClearTournamentPairingGrid(FGrid);
  FAcceptedTournamentSignature := TournamentSignature;
  if FInvalidationPanel <> nil then
    FInvalidationPanel.Visible := False;
  UpdateCrossTable;
  AutoSaveTournament;
end;

procedure TTournamentDialog.ClearStaleRunningReasons;
var
  Row: Integer;
begin
  for Row := 1 to FGrid.RowCount - 1 do
    if TournamentReasonIsTransient(FGrid.Cells[TournamentColReason, Row]) and
      (not IsRowRunning(Row)) then
      FGrid.Cells[TournamentColReason, Row] := '';
end;

function TTournamentDialog.HasNonByeResults: Boolean;
var
  Row: Integer;
begin
  Result := False;
  for Row := 1 to FGrid.RowCount - 1 do
  begin
    if not TournamentGridHasPairingAtRow(FGrid, Row) then
      Continue;
    if TournamentReasonIsTransient(FGrid.Cells[TournamentColReason, Row]) and
      (not IsRowRunning(Row)) then
      FGrid.Cells[TournamentColReason, Row] := '';
    if SameText(Trim(FGrid.Cells[TournamentColReason, Row]), 'Bye') then
      Continue;
    if TournamentResultIsKnown(ParseTournamentResult(
      FGrid.Cells[TournamentColResult, Row],FProfile.FileFormat)) then
      Exit(True);
  end;
end;

function TTournamentDialog.FindNextUnplayedRow: Integer;
var
  BlackEngines: TStringList;
  I: Integer;
  LatestRound: Integer;
  Results: TStringList;
  Rounds: TStringList;
  WhiteEngines: TStringList;
begin
  Result := 0;
  WhiteEngines := TStringList.Create;
  BlackEngines := TStringList.Create;
  Results := TStringList.Create;
  Rounds := TStringList.Create;
  try
    CollectPairingRows(WhiteEngines, BlackEngines, Results);
    CollectRoundRows(Rounds);
    LatestRound := 0;
    if TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) then
      for I := 0 to Rounds.Count - 1 do
        if StrToIntDef(Rounds[I], 0) > LatestRound then
          LatestRound := StrToIntDef(Rounds[I], 0);

    for I := 0 to Results.Count - 1 do
    begin
      if TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) and
        (StrToIntDef(Rounds[I], 0) <> LatestRound) then
        Continue;
      if IsRowRunning(I + 1) then
        Continue;
      if (Trim(FGrid.Cells[TournamentColReason, I + 1]) <> '') and
        not TournamentReasonIsTransient(FGrid.Cells[TournamentColReason,I+1]) then
        Continue;
      if not TournamentResultIsKnown(ParseTournamentResult(Results[I],FProfile.FileFormat)) then
        Exit(I + 1);
    end;
  finally
    Rounds.Free;
    Results.Free;
    BlackEngines.Free;
    WhiteEngines.Free;
  end;
end;

function TTournamentDialog.ActiveRunningGameCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  if FRunningGames = nil then
    Exit;
  for I := 0 to FRunningGames.Count - 1 do
    if TTournamentRunningGame(FRunningGames[I]).Active then
      Inc(Result);
end;

function TTournamentDialog.FindTournamentGameByRow(
  ARow: Integer): TTournamentRunningGame;
var
  I: Integer;
begin
  Result := nil;
  if FRunningGames = nil then
    Exit;
  for I := FRunningGames.Count - 1 downto 0 do
    if TTournamentRunningGame(FRunningGames[I]).Row = ARow then
      Exit(TTournamentRunningGame(FRunningGames[I]));
end;

function TTournamentDialog.IsRowRunning(ARow: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FRunningGames.Count - 1 do
    if TTournamentRunningGame(FRunningGames[I]).Active and
      (TTournamentRunningGame(FRunningGames[I]).Row = ARow) then
      Exit(True);
end;

function TTournamentDialog.IsRowStartable(ARow: Integer;
  ABusyEngineKeys: TStrings): Boolean;
var
  BlackKey: string;
  BlackEngine: TExternalEngineDefinition;
  CandidateKeys: TStringList;
  I,SideIndex: Integer;
  Candidate:TExternalEngineDefinition;
  Description:string;
  WhiteKey: string;
  WhiteEngine: TExternalEngineDefinition;
begin
  Result := False;
  if (ARow <= 0) or (ARow >= FGrid.RowCount) then
    Exit;
  if IsRowRunning(ARow) then
    Exit;
  if not TournamentGridHasPairingAtRow(FGrid, ARow) then
    Exit;
  if TournamentReasonIsTransient(FGrid.Cells[TournamentColReason, ARow]) and
    (not IsRowRunning(ARow)) then
    FGrid.Cells[TournamentColReason, ARow] := '';
  if TournamentResultIsKnown(ParseTournamentResult(
    FGrid.Cells[TournamentColResult, ARow],FProfile.FileFormat)) then
    Exit;
  if Trim(FGrid.Cells[TournamentColReason, ARow]) <> '' then
    Exit;

  WhiteEngine := EngineForRow(ARow, True);
  BlackEngine := EngineForRow(ARow, False);
  WhiteKey := EngineIdentityKey(WhiteEngine);
  BlackKey := EngineIdentityKey(BlackEngine);
  if (WhiteKey = '') or (BlackKey = '') then
  begin StartFailure(ARow,'Missing engine'); Exit; end;
  if EngineExecutableProblem(WhiteEngine)<>'' then
  begin StartFailure(ARow,EngineExecutableProblem(WhiteEngine)); Exit; end;
  if EngineExecutableProblem(BlackEngine)<>'' then
  begin StartFailure(ARow,EngineExecutableProblem(BlackEngine)); Exit; end;
  if ABusyEngineKeys <> nil then
  begin
    CandidateKeys := TStringList.Create;
    try
      for SideIndex:=0 to 1 do begin
        if SideIndex=0 then Candidate:=WhiteEngine else Candidate:=BlackEngine;
        CandidateKeys.Clear;AddEngineReservationKeys(Candidate,CandidateKeys);
        for I:=0 to CandidateKeys.Count-1 do
          if ABusyEngineKeys.IndexOf(CandidateKeys[I])>=0 then begin
            Description:='';
            if Owner is TMainForm then Description:=TMainForm(Owner).EngineReservationDescription(CandidateKeys[I]);
            FGrid.Cells[TournamentColReason,ARow]:='Waiting for engine '+DisplayNameForEngine(Candidate);
            if Description<>'' then FGrid.Cells[TournamentColReason,ARow]:=FGrid.Cells[TournamentColReason,ARow]+', in use by '+Description;
            Exit;
          end;
      end;
    finally
      CandidateKeys.Free;
    end;
  end;
  Result := True;
end;

procedure TTournamentDialog.PairingGridDrawCell(Sender: TObject; ACol,
  ARow: Integer; Rect: TRect; State: TGridDrawState);
begin
  if ARow = 0 then
  begin
    FGrid.Canvas.Brush.Color := clBtnFace;
    FGrid.Canvas.Font.Color := clWindowText;
  end
  else if IsRowRunning(ARow) then
  begin
    FGrid.Canvas.Brush.Color := TColor($00CCFFFF);
    FGrid.Canvas.Font.Color := clBlack;
  end
  else
  begin
    FGrid.Canvas.Brush.Color := clWindow;
    FGrid.Canvas.Font.Color := clWindowText;
  end;
  DrawGridText(FGrid, ACol, ARow, Rect);
end;

procedure TTournamentDialog.PairingGridMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Col: Integer;
  Game: TRunningGame;
  Row: Integer;
  RunningGame: TTournamentRunningGame;
begin
  if FGrid = nil then
    Exit;

  FGrid.MouseToCell(X, Y, Col, Row);
  if (Col >= 0) and (Col < FGrid.ColCount) and (Row > 0) and
    (Row < FGrid.RowCount) then
  begin
    FGrid.Col := Col;
    FGrid.Row := Row;
    if Button = mbLeft then
    begin
      RunningGame := FindTournamentGameByRow(Row);
      Game := TournamentRunningGameFor(Owner, RunningGame);
      if (Game <> nil) and Assigned(FOnSelectGame) then
        FOnSelectGame(Self, Game);
    end;
  end;
end;

procedure TTournamentDialog.SetSelectedResult(const AResultText: string);
begin
  if (FGrid = nil) or (FGrid.Row <= 0) or
    (FGrid.Row >= FGrid.RowCount) or IsRowRunning(FGrid.Row) or
    (not TournamentGridHasPairingAtRow(FGrid, FGrid.Row)) then
    Exit;

  if (AResultText <> '*') and
    not TournamentResultIsKnown(ParseTournamentResult(AResultText,FProfile.FileFormat)) then
    raise EConvertError.Create('Invalid manual tournament result');
  GameRecord(FGrid.Row).OverrideResult(AResultText);
  FGrid.Cells[TournamentColResult, FGrid.Row] := GameRecord(FGrid.Row).EffectiveResult;
  if GameRecord(FGrid.Row).ManualResult <> '' then
    FGrid.Cells[TournamentColReason, FGrid.Row] := TournamentRefereeReason(
      FGrid.Cells[TournamentColReason,FGrid.Row],GameRecord(FGrid.Row).EffectiveResult,FProfile.FileFormat)
  else begin
    FGrid.Cells[TournamentColReason,FGrid.Row]:=TournamentPlayedReason(FGrid.Cells[TournamentColReason,FGrid.Row]);
    if (FGrid.Cells[TournamentColReason,FGrid.Row]='') and (GameRecord(FGrid.Row).PlayedResult<>'') then
      FGrid.Cells[TournamentColReason,FGrid.Row]:='Played result';
  end;
  UpdateCrossTable;
  AutoSaveTournament;
end;

procedure TTournamentDialog.SetSelectedResultClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    SetSelectedResult(TMenuItem(Sender).Caption);
end;

procedure TTournamentDialog.RescheduleSelectedGame(Sender: TObject);
var
  Row, I: Integer;
  Running: TTournamentRunningGame;
begin
  if FStorageError <> '' then Exit;
  Row := FGrid.Row;
  if (Row <= 0) or (Row >= FGrid.RowCount) then
    Exit;
  if IsRowRunning(Row) then
    Exit;
  if not TournamentGridHasPairingAtRow(FGrid, Row) then
    Exit;

  for I := 0 to FRunningGames.Count - 1 do
  begin
    Running := TTournamentRunningGame(FRunningGames[I]);
    if Running.Row = Row then
    begin Running.PendingCapture := False; Running.Active := False; Running.GameId := 0; end;
  end;
  GameRecord(Row).Reschedule;
  FGrid.Cells[TournamentColResult, Row] := '*';
  FGrid.Cells[TournamentColReason, Row] := '';
  FGrid.Invalidate;
  UpdateCrossTable;
  UpdateButtons;
  AutoSaveTournament;
end;

procedure TTournamentDialog.SaveClick(Sender: TObject);
begin
  if IsRunning then Exit;
  SaveTournamentWithDialog;
end;

procedure TTournamentDialog.GameContextChanged(Sender:TObject);
var TargetVariant:TGameVariant;I:Integer;
begin
  if (FGameCombo=nil) or (FGameCombo.ItemIndex<0) then Exit;
  TargetVariant:=TGameVariant(FGameCombo.Items.Objects[FGameCombo.ItemIndex]);
  for I:=0 to FGameCombo.Items.Count-1 do if FGameCombo.Items.Objects[I]=FVariant then FGameCombo.ItemIndex:=I;
  if (TargetVariant<>FVariant) and Assigned(FOnContextRequested) then FOnContextRequested(Self,TargetVariant,'');
end;

procedure TTournamentDialog.LoadClick(Sender: TObject);
var
  Dialog: TOpenDialog;
  TargetVariant:TGameVariant;
begin
  if IsRunning then Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := 'Load tournament';
    if FFileName <> '' then
      Dialog.InitialDir := ExtractFilePath(FFileName)
    else if DirectoryExists(IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'tournaments') then
      Dialog.InitialDir := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'tournaments';
    Dialog.Filter := 'Tournament files (*.json)|*.json|All files (*.*)|*.*';
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if ExecuteGuiFileDialog(Dialog) then
    try
      TargetVariant:=TournamentFileVariant(Dialog.FileName,FVariant);
      if Assigned(FOnContextRequested) then FOnContextRequested(Self,TargetVariant,Dialog.FileName)
      else LoadTournamentFromFile(Dialog.FileName);
    except on E:Exception do ShowGuiOkDialog(Self,'Load tournament',E.Message);end;
  finally
    Dialog.Free;
  end;
end;

procedure TTournamentDialog.SaveTournamentToFile(const AFileName: string);
var
  OldJson, OldPdn, OldHash, OldVerified, RecoveryDirectory: string;
  OldOwned, Relocate: Boolean;
  I: Integer;
  Running: TTournamentRunningGame;
  Game: TRunningGame;
begin
  ReadSettings;MaxConcurrentGames;
  if Assigned(FOnTargets) then FOnTargets(Self,AFileName,FPdnFileName,FTournamentId);
  for I := 0 to FRunningGames.Count - 1 do
  begin
    Running := TTournamentRunningGame(FRunningGames[I]);
    if not Running.PendingCapture then Continue;
    Game := TournamentRunningGameFor(Owner, Running);
    if Game <> nil then CaptureTournamentGame(Running, Game);
  end;
  OldJson := FFileName;
  OldPdn := FPdnFileName;
  OldOwned := FPdnFileOwned;
  OldHash := FPdnPublishedHash;
  OldVerified := FVerifiedPdnFingerprint;
  RecoveryDirectory := IncludeTrailingPathDelimiter(ExpandFileName(
    IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'tournaments'));
  Relocate := (OldJson <> '') and
    (ExtractFilePath(ExpandFileName(OldJson)) = RecoveryDirectory) and
    (ExtractFilePath(ExpandFileName(AFileName)) <> RecoveryDirectory);
  try
    if Relocate and ((OldPdn = '') or
      (ExtractFilePath(ExpandFileName(OldPdn)) = RecoveryDirectory)) then
    begin
      FPdnFileName := UnusedTournamentPdnPath(ChangeFileExt(
        ExpandFileName(AFileName), GameFileExtension),FProfile.FileFormat);
      FPdnFileOwned := False;
    end;
    FFileName := ExpandFileName(AFileName);
    EnsureStoragePaths;
    try
      WritePdnProjection;
    finally
      SaveTournamentSnapshot(AFileName);
    end;
  except
    // A failed Save As must leave the recoverable source and its identity intact.
    FFileName := OldJson;
    FPdnFileName := OldPdn;
    FPdnFileOwned := OldOwned;
    FPdnPublishedHash := OldHash;
    FVerifiedPdnFingerprint := OldVerified;
    raise;
  end;
  if Relocate then
  begin
    // Only remove the source once both new files have been published successfully.
    if OldOwned and (OldPdn <> FPdnFileName) and
      (ExtractFilePath(ExpandFileName(OldPdn)) = RecoveryDirectory) and
      FileExists(OldPdn) and not DeleteFile(OldPdn) then
      raise EInOutError.Create('Tournament saved, but could not remove recovery PDN');
    if FileExists(OldJson) and not DeleteFile(OldJson) then
      raise EInOutError.Create('Tournament saved, but could not remove recovery JSON');
  end;
  FStorageError := '';
  UpdateButtons;
end;

procedure TTournamentDialog.SaveTournamentSnapshot(const AFileName: string);
var
  Data: TJSONObject;
  EngineArray, EngineKeys: TJSONArray;
  Game: TJSONObject;
  Games: TJSONArray;
  I: Integer;
  NextPdnFileName: string;
  Clock:TTimeControl;
begin
  Clock:=ReadSettings;
  NextPdnFileName := FPdnFileName;
  if NextPdnFileName = '' then
    NextPdnFileName := ChangeFileExt(ExpandFileName(AFileName), GameFileExtension);
  if not FPdnFileOwned then
    NextPdnFileName := UnusedTournamentPdnPath(NextPdnFileName,FProfile.FileFormat);
  Data := TJSONObject.Create;
  try
    if FProfile.FileFormat=gffPgn then begin
      Data.Add('storage_version',3);Data.Add('game_variant','chess');
      Data.Add('notation_format','pgn');Data.Add('force_ponder_off',FProfile.TournamentForcePonderOff);
    end else Data.Add('storage_version', 2);
    Data.Add('legacy_pdn_file_name', FLegacyPdnFileName);
    Data.Add('tournament_id', FTournamentId);
    Data.Add('pdn_file_name', ExtractRelativePath(ExpandFileName(AFileName),
      NextPdnFileName));
    Data.Add('pdn_owned', FPdnFileOwned);
    Data.Add('pdn_published_hash', FPdnPublishedHash);
    Data.Add('tournament_name', FTournamentNameEdit.Text);
    if Trim(FStartingFENEdit.Text)='' then Data.Add('starting_fen',FVariant.DefaultStartingFEN)
    else Data.Add('starting_fen', Trim(FStartingFENEdit.Text));
    Data.Add('moves_per_period', Clock.MovesPerPeriod);
    Data.Add('minutes_per_period', Clock.MinutesPerPeriod);
    if FTimeUnitCombo.ItemIndex=1 then Data.Add('time_unit','seconds')
    else Data.Add('time_unit','minutes');
    Data.Add('increment_seconds', Clock.IncrementSeconds);
    Data.Add('concurrent_games', MaxConcurrentGames);
    if FIncrementModeCombo.ItemIndex = 1 then
      Data.Add('increment_mode', 'after-move-limit')
    else
      Data.Add('increment_mode', 'from-start');
    Data.Add('pairing_type',
      TournamentTypeForRoundRobinIndex(FRoundRobinGroup.ItemIndex));

    EngineArray := TJSONArray.Create;
    Data.Add('selected_engines', EngineArray);
    EngineKeys := TJSONArray.Create;
    Data.Add('selected_engine_keys', EngineKeys);
    for I := 0 to FEngineCheckList.Items.Count - 1 do
      if FEngineCheckList.Checked[I] then
      begin
        EngineArray.Add(FEngineCheckList.Items[I]);
        EngineKeys.Add(EngineIdentityKey(TExternalEngineDefinition(FEngineCheckList.Items.Objects[I])));
      end;

    Games := TJSONArray.Create;
    Data.Add('games', Games);
    for I := 1 to FGrid.RowCount - 1 do
      if TournamentGridHasPairingAtRow(FGrid, I) then
      begin
        // Byes award points without a running game producing a record.
        if SameText(FGrid.Cells[TournamentColReason, I], 'Bye') and
          not GameRecord(I).HasRecord then
          GameRecord(I).RecordPlayedGame('', FGrid.Cells[TournamentColResult, I]);
        EngineForRow(I, True);
        EngineForRow(I, False);
        Game := TJSONObject.Create;
        Game.Add('game', StrToIntDef(FGrid.Cells[TournamentColGame, I], I));
        Game.Add('round', StrToIntDef(FGrid.Cells[TournamentColRound, I], 1));
        Game.Add('white', FGrid.Cells[TournamentColWhite, I]);
        Game.Add('black', FGrid.Cells[TournamentColBlack, I]);
        Game.Add('result', GameRecord(I).EffectiveResult);
        Game.Add('record', GameRecord(I).ToJson);
        Game.Add('reason', FGrid.Cells[TournamentColReason, I]);
        Games.Add(Game);
      end;

    WriteTextFileAtomically(AFileName, TournamentDocumentText(Data));
    FFileName := ExpandFileName(AFileName);
    FPdnFileName := NextPdnFileName;
  finally
    Data.Free;
  end;
end;

procedure TTournamentDialog.LoadTournamentFromFile(const AFileName: string);
var
  Data: TJSONObject;
  EngineName: string;
  Engines, SelectedKeys: TJSONData;
  Engine: TExternalEngineDefinition;
  KeyIndex: Integer;
  Game: TJSONObject;
  Games: TJSONData;
  I: Integer;
  Row: Integer;
  PairingType,TimeUnit: string;
  Id: TGUID;
  Setup:TGameSetup;
begin
  if IsRunning then
    Exit;
  Data := ReadTournamentDocument(AFileName,FProfile.FileFormat);
  try
    Setup:=Default(TGameSetup);Setup.Variant:=FVariant;Setup.WhitePlayer:=pkHuman;Setup.BlackPlayer:=pkHuman;
    Setup.StartingFEN:=Data.Get('starting_fen',FVariant.DefaultStartingFEN);
    Setup.TimeControl:=FProfile.DefaultClock;
    Setup.TimeControl.MovesPerPeriod:=Data.Get('moves_per_period',Setup.TimeControl.MovesPerPeriod);
    Setup.TimeControl.MinutesPerPeriod:=Data.Get('minutes_per_period',Setup.TimeControl.MinutesPerPeriod);
    Setup.TimeControl.IncrementSeconds:=Data.Get('increment_seconds',Setup.TimeControl.IncrementSeconds);
    if Setup.StartingFEN='' then Setup.StartingFEN:=FVariant.DefaultStartingFEN;
    ValidateGameSetup(Setup,FVariant,FProfile.EngineKinds);
    TimeUnit:=Data.Get('time_unit','minutes');
  except Data.Free;raise;end;
  FLoadingTournament := True;
  try
    FTournamentNameEdit.Text := TJSONObject(Data).Get('tournament_name',
      'Tournament');
    FStartingFENEdit.Text := TJSONObject(Data).Get('starting_fen',
      FVariant.DefaultStartingFEN);
    FMovesEdit.Text := IntToStr(TJSONObject(Data).Get('moves_per_period', FProfile.DefaultClock.MovesPerPeriod));
    if TimeUnit='seconds' then begin
      FTimeUnitCombo.ItemIndex:=1;FMinutesEdit.Text:=FloatToStr(Setup.TimeControl.MinutesPerPeriod*60);
    end else begin
      FTimeUnitCombo.ItemIndex:=0;FMinutesEdit.Text:=FloatToStr(Setup.TimeControl.MinutesPerPeriod);
    end;
    FIncrementEdit.Text := FloatToStr(TJSONObject(Data).Get('increment_seconds', FProfile.DefaultClock.IncrementSeconds));
    FConcurrentGamesEdit.Text := IntToStr(TJSONObject(Data).Get('concurrent_games', 1));
    if SameText(TJSONObject(Data).Get('increment_mode', 'from-start'),
      'after-move-limit') then
      FIncrementModeCombo.ItemIndex := 1
    else
      FIncrementModeCombo.ItemIndex := 0;

    PairingType := TJSONObject(Data).Get('pairing_type',
      TournamentTypeSingleRoundRobin);
    if SameText(PairingType, TournamentTypeSwiss) then
      FRoundRobinGroup.ItemIndex := TournamentPairingIndexSwiss
    else if SameText(PairingType, TournamentTypeDoubleRoundRobin) then
      FRoundRobinGroup.ItemIndex := TournamentPairingIndexDoubleRoundRobin
    else
      FRoundRobinGroup.ItemIndex := TournamentPairingIndexSingleRoundRobin;

    for I := 0 to FEngineCheckList.Items.Count - 1 do
      FEngineCheckList.Checked[I] := False;
    Engines := TJSONObject(Data).Find('selected_engines');
    SelectedKeys := Data.Find('selected_engine_keys');
    if (SelectedKeys <> nil) and (SelectedKeys.JSONType = jtArray) then
    begin
      for KeyIndex := 0 to SelectedKeys.Count - 1 do
      begin
        Engine := FindEngineByIdentityKey(FEngines, TJSONArray(SelectedKeys).Strings[KeyIndex]);
        if Engine <> nil then
          for I := 0 to FEngineCheckList.Items.Count - 1 do
            if FEngineCheckList.Items.Objects[I] = Engine then FEngineCheckList.Checked[I] := True;
      end;
    end
    else if (Engines <> nil) and (Engines.JSONType = jtArray) then
      for I := 0 to TJSONArray(Engines).Count - 1 do
      begin
        EngineName := TJSONArray(Engines).Strings[I];
        Row := FEngineCheckList.Items.IndexOf(EngineName);
        if Row >= 0 then FEngineCheckList.Checked[Row] := True;
      end;

    ClearTournamentGameRefs;
    ClearTournamentPairingGrid(FGrid);
    Games := TJSONObject(Data).Find('games');
    if (Games <> nil) and (Games.JSONType = jtArray) then
      for I := 0 to TJSONArray(Games).Count - 1 do
        if TJSONArray(Games).Items[I].JSONType = jtObject then
        begin
          Game := TJSONObject(TJSONArray(Games).Items[I]);
          Row := AddTournamentPairingRow(FGrid, Game.Get('white', ''),
            Game.Get('black', ''), Game.Get('round', 1));
          FGrid.Cells[TournamentColGame, Row] := IntToStr(Game.Get('game', Row));
          GameRecord(Row).LoadFromJson(Game);
          Engine := EngineForRow(Row, True);
          if Engine <> nil then FGrid.Cells[TournamentColWhite, Row] := DisplayNameForEngine(Engine);
          Engine := EngineForRow(Row, False);
          if Engine <> nil then FGrid.Cells[TournamentColBlack, Row] := DisplayNameForEngine(Engine);
          FGrid.Cells[TournamentColResult, Row] := GameRecord(Row).EffectiveResult;
          if GameRecord(Row).ManualResult <> '' then
            FGrid.Cells[TournamentColReason, Row] := TournamentRefereeReason(
              Game.Get('reason',''),GameRecord(Row).EffectiveResult,FProfile.FileFormat)
          else
            FGrid.Cells[TournamentColReason, Row] := Game.Get('reason', '');
          if GameRecord(Row).CaptureError <> '' then
            FGrid.Cells[TournamentColReason, Row] := 'Capture failed: ' + GameRecord(Row).CaptureError;
        end;
    FTournamentId := Data.Get('tournament_id', '');
    if FTournamentId = '' then
    begin
      if CreateGUID(Id) <> 0 then raise EInOutError.Create('Could not create a tournament identity');
      FTournamentId := GUIDToString(Id);
    end;
    FPdnPublishedHash := Data.Get('pdn_published_hash', '');
    FVerifiedPdnFingerprint := '';
    FStorageNotice := '';
    FPdnFileName := Data.Get('pdn_file_name', ChangeFileExt(ExpandFileName(AFileName), GameFileExtension));
    if (FPdnFileName <> '') and not FilenameIsAbsolute(FPdnFileName) then
      FPdnFileName := ExpandFileName(ExtractFilePath(ExpandFileName(AFileName)) + FPdnFileName);
    FLegacyPdnFileName := Data.Get('legacy_pdn_file_name', '');
    FPdnFileOwned := (Data.Get('storage_version', 0) >= 2) and
      Data.Get('pdn_owned', False);
    if (FPdnFileName = '') or not DirectoryExists(ExtractFilePath(FPdnFileName)) then
    begin
      // Rebuild from authoritative JSON at the new location. A pre-existing
      // sibling PDN has not been claimed by this snapshot and must be preserved.
      FPdnFileName := ChangeFileExt(ExpandFileName(AFileName), GameFileExtension);
      FPdnFileOwned := False;
    end;
    if (Data.Get('storage_version', 0) >= 2) and
      (Data.Find('pdn_owned') = nil) and FileExists(FPdnFileName) and
      (FLegacyPdnFileName = '') then
      FLegacyPdnFileName := FPdnFileName;
    if (Data.Get('storage_version', 0) < 2) and FileExists(FPdnFileName) then
    begin
      // Never overwrite an older, unlinked archive while migrating standings.
      FLegacyPdnFileName := FPdnFileName;
      FPdnFileName := ChangeFileExt(FPdnFileName, '') + '.' + FTournamentId + GameFileExtension;
    end;
    FStorageError := '';
    FFileName := ExpandFileName(AFileName);
    FAcceptedTournamentSignature := TournamentSignature;
    if FInvalidationPanel <> nil then
      FInvalidationPanel.Visible := False;
    AdjustPairingGridColumnWidths;
    UpdateCrossTable;
  finally
    FLoadingTournament := False;
    Data.Free;
  end;
  AutoSaveTournament;
  if Assigned(FOnTitleChanged) then FOnTitleChanged(Self);
end;

procedure TTournamentDialog.InvalidateTournamentResults(Sender: TObject);
begin
  if FLoadingTournament then
    Exit;
  if FGrid = nil then
    Exit;
  if TournamentPairingGridIsEmpty(FGrid) then
  begin
    FAcceptedTournamentSignature := TournamentSignature;
    Exit;
  end;
  if TournamentSignature = FAcceptedTournamentSignature then
  begin
    if FInvalidationPanel <> nil then
      FInvalidationPanel.Visible := False;
    Exit;
  end;

  if FInvalidationPanel <> nil then
    FInvalidationPanel.Visible := True;
  UpdateButtons;
end;

function TTournamentDialog.PendingInvalidatingChange: Boolean;
begin
  Result := (FInvalidationPanel <> nil) and FInvalidationPanel.Visible;
end;

function TTournamentDialog.TournamentSignature: string;
begin
  Result := Trim(FStartingFENEdit.Text) + '|' + Trim(FMovesEdit.Text) + '|' +
    Trim(FMinutesEdit.Text) + '|' + Trim(FIncrementEdit.Text) + '|' +
    IntToStr(FIncrementModeCombo.ItemIndex) + '|' +
    IntToStr(FRoundRobinGroup.ItemIndex)+'|'+IntToStr(FTimeUnitCombo.ItemIndex);
end;

procedure TTournamentDialog.ApplyInvalidatingChange(Sender: TObject);
begin
  try ReadSettings;MaxConcurrentGames;
  except on E:Exception do begin ShowGuiOkDialog(Self,'Tournament',E.Message);Exit;end;end;
  if not StartNewTournamentStorage then Exit;
  if FInvalidationPanel <> nil then
    FInvalidationPanel.Visible := False;

  if FRunning then
  begin
    FRunning := False;
    StopRunningGames;
    FTimer.Enabled := ActiveRunningGameCount > 0;
    UpdateButtons;
  end;

  ClearTournamentGameRefs;
  if FTimer <> nil then
    FTimer.Enabled := False;
  ClearTournamentPairingGrid(FGrid);
  FAcceptedTournamentSignature := TournamentSignature;
  UpdateCrossTable;
  UpdateButtons;
  AutoSaveTournament;
end;

procedure TTournamentDialog.RevertInvalidatingChange(Sender: TObject);
var
  Parts: TStringList;
begin
  if FInvalidationPanel <> nil then
    FInvalidationPanel.Visible := False;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := '|';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := FAcceptedTournamentSignature;
    if Parts.Count >= 6 then
    begin
      FLoadingTournament := True;
      try
        FStartingFENEdit.Text := Parts[0];
        FMovesEdit.Text := Parts[1];
        FMinutesEdit.Text := Parts[2];
        FIncrementEdit.Text := Parts[3];
        FIncrementModeCombo.ItemIndex := StrToIntDef(Parts[4], 0);
        FRoundRobinGroup.ItemIndex := StrToIntDef(Parts[5], 0);
        if Parts.Count>=7 then FTimeUnitCombo.ItemIndex:=StrToIntDef(Parts[6],0)
        else FTimeUnitCombo.ItemIndex:=0;
      finally
        FLoadingTournament := False;
      end;
    end;
  finally
    Parts.Free;
  end;
  UpdateButtons;
end;

function TTournamentDialog.GameSetupForRow(ARow: Integer;
  out ASetup: TGameSetup): Boolean;
begin
  Result := False;
  ASetup:=Default(TGameSetup);ASetup.Variant:=FVariant;
  ASetup.WhitePlayer:=pkRegistered;ASetup.BlackPlayer:=pkRegistered;
  if not TournamentGridHasPairingAtRow(FGrid,ARow) then Exit;
  ASetup.WhiteEngine:=EngineForRow(ARow,True);ASetup.BlackEngine:=EngineForRow(ARow,False);
  if (ASetup.WhiteEngine=nil) or (ASetup.BlackEngine=nil) then
  begin FGrid.Cells[TournamentColReason,ARow]:='Missing engine';Exit;end;
  ASetup.StartingFEN:=Trim(FStartingFENEdit.Text);
  if ASetup.StartingFEN='' then ASetup.StartingFEN:=FVariant.DefaultStartingFEN;
  try
    ASetup.TimeControl:=ReadSettings;
    ASetup.ForcePonderOff:=FProfile.TournamentForcePonderOff;
    ValidateGameSetup(ASetup,FVariant,FProfile.EngineKinds);
  except on E:Exception do begin StartFailure(ARow,E.Message);Exit;end;end;
  Result := True;
end;

function TTournamentDialog.MaxConcurrentGames: Integer;
begin
  if not TryStrToInt(Trim(FConcurrentGamesEdit.Text),Result) or (Result<1) then
    raise EConvertError.Create('Concurrent games must be a positive integer');
end;

procedure TTournamentDialog.HighlightRow(ARow: Integer);
var
  Bounds: TRect;
  FixedBottom: Integer;
begin
  if (ARow > 0) and (ARow < FGrid.RowCount) then
  begin
    // Native row selection scrolls only as far as needed to reveal the row.
    FGrid.Row := ARow;
    // Selecting the same row is a no-op in LCL, even after manual scrolling.
    Bounds := FGrid.CellRect(FGrid.Col, ARow);
    FixedBottom := 0;
    if FGrid.FixedRows > 0 then
      FixedBottom := FGrid.CellRect(FGrid.Col, FGrid.FixedRows - 1).Bottom;
    if (Bounds.Top < FixedBottom) or (Bounds.Bottom > FGrid.ClientHeight) then
      FGrid.TopRow := ARow;
  end;
end;

procedure TTournamentDialog.StartStopClick(Sender: TObject);
begin
  if FRunning or FRefereeStopPending or TournamentPairingGridIsEmpty(FGrid) then Exit;

  if PendingInvalidatingChange then
    Exit;

  try ReadSettings;MaxConcurrentGames;
  except on E:Exception do begin ShowGuiOkDialog(Self,'Tournament',E.Message);Exit;end;end;
  if not ConfirmSharedExecutables then Exit;
  AutoSaveTournament;
  if FStorageError <> '' then
    Exit;
  ClearStaleRunningReasons;
  FCloseStopped:=False;
  FRunning := True;
  FLastGameStartTick := 0;
  StartPendingGames;
  FTimer.Enabled := FRunning or (ActiveRunningGameCount>0);
  UpdateButtons;
end;

procedure TTournamentDialog.RefereeStopClick(Sender:TObject);
begin
  if FRefereeStopPending or ((not FRunning) and (ActiveRunningGameCount=0)) then Exit;
  FRunning:=False;FCloseStopped:=False;FRefereeStopPending:=True;
  StopRunningGames('Referee stopped tournament');
  FTimer.Enabled:=ActiveRunningGameCount>0;
  UpdateButtons;
end;

procedure TTournamentDialog.StopRunningGames(const AReason:string);
var
  Game: TRunningGame;
  I: Integer;
  RunningGame: TTournamentRunningGame;
begin
  LeaveEngineQueue;
  for I := FRunningGames.Count - 1 downto 0 do
  begin
    RunningGame := TTournamentRunningGame(FRunningGames[I]);
    if not RunningGame.Active then
      Continue;
    Game := TournamentRunningGameFor(Owner, RunningGame);
    if Game <> nil then
    begin
      if Game.Lifecycle = rglFinished then
      begin
        CaptureTournamentGame(RunningGame, Game);
        ApplyTournamentGameResultToRow(FGrid, RunningGame.Row, Game,FProfile.FileFormat);
        RunningGame.Active := False;
      end
      else
      begin
        if Owner is TMainForm then
          if FCloseStopped then TMainForm(Owner).MarkGameStopped(Game,'Stopped: tournament closed')
          else TMainForm(Owner).MarkGameStopped(Game, AReason)
        else if AReason='Referee stopped tournament' then Game.RequestStop(AReason)
        else Game.Runner.PostStop;
        if (RunningGame.Row > 0) and (RunningGame.Row < FGrid.RowCount) then
        begin
          FGrid.Cells[TournamentColResult, RunningGame.Row] := '*';
          if AReason='Referee stopped tournament' then
            FGrid.Cells[TournamentColReason,RunningGame.Row]:=AReason
          else FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Stopping';
        end;
        Continue;
      end;
    end;
    RunningGame.Active := False;
  end;
  if (not FClosing) and (FGrid <> nil) then
    FGrid.Invalidate;
  if not FClosing then
    UpdateCrossTable;
  AutoSaveTournament;
end;

procedure TTournamentDialog.GameRemoved(AGame: TObject);
var I: Integer; Running: TTournamentRunningGame;
begin
  if not (AGame is TRunningGame) then Exit;
  for I := FRunningGames.Count - 1 downto 0 do
  begin
    Running := TTournamentRunningGame(FRunningGames[I]);
    if Running.GameId = TRunningGame(AGame).Id then
    begin Running.Free; FRunningGames.Delete(I); end;
  end;
  // A capture error/result is already durable row data. Removing its live game
  // must not leave an unretryable pending reference blocking subsequent saves.
  AutoSaveTournament;
end;

procedure TTournamentDialog.GameStopped(AGame: TObject);
var
  I: Integer;
  RunningGame: TTournamentRunningGame;
begin
  for I := FRunningGames.Count - 1 downto 0 do
  begin
    RunningGame := TTournamentRunningGame(FRunningGames[I]);
    if not RunningGame.Active and not RunningGame.PendingCapture then
      Continue;
    if not (AGame is TRunningGame) then
      Continue;
    if RunningGame.GameId <> TRunningGame(AGame).Id then
      Continue;

    if TRunningGame(AGame).Lifecycle = rglFinished then
      CaptureTournamentGame(RunningGame, AGame);
    if (RunningGame.Row > 0) and (RunningGame.Row < FGrid.RowCount) then
    begin
      if (AGame is TRunningGame) and
        (TRunningGame(AGame).Lifecycle = rglFinished) and
        (TRunningGame(AGame).State in [gosGameOver, gosError]) then
      begin
        ApplyTournamentGameResultToRow(FGrid, RunningGame.Row,
          TRunningGame(AGame),FProfile.FileFormat);
        if GameRecord(RunningGame.Row).ManualResult <> '' then
        begin
          FGrid.Cells[TournamentColResult, RunningGame.Row] := GameRecord(RunningGame.Row).EffectiveResult;
          FGrid.Cells[TournamentColReason, RunningGame.Row] := TournamentRefereeReason(
            FGrid.Cells[TournamentColReason,RunningGame.Row],GameRecord(RunningGame.Row).EffectiveResult,FProfile.FileFormat);
        end;
        if GameRecord(RunningGame.Row).CaptureError <> '' then
          FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Capture failed: ' + GameRecord(RunningGame.Row).CaptureError;
      end
      else
      begin
        FGrid.Cells[TournamentColResult, RunningGame.Row] := '*';
        if (AGame is TRunningGame) and
          (TRunningGame(AGame).Lifecycle <> rglFinished) then
          FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Stopping'
        else
          if FCloseStopped then FGrid.Cells[TournamentColReason, RunningGame.Row]:='Stopped: tournament closed'
          else if TRunningGame(AGame).StopReason='Referee stopped tournament' then
            FGrid.Cells[TournamentColReason,RunningGame.Row]:='Referee stopped tournament'
          else FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Stopped';
      end;
    end;
    if (not (AGame is TRunningGame)) or
      (TRunningGame(AGame).Lifecycle = rglFinished) then
      RunningGame.Active := False
    else if (AGame is TRunningGame) and
      (TRunningGame(AGame).Lifecycle = rglRemoveRequested) then
    begin
      RunningGame.Free;
      FRunningGames.Delete(I);
    end;
    Break;
  end;

  if (not FClosing) and (FGrid <> nil) then
    FGrid.Invalidate;
  if not FClosing then
  begin
    UpdateCrossTable;
    UpdateButtons;
  end;
  AutoSaveTournament;
end;

procedure TTournamentDialog.RegisterRunningGame(ARow: Integer; AGame: TObject);
var
  RunningGame: TTournamentRunningGame;
begin
  if not (AGame is TRunningGame) or
    (not TournamentGridHasPairingAtRow(FGrid, ARow)) or IsRowRunning(ARow) then
    raise EInvalidOperation.Create('Cannot register a game for this tournament row');
  RunningGame := TTournamentRunningGame.Create;
  RunningGame.Active := True;
  RunningGame.Row := ARow;
  RunningGame.GameId := TRunningGame(AGame).Id;
  TRunningGame(AGame).TournamentOwner := Self;
  if FProfile.FileFormat=gffPgn then GameRecord(ARow).StartDate:=FormatDateTime('yyyy.mm.dd',TRunningGame(AGame).StartedAt);
  FRunningGames.Add(RunningGame);
  FGrid.Cells[TournamentColReason, ARow] := 'Running';
  UpdateButtons;
  AutoSaveTournament;
end;

procedure TTournamentDialog.StartFailure(ARow: Integer; const AReason: string);
begin
  FGrid.Cells[TournamentColResult,ARow]:='*';
  FGrid.Cells[TournamentColReason,ARow]:='Could not start: '+AReason;
  DebugLn(['Tournament row ',ARow,': ',FGrid.Cells[TournamentColReason,ARow]]);
  AutoSaveTournament;
end;

procedure TTournamentDialog.StartPendingGames;
var
  BusyEngineKeys, RequestKeys: TStringList;
  Queue: TTournamentEngineQueue;
  Blocker: TObject;
  GameObject: TObject;
  LatestRound, MaxGames, Row: Integer;
  Setup: TGameSetup;
  StartedAny: Boolean;

  function Eligible(ARow: Integer): Boolean;
  begin
    Result := (not TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) or
      (StrToIntDef(FGrid.Cells[TournamentColRound, ARow], 0) = LatestRound)) and
      IsRowStartable(ARow, nil);
  end;
begin
  if not FRunning or not Assigned(FOnStartGame) then begin
    LeaveEngineQueue;
    Exit;
  end;
  ClearStaleRunningReasons;
  StartedAny := False;
  try
    MaxGames := MaxConcurrentGames;
  except on E: Exception do begin
    FStorageError := E.Message; FRunning := False;
    LeaveEngineQueue; UpdateButtons; Exit;
  end; end;
  if ActiveRunningGameCount >= MaxGames then begin LeaveEngineQueue; Exit; end;
  if (FLastGameStartTick > 0) and
    (GetTickCount64 - FLastGameStartTick < TournamentLaunchStaggerMs) then Exit;

  Queue := nil;
  if Owner is TMainForm then Queue := TMainForm(Owner).TournamentEngineQueue;
  BusyEngineKeys := TStringList.Create;
  RequestKeys := TStringList.Create;
  try
    BusyEngineKeys.Sorted := True;
    BusyEngineKeys.Duplicates := dupIgnore;
    if Owner is TMainForm then
      TMainForm(Owner).CollectBusyEngineKeys(BusyEngineKeys);
    LatestRound := 0;
    if TournamentRoundRobinIndexIsSwiss(FRoundRobinGroup.ItemIndex) then
      for Row := 1 to FGrid.RowCount - 1 do
        if StrToIntDef(FGrid.Cells[TournamentColRound, Row], 0) > LatestRound then
          LatestRound := StrToIntDef(FGrid.Cells[TournamentColRound, Row], 0);

    // Publish this turn's candidates before checking precedence. Busy engines
    // still enter the queue; their wait survives subsequent timer ticks.
    if Queue <> nil then begin
      Queue.BeginUpdate(Self);
      try
        for Row := 1 to FGrid.RowCount - 1 do if Eligible(Row) and GameSetupForRow(Row, Setup) then begin
          RequestKeys.Clear;
          AddEngineReservationKeys(Setup.WhiteEngine, RequestKeys);
          AddEngineReservationKeys(Setup.BlackEngine, RequestKeys);
          Queue.Request(Self, Row, RequestKeys);
        end;
      finally Queue.EndUpdate(Self); end;
    end;

    for Row := 1 to FGrid.RowCount - 1 do begin
      if not FRunning then Break;
      if not Eligible(Row) or not IsRowStartable(Row, BusyEngineKeys) then Continue;
      Blocker := nil;
      if Queue <> nil then Blocker := Queue.BlockingOwner(Self, Row);
      if Blocker <> nil then begin
        FGrid.Cells[TournamentColReason, Row] := 'Waiting for engine allocation';
        if Blocker is TTournamentDialog then
          FGrid.Cells[TournamentColReason, Row] := 'Waiting for engine allocation: '+
            TTournamentDialog(Blocker).TournamentName+' has waited longer';
        Continue;
      end;
      if not GameSetupForRow(Row, Setup) then Continue;
      GameObject := nil;
      try
        FOnStartGame(Self, Setup, 'Tournament game', GameObject);
      except on E: Exception do begin StartFailure(Row, E.Message); Continue; end; end;
      if not (GameObject is TRunningGame) then begin
        StartFailure(Row, 'Game start was rejected'); Continue;
      end;
      RegisterRunningGame(Row, GameObject);
      FGrid.Invalidate;
      HighlightRow(Row);
      StartedAny := True;
      FLastGameStartTick := GetTickCount64;
      // Both engines are now reserved by the existing game infrastructure.
      // Rejoin at the back for this tournament's next game.
      LeaveEngineQueue;
      Break;
    end;
  finally
    RequestKeys.Free;
    BusyEngineKeys.Free;
  end;
  if (not StartedAny) and (ActiveRunningGameCount = 0) and
    (FindNextUnplayedRow = 0) then begin
    FRunning := False;
    LeaveEngineQueue;
    FTimer.Enabled := False;
    HighlightRow(0);
  end;
end;

procedure TTournamentDialog.TimerTick(Sender: TObject);
var
  Game: TRunningGame;
  I: Integer;
  RunningGame: TTournamentRunningGame;
begin
  if (not FRunning) and (ActiveRunningGameCount = 0) then
    Exit;

  for I := FRunningGames.Count - 1 downto 0 do
  begin
    RunningGame := TTournamentRunningGame(FRunningGames[I]);
    if not RunningGame.Active then
      Continue;
    Game := TournamentRunningGameFor(Owner, RunningGame);
    if Game = nil then
    begin
      RunningGame.Active := False;
      Continue;
    end;
    if Game.Lifecycle <> rglFinished then
      Continue;

    CaptureTournamentGame(RunningGame, Game);
    if Game.State in [gosGameOver, gosError] then
    begin
      ApplyTournamentGameResultToRow(FGrid, RunningGame.Row, Game,FProfile.FileFormat);
      if GameRecord(RunningGame.Row).ManualResult <> '' then
      begin
        FGrid.Cells[TournamentColResult, RunningGame.Row] := GameRecord(RunningGame.Row).EffectiveResult;
        FGrid.Cells[TournamentColReason, RunningGame.Row] := TournamentRefereeReason(
            FGrid.Cells[TournamentColReason,RunningGame.Row],GameRecord(RunningGame.Row).EffectiveResult,FProfile.FileFormat);
      end;
      if GameRecord(RunningGame.Row).CaptureError <> '' then
        FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Capture failed: ' + GameRecord(RunningGame.Row).CaptureError;
    end
    else if (RunningGame.Row > 0) and (RunningGame.Row < FGrid.RowCount) then
    begin
      FGrid.Cells[TournamentColResult, RunningGame.Row] := '*';
      if FCloseStopped then FGrid.Cells[TournamentColReason, RunningGame.Row]:='Stopped: tournament closed'
      else if Game.StopReason='Referee stopped tournament' then
        FGrid.Cells[TournamentColReason,RunningGame.Row]:='Referee stopped tournament'
      else if SameText(FGrid.Cells[TournamentColReason, RunningGame.Row], 'Stopping') then
        FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Stopped'
      else
        FGrid.Cells[TournamentColReason, RunningGame.Row] := 'Unknown result';
    end;
    RunningGame.Active := False;
    FLastGameStartTick := GetTickCount64;
    FGrid.Invalidate;
    AutoSaveTournament;
  end;

  UpdateCrossTable;
  if FRunning then
    StartPendingGames
  else if ActiveRunningGameCount = 0 then
    FTimer.Enabled := False;
  UpdateButtons;
end;

procedure TTournamentDialog.UpdateButtons;
var
  I, FailedCaptures: Integer;
  Button: TComponent;
const
  PairingActions: array[0..4] of string = ('CreatePairing', 'ClearPairing',
    'LoadTournament', 'SaveTournament', 'ApplyTournamentChanges');
begin
  if FClosing then
    Exit;
  for I := Low(PairingActions) to High(PairingActions) do
  begin
    Button := FindComponent(PairingActions[I]);
    if Button is TButton then
      TButton(Button).Enabled := (not IsRunning) and
        ((PairingActions[I]='LoadTournament') or (PairingActions[I]='SaveTournament') or (FStorageError=''));
  end;
  Caption := 'Tournament';
  if RegisteredGameCount>1 then Caption:=Caption+' - '+FVariant.Name;
  FailedCaptures := 0;
  for I := 0 to FGameRecords.Count - 1 do
    if TTournamentGameRecord(FGameRecords[I]).CaptureError <> '' then Inc(FailedCaptures);
  if FailedCaptures > 0 then Caption := Caption + ' - ' + IntToStr(FailedCaptures) + ' game capture(s) failed; see rows';
  if FStorageNotice <> '' then Caption := Caption + ' - ' + FStorageNotice;
  if FStorageError <> '' then
    Caption := Caption + ' - save failed: ' + FStorageError;
  if FRunning then
    Caption := Caption + ' - running'
  else if PendingInvalidatingChange then
    Caption := Caption + ' - settings changed';
  if FStartStopButton <> nil then
  begin
    if ActiveRunningGameCount=0 then FRefereeStopPending:=False;
    FStartStopButton.Enabled := (not FRunning) and (not FRefereeStopPending) and
      (not PendingInvalidatingChange) and (not TournamentPairingGridIsEmpty(FGrid));
    FStopButton.Enabled := (FRunning or (ActiveRunningGameCount>0)) and
      (not FRefereeStopPending);
  end;
end;

procedure TTournamentDialog.UpdateCrossTable;
var
  BlackEngines: TStringList;
  Col: Integer;
  Engines: TStringList;
  I: Integer;
  J: Integer;
  Results: TStringList;
  Table: TTournamentCrossTable;
  WhiteEngines: TStringList;
begin
  if FClosing then
    Exit;
  if FCrossTableGrid = nil then
    Exit;

  Engines := TStringList.Create;
  WhiteEngines := TStringList.Create;
  BlackEngines := TStringList.Create;
  Results := TStringList.Create;
  try
    CollectSelectedEngines(Engines);
    CollectPairingRows(WhiteEngines, BlackEngines, Results);
    BuildTournamentCrossTable(Engines, WhiteEngines, BlackEngines, Results, Table,FProfile.FileFormat);

    FCrossTableGrid.ColCount := Max(4, Length(Table.EngineNames) + 4);
    FCrossTableGrid.RowCount := Max(2, Length(Table.EngineNames) + 1);
    for I := 0 to FCrossTableGrid.ColCount - 1 do
      for J := 0 to FCrossTableGrid.RowCount - 1 do
        FCrossTableGrid.Cells[I, J] := '';

    FCrossTableGrid.Cells[0, 0] := 'Engine';
    for I := 0 to High(Table.Order) do
    begin
      FCrossTableGrid.Cells[I + 1, 0] :=
        CompactTournamentEngineHeader(Table.EngineNames[Table.Order[I]]);
      FCrossTableGrid.Cells[0, I + 1] := Table.EngineNames[Table.Order[I]];
    end;

    Col := Length(Table.EngineNames) + 1;
    FCrossTableGrid.Cells[Col, 0] := 'Points';
    FCrossTableGrid.Cells[Col + 1, 0] := '#Wins';
    FCrossTableGrid.Cells[Col + 2, 0] := 'SB';

    if Length(Table.EngineNames) = 0 then
    begin
      FCrossTableGrid.Cells[0, 1] := '';
      FCrossTableGrid.Cells[1, 1] := '0';
    end
    else
      for I := 0 to High(Table.Order) do
      begin
        for J := 0 to High(Table.Order) do
          FCrossTableGrid.Cells[J + 1, I + 1] :=
            Table.Matrix[Table.Order[I], Table.Order[J]];
        FCrossTableGrid.Cells[Col, I + 1] :=
          FormatTournamentSB(Table.Points[Table.Order[I]],FProfile.FileFormat);
        FCrossTableGrid.Cells[Col + 1, I + 1] :=
          IntToStr(Table.Wins[Table.Order[I]]);
        FCrossTableGrid.Cells[Col + 2, I + 1] :=
          FormatTournamentSB(Table.SB[Table.Order[I]],FProfile.FileFormat);
      end;

    FCrossTableGrid.ColWidths[0] := 260;
    for I := 1 to FCrossTableGrid.ColCount - 1 do
      FCrossTableGrid.ColWidths[I] := 72;
  finally
    Results.Free;
    BlackEngines.Free;
    WhiteEngines.Free;
    Engines.Free;
  end;
end;

end.
