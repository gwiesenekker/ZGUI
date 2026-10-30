unit uPdnOpenDialog;

{$mode objfpc}{$H+}

interface

uses
  uGuiLayout, Classes, Controls, Forms, Graphics, Grids, StdCtrls, SysUtils, uGuiDialogs,
  uDraughtsPdn, uGameFileReader, uGamePosition;

type
  TPdnGameSelectedEvent = procedure(Sender: TObject; AGame: TPdnGame) of object;

  TFileGameSelectedEvent = procedure(Sender: TObject; Entry: TGameFileEntry) of object;

  TPdnOpenDialog = class(TGuiLayoutForm)
  private
    FFileName: string;
    FVariant:TGameVariant;
    FReader: TGameFileReader;
    FOnFileGameSelected: TFileGameSelectedEvent;
    FGrid: TStringGrid;
    FOnGameSelected: TPdnGameSelectedEvent;
    FStatusLabel: TLabel;
    FWarningLabel: TLabel;
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Integer; var CanSelect: Boolean);
    procedure ShowGameWarnings(ARow: Integer);
    function GameAtRow(ARow: Integer): TGameFileEntry;
    procedure GridDblClick(Sender: TObject);
    procedure PopulateGrid;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenPdnFile(const AFileName: string);
    procedure OpenGameFile(const AFileName, AFormatName: string; AReader: TGameFileReader;AVariant:TGameVariant=nil);
    property Variant:TGameVariant read FVariant;
    property OnFileGameSelected: TFileGameSelectedEvent read FOnFileGameSelected write FOnFileGameSelected;
    property OnGameSelected: TPdnGameSelectedEvent read FOnGameSelected
      write FOnGameSelected;
  end;

implementation

uses uPdnFileReader;

constructor TPdnOpenDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  Caption := 'Open PDN';
  Position := poDesigned;
  Width := 860;
  Height := 420;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 260;

  FReader := TPdnFileReader.Create;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Name := 'PdnImportStatus';
  FStatusLabel.Parent := Self;
  FStatusLabel.Align := alBottom;
  FStatusLabel.Height := 26;
  FStatusLabel.Layout := tlCenter;
  FStatusLabel.BorderSpacing.Left := 8;

  FWarningLabel := TLabel.Create(Self);
  FWarningLabel.Name := 'PdnImportWarnings';
  FWarningLabel.Parent := Self;
  FWarningLabel.Align := alBottom;
  FWarningLabel.AutoSize := False;
  FWarningLabel.Height := 50;
  FWarningLabel.WordWrap := True;
  FWarningLabel.ShowHint := True;
  FWarningLabel.BorderSpacing.Left := 8;
  FWarningLabel.BorderSpacing.Right := 8;
  FWarningLabel.Visible := False;

  FGrid := TStringGrid.Create(Self);
  FGrid.Name := 'PdnGames';
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.ColCount := 5;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.Options := FGrid.Options + [goRowSelect] -
    [goEditing, goRangeSelect];
  FGrid.Cells[0, 0] := 'White';
  FGrid.Cells[1, 0] := 'Black';
  FGrid.Cells[2, 0] := 'Event';
  FGrid.Cells[3, 0] := 'Result';
  FGrid.Cells[4, 0] := 'Warnings';
  FGrid.ColWidths[0] := 170;
  FGrid.ColWidths[1] := 170;
  FGrid.ColWidths[2] := 250;
  FGrid.ColWidths[3] := 70;
  FGrid.ColWidths[4] := 90;
  FGrid.RowCount := 2;
  FGrid.OnDblClick := @GridDblClick;
  FGrid.OnSelectCell := @GridSelectCell;
  FStatusLabel.AutoSize:=True;FWarningLabel.AutoSize:=True;
  EnableAutoLayout;
end;

destructor TPdnOpenDialog.Destroy;
begin FReader.Free; inherited Destroy; end;

function TPdnOpenDialog.GameAtRow(ARow: Integer): TGameFileEntry;
begin
  Result:=nil;
  if (ARow<=0) or (ARow>FReader.Entries.Count) then Exit;
  Result:=TGameFileEntry(FReader.Entries[ARow-1]);
  Result.Validate;
end;

