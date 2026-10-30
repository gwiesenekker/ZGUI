unit uEngineEditForm;

{$mode objfpc}{$H+}

interface

uses
  uGamePosition, uGuiLayout, Classes, Controls, Dialogs, ExtCtrls, Forms, Graphics, Grids, StdCtrls,
  SysUtils, uDraughtsDxpTestConnection, uEngineParamsJson, uEngineRegistry,
  uPlatformProcess, SyncObjs, uChessUciEngine, uChessUciProtocol, uProcessEngineWorker, uThreadMessageQueue;

type
  TEngineAcceptedEvent = procedure(Sender: TObject;
    AEngine: TExternalEngineDefinition; var AAccepted: Boolean) of object;

  TEngineEditForm = class(TGuiLayoutForm)
  private
    FVariant:TGameVariant;
    FUciEngine: TUciEngine;
    FUciInit,FUciButton: TProcessEngineCommand;
    FUciLogs: TThreadMessageQueue;
    FIdLabel,FArgsLabel: TLabel;
    FAcceptedEngine: TExternalEngineDefinition;
    FAcceptButton: TButton;
    FAllowHubIdAutoUpdate: Boolean;
    FBrowseDialog: TOpenDialog;
    FAcceptingClose: Boolean;
    FCapturedParams: TEngineParamArray;
    FDirectoryDialog: TSelectDirectoryDialog;
    FDxpArgsEdit: TEdit;
    FDxpThread: TDxpTestConnectionThread;
    FDxpHostEdit: TEdit;
    FDxpIdEdit: TEdit;
    FDxpPortEdit: TEdit;
    FDxpRoleCombo: TComboBox;
    FExeEdit: TEdit;
    FHubArgsEdit: TEdit;
    FHubIdEdit: TEdit;
    FIniBrowseDialog: TOpenDialog;
    FIniContentMemo: TMemo;
    FIniPathEdit: TEdit;
    FInitMemo: TMemo;
    FKindCombo: TComboBox;
    FOnAccepted: TEngineAcceptedEvent;
    FParamsGrid: TStringGrid;
    FInlineParamCombo: TComboBox;
    FProcess: TPlatformProcess;
    FProcessPollTimer: TTimer;
    FSelectedParamRow: Integer;
    FStdoutMemo: TMemo;
    FTextBuffer: string;
    procedure UciLog(Sender: TObject; const AText: string);
    procedure FinishUciDiscovery;
    procedure ParamDoubleClick(Sender: TObject);
    function IsComboParamRow(Row: Integer): Boolean;
    procedure AcceptClick(Sender: TObject);
    procedure ButtonPanelResize(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CaptureHubLine(const ALine: string);
    procedure CloseRunningEngine;
    function CurrentEngineDefinition: TExternalEngineDefinition;
    procedure DxpLog(Sender: TObject; const AText: string);
    function FormatHubId(const AName, AVersion: string): string;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure HideInlineParamCombo(Sender: TObject);
    procedure InlineParamComboSelect(Sender: TObject);
    procedure IniPathClick(Sender: TObject);
    function IsBoolParamRow(ARow: Integer): Boolean;
    function IsDirParamRow(ARow: Integer): Boolean;
    function IsScorePerspectiveParamRow(ARow: Integer): Boolean;
    procedure KindChanged(Sender: TObject);
    procedure LaunchClick(Sender: TObject);
    procedure LoadParamsForExecutable;
    procedure LoadParamsGrid;
    procedure Log(const AText: string);
    procedure ParamsGridMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ParamsGridSelectCell(Sender: TObject; aCol, aRow: Integer;
      var CanSelect: Boolean);
    procedure PrepareInlineParamComboForRow(ARow: Integer);
    procedure ProcessData(Sender: TObject; const AText: string);
    procedure ProcessPollTimer(Sender: TObject);
    procedure ReadForMs(AWaitMs: Integer);
    procedure SendHubParamsToProcess;
    procedure StopProcessFor(AEngine: TExternalEngineDefinition);
    procedure StoreArgumentParams;
    procedure StoreIniParams;
    procedure StoreParamsGrid;
    procedure UpdateFieldsFromParams;
    procedure UpdateKindFields;
  public
    constructor Create(AOwner:TComponent;AVariant:TGameVariant); reintroduce;
    property Variant:TGameVariant read FVariant;
    destructor Destroy; override;
    procedure LoadEngine(AEngine: TExternalEngineDefinition);
    procedure RefreshLayout; override;
    property OnAccepted: TEngineAcceptedEvent read FOnAccepted write FOnAccepted;
  end;

implementation

uses
  LCLType, uGuiDialogs, uGameGuiProfile;
type TUciEditorLog=class(TThreadMessage)
  Text: string;
end;

const
  HubArgsHint =
    'Command-line arguments passed to the engine, such as hub.';
  DxpArgsHint =
    'Command-line arguments passed to the engine, such as dxp.' +
    LineEnding +
    'You can use {ip}/{host} and {port} macros. These will be expanded into the configured host and port settings.';
  EngineIniHint =
    'You can use {ip}/{host} and {port} macros.' +
    LineEnding +
    'These will be expanded into the configured host and port settings.';

constructor TEngineEditForm.Create(AOwner:TComponent;AVariant:TGameVariant);
var
  LBrowseButton: TButton;
  LButtonPanel: TPanel;
  LCancelButton: TButton;
  LFieldsPanel: TPanel;
  LInitialEngine: TExternalEngineDefinition;
  LLabel: TLabel;
  LLaunchButton: TButton;
  LLeftPanel: TPanel;
  LParamsLabel: TLabel;
  LParamsPanel: TPanel;
  LParamsSplitter: TSplitter;
  LRightPanel: TPanel;
  LSplitter: TSplitter;
  LTop: Integer;
  Labels:array[0..7] of TLabel;IniLabel:TLabel;ExeRow,PortRow,Fields:TPanel;
begin
  inherited Create(AOwner);
  if AVariant=nil then raise EGamePositionError.Create('Missing dialog game variant');
  FVariant:=AVariant;

  Caption := 'Add engine';
  Position := poDesigned;
  Width := 860;
  Height := 620;
  Constraints.MinWidth := 700;
  Constraints.MinHeight := 480;
  OnClose := @FormClose;

  FUciLogs:=TThreadMessageQueue.Create;
  FProcess := TPlatformProcess.Create;
  FProcess.OnData := @ProcessData;
  FProcessPollTimer := TTimer.Create(Self);
  FProcessPollTimer.Enabled := False;
  FProcessPollTimer.Interval := 100;
  FProcessPollTimer.OnTimer := @ProcessPollTimer;
  FAcceptingClose := False;
  FAllowHubIdAutoUpdate := False;
  FSelectedParamRow := 0;
  FBrowseDialog := TOpenDialog.Create(Self);
  FBrowseDialog.Title := 'Select engine executable';
  {$IFDEF MSWINDOWS}
  FBrowseDialog.Filter := 'Executables (*.exe)|*.exe|All files (*.*)|*.*';
  FBrowseDialog.FilterIndex := 1;
  {$ELSE}
  FBrowseDialog.Filter := 'All files (*)|*';
  FBrowseDialog.FilterIndex := 1;
  {$ENDIF}
  FIniBrowseDialog := TOpenDialog.Create(Self);
  FIniBrowseDialog.Title := 'Select engine INI/config file';
  FIniBrowseDialog.Filter := 'INI files (*.ini)|*.ini|All files (*.*)|*.*';
  FIniBrowseDialog.FilterIndex := 1;
  FDirectoryDialog := TSelectDirectoryDialog.Create(Self);
  FDirectoryDialog.Title := 'Select parameter directory';

  LButtonPanel := TPanel.Create(Self);
  LButtonPanel.Parent := Self;
  LButtonPanel.Align := alBottom;
  LButtonPanel.Height := 46;
  LButtonPanel.BevelOuter := bvNone;
  LButtonPanel.BorderSpacing.Around := 6;
  LButtonPanel.OnResize := @ButtonPanelResize;

  LLaunchButton := TButton.Create(Self);
  LLaunchButton.Parent := LButtonPanel;
  LLaunchButton.SetBounds(0, 6, 130, 34);
  LLaunchButton.Anchors := [akLeft, akTop];
  LLaunchButton.Caption := 'Launch engine';
  LLaunchButton.OnClick := @LaunchClick;

  LCancelButton := TButton.Create(Self);
  LCancelButton.Parent := LButtonPanel;
  LCancelButton.SetBounds(LButtonPanel.ClientWidth - 90, 6, 90, 34);
  LCancelButton.Anchors := [akRight, akTop];
  LCancelButton.Caption := 'Cancel';
  LCancelButton.OnClick := @CancelClick;

  FAcceptButton := TButton.Create(Self);
  FAcceptButton.Parent := LButtonPanel;
  FAcceptButton.SetBounds((LButtonPanel.ClientWidth - 170) div 2, 6, 170, 34);
  FAcceptButton.Anchors := [akTop];
  FAcceptButton.Caption := 'Launched correctly';
  FAcceptButton.OnClick := @AcceptClick;

  LLeftPanel := TPanel.Create(Self);
  LLeftPanel.Parent := Self;
  LLeftPanel.Align := alLeft;
  LLeftPanel.Width := 360;
  LLeftPanel.Constraints.MinWidth := 320;
  LLeftPanel.BevelOuter := bvNone;
  LLeftPanel.BorderSpacing.Around := 8;

  LSplitter := TSplitter.Create(Self);
  LSplitter.Parent := Self;
  LSplitter.Align := alLeft;
  LSplitter.Width := 8;
  LSplitter.ResizeAnchor := akLeft;

  LRightPanel := TPanel.Create(Self);
  LRightPanel.Parent := Self;
  LRightPanel.Align := alClient;
  LRightPanel.BevelOuter := bvNone;
  LRightPanel.BorderSpacing.Around := 8;

  LFieldsPanel := LLeftPanel;
  LTop := 0;

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Executable';Labels[0]:=LLabel;
  LLabel.Layout := tlCenter;

  LBrowseButton := TButton.Create(Self);
  LBrowseButton.Parent := LFieldsPanel;
  LBrowseButton.SetBounds(LFieldsPanel.Width - 82, LTop, 82, 28);
  LBrowseButton.Anchors := [akTop, akRight];
  LBrowseButton.Caption := 'Browse...';
  LBrowseButton.OnClick := @BrowseClick;

  FExeEdit := TEdit.Create(Self);
  FExeEdit.Parent := LFieldsPanel;
  FExeEdit.SetBounds(86, LTop, LFieldsPanel.Width - 176, 28);
  FExeEdit.Anchors := [akTop, akLeft, akRight];
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Type';Labels[1]:=LLabel;
  LLabel.Layout := tlCenter;

  FKindCombo := TComboBox.Create(Self);
  FKindCombo.Parent := LFieldsPanel;
  FKindCombo.SetBounds(86, LTop, 120, 28);
  FKindCombo.Style := csDropDownList;
  FKindCombo.Items.Add('hub');
  FKindCombo.Items.Add('DXP');
  FKindCombo.Items.Add('UCI');
  FKindCombo.ItemIndex := 0;
  FKindCombo.OnChange := @KindChanged;
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Hub id';Labels[2]:=LLabel; FIdLabel:=LLabel;
  LLabel.Layout := tlCenter;

  FHubIdEdit := TEdit.Create(Self);
  FHubIdEdit.Parent := LFieldsPanel;
  FHubIdEdit.SetBounds(86, LTop, LFieldsPanel.Width - 86, 28);
  FHubIdEdit.Anchors := [akTop, akLeft, akRight];
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Hub args';Labels[3]:=LLabel; FArgsLabel:=LLabel;
  LLabel.Layout := tlCenter;

  FHubArgsEdit := TEdit.Create(Self);
  FHubArgsEdit.Parent := LFieldsPanel;
  FHubArgsEdit.SetBounds(86, LTop, LFieldsPanel.Width - 86, 28);
  FHubArgsEdit.Anchors := [akTop, akLeft, akRight];
  FHubArgsEdit.Hint := HubArgsHint;
  FHubArgsEdit.ShowHint := True;
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'DXP id';Labels[4]:=LLabel;
  LLabel.Layout := tlCenter;

  FDxpIdEdit := TEdit.Create(Self);
  FDxpIdEdit.Parent := LFieldsPanel;
  FDxpIdEdit.SetBounds(86, LTop, LFieldsPanel.Width - 86, 28);
  FDxpIdEdit.Anchors := [akTop, akLeft, akRight];
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Host';Labels[5]:=LLabel;
  LLabel.Layout := tlCenter;

  FDxpHostEdit := TEdit.Create(Self);
  FDxpHostEdit.Parent := LFieldsPanel;
  FDxpHostEdit.SetBounds(86, LTop, LFieldsPanel.Width - 86, 28);
  FDxpHostEdit.Anchors := [akTop, akLeft, akRight];
  FDxpHostEdit.Text := '127.0.0.1';
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'Port';Labels[6]:=LLabel;
  LLabel.Layout := tlCenter;

  FDxpPortEdit := TEdit.Create(Self);
  FDxpPortEdit.Parent := LFieldsPanel;
  FDxpPortEdit.SetBounds(86, LTop, 90, 28);
  FDxpPortEdit.Text := '27531';

  FDxpRoleCombo := TComboBox.Create(Self);
  FDxpRoleCombo.Parent := LFieldsPanel;
  FDxpRoleCombo.SetBounds(186, LTop, LFieldsPanel.Width - 186, 28);
  FDxpRoleCombo.Anchors := [akTop, akLeft, akRight];
  FDxpRoleCombo.Style := csDropDownList;
  FDxpRoleCombo.Items.Add('listen');
  FDxpRoleCombo.Items.Add('connect');
  FDxpRoleCombo.ItemIndex := 0;
  Inc(LTop, 36);

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, 80, 22);
  LLabel.Caption := 'DXP args';Labels[7]:=LLabel;
  LLabel.Layout := tlCenter;

  FDxpArgsEdit := TEdit.Create(Self);
  FDxpArgsEdit.Parent := LFieldsPanel;
  FDxpArgsEdit.SetBounds(86, LTop, LFieldsPanel.Width - 86, 28);
  FDxpArgsEdit.Anchors := [akTop, akLeft, akRight];
  FDxpArgsEdit.Hint := DxpArgsHint;
  FDxpArgsEdit.ShowHint := True;
  Inc(LTop, 38);

  FInitMemo := TMemo.Create(Self);
  FInitMemo.Parent := Self;
  FInitMemo.Visible := False;
  FInitMemo.Text := 'init';

  LLabel := TLabel.Create(Self);
  LLabel.Parent := LFieldsPanel;
  LLabel.SetBounds(0, LTop, LFieldsPanel.Width, 22);
  LLabel.Anchors := [akTop, akLeft, akRight];
  LLabel.Caption := 'INI/config file (click path to browse)';IniLabel:=LLabel;
  LLabel.Layout := tlCenter;
  Inc(LTop, 24);

  FIniPathEdit := TEdit.Create(Self);
  FIniPathEdit.Parent := LFieldsPanel;
  FIniPathEdit.SetBounds(0, LTop, LFieldsPanel.Width, 28);
  FIniPathEdit.Anchors := [akTop, akLeft, akRight];
  FIniPathEdit.ReadOnly := True;
  FIniPathEdit.Hint := EngineIniHint;
  FIniPathEdit.ShowHint := True;
  FIniPathEdit.OnClick := @IniPathClick;
  Inc(LTop, 32);

  FIniContentMemo := TMemo.Create(Self);
  FIniContentMemo.Parent := LFieldsPanel;
  FIniContentMemo.SetBounds(0, LTop, LFieldsPanel.Width,
    LFieldsPanel.Height - LTop);
  FIniContentMemo.Anchors := [akTop, akLeft, akRight, akBottom];
  FIniContentMemo.AnchorSideBottom.Control := LFieldsPanel;
  FIniContentMemo.AnchorSideBottom.Side := asrBottom;
  FIniContentMemo.ScrollBars := ssAutoBoth;
  FIniContentMemo.WordWrap := False;
  FIniContentMemo.Hint := EngineIniHint;
  FIniContentMemo.ShowHint := True;

  FStdoutMemo := TMemo.Create(Self);
  FStdoutMemo.Parent := LRightPanel;
  FStdoutMemo.Align := alClient;
  FStdoutMemo.ReadOnly := True;
  FStdoutMemo.ScrollBars := ssAutoBoth;
  FStdoutMemo.WordWrap := False;

  LParamsPanel := TPanel.Create(Self);
  LParamsPanel.Parent := LRightPanel;
  LParamsPanel.Align := alBottom;
  LParamsPanel.Height := 230;
  LParamsPanel.Constraints.MinHeight := 140;
  LParamsPanel.BevelOuter := bvNone;

  LParamsSplitter := TSplitter.Create(Self);
  LParamsSplitter.Parent := LRightPanel;
  LParamsSplitter.Align := alBottom;
  LParamsSplitter.Height := 8;
  LParamsSplitter.ResizeAnchor := akBottom;

  LParamsLabel := TLabel.Create(Self);
  LParamsLabel.Parent := LParamsPanel;
  LParamsLabel.Align := alTop;
  LParamsLabel.Height := 22;
  LParamsLabel.Caption := 'Parameters';
  LParamsLabel.Layout := tlCenter;

  FParamsGrid := TStringGrid.Create(Self);
  FParamsGrid.Parent := LParamsPanel;
  FParamsGrid.Align := alClient;
  FParamsGrid.ColCount := 3;
  FParamsGrid.FixedRows := 1;
  FParamsGrid.Options := FParamsGrid.Options + [goEditing, goColSizing];
  FParamsGrid.Cells[0, 0] := 'name';
  // The name column remains fixed; only the value column absorbs spare width.
  FParamsGrid.Columns.Add.Title.Caption := 'type';
  FParamsGrid.Columns[0].SizePriority := 0;
  FParamsGrid.Columns.Add.Title.Caption := 'value';
  FParamsGrid.Columns[1].SizePriority := 1;
  FParamsGrid.AutoFillColumns := True;

  FInlineParamCombo := TComboBox.Create(Self);
  FInlineParamCombo.Parent := FParamsGrid;
  FInlineParamCombo.Visible := False;
  FInlineParamCombo.Style := csDropDownList;
  FInlineParamCombo.OnSelect := @InlineParamComboSelect;
  FInlineParamCombo.OnCloseUp := @HideInlineParamCombo;
  FInlineParamCombo.OnExit := @HideInlineParamCombo;

  FParamsGrid.OnDblClick := @ParamDoubleClick;
  FParamsGrid.OnMouseUp := @ParamsGridMouseUp;
  FParamsGrid.OnSelectCell := @ParamsGridSelectCell;

  LInitialEngine := CurrentEngineDefinition;
  try
    SeedDefaultGuiParams(FCapturedParams, LInitialEngine);
  finally
    LInitialEngine.Free;
  end;
  ExeRow:=LayoutRow(LLeftPanel,[FExeEdit,LBrowseButton],0);
  PortRow:=LayoutRow(LLeftPanel,[FDxpPortEdit,FDxpRoleCombo],0);
  Fields:=LayoutFields(LLeftPanel,[Labels[0],ExeRow,Labels[1],FKindCombo,
    Labels[2],FHubIdEdit,Labels[3],FHubArgsEdit,Labels[4],FDxpIdEdit,
    Labels[5],FDxpHostEdit,Labels[6],PortRow,Labels[7],FDxpArgsEdit]);
  Fields.Top:=0;IniLabel.Align:=alTop;IniLabel.AutoSize:=True;
  FIniPathEdit.Align:=alTop;FIniContentMemo.Align:=alClient;
  // Keep an editable viewport below the measured fixed rows.
  LLeftPanel.Constraints.MinWidth:=0;
  LoadParamsGrid;
  UpdateKindFields;
  EnableAutoLayout;
