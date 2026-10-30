unit uDraughtsPositionSetupForm;

{$mode objfpc}{$H+}

interface

uses
  uGuiLayout, Classes, Controls, ExtCtrls, Forms, Graphics, StdCtrls, SysUtils,
  uGameBoardControl, uGamePosition, uPositionSetupAdapter, uGuiDialogs, uPreferences;

type
  TPositionSetupAcceptedEvent = procedure(Sender: TObject;
    const AFEN: string; var AAccepted:Boolean) of object;

  TPositionSetupForm = class(TGuiLayoutForm)
  private
    FVariant:TGameVariant; // Borrowed from application composition.
    FAdapter:TPositionSetupAdapter;
    FGeneratedFen,FDirtyPrompted,FTypedFenDirty:Boolean;
    FBoardControl: TGameBoardControl;
    FFenEdit: TEdit;
    FOnAccepted: TPositionSetupAcceptedEvent;
    FPaletteLabel: TLabel;
    FPalettePanel: TPanel;
    FPiecePaintBoxes: array of TPaintBox;
    FSelectedPiece: Integer;
    FSideGroup: TRadioGroup;
    procedure FenChanged(Sender:TObject);
    function AllowBoardEdit:Boolean;
    procedure ApplyClick(Sender: TObject);
    procedure BoardMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure CancelClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    function CurrentPiece: Integer;
    procedure FormResizeHandler(Sender: TObject);
    function PalettePiece(AIndex: Integer): Integer;
    procedure PiecePaletteClick(Sender: TObject);
    procedure PiecePalettePaint(Sender: TObject);
    procedure SetFenClick(Sender: TObject);
    procedure SetStartClick(Sender: TObject);
    procedure SideChange(Sender: TObject);
    procedure UpdateFenEdit;
    procedure UpdatePiecePalette;
    procedure UpdatePiecePaletteLayout;
  public
    constructor Create(AOwner:TComponent;AVariant:TGameVariant); reintroduce;
    property Variant:TGameVariant read FVariant;
    destructor Destroy; override;
    procedure ApplyPreferences(const APreferences: TGuiPreferences);
    procedure StartSetup(const AFEN: string);
    property OnAccepted: TPositionSetupAcceptedEvent read FOnAccepted
      write FOnAccepted;
  end;

implementation

uses
  Math,uGameGuiProfile;

constructor TPositionSetupForm.Create(AOwner:TComponent;AVariant:TGameVariant);
var
  LApplyButton: TButton;
  LBottomPanel: TPanel;
  LButton: TButton;
  LControlsPanel: TPanel;
  LStartButton,LClearButton,LPasteButton:TButton;
  I: Integer;
