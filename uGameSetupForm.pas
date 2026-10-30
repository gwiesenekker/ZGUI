unit uGameSetupForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, Controls, ExtCtrls, Forms, StdCtrls, SysUtils,
  uEngineRegistry, uGameOrchestrator, uGameSetupTypes, uPreferences, uGameGuiProfile, uGamePosition, uGuiDialogs;

type
  TGameSetupForm = class(TForm)
  private
    FVariant:TGameVariant;
    FBlackPlayerCombo: TComboBox;
    FGameCombo:TComboBox;
    procedure GameChanged(Sender:TObject);
  private
    FBusyEngineKeys: TStringList;
    FDefaultTimeControl: TTimeControl;
    FIncrementEdit: TEdit;
    FIncrementModeCombo: TComboBox;
    FMovesEdit: TEdit;
    FMinutesEdit: TEdit;
    FOnAccepted: TGameSetupAcceptedEvent;
    FRegisteredEngines: TExternalEngineList;
    FStartingFENEdit: TEdit;
    FUpdatingCombos: Boolean;
    FWhitePlayerCombo: TComboBox;
    procedure AddLabelledEdit(AParent: TWinControl; const ACaption: string;
      AEdit: TEdit; var ATop: Integer);
    procedure AddLabelledCombo(AParent: TWinControl; const ACaption: string;
      ACombo: TComboBox; var ATop: Integer);
    procedure CancelClick(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    function CopySelectedEngine(ACombo: TComboBox): TExternalEngineDefinition;
    function FindEngineItemByKey(ACombo: TComboBox; const AEngineKey: string): Integer;
    procedure FillPlayerCombo(ACombo: TComboBox; ASlotIndex: Integer;
      const AExcludeEngineKey: string = '');
    procedure FormShow(Sender: TObject);
    function IsEngineBusy(AEngine: TExternalEngineDefinition): Boolean;
    procedure OkClick(Sender: TObject);
    procedure RefillPlayerCombos(AChangedCombo: TComboBox);
    procedure RestorePlayerSelection(ACombo: TComboBox; APlayer: TPlayerKind;
      const AEngineKey: string);
    function SelectedEngineKey(ACombo: TComboBox): string;
    function SelectedPlayer(ACombo: TComboBox): TPlayerKind;
  public
    constructor Create(AOwner: TComponent); override; overload;
    constructor Create(AOwner:TComponent;AVariant:TGameVariant); reintroduce; overload;
    property Variant:TGameVariant read FVariant;
    destructor Destroy; override;
    procedure ApplyPreferences(const APreferences: TGuiPreferences);
    procedure SetBusyEngineKeys(AKeys: TStrings);
    property OnAccepted: TGameSetupAcceptedEvent read FOnAccepted write FOnAccepted;
  end;

implementation

constructor TGameSetupForm.Create(AOwner:TComponent);
begin Create(AOwner,DefaultGameVariant);end;

constructor TGameSetupForm.Create(AOwner:TComponent;AVariant:TGameVariant);
var
  LButtonPanel, LContentPanel: TPanel;
  LCancelButton, LOkButton: TButton;
  LTop,I: Integer;
begin
  inherited Create(AOwner);
  if AVariant=nil then raise EGamePositionError.Create('Missing dialog game variant');
  FVariant:=AVariant;

  Caption := 'New game';
  Position := poDesigned;
  Width := 560;
  Height := 420;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 380;
  OnShow := @FormShow;
  FBusyEngineKeys := TStringList.Create;
  FBusyEngineKeys.Sorted := True;
  FBusyEngineKeys.Duplicates := dupIgnore;
  FDefaultTimeControl := GameGuiProfileFor(FVariant).DefaultClock;
  FRegisteredEngines := TExternalEngineList.Create;
  LoadExternalEngines(EnginesJsonFileName, FRegisteredEngines);

  LContentPanel := TPanel.Create(Self);
  LContentPanel.Parent := Self;
  LContentPanel.Align := alClient;
  LContentPanel.BevelOuter := bvNone;
  LContentPanel.BorderSpacing.Around := 12;

  LTop := 0;
  if RegisteredGameCount>1 then begin
    Height:=Height+38;FGameCombo:=TComboBox.Create(Self);FGameCombo.Name:='NewGameVariant';
    FGameCombo.Style:=csDropDownList;
    for I:=0 to RegisteredGameCount-1 do begin
      FGameCombo.Items.AddObject(RegisteredGame(I).Name,RegisteredGame(I));
      if RegisteredGame(I)=FVariant then FGameCombo.ItemIndex:=I;
    end;
    FGameCombo.OnChange:=@GameChanged;AddLabelledCombo(LContentPanel,'Game',FGameCombo,LTop);
  end;


  FStartingFENEdit := TEdit.Create(Self);
  FStartingFENEdit.Text := FVariant.DefaultStartingFEN;
  AddLabelledEdit(LContentPanel, 'Starting position (FEN)', FStartingFENEdit, LTop);

  FWhitePlayerCombo := TComboBox.Create(Self);
  FillPlayerCombo(FWhitePlayerCombo, 1);
  FWhitePlayerCombo.ItemIndex := 0;
  FWhitePlayerCombo.OnChange := @ComboChange;
  AddLabelledCombo(LContentPanel, 'White player', FWhitePlayerCombo, LTop);

  FBlackPlayerCombo := TComboBox.Create(Self);
  FillPlayerCombo(FBlackPlayerCombo, 2);
  FBlackPlayerCombo.ItemIndex := 0;
  FBlackPlayerCombo.OnChange := @ComboChange;
  AddLabelledCombo(LContentPanel, 'Black player', FBlackPlayerCombo, LTop);

  FMovesEdit := TEdit.Create(Self);
  FMovesEdit.Text := IntToStr(FDefaultTimeControl.MovesPerPeriod);
  AddLabelledEdit(LContentPanel, 'Moves per period', FMovesEdit, LTop);

  FMinutesEdit := TEdit.Create(Self);
  FMinutesEdit.Text := FormatFloat('0.###',
    FDefaultTimeControl.MinutesPerPeriod);
  AddLabelledEdit(LContentPanel, 'Minutes per period', FMinutesEdit, LTop);

  FIncrementEdit := TEdit.Create(Self);
  FIncrementEdit.Text := FormatFloat('0.###',
    FDefaultTimeControl.IncrementSeconds);
  AddLabelledEdit(LContentPanel, 'Increment seconds', FIncrementEdit, LTop);

  FIncrementModeCombo := TComboBox.Create(Self);
  FIncrementModeCombo.Items.Add('From start');
  FIncrementModeCombo.Items.Add('After move limit');
  FIncrementModeCombo.ItemIndex := 0;
  AddLabelledCombo(LContentPanel, 'Increment mode', FIncrementModeCombo, LTop);

  LButtonPanel := TPanel.Create(Self);
  LButtonPanel.Parent := Self;
  LButtonPanel.Align := alBottom;
  LButtonPanel.Height := 48;
  LButtonPanel.BevelOuter := bvNone;
  LButtonPanel.BorderSpacing.Around := 8;

  LCancelButton := TButton.Create(Self);
  LCancelButton.Parent := LButtonPanel;
  LCancelButton.Align := alRight;
  LCancelButton.Width := 90;
  LCancelButton.Caption := 'Cancel';
  LCancelButton.OnClick := @CancelClick;

  LOkButton := TButton.Create(Self);
  LOkButton.Parent := LButtonPanel;
  LOkButton.Align := alRight;
  LOkButton.Width := 90;
  LOkButton.BorderSpacing.Right := 8;
  LOkButton.Caption := 'OK';
  LOkButton.OnClick := @OkClick;
end;

destructor TGameSetupForm.Destroy;
begin
  FBusyEngineKeys.Free;
  FRegisteredEngines.Free;
  inherited Destroy;
end;

procedure TGameSetupForm.GameChanged(Sender:TObject);
begin
  if (FGameCombo=nil) or (FGameCombo.ItemIndex<0) then Exit;
  FVariant:=TGameVariant(FGameCombo.Items.Objects[FGameCombo.ItemIndex]);
  FStartingFENEdit.Text:=FVariant.DefaultStartingFEN;FDefaultTimeControl:=GameGuiProfileFor(FVariant).DefaultClock;
  FMovesEdit.Text:=IntToStr(FDefaultTimeControl.MovesPerPeriod);
  FMinutesEdit.Text:=FloatToStr(FDefaultTimeControl.MinutesPerPeriod);
  FIncrementEdit.Text:=FloatToStr(FDefaultTimeControl.IncrementSeconds);
  RefillPlayerCombos(nil);
end;

procedure TGameSetupForm.ApplyPreferences(const APreferences: TGuiPreferences);
begin
  FDefaultTimeControl := GameGuiProfileFor(FVariant).DefaultClock;
  if FMinutesEdit <> nil then
    FMinutesEdit.Text := FormatFloat('0.###',
      FDefaultTimeControl.MinutesPerPeriod);
  if FMovesEdit <> nil then
    FMovesEdit.Text := IntToStr(FDefaultTimeControl.MovesPerPeriod);
  if FIncrementEdit <> nil then
    FIncrementEdit.Text := FormatFloat('0.###',
      FDefaultTimeControl.IncrementSeconds);
end;

procedure TGameSetupForm.SetBusyEngineKeys(AKeys: TStrings);
begin
  FBusyEngineKeys.Clear;
  if AKeys <> nil then
    FBusyEngineKeys.AddStrings(AKeys);
end;

procedure TGameSetupForm.AddLabelledEdit(AParent: TWinControl; const ACaption: string;
  AEdit: TEdit; var ATop: Integer);
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := AParent;
  LLabel.SetBounds(0, ATop, AParent.ClientWidth, 20);
  LLabel.Anchors := [akTop, akLeft, akRight];
  LLabel.Height := 20;
  LLabel.Caption := ACaption;
  Inc(ATop, 20);

  AEdit.Parent := AParent;
  AEdit.SetBounds(0, ATop, AParent.ClientWidth, 28);
  AEdit.Anchors := [akTop, akLeft, akRight];
  Inc(ATop, 36);
end;

procedure TGameSetupForm.AddLabelledCombo(AParent: TWinControl; const ACaption: string;
  ACombo: TComboBox; var ATop: Integer);
var
  LLabel: TLabel;
begin
  LLabel := TLabel.Create(Self);
  LLabel.Parent := AParent;
  LLabel.SetBounds(0, ATop, AParent.ClientWidth, 20);
  LLabel.Anchors := [akTop, akLeft, akRight];
  LLabel.Height := 20;
  LLabel.Caption := ACaption;
  Inc(ATop, 20);

  ACombo.Parent := AParent;
  ACombo.SetBounds(0, ATop, AParent.ClientWidth, 28);
  ACombo.Anchors := [akTop, akLeft, akRight];
  ACombo.Style := csDropDownList;
  Inc(ATop, 36);
end;

procedure TGameSetupForm.CancelClick(Sender: TObject);
begin
  Close;
end;

procedure TGameSetupForm.ComboChange(Sender: TObject);
begin
  if FUpdatingCombos then
    Exit;
  if Sender is TComboBox then
    RefillPlayerCombos(TComboBox(Sender));
end;

function TGameSetupForm.CopySelectedEngine(ACombo: TComboBox): TExternalEngineDefinition;
var
  Source: TExternalEngineDefinition;
begin
  Result := nil;
  if (ACombo.ItemIndex < 0) or (ACombo.ItemIndex >= ACombo.Items.Count) then
    Exit;
  Source := TExternalEngineDefinition(ACombo.Items.Objects[ACombo.ItemIndex]);
  if Source = nil then
    Exit;
  Result := TExternalEngineDefinition.Create;
  Result.Assign(Source);
end;

function TGameSetupForm.FindEngineItemByKey(ACombo: TComboBox;
  const AEngineKey: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if AEngineKey = '' then
    Exit;
  for I := 0 to ACombo.Items.Count - 1 do
    if EngineIdentityKey(TExternalEngineDefinition(ACombo.Items.Objects[I])) =
      AEngineKey then
      Exit(I);
end;

procedure TGameSetupForm.FillPlayerCombo(ACombo: TComboBox; ASlotIndex: Integer;
  const AExcludeEngineKey: string);
var
  EngineKey: string;
  I: Integer;
begin
  ACombo.Items.Clear;
  ACombo.Items.AddObject('Human', nil);
  for I := 0 to FRegisteredEngines.Count - 1 do
  begin
    EngineKey := EngineIdentityKey(FRegisteredEngines[I]);
    if (FRegisteredEngines[I].Kind in GameGuiProfileFor(FVariant).EngineKinds) and (not IsEngineBusy(FRegisteredEngines[I])) and
      ((AExcludeEngineKey = '') or (EngineKey <> AExcludeEngineKey)) then
      ACombo.Items.AddObject(EnginePickerDisplayName(FRegisteredEngines[I],
        ASlotIndex), FRegisteredEngines[I]);
  end;
end;

procedure TGameSetupForm.FormShow(Sender: TObject);
var
  BlackKey: string;
  BlackPlayer: TPlayerKind;
  WhiteKey: string;
  WhitePlayer: TPlayerKind;
begin
  FUpdatingCombos := True;
  WhitePlayer := SelectedPlayer(FWhitePlayerCombo);
  BlackPlayer := SelectedPlayer(FBlackPlayerCombo);
  WhiteKey := SelectedEngineKey(FWhitePlayerCombo);
  BlackKey := SelectedEngineKey(FBlackPlayerCombo);
  try
    LoadExternalEngines(EnginesJsonFileName, FRegisteredEngines);
    FillPlayerCombo(FWhitePlayerCombo, 1, BlackKey);
    FillPlayerCombo(FBlackPlayerCombo, 2, WhiteKey);

    RestorePlayerSelection(FWhitePlayerCombo, WhitePlayer, WhiteKey);
    RestorePlayerSelection(FBlackPlayerCombo, BlackPlayer, BlackKey);
  finally
    FUpdatingCombos := False;
  end;
end;

function TGameSetupForm.IsEngineBusy(AEngine: TExternalEngineDefinition): Boolean;
begin
  Result := FBusyEngineKeys.IndexOf(EngineIdentityKey(AEngine)) >= 0;
end;

function TGameSetupForm.SelectedEngineKey(ACombo: TComboBox): string;
begin
  Result := '';
  if (ACombo.ItemIndex < 0) or (ACombo.ItemIndex >= ACombo.Items.Count) then
    Exit;
  Result := EngineIdentityKey(
    TExternalEngineDefinition(ACombo.Items.Objects[ACombo.ItemIndex]));
end;

function TGameSetupForm.SelectedPlayer(ACombo: TComboBox): TPlayerKind;
begin
  if ACombo.ItemIndex = 0 then
    Result := pkHuman
  else
    Result := pkRegistered;
end;

procedure TGameSetupForm.RestorePlayerSelection(ACombo: TComboBox;
  APlayer: TPlayerKind; const AEngineKey: string);
var
  LIndex: Integer;
begin
  case APlayer of
    pkHuman:
      ACombo.ItemIndex := 0;
    pkRegistered:
      begin
        LIndex := FindEngineItemByKey(ACombo, AEngineKey);
        if LIndex >= 0 then
          ACombo.ItemIndex := LIndex
        else
          ACombo.ItemIndex := 0;
      end;
  end;
end;

procedure TGameSetupForm.OkClick(Sender: TObject);
var
  LSetup: TGameSetup;
begin
  LSetup:=Default(TGameSetup);LSetup.Variant:=FVariant;
  try
    try
      LSetup.StartingFEN:=Trim(FStartingFENEdit.Text);
      LSetup.WhitePlayer:=SelectedPlayer(FWhitePlayerCombo); LSetup.BlackPlayer:=SelectedPlayer(FBlackPlayerCombo);
      LSetup.WhiteEngine:=CopySelectedEngine(FWhitePlayerCombo); LSetup.BlackEngine:=CopySelectedEngine(FBlackPlayerCombo);
      if not TryStrToInt(Trim(FMovesEdit.Text),LSetup.TimeControl.MovesPerPeriod) or
        not TryStrToFloat(Trim(FMinutesEdit.Text),LSetup.TimeControl.MinutesPerPeriod) or
        not TryStrToFloat(Trim(FIncrementEdit.Text),LSetup.TimeControl.IncrementSeconds) then
        raise EConvertError.Create('Enter valid numbers for moves, minutes and increment');
      if FIncrementModeCombo.ItemIndex=1 then LSetup.TimeControl.IncrementMode:=cimAfterMoveLimit
      else LSetup.TimeControl.IncrementMode:=cimFromStart;
      ValidateGameSetup(LSetup,FVariant,GameGuiProfileFor(FVariant).EngineKinds);
      if Assigned(FOnAccepted) then FOnAccepted(Self,LSetup);
      Close;
    except on E:Exception do ShowGuiOkDialog(Self,'New game',E.Message); end;
  finally LSetup.WhiteEngine.Free; LSetup.BlackEngine.Free; end;
end;

procedure TGameSetupForm.RefillPlayerCombos(AChangedCombo: TComboBox);
var
  BlackKey: string;
  BlackPlayer: TPlayerKind;
  WhiteKey: string;
  WhitePlayer: TPlayerKind;
begin
  FUpdatingCombos := True;
  try
    WhitePlayer := SelectedPlayer(FWhitePlayerCombo);
    BlackPlayer := SelectedPlayer(FBlackPlayerCombo);
    WhiteKey := SelectedEngineKey(FWhitePlayerCombo);
    BlackKey := SelectedEngineKey(FBlackPlayerCombo);

    if AChangedCombo = FWhitePlayerCombo then
    begin
      FillPlayerCombo(FBlackPlayerCombo, 2, WhiteKey);
      RestorePlayerSelection(FBlackPlayerCombo, BlackPlayer, BlackKey);
    end
    else if AChangedCombo = FBlackPlayerCombo then
    begin
      FillPlayerCombo(FWhitePlayerCombo, 1, BlackKey);
      RestorePlayerSelection(FWhitePlayerCombo, WhitePlayer, WhiteKey);
    end;
  finally
    FUpdatingCombos := False;
  end;
end;

end.