end;

destructor TEngineEditForm.Destroy;
begin
  CloseRunningEngine;
  FUciLogs.Free;
  FAcceptedEngine.Free;
  FProcess.Free;
  inherited Destroy;
end;

procedure TEngineEditForm.LoadEngine(AEngine: TExternalEngineDefinition);
var
  Engine: TExternalEngineDefinition;
begin
  CloseRunningEngine;
  FStdoutMemo.Clear;
  FTextBuffer := '';
  SetLength(FCapturedParams, 0);

  if AEngine = nil then
  begin
    Caption := 'Add engine';
    FExeEdit.Text := '';
    FKindCombo.ItemIndex := 0;
    FHubIdEdit.Text := '';
    FDxpIdEdit.Text := '';
    FDxpHostEdit.Text := '127.0.0.1';
    FDxpPortEdit.Text := '27531';
    FDxpRoleCombo.ItemIndex := 0;
    FHubArgsEdit.Text := '';
    FDxpArgsEdit.Text := '';
    FInitMemo.Text := 'init';
    if GameGuiProfileFor(FVariant).EngineKinds=[eekUci] then begin
      FKindCombo.ItemIndex:=2;FInitMemo.Clear;
    end;
  end
  else
  begin
    Caption := 'Edit engine';
    FExeEdit.Text := AEngine.ExePath;
    if AEngine.Kind=eekUci then FKindCombo.ItemIndex:=2
    else if AEngine.Kind = eekDxp then
      FKindCombo.ItemIndex := 1
    else
      FKindCombo.ItemIndex := 0;
    if AEngine.Kind=eekUci then FHubIdEdit.Text:=AEngine.UciId
    else FHubIdEdit.Text := AEngine.HubId;
    FDxpIdEdit.Text := AEngine.DxpId;
    FHubArgsEdit.Text := '';
    FDxpArgsEdit.Text := '';
    if AEngine.Kind = eekDxp then
      FDxpArgsEdit.Text := AEngine.Arguments
    else
      FHubArgsEdit.Text := AEngine.Arguments;
    FInitMemo.Text := AEngine.InitText;
    if AEngine.Kind=eekUci then begin
      FIniPathEdit.Text:=AEngine.IniFileName; FIniContentMemo.Text:=AEngine.IniContent;
    end;
    FDXpHostEdit.Text := AEngine.DxpHost;
    FDxpPortEdit.Text := IntToStr(AEngine.DxpPort);
    if AEngine.DxpRole = derConnect then
      FDxpRoleCombo.ItemIndex := 1
    else
      FDxpRoleCombo.ItemIndex := 0;
  end;

  Engine := CurrentEngineDefinition;
  try
    SeedDefaultGuiParams(FCapturedParams, Engine);
  finally
    Engine.Free;
  end;
  LoadParamsForExecutable;
  LoadParamsGrid;
  UpdateKindFields;