begin
  inherited Create(AOwner);
  if AVariant=nil then raise EGamePositionError.Create('Missing dialog game variant');
  FVariant:=AVariant;

  Caption := 'Setup position';
  Position := poDesigned;
  OnResize := @FormResizeHandler;
  Width := 520;
  Height := 620;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 420;


  FAdapter:=GameGuiProfileFor(FVariant).SetupAdapterClass.Create;
  FSelectedPiece:=FAdapter.PalettePiece(0);
  SetLength(FPiecePaintBoxes,FAdapter.PaletteCount);

  LBottomPanel := TPanel.Create(Self);
  LBottomPanel.Parent := Self;
  LBottomPanel.Align := alBottom;
  LBottomPanel.Height := 40;
  LBottomPanel.BevelOuter := bvNone;
  LBottomPanel.BorderSpacing.Around := 6;

  LApplyButton := TButton.Create(Self);
  LApplyButton.Parent := LBottomPanel;
  LApplyButton.Align := alRight;
  LApplyButton.Width := 100;
  LApplyButton.Caption := 'Apply';
  LApplyButton.OnClick := @ApplyClick;

  LButton := TButton.Create(Self);
  LButton.Parent := LBottomPanel;
  LButton.Align := alRight;
  LButton.Width := 100;
  LButton.BorderSpacing.Right := 8;
  LButton.Caption := 'Cancel';
  LButton.OnClick := @CancelClick;

  LControlsPanel := TPanel.Create(Self);
  LControlsPanel.Parent := Self;
  LControlsPanel.Align := alTop;
  LControlsPanel.Height := 76;
  LControlsPanel.BevelOuter := bvNone;
  LControlsPanel.BorderSpacing.Around := 8;

  LButton := TButton.Create(Self);
  LButton.Parent := LControlsPanel;
  LButton.SetBounds(0, 8, 76, 24);
  LButton.Caption := 'Start';LStartButton:=LButton;
  LButton.OnClick := @SetStartClick;

  LButton := TButton.Create(Self);
  LButton.Parent := LControlsPanel;
  LButton.SetBounds(84, 8, 76, 24);
  LButton.Caption := 'Clear';LClearButton:=LButton;
  LButton.OnClick := @ClearClick;

  FFenEdit := TEdit.Create(Self);
  FFenEdit.Parent := LControlsPanel;
  FFenEdit.Name:='SetupFen';FFenEdit.OnChange:=@FenChanged;
  FFenEdit.SetBounds(0, 42, 500, 24);
  FFenEdit.Anchors := [akTop, akLeft, akRight];

  LButton := TButton.Create(Self);
  LButton.Parent := LControlsPanel;
  LButton.SetBounds(512, 42, 96, 24);
  LButton.Anchors := [akTop, akRight];
  LButton.Caption := 'Paste FEN';LPasteButton:=LButton;
  LButton.OnClick := @SetFenClick;

  FPalettePanel := TPanel.Create(Self);
  FPalettePanel.Parent := Self;
  FPalettePanel.Align := alLeft;
  FPalettePanel.Width := 104;
  FPalettePanel.BevelOuter := bvNone;
  FPalettePanel.Color := clBtnFace;
  FPalettePanel.ParentColor := False;
  FPalettePanel.BorderSpacing.Left := 4;
  FPalettePanel.BorderSpacing.Right := 4;
  FPalettePanel.BorderSpacing.Bottom := 8;

  for I := 0 to High(FPiecePaintBoxes) do
  begin
    FPiecePaintBoxes[I] := TPaintBox.Create(Self);
    FPiecePaintBoxes[I].Parent := FPalettePanel;
    FPiecePaintBoxes[I].Name:='SetupPiece'+IntToStr(I);
    FPiecePaintBoxes[I].Hint:=FAdapter.PieceName(I);
    FPiecePaintBoxes[I].ShowHint:=True;
    FPiecePaintBoxes[I].Height := 64;
    FPiecePaintBoxes[I].BorderSpacing.Left := 8;
    FPiecePaintBoxes[I].BorderSpacing.Right := 8;
    FPiecePaintBoxes[I].BorderSpacing.Bottom := 8;
    FPiecePaintBoxes[I].Tag := I;
    FPiecePaintBoxes[I].OnClick := @PiecePaletteClick;
    FPiecePaintBoxes[I].OnPaint := @PiecePalettePaint;
  end;

  FPaletteLabel := TLabel.Create(Self);
  FPaletteLabel.Parent := FPalettePanel;
  FPaletteLabel.Height := 24;
  FPaletteLabel.Caption := 'Pieces';
  FPaletteLabel.Alignment := taCenter;
  FPaletteLabel.Layout := tlCenter;
  FPaletteLabel.Color := clBtnFace;
  FPaletteLabel.ParentColor := False;

  FSideGroup := TRadioGroup.Create(Self);
  FSideGroup.Parent := FPalettePanel;
  FSideGroup.Height := 72;
  FSideGroup.Caption := 'Side to move';
  FSideGroup.Columns := 1;
  FSideGroup.Items.Add('White');
  FSideGroup.Items.Add('Black');
  FSideGroup.ItemIndex := 0;
  FSideGroup.BorderSpacing.Bottom := 8;
  FSideGroup.OnClick := @SideChange;

  FBoardControl := FAdapter.CreateBoard(Self);
  FBoardControl.Name:='SetupBoard';
  FBoardControl.Parent := Self;
  FBoardControl.Align := alClient;
  FBoardControl.ShowSideToMoveMarker := True;
  FBoardControl.OnMouseDown := @BoardMouseDown;
  with LayoutRow(LControlsPanel,[LStartButton,LClearButton]) do Top:=0;
  with LayoutRow(LControlsPanel,[FFenEdit,LPasteButton],0) do Top:=1;
  LControlsPanel.AutoSize:=True;LBottomPanel.AutoSize:=True;
  EnableAutoLayout;
  UpdatePiecePaletteLayout;
end;

destructor TPositionSetupForm.Destroy;
begin
  // Destroy the borrowing view before its dialog-local draft.
  FreeAndNil(FBoardControl);FAdapter.Free;
  inherited Destroy;
end;

procedure TPositionSetupForm.ApplyPreferences(
  const APreferences: TGuiPreferences);