procedure TPdnOpenDialog.GridDblClick(Sender: TObject);
var Entry: TGameFileEntry;
begin
  Entry:=GameAtRow(FGrid.Row);
  if Entry=nil then Exit;
  if Entry.ErrorText<>'' then begin
    ShowGuiOkDialog(Self,Caption,Entry.ErrorText); Exit;
  end;
  if Entry is TPdnFileEntry then begin
    if Assigned(FOnGameSelected) then FOnGameSelected(Self,TPdnFileEntry(Entry).Game);
  end else if Assigned(FOnFileGameSelected) then FOnFileGameSelected(Self,Entry);
end;

procedure TPdnOpenDialog.ShowGameWarnings(ARow: Integer);
var
  Game: TGameFileEntry;
  Warnings: TStringList;
begin
  Game := GameAtRow(ARow);
  FWarningLabel.Caption := '';
  if Game <> nil then
  begin
    FWarningLabel.Caption := Trim(StringReplace(Game.ErrorText+LineEnding+Game.WarningsText,
      LineEnding, ' ', [rfReplaceAll]));
    Warnings := TStringList.Create;
    try
      Warnings.Text := Game.WarningsText;
      FGrid.Cells[4, ARow] := '';
      if Warnings.Count > 0 then FGrid.Cells[4, ARow] := IntToStr(Warnings.Count);
      FStatusLabel.Caption := IntToStr(FReader.Entries.Count) + ' game(s) found in ' +
        ExtractFileName(FFileName) + ' — selected game: ' + IntToStr(Warnings.Count) +
        ' import warning(s); other games checked on selection';
    finally Warnings.Free; end;
  end;
  FWarningLabel.Hint := FWarningLabel.Caption;
  FWarningLabel.Visible := FWarningLabel.Caption <> '';
end;

procedure TPdnOpenDialog.GridSelectCell(Sender: TObject; ACol, ARow: Integer;
  var CanSelect: Boolean);
begin
  ShowGameWarnings(ARow);
end;

procedure TPdnOpenDialog.PopulateGrid;
var
  Game: TGameFileEntry;
  Row, WarningCount: Integer;
  Warnings: TStringList;
begin
  if FReader.Entries.Count = 0 then
    FGrid.RowCount := 2
  else
    FGrid.RowCount := FReader.Entries.Count + 1;
  for Row := 1 to FGrid.RowCount - 1 do
  begin
    FGrid.Cells[0, Row] := '';
    FGrid.Cells[1, Row] := '';
    FGrid.Cells[2, Row] := '';
    FGrid.Cells[3, Row] := '';
    FGrid.Cells[4, Row] := '';
  end;

  WarningCount := 0;
  Warnings := TStringList.Create;
  try
    for Row := 1 to FReader.Entries.Count do
    begin
      Game := TGameFileEntry(FReader.Entries[Row - 1]);
      FGrid.Cells[0, Row] := Game.WhiteName;
      FGrid.Cells[1, Row] := Game.BlackName;
      FGrid.Cells[2, Row] := Game.EventName;
      FGrid.Cells[3, Row] := Game.ResultText;
      Warnings.Text := Game.WarningsText;
      Inc(WarningCount, Warnings.Count);
      if Game.Deferred then FGrid.Cells[4, Row] := 'On selection'
      else if Warnings.Count > 0 then FGrid.Cells[4, Row] := IntToStr(Warnings.Count);
    end;
  finally
    Warnings.Free;
  end;

  FStatusLabel.Caption := IntToStr(FReader.Entries.Count) + ' game(s) found in ' +
    ExtractFileName(FFileName);
  if WarningCount > 0 then
    FStatusLabel.Caption := FStatusLabel.Caption + ' — ' + IntToStr(WarningCount) + ' import warning(s)';
  ShowGameWarnings(FGrid.Row);
end;

procedure TPdnOpenDialog.OpenPdnFile(const AFileName: string);
begin OpenGameFile(AFileName,'PDN',TPdnFileReader.Create); end;

procedure TPdnOpenDialog.OpenGameFile(const AFileName,AFormatName: string; AReader: TGameFileReader;AVariant:TGameVariant);
begin
  try AReader.OpenFile(AFileName); except AReader.Free; raise; end;
  FReader.Free; FReader:=AReader;FVariant:=AVariant;
  FFileName:=AFileName; Caption:='Open '+AFormatName;
  PopulateGrid;
  {$IFNDEF GWDGUI_NONINTERACTIVE_TEST}
  if Owner is TCustomForm then
    ShowFormCenteredOnOwner(Self, TCustomForm(Owner))
  else
  begin
    Show;
    BringToFront;
  end;
  {$ENDIF}
end;

end.