end;

procedure TEngineEditForm.AcceptClick(Sender: TObject);
var
  Accepted: Boolean;
  I: Integer;
begin
  StoreParamsGrid;
  StoreArgumentParams;
  FreeAndNil(FAcceptedEngine);
  FAcceptedEngine := CurrentEngineDefinition;
  if FAcceptedEngine.Kind in [eekHub,eekUci] then
    try
      if FAcceptedEngine.Kind=eekUci then begin
        for I:=0 to High(FCapturedParams) do
          if Copy(LowerCase(FCapturedParams[I].Name),1,4)<>'gui-' then ValidateUciValue(FCapturedParams[I],FCapturedParams[I].Value);
      end else ValidateHubParams(FCapturedParams);
    except
      on E: EConvertError do
      begin
        Log('[cannot save: ' + E.Message + ']');
        ShowGuiOkDialog(Self, 'Invalid engine parameter', E.Message);
        Exit;
      end;
    end;
  Accepted := True;
  if Assigned(FOnAccepted) then
    FOnAccepted(Self, FAcceptedEngine, Accepted);
  if not Accepted then
    Exit;

  SaveEngineDefinitionParams(FAcceptedEngine, FCapturedParams);
  Log('[saved parameters to ' + EngineParamsFileName(FAcceptedEngine.ExePath) + ']');
  FAcceptingClose := True;
  CloseRunningEngine;
  Close;
  FAcceptingClose := False;