begin
  if FBoardControl = nil then
    Exit;
  FBoardControl.BoardLightColor := APreferences.MainBoardLightColor;
  FBoardControl.BoardDarkColor := APreferences.MainBoardDarkColor;
  FBoardControl.GridColor := APreferences.MainBoardDarkColor;
  FBoardControl.PvSourceSquareColor := APreferences.PvMoveColor;
  FBoardControl.HintSourceSquareColor := APreferences.HintMoveColor;
  FBoardControl.LastMoveTargetSquareColor := APreferences.LastMoveColor;
  FBoardControl.TargetSquareColor := APreferences.TargetSquareColor;
  UpdatePiecePalette;
end;

procedure TPositionSetupForm.StartSetup(const AFEN: string);
begin
  try
    FAdapter.LoadFen(AFEN);
  except
    if FAdapter.IsChessSetup then raise;
    FAdapter.Start;
  end;
  if FAdapter.Side = gsBlack then
    FSideGroup.ItemIndex := 1
  else
    FSideGroup.ItemIndex := 0;
  UpdateFenEdit;
  UpdatePiecePalette;
  FBoardControl.Invalidate;
end;

function TPositionSetupForm.CurrentPiece: Integer;
begin
  Result := FSelectedPiece;
end;

procedure TPositionSetupForm.FormResizeHandler(Sender: TObject);
begin
  UpdatePiecePaletteLayout;
end;

function TPositionSetupForm.PalettePiece(AIndex: Integer): Integer;
begin Result:=FAdapter.PalettePiece(AIndex);end;

procedure TPositionSetupForm.PiecePaletteClick(Sender: TObject);
begin
  if Sender is TPaintBox then
  begin
    FSelectedPiece := PalettePiece(TPaintBox(Sender).Tag);
    UpdatePiecePalette;
  end;
end;

procedure TPositionSetupForm.PiecePalettePaint(Sender: TObject);
var Box:TPaintBox;
begin
 if not (Sender is TPaintBox) then Exit;Box:=TPaintBox(Sender);
 FAdapter.PaintTile(Box.Canvas,Box.ClientRect,Box.Tag,FSelectedPiece,FBoardControl.BoardDarkColor);
end;

procedure TPositionSetupForm.FenChanged(Sender:TObject);
begin
 if not FGeneratedFen then begin
  FDirtyPrompted:=False;FTypedFenDirty:=True;
  if FAdapter.IsChessSetup then begin
   FPaletteLabel.Caption:='FEN edited';
   FPaletteLabel.Hint:='Use Paste FEN or Apply to read the text; Start/Clear replaces it.';
   FPaletteLabel.ShowHint:=True;
  end;
 end;
end;

function TPositionSetupForm.AllowBoardEdit:Boolean;
begin
 Result:=True;
 if not FAdapter.IsChessSetup or not FTypedFenDirty then Exit;
 Result:=False;
 if FDirtyPrompted then Exit;
 FDirtyPrompted:=True;
 if ShowGuiConfirmationDialog(Self,'Setup position',
   'Discard the typed FEN changes and continue editing the board?',
   'Discard','',mrCancel,True)<>mrYes then Exit;
 UpdateFenEdit;Result:=True;
end;

procedure TPositionSetupForm.UpdateFenEdit;
begin
  FGeneratedFen:=True;
  try FFenEdit.Text:=FAdapter.DraftFen;finally FGeneratedFen:=False;end;
  FDirtyPrompted:=False;FTypedFenDirty:=False;FPaletteLabel.Caption:='Pieces';
end;

procedure TPositionSetupForm.SideChange(Sender: TObject);
begin
  if not AllowBoardEdit then begin
    FSideGroup.ItemIndex:=Ord(FAdapter.Side=gsBlack);Exit;
  end;
  if FSideGroup.ItemIndex=1 then FAdapter.SetSide(gsBlack) else FAdapter.SetSide(gsWhite);
  UpdateFenEdit;
  FBoardControl.Invalidate;
end;

procedure TPositionSetupForm.BoardMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  LPiece: Integer;
  LSquare: Integer;
begin
  if Button <> mbLeft then
    Exit;
  LSquare := FBoardControl.SquareAtPoint(X, Y);
  if LSquare <= 0 then
    Exit;
  if not AllowBoardEdit then Exit;
  LPiece := CurrentPiece;FAdapter.Toggle(LSquare,LPiece);
  UpdateFenEdit;
  FBoardControl.Invalidate;
end;