end;

procedure TEngineEditForm.ButtonPanelResize(Sender: TObject);
begin
  if FAcceptButton <> nil then
  begin
    FAcceptButton.Left := (TWinControl(Sender).ClientWidth -
      FAcceptButton.Width) div 2;
    if FAcceptButton.Left < 0 then
      FAcceptButton.Left := 0;
    FAcceptButton.Top := (TWinControl(Sender).ClientHeight -
      FAcceptButton.Height) div 2;
    if FAcceptButton.Top < 0 then
      FAcceptButton.Top := 0;
  end;
end;

procedure TEngineEditForm.BrowseClick(Sender: TObject);
begin
  if FBrowseDialog.Execute then
  begin
    FExeEdit.Text := FBrowseDialog.FileName;
    LoadParamsForExecutable;
    LoadParamsGrid;
    UpdateKindFields;
  end;
end;

procedure TEngineEditForm.CancelClick(Sender: TObject);
begin
  Close;
end;

procedure TEngineEditForm.CaptureHubLine(const ALine: string);
var
  LowerLine: string;
  HubIdText: string;
  NameText: string;
  TypeText: string;
  ValueText: string;
  VersionText: string;
begin
  LowerLine := LowerCase(Trim(ALine));
  if Copy(LowerLine, 1, 6) = 'param ' then
  begin
    NameText := ExtractHubArgument(ALine, 'name');
    TypeText := ExtractHubArgument(ALine, 'type');
    ValueText := ExtractHubArgument(ALine, 'value');
    if ValueText = '' then
      ValueText := ExtractHubArgument(ALine, 'default');
    AddOrUpdateParam(FCapturedParams, NameText, TypeText, ValueText, True);
    LoadParamsGrid;
  end
  else if (Copy(LowerLine, 1, 3) = 'id ') or
    (Copy(LowerLine, 1, 3) = 'id=') then
  begin
    NameText := ExtractHubArgument(ALine, 'name');
    VersionText := ExtractHubArgument(ALine, 'version');
    if (NameText = '') and (Copy(LowerLine, 1, 3) = 'id=') then
      NameText := Trim(Copy(ALine, 4, Length(ALine)));
    if (NameText = '') and (Copy(LowerLine, 1, 3) = 'id ') then
      NameText := Trim(Copy(ALine, 4, Length(ALine)));
    if (Length(NameText) >= 2) and (NameText[1] = '"') and
      (NameText[Length(NameText)] = '"') then
      NameText := Copy(NameText, 2, Length(NameText) - 2);
    HubIdText := FormatHubId(NameText, VersionText);
    if HubIdText <> '' then
      Log('[engine reports Hub id: ' + HubIdText + ']');
  end;
end;

procedure TEngineEditForm.CloseRunningEngine;
begin
  if FProcessPollTimer <> nil then
    FProcessPollTimer.Enabled := False;

  if FUciEngine<>nil then begin
    FUciEngine.RequestStop;
    FUciEngine.Free; FUciEngine:=nil;
    FreeAndNil(FUciInit); FreeAndNil(FUciButton);
    FUciLogs.Clear;
  end;

  if FDxpThread <> nil then
  begin
    FDxpThread.StopConnection;
    FDxpThread.WaitFor;
    FreeAndNil(FDxpThread);
  end;

  if FProcess = nil then
    Exit;
  if FKindCombo.ItemIndex = 0 then
    FProcess.RequestQuit('quit', 800);
  if FProcess.IsRunning then
  begin
    Log('[process did not stop cleanly; terminating]');
    FProcess.Terminate(1000);
  end;
  FProcess.Close;
end;

function TEngineEditForm.CurrentEngineDefinition: TExternalEngineDefinition;
begin
  Result := TExternalEngineDefinition.Create;
  Result.ExePath := Trim(FExeEdit.Text);
  Result.ExecutableName := ExtractFileName(Result.ExePath);
  if FKindCombo.ItemIndex=2 then Result.Kind:=eekUci
  else if FKindCombo.ItemIndex = 1 then
    Result.Kind := eekDxp
  else
    Result.Kind := eekHub;
  if Result.Kind=eekUci then Result.UciId:=Trim(FHubIdEdit.Text)
  else Result.HubId := Trim(FHubIdEdit.Text);
  Result.DxpId := Trim(FDxpIdEdit.Text);
  Result.DxpHost := Trim(FDxpHostEdit.Text);
  if Result.DxpHost = '' then
    Result.DxpHost := '127.0.0.1';
  Result.DxpPort := StrToIntDef(Trim(FDxpPortEdit.Text), 27531);
  if FDxpRoleCombo.ItemIndex = 1 then
    Result.DxpRole := derConnect
  else
    Result.DxpRole := derListen;
  if Result.Kind = eekDxp then
    Result.Arguments := EngineParamValue(FCapturedParams,
      EngineLaunchArgumentParamName(Result.Kind), Trim(FDxpArgsEdit.Text))
  else
    Result.Arguments := EngineParamValue(FCapturedParams,
      EngineLaunchArgumentParamName(Result.Kind), Trim(FHubArgsEdit.Text));
  Result.IniFileName := Trim(FIniPathEdit.Text);
  Result.IniContent := FIniContentMemo.Lines.Text;
  Result.InitText := FInitMemo.Text;
  Result.NormalizeIds;
end;

procedure TEngineEditForm.DxpLog(Sender: TObject; const AText: string);
begin
  Log(AText);
end;

function TEngineEditForm.FormatHubId(const AName, AVersion: string): string;
begin
  Result := Trim(AName);
  if (Result <> '') and (Trim(AVersion) <> '') then
    Result := Result + '_' + Trim(AVersion);
end;

procedure TEngineEditForm.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  if not FAcceptingClose then
    CloseRunningEngine;
end;

procedure TEngineEditForm.KindChanged(Sender: TObject);
var
  Engine: TExternalEngineDefinition;
begin
  CloseRunningEngine;
  StoreParamsGrid;
  if (FKindCombo.ItemIndex=2) and (Trim(FInitMemo.Text)='init') then FInitMemo.Clear;
  StoreArgumentParams;
  if FKindCombo.ItemIndex=2 then LoadParamsForExecutable;
  Engine := CurrentEngineDefinition;
  try
    SeedDefaultGuiParams(FCapturedParams, Engine);
  finally
    Engine.Free;
  end;
  UpdateFieldsFromParams;
  LoadParamsGrid;
  UpdateKindFields;
end;

procedure TEngineEditForm.HideInlineParamCombo(Sender: TObject);
begin
  FInlineParamCombo.Visible := False;
end;

procedure TEngineEditForm.InlineParamComboSelect(Sender: TObject);
begin
  if FInlineParamCombo.Visible and
    (FSelectedParamRow > 0) and
    (FSelectedParamRow < FParamsGrid.RowCount) and
    (IsBoolParamRow(FSelectedParamRow) or
    IsScorePerspectiveParamRow(FSelectedParamRow)) and
    (FInlineParamCombo.ItemIndex >= 0) then
    FParamsGrid.Cells[2, FSelectedParamRow] := FInlineParamCombo.Text;
end;

procedure TEngineEditForm.IniPathClick(Sender: TObject);
var
  InitialPath: string;
  Lines: TStringList;
begin
  InitialPath := Trim(FIniPathEdit.Text);
  if InitialPath = '' then
    InitialPath := Trim(FExeEdit.Text);
  if InitialPath <> '' then
    FIniBrowseDialog.InitialDir := ExtractFilePath(InitialPath);
  if FIniBrowseDialog.Execute then
  begin
    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(FIniBrowseDialog.FileName);
        FIniPathEdit.Text := FIniBrowseDialog.FileName;
        FIniContentMemo.Lines.Assign(Lines);
      except
        on E: Exception do
          Log('[could not load INI/config file: ' + E.Message + ']');
      end;
    finally
      Lines.Free;
    end;
  end;
end;

function TEngineEditForm.IsBoolParamRow(ARow: Integer): Boolean;
begin
  Result := (FParamsGrid <> nil) and (ARow > 0) and
    (ARow < FParamsGrid.RowCount) and
    (SameText(FParamsGrid.Cells[1, ARow], 'bool') or SameText(FParamsGrid.Cells[1, ARow], 'check'));
end;

function TEngineEditForm.IsDirParamRow(ARow: Integer): Boolean;
var
  ParamName: string;
begin
  Result := False;
  if (FParamsGrid = nil) or (ARow <= 0) or
    (ARow >= FParamsGrid.RowCount) then
    Exit;

  ParamName := LowerCase(FParamsGrid.Cells[0, ARow]);
  Result := (Pos('dir', ParamName) > 0) or
    (Copy(ParamName, Length(ParamName) - 3, 4) = '-dir') or
    (Copy(ParamName, Length(ParamName) - 4, 5) = '-path');
end;

function TEngineEditForm.IsScorePerspectiveParamRow(ARow: Integer): Boolean;
begin
  Result := (FParamsGrid <> nil) and (ARow > 0) and
    (ARow < FParamsGrid.RowCount) and
    SameText(FParamsGrid.Cells[0, ARow], 'gui-score-perspective');
end;

procedure TEngineEditForm.LaunchClick(Sender: TObject);
var
  Args: TStringList;
  Engine: TExternalEngineDefinition;
  I: Integer;
  InitLines: TStringList;
  LaunchArguments: string;
begin
  Args := TStringList.Create;
  InitLines := TStringList.Create;
  StoreParamsGrid;
  StoreArgumentParams;
  Engine := CurrentEngineDefinition;
  try
    FStdoutMemo.Clear;
    FTextBuffer := '';
    FAllowHubIdAutoUpdate := False;
    CloseRunningEngine;
    if Engine.Kind=eekUci then begin
      FUciEngine:=TUciEngine.Create(Engine);
      FUciEngine.ConfigureOptions(FCapturedParams);
      FUciEngine.OnLog:=@UciLog;
      FUciInit:=FUciEngine.BeginInitialize;
      FProcessPollTimer.Enabled:=True;
      Exit;
    end;
    StopProcessFor(Engine);

    if Engine.ExePath = '' then
    begin
      Log('[no executable selected]');
      Exit;
    end;
    if not FileExists(Engine.ExePath) then
    begin
      Log('[executable does not exist: ' + Engine.ExePath + ']');
      Exit;
    end;
    try
      WriteEngineIniFile(Engine.IniFileName, Engine.IniContent, Engine);
      if Trim(Engine.IniFileName) <> '' then
        Log('[wrote expanded INI/config file: ' + Engine.IniFileName + ']');
    except
      on E: Exception do
      begin
        Log('[could not write INI/config file: ' + E.Message + ']');
        Exit;
      end;
    end;

    LaunchArguments := EngineParamValue(FCapturedParams,
      EngineLaunchArgumentParamName(Engine.Kind), Engine.Arguments);
    SplitLaunchArguments(ExpandEnginePlaceholders(LaunchArguments, Engine), Args);
    Log('[launching ' + Engine.ExePath + ']');
    if Args.Count > 0 then
      Log('[arguments: ' + Args.DelimitedText + ']');
    FProcess.Start(Engine.ExePath, Args, ExtractFilePath(Engine.ExePath));
    FProcessPollTimer.Enabled := True;
    ReadForMs(250);

    if Engine.Kind = eekHub then
    begin
      Log('> hub');
      FProcess.WriteLine('hub');
      ReadForMs(1000);

      SendHubParamsToProcess;

      InitLines.Text := ExpandEnginePlaceholders(Engine.InitText, Engine);
      for I := 0 to InitLines.Count - 1 do
        if Trim(InitLines[I]) <> '' then
        begin
          Log('> ' + InitLines[I]);
          FProcess.WriteLine(InitLines[I]);
        end;
      ReadForMs(2500);
      if Trim(FHubIdEdit.Text) = '' then
        FHubIdEdit.Text := ExtractFileName(Engine.ExePath);
      FAllowHubIdAutoUpdate := False;
      Log('[hub launch test finished; verify ready/parameter lines above]');
    end
    else
    begin
      if Engine.DxpRole = derListen then
        Log('[DXP configured as listener on ' + Engine.DxpHost + ':' +
          IntToStr(Engine.DxpPort) + ']')
      else
        Log('[DXP configured to connect to ' + Engine.DxpHost + ':' +
          IntToStr(Engine.DxpPort) + ']');
      FreeAndNil(FDxpThread);
      FDxpThread := TDxpTestConnectionThread.Create(Engine.DxpHost,
        Engine.DxpPort, Engine.DxpRole, @DxpLog,
        EngineParamValue(FCapturedParams, 'gui-dxp-peer-ip', ''));
      if Trim(FDxpIdEdit.Text) = '' then
        FDxpIdEdit.Text := ExtractFileName(Engine.ExePath);
      ReadForMs(1000);
    end;
  finally
    FAllowHubIdAutoUpdate := False;
    InitLines.Free;
    Args.Free;
    Engine.Free;
  end;