procedure TPositionSetupForm.SetFenClick(Sender: TObject);
begin
  try
    FAdapter.LoadFen(Trim(FFenEdit.Text));
    if FAdapter.Side = gsBlack then
      FSideGroup.ItemIndex := 1
    else
      FSideGroup.ItemIndex := 0;
    UpdateFenEdit;
    FBoardControl.Invalidate;
  except
    on E: Exception do
      ShowGuiOkDialog(Self, 'Setup position', 'Invalid FEN: ' + E.Message);
  end;
end;

procedure TPositionSetupForm.SetStartClick(Sender: TObject);
begin
  FAdapter.Start;
  FSideGroup.ItemIndex := 0;
  UpdateFenEdit;
  FBoardControl.Invalidate;
end;

procedure TPositionSetupForm.ClearClick(Sender: TObject);
begin
  FAdapter.Clear;
  FSideGroup.ItemIndex := 0;
  UpdateFenEdit;
  FBoardControl.Invalidate;
end;

procedure TPositionSetupForm.UpdatePiecePalette;
var
  I: Integer;
begin
  for I := 0 to High(FPiecePaintBoxes) do
    if FPiecePaintBoxes[I] <> nil then
      FPiecePaintBoxes[I].Invalidate;
end;

procedure TPositionSetupForm.UpdatePiecePaletteLayout;
var
  I: Integer;
  PaletteWidth: Integer;
  SquareSize: Integer;
  SideMargin: Integer;
  TopPos,TileSize,Row,Col: Integer;
begin
  if (FBoardControl = nil) or (FPalettePanel = nil) then
    Exit;

  SquareSize := Max(32, FBoardControl.BoardSquareSize);
  PaletteWidth := Max(Max(SquareSize + 8, 96),MeasureGuiText('Side to move',Font).cx+16);
  SideMargin := Max(0, (PaletteWidth - SquareSize) div 2);
  FPalettePanel.Width := PaletteWidth;

  TopPos := 0;
  if FSideGroup <> nil then
  begin
    FSideGroup.SetBounds(0, TopPos, PaletteWidth,MeasureGuiText('Side to move'+LineEnding+'White'+LineEnding+'Black',Font).cy+16);
    Inc(TopPos, FSideGroup.Height + 8);
  end;
  if FPaletteLabel <> nil then
  begin
    FPaletteLabel.SetBounds(0, TopPos, PaletteWidth, 24);
    Inc(TopPos, FPaletteLabel.Height + 4);
  end;
  if FAdapter.IsChessSetup then begin
    FPalettePanel.Constraints.MinHeight:=TopPos+6*16;
    TileSize:=Max(12,Min((PaletteWidth-24) div 2,(FPalettePanel.ClientHeight-TopPos-12) div 6-4));
    for I:=0 to High(FPiecePaintBoxes) do begin
      Row:=I div 2;Col:=I mod 2;
      FPiecePaintBoxes[I].SetBounds((PaletteWidth-2*TileSize-8) div 2+Col*(TileSize+8),
        TopPos+Row*(TileSize+4),TileSize,TileSize);
    end;
  end else begin
  FPalettePanel.Constraints.MinHeight:=TopPos+Length(FPiecePaintBoxes)*20;
  SquareSize:=Min(SquareSize,Max(12,(FPalettePanel.ClientHeight-TopPos) div Length(FPiecePaintBoxes)-8));
  SideMargin:=Max(0,(PaletteWidth-SquareSize) div 2);
  for I := 0 to High(FPiecePaintBoxes) do
    if FPiecePaintBoxes[I] <> nil then
    begin
      FPiecePaintBoxes[I].SetBounds(SideMargin, TopPos, SquareSize,
        SquareSize);
      Inc(TopPos, SquareSize + 8);
    end;
  end;
  UpdatePiecePalette;
end;

procedure TPositionSetupForm.ApplyClick(Sender: TObject);
var Fen:string;Accepted:Boolean;P:TGamePosition;
begin
 try
  if FAdapter.IsChessSetup then begin
   // Typed text is consumed only by this explicit action or Paste FEN.
   if FTypedFenDirty then begin
    P:=FVariant.CreatePosition;
    try P.LoadFromFEN(Trim(FFenEdit.Text));Fen:=P.ToFEN;finally P.Free;end;
   end else Fen:=FAdapter.ValidatedFen;
  end else Fen:=FAdapter.DraftFen;
 except on E:Exception do begin ShowGuiOkDialog(Self,'Setup position','Invalid FEN: '+E.Message);Exit;end;end;
 Accepted:=False;
 if Assigned(FOnAccepted) then FOnAccepted(Self,Fen,Accepted);
 if Accepted then Hide;
end;

procedure TPositionSetupForm.CancelClick(Sender: TObject);
begin
  Hide;
end;

end.