end;

procedure TEngineEditForm.LoadParamsForExecutable;
var
  Engine: TExternalEngineDefinition;
  OtherParams: TEngineParamArray;
  OtherSection: string;
  OtherValue: string;
  ParamsFileName: string;
  Section: string;

  procedure CopyOtherParam(const AName: string);
  var
    OtherParamIndex: Integer;
  begin
    for OtherParamIndex := 0 to High(OtherParams) do
      if SameText(OtherParams[OtherParamIndex].Name, AName) then
      begin
        OtherValue := OtherParams[OtherParamIndex].Value;
        if (OtherValue <> '') and
          (EngineParamValue(FCapturedParams, AName, '') = '') then
          AddOrUpdateParam(FCapturedParams, AName,
            OtherParams[OtherParamIndex].ParamType, OtherValue, False);
        Break;
      end;
  end;

begin
  OtherParams := nil;
  ParamsFileName := EngineParamsFileName(Trim(FExeEdit.Text));
  if ParamsFileName = '' then
    Exit;

  if FKindCombo.ItemIndex=2 then begin
    FCapturedParams:=nil; LoadEngineParamsFromJson(ParamsFileName,'uci',FCapturedParams);
    UpdateFieldsFromParams;
    Engine:=CurrentEngineDefinition; try SeedDefaultGuiParams(FCapturedParams,Engine); finally Engine.Free; end;
    Exit;
  end;
  if FKindCombo.ItemIndex = 1 then
    Section := 'dxp'
  else
    Section := 'hub';

  SetLength(FCapturedParams, 0);
  LoadEngineParamsFromJson(ParamsFileName, Section, FCapturedParams);
  if Section = 'hub' then
    OtherSection := 'dxp'
  else
    OtherSection := 'hub';

  if Length(FCapturedParams) = 0 then
    LoadEngineParamsFromJson(ParamsFileName, OtherSection, FCapturedParams);

  SetLength(OtherParams, 0);
  LoadEngineParamsFromJson(ParamsFileName, OtherSection, OtherParams);
  if OtherSection = 'hub' then
  begin
    CopyOtherParam('gui-hub-id');
    CopyOtherParam('gui-hub-launch-argument');
    CopyOtherParam('gui-hub-init');
  end
  else
  begin
    CopyOtherParam('gui-dxp-id');
    CopyOtherParam('gui-dxp-ip');
    CopyOtherParam('gui-dxp-socket');
    CopyOtherParam('gui-dxp-role');
    CopyOtherParam('gui-dxp-supports-fischer');
    CopyOtherParam('gui-dxp-launch-arguments');
  end;

  UpdateFieldsFromParams;
  Engine := CurrentEngineDefinition;
  try
    SeedDefaultGuiParams(FCapturedParams, Engine);
  finally
    Engine.Free;
  end;
end;

procedure TEngineEditForm.LoadParamsGrid;
var
  I, Col, Margin: Integer;
begin
  if FParamsGrid = nil then
    Exit;

  SortEngineParams(FCapturedParams);
  FParamsGrid.RowCount := 1;
  for I := 0 to High(FCapturedParams) do
  begin
    if SameText(FCapturedParams[I].Name,'gui-uci-init') or
      SameText(FCapturedParams[I].Name,'gui-uci-launch-arguments') or
      SameText(FCapturedParams[I].Name, 'gui-ini-file') or
      SameText(FCapturedParams[I].Name, 'gui-ini-content') or
      SameText(FCapturedParams[I].Name, 'gui-hub-init') or
      SameText(FCapturedParams[I].Name, 'gui-hub-launch-argument') or
      SameText(FCapturedParams[I].Name, 'gui-dxp-launch-arguments') then
      Continue;
    FParamsGrid.RowCount := FParamsGrid.RowCount + 1;
    FParamsGrid.Cells[0, FParamsGrid.RowCount - 1] := FCapturedParams[I].Name;
    FParamsGrid.Cells[1, FParamsGrid.RowCount - 1] := FCapturedParams[I].ParamType;
    FParamsGrid.Cells[2, FParamsGrid.RowCount - 1] := FCapturedParams[I].Value;
  end;
  Margin:=MeasureGuiText('MM',FParamsGrid.Font).cx;
  for Col:=0 to 1 do begin
    FParamsGrid.AutoSizeColumn(Col);
    FParamsGrid.ColWidths[Col]:=FParamsGrid.ColWidths[Col]+Margin;
  end;
end;

procedure TEngineEditForm.RefreshLayout;
var Col,Margin:Integer;
begin
  inherited RefreshLayout;
  if FParamsGrid=nil then Exit;
  Margin:=MeasureGuiText('MM',FParamsGrid.Font).cx;
  for Col:=0 to 1 do begin
    FParamsGrid.AutoSizeColumn(Col);
    FParamsGrid.ColWidths[Col]:=FParamsGrid.ColWidths[Col]+Margin;
  end;
end;

procedure TEngineEditForm.UpdateFieldsFromParams;
var
  Value: string;
begin
  Value := LowerCase(Trim(EngineParamValue(FCapturedParams,
    'gui-engine-type', '')));
  if Value='uci' then FKindCombo.ItemIndex:=2
  else if Value = 'dxp' then
    FKindCombo.ItemIndex := 1
  else if Value = 'hub' then
    FKindCombo.ItemIndex := 0;

  if FKindCombo.ItemIndex=2 then begin
    FHubIdEdit.Text:=EngineParamValue(FCapturedParams,'gui-uci-id',FHubIdEdit.Text);
    FHubArgsEdit.Text:=EngineParamValue(FCapturedParams,EngineLaunchArgumentParamName(eekUci),FHubArgsEdit.Text);
    FInitMemo.Text:=EngineParamValue(FCapturedParams,'gui-uci-init',FInitMemo.Text);
  end;
  if FKindCombo.ItemIndex<>2 then FHubIdEdit.Text := EngineParamValue(FCapturedParams, 'gui-hub-id',
    FHubIdEdit.Text);
  FDxpIdEdit.Text := EngineParamValue(FCapturedParams, 'gui-dxp-id',
    FDxpIdEdit.Text);
  FDxpHostEdit.Text := EngineParamValue(FCapturedParams, 'gui-dxp-ip',
    FDxpHostEdit.Text);
  FDxpPortEdit.Text := EngineParamValue(FCapturedParams, 'gui-dxp-socket',
    FDxpPortEdit.Text);

  Value := LowerCase(Trim(EngineParamValue(FCapturedParams, 'gui-dxp-role',
    '')));
  if Value = 'connect' then
    FDxpRoleCombo.ItemIndex := 1
  else if Value = 'listen' then
    FDxpRoleCombo.ItemIndex := 0;

  if FKindCombo.ItemIndex<>2 then FHubArgsEdit.Text := EngineParamValue(FCapturedParams,
    'gui-hub-launch-argument', FHubArgsEdit.Text);
  FDxpArgsEdit.Text := EngineParamValue(FCapturedParams,
    'gui-dxp-launch-arguments', FDxpArgsEdit.Text);
  if FKindCombo.ItemIndex<>2 then FInitMemo.Text := EngineParamValue(FCapturedParams, 'gui-hub-init',
    FInitMemo.Text);
  FIniPathEdit.Text := EngineParamValue(FCapturedParams, 'gui-ini-file',
    FIniPathEdit.Text);
  FIniContentMemo.Lines.Text := EngineParamValue(FCapturedParams,
    'gui-ini-content', FIniContentMemo.Lines.Text);
end;

procedure TEngineEditForm.Log(const AText: string);
begin
  FStdoutMemo.Lines.Add(AText);
  FStdoutMemo.SelStart := Length(FStdoutMemo.Text);
end;

procedure TEngineEditForm.ParamsGridMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  CellRect: TRect;
  Col: LongInt;
  Row: LongInt;
begin
  if Button <> mbLeft then
    Exit;

  FParamsGrid.MouseToCell(X, Y, Col, Row);
  if (Row <= 0) or (Row >= FParamsGrid.RowCount) then
    Exit;

  FSelectedParamRow := Row;
  if (Col = 2) and
    (IsBoolParamRow(Row) or IsComboParamRow(Row) or IsScorePerspectiveParamRow(Row)) then
  begin
    PrepareInlineParamComboForRow(Row);
    CellRect := FParamsGrid.CellRect(Col, Row);
    FInlineParamCombo.SetBounds(CellRect.Left, CellRect.Top,
      CellRect.Right - CellRect.Left, CellRect.Bottom - CellRect.Top);
    FInlineParamCombo.Visible := True;
    FInlineParamCombo.BringToFront;
    FInlineParamCombo.SetFocus;
    FInlineParamCombo.DroppedDown := True;
  end
  else if ((Col = 0) or (Col = 2)) and IsDirParamRow(Row) then
  begin
    FInlineParamCombo.Visible := False;
    FDirectoryDialog.InitialDir := FParamsGrid.Cells[2, Row];
    if FDirectoryDialog.Execute then
      FParamsGrid.Cells[2, Row] := FDirectoryDialog.FileName;
  end
  else
    FInlineParamCombo.Visible := False;
end;

procedure TEngineEditForm.ParamsGridSelectCell(Sender: TObject; aCol,
  aRow: Integer; var CanSelect: Boolean);
begin
  FSelectedParamRow := aRow;
  if (aCol <> 2) or
    not (IsBoolParamRow(aRow) or IsComboParamRow(aRow) or IsScorePerspectiveParamRow(aRow)) then
    FInlineParamCombo.Visible := False;
end;

procedure TEngineEditForm.PrepareInlineParamComboForRow(ARow: Integer);
var
  Value: string;
  I: Integer;
begin
  FInlineParamCombo.Items.Clear;
  if IsComboParamRow(ARow) then begin
    for I:=0 to High(FCapturedParams) do if SameText(FCapturedParams[I].Name,FParamsGrid.Cells[0,ARow]) then FInlineParamCombo.Items.Text:=FCapturedParams[I].Choices;
    FInlineParamCombo.ItemIndex:=FInlineParamCombo.Items.IndexOf(FParamsGrid.Cells[2,ARow]); Exit;
  end;
  if IsScorePerspectiveParamRow(ARow) then
  begin
    FInlineParamCombo.Items.Add('side-to-move');
    FInlineParamCombo.Items.Add('white');
    FInlineParamCombo.Items.Add('black');
    Value := LowerCase(FParamsGrid.Cells[2, ARow]);
    if Value = 'white' then
      FInlineParamCombo.ItemIndex := 1
    else if Value = 'black' then
      FInlineParamCombo.ItemIndex := 2
    else
      FInlineParamCombo.ItemIndex := 0;
  end
  else
  begin
    FInlineParamCombo.Items.Add('false');
    FInlineParamCombo.Items.Add('true');
    if SameText(FParamsGrid.Cells[2, ARow], 'true') then
      FInlineParamCombo.ItemIndex := 1
    else
      FInlineParamCombo.ItemIndex := 0;
  end;
end;

procedure TEngineEditForm.ProcessData(Sender: TObject; const AText: string);
var
  DelimiterLength: Integer;
  Line: string;
  LineEnd: Integer;
begin
  FStdoutMemo.Text := FStdoutMemo.Text + AText;
  FStdoutMemo.SelStart := Length(FStdoutMemo.Text);
  FTextBuffer += AText;

  while True do
  begin
    DelimiterLength := Length(LineEnding);
    LineEnd := Pos(LineEnding, FTextBuffer);
    if LineEnd = 0 then
    begin
      LineEnd := Pos(#10, FTextBuffer);
      DelimiterLength := 1;
    end;
    if LineEnd = 0 then
      Break;

    Line := Trim(Copy(FTextBuffer, 1, LineEnd - 1));
    Delete(FTextBuffer, 1, LineEnd + DelimiterLength - 1);
    CaptureHubLine(Line);
  end;
end;

procedure TEngineEditForm.ProcessPollTimer(Sender: TObject);
var Obj: TObject;
begin
  while FUciLogs.TryPop(Obj) do try Log(TUciEditorLog(Obj).Text); finally Obj.Free; end;
  if FUciEngine<>nil then begin
    if (FUciInit<>nil) and (FUciInit.Completed.WaitFor(0)=wrSignaled) then FinishUciDiscovery;
    if (FUciButton<>nil) and (FUciButton.Completed.WaitFor(0)=wrSignaled) then begin
      if FUciButton.ErrorMessage<>'' then Log(FUciButton.ErrorMessage);
      FreeAndNil(FUciButton);
    end;
    Exit;
  end;
  if FProcess = nil then
    Exit;
  if FProcess.NeedsPolling then
    FProcess.ReadAvailable;
  if FProcess.HasProcess and (not FProcess.IsRunning) then
  begin
    if FProcess.NeedsPolling then
      FProcess.ReadAvailable;
    FProcessPollTimer.Enabled := False;
  end;
end;

procedure TEngineEditForm.ReadForMs(AWaitMs: Integer);
var
  UntilTick: QWord;
begin
  UntilTick := GetTickCount64 + QWord(AWaitMs);
  repeat
    if FProcess.NeedsPolling then
      FProcess.ReadAvailable;
    Application.ProcessMessages;
    Sleep(25);
  until GetTickCount64 >= UntilTick;
  if FProcess.NeedsPolling then
    FProcess.ReadAvailable;
end;

procedure TEngineEditForm.SendHubParamsToProcess;
var
  Command: string;
  I: Integer;
begin
  for I := 0 to High(FCapturedParams) do
  begin
    if not EngineParamShouldSendToHub(FCapturedParams[I].Name) then
      Continue;
    Command := 'set-param name=' + HubParamQuote(FCapturedParams[I].Name) +
      ' value=' + HubParamQuote(FCapturedParams[I].Value);
    Log('> ' + Command);
    FProcess.WriteLine(Command);
  end;
end;

procedure TEngineEditForm.StopProcessFor(AEngine: TExternalEngineDefinition);
begin
  if FProcess = nil then
    Exit;

  if FProcessPollTimer <> nil then
    FProcessPollTimer.Enabled := False;

  if FDxpThread <> nil then
  begin
    Log('[closing previous DXP socket test]');
    FDxpThread.StopConnection;
    FDxpThread.WaitFor;
    FreeAndNil(FDxpThread);
  end;

  if not FProcess.HasProcess then
    Exit;

  if (AEngine <> nil) and (AEngine.Kind = eekHub) then
  begin
    Log('[stopping previous hub process with quit]');
    FProcess.RequestQuit('quit', 800);
  end
  else
    Log('[closing previous DXP/process test]');

  if FProcess.IsRunning then
  begin
    Log('[previous process still running; terminating]');
    FProcess.Terminate(1000);
  end;
  FProcess.Close;
end;

procedure TEngineEditForm.StoreParamsGrid;
var
  Old: TEngineParamArray;
  J: Integer;
  I: Integer;
  Row: Integer;
begin
  if FParamsGrid = nil then
    Exit;

  if FInlineParamCombo.Visible then
    InlineParamComboSelect(nil);
  FInlineParamCombo.Visible := False;
  Old:=Copy(FCapturedParams);
  SetLength(FCapturedParams, 0);
  for Row := 1 to FParamsGrid.RowCount - 1 do
  begin
    if Trim(FParamsGrid.Cells[0, Row]) = '' then
      Continue;
    I := Length(FCapturedParams);
    SetLength(FCapturedParams, I + 1);
    for J:=0 to High(Old) do if SameText(Old[J].Name,Trim(FParamsGrid.Cells[0,Row])) then begin FCapturedParams[I]:=Old[J]; Break; end;
    FCapturedParams[I].Name := Trim(FParamsGrid.Cells[0, Row]);
    FCapturedParams[I].ParamType := Trim(FParamsGrid.Cells[1, Row]);
    FCapturedParams[I].Value := FParamsGrid.Cells[2, Row];
    if FCapturedParams[I].ParamType='button' then FCapturedParams[I].Value:='';
  end;
  StoreIniParams;
end;

procedure TEngineEditForm.StoreArgumentParams;
begin
  if (FHubArgsEdit = nil) or (FDxpArgsEdit = nil) then
    Exit;
  if FKindCombo.ItemIndex=2 then begin
    AddOrUpdateParam(FCapturedParams,EngineLaunchArgumentParamName(eekUci),'string',Trim(FHubArgsEdit.Text),False);
    AddOrUpdateParam(FCapturedParams,'gui-uci-init','string',FInitMemo.Text,False);
    Exit;
  end;
  AddOrUpdateParam(FCapturedParams, EngineLaunchArgumentParamName(eekHub),
    'string', Trim(FHubArgsEdit.Text), False);
  AddOrUpdateParam(FCapturedParams, EngineLaunchArgumentParamName(eekDxp),
    'string', Trim(FDxpArgsEdit.Text), False);
end;

procedure TEngineEditForm.StoreIniParams;
begin
  if FIniPathEdit = nil then
    Exit;
  AddOrUpdateParam(FCapturedParams, 'gui-ini-file', 'string',
    Trim(FIniPathEdit.Text), False);
  AddOrUpdateParam(FCapturedParams, 'gui-ini-content', 'string',
    FIniContentMemo.Lines.Text, False);
end;

procedure TEngineEditForm.UpdateKindFields;
var
  IsDxp: Boolean;
begin
  IsDxp := FKindCombo.ItemIndex = 1;
  if FKindCombo.ItemIndex=2 then begin
    FIdLabel.Caption:='UCI id'; FArgsLabel.Caption:='UCI args';
    FHubArgsEdit.Hint:='Command-line arguments passed to the UCI engine.';
  end else begin
    FIdLabel.Caption:='Hub id'; FArgsLabel.Caption:='Hub args'; FHubArgsEdit.Hint:=HubArgsHint;
  end;
  FHubIdEdit.Enabled := not IsDxp;
  FDxpIdEdit.Enabled := IsDxp;
  FDxpHostEdit.Enabled := IsDxp;
  FDxpPortEdit.Enabled := IsDxp;
  FDxpRoleCombo.Enabled := IsDxp;
  InvalidateLayout;
end;

procedure TEngineEditForm.UciLog(Sender: TObject; const AText: string);
var Msg: TUciEditorLog;
begin
  if FUciLogs.Count>=1024 then Exit;
  Msg:=TUciEditorLog.Create('uci-log'); Msg.Text:=Copy(AText,1,8192); FUciLogs.TryPost(Msg);
end;
procedure TEngineEditForm.FinishUciDiscovery;
var Options: TEngineParamArray; I,J,N: Integer; Value: string;
begin
  try
    if not FUciInit.BoolResult then Log('[UCI discovery failed: '+FUciEngine.LastError+']');
    StoreParamsGrid;
    Options:=FUciEngine.DiscoveredOptions;
    for I:=0 to High(Options) do begin
      Value:=Options[I].DefaultValue; N:=-1;
      for J:=0 to High(FCapturedParams) do if SameText(FCapturedParams[J].Name,Options[I].Name) then begin N:=J; Value:=FCapturedParams[J].Value; Break; end;
      if N<0 then begin N:=Length(FCapturedParams); SetLength(FCapturedParams,N+1); end;
      FCapturedParams[N]:=Options[I]; FCapturedParams[N].Value:=Value;
    end;
    if (Trim(FHubIdEdit.Text)='') and (FUciEngine.ReportedName<>'') then FHubIdEdit.Text:=FUciEngine.ReportedName;
    LoadParamsGrid;
    if FUciInit.BoolResult then Log('[UCI ready; button options: double-click their value cell]');
  finally FreeAndNil(FUciInit); end;
end;
function TEngineEditForm.IsComboParamRow(Row: Integer): Boolean;
begin Result:=(Row>0) and (Row<FParamsGrid.RowCount) and SameText(FParamsGrid.Cells[1,Row],'combo'); end;
procedure TEngineEditForm.ParamDoubleClick(Sender: TObject);
var Row: Integer;
begin
  Row:=FParamsGrid.Row;
  if (Row>0) and (FParamsGrid.Col=2) and SameText(FParamsGrid.Cells[1,Row],'button') then begin
    if (FUciEngine=nil) or (FUciInit<>nil) or (FUciButton<>nil) then begin Log('[launch UCI discovery before using a button]'); Exit; end;
    try FUciButton:=FUciEngine.BeginButton(FParamsGrid.Cells[0,Row]); except on E:Exception do Log(E.Message); end;
  end;
end;
end.
