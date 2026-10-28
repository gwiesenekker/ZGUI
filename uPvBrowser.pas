unit uPvBrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, LCLType, StdCtrls, SysUtils, uGameBoardControl,
  uGamePosition, uGameTreeBuilder, uPvSnapshot;

type
  TIntArray = array of Integer;

  // One existing PV view for the selected game; all positions are owned copies.
  TPvBrowser = class
  private
    FVariant: TGameVariant; // Owned by application composition.
    FPositionClass: TClass;
    FBaseBoard: TGamePosition;
    FBasePly: Integer;
    FBoard: TGamePosition;
    FBoardControl: TGameBoardControl;
    FBrowsePly: Integer;
    FDepth: string;
    FInfoLabel: TLabel;
    FMoveLengths: TIntArray;
    FMoveStarts: TIntArray;
    FOnBoardChanged: TNotifyEvent;
    FPendingBaseBoard: TGamePosition;
    FPendingBasePly: Integer;
    FPendingDepth: string;
    FPendingScore: string;
    FPendingStartingFEN: string;
    FPendingTimeText: string;
    FPendingVariation: string;
    FHasPendingData: Boolean;
    FPvMemo: TMemo;
    FScore: string;
    FStartingFEN: string;
    FTimeText: string;
    FVariation: string;
    FValidMoveCount: Integer;
    FInvalidMove: string;
    procedure ApplyBrowsePly(APly: Integer);
    procedure ApplyPendingData;
    function FormatInfo: string;
    function MoveCount: Integer;
    procedure BuildMoveText(out AText: string; var AStarts,
      ALengths: TIntArray);
    procedure HighlightSelection(AFocusMemo: Boolean);
    procedure MemoClick(Sender: TObject);
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RenderBoard;
    procedure RenderMemo(const AText: string);
    procedure SetDataInternal(ABaseBoard: TGamePosition; ABasePly: Integer;
      const AStartingFEN, APv, AScore, ADepth, ATimeText: string);
    procedure StorePendingData(ABaseBoard: TGamePosition; ABasePly: Integer;
      const AStartingFEN, APv, AScore, ADepth, ATimeText: string);
    procedure UnlockUpdates;
    procedure ValidateVariation;
  public
    constructor Create(AVariant: TGameVariant; ABoardControl: TGameBoardControl;
      AInfoLabel: TLabel; APvMemo: TMemo);
    destructor Destroy; override;

    procedure Clear;
    procedure SetSnapshot(ASnapshot: TPvSnapshot; const AStartingFEN: string);
    procedure SetData(ABasePosition: TGamePosition; ABasePly: Integer;
      const AStartingFEN, APv, AScore, ADepth, ATimeText: string);

    property Position: TGamePosition read FBoard; // read-only, owned by browser
    property PrincipalVariation: string read FVariation;
    property Score: string read FScore;
    property Depth: string read FDepth;
    property OnBoardChanged: TNotifyEvent read FOnBoardChanged write FOnBoardChanged;
    property TimeText: string read FTimeText;
  end;

implementation

function MoveSegmentText(APly, ADisplayedIndex: Integer; const AMove: string;
  AStartingSide: TGameSide; AStartingNumber: Integer): string;
var LMoveNumber: Integer; LSide: TGameSide;
begin
  LMoveNumber := GameMoveNumberForPly(AStartingSide,AStartingNumber,APly);
  LSide := GameSideForPly(AStartingSide,APly);
  if LSide = gsWhite then Result := IntToStr(LMoveNumber)+'.'+AMove
  else if ADisplayedIndex = 0 then Result := IntToStr(LMoveNumber)+'...'+AMove
  else Result := AMove;
end;

constructor TPvBrowser.Create(AVariant: TGameVariant;
  ABoardControl: TGameBoardControl; AInfoLabel: TLabel; APvMemo: TMemo);
begin
  inherited Create;
  if AVariant = nil then AVariant := DefaultGameVariant;
  FVariant := AVariant;
  FBaseBoard := FVariant.CreatePosition;
  FPositionClass := FBaseBoard.ClassType;
  FBrowsePly := -1;

  FBoardControl := ABoardControl;
  FInfoLabel := AInfoLabel;
  FPvMemo := APvMemo;
  if FPvMemo <> nil then
  begin
    FPvMemo.OnClick := @MemoClick;
    FPvMemo.OnKeyDown := @MemoKeyDown;
  end;
  Clear;
end;

destructor TPvBrowser.Destroy;
begin
  if FBoardControl <> nil then FBoardControl.SetPosition(nil);
  FBoard.Free;
  FPendingBaseBoard.Free;
  FBaseBoard.Free;
  inherited Destroy;
end;

procedure TPvBrowser.Clear;
begin
  FreeAndNil(FBaseBoard);
  FreeAndNil(FPendingBaseBoard);
  FreeAndNil(FBoard);
  FBasePly := 0;
  FStartingFEN := '';
  FVariation := '';
  FValidMoveCount := 0;
  FInvalidMove := '';
  FScore := '';
  FDepth := '';
  FTimeText := '';
  FHasPendingData := False;
  FBrowsePly := -1;
  SetLength(FMoveStarts, 0);
  SetLength(FMoveLengths, 0);
  RenderMemo('No PV');
  RenderBoard;
  if FInfoLabel <> nil then
    FInfoLabel.Caption := FormatInfo;
  if (FBoardControl <> nil) then
    FBoardControl.Invalidate;
end;

function TPvBrowser.FormatInfo: string;
begin
  Result := 'PV:';
  if Trim(FScore) <> '' then
    Result += ' score ' + Trim(FScore);
  if Trim(FDepth) <> '' then
    Result += ' depth ' + Trim(FDepth);
  if Trim(FTimeText) <> '' then
    Result += ' time ' + Trim(FTimeText);
  if Result = 'PV:' then
    Result += ' no info';
  if FInvalidMove <> '' then
    Result += ' — invalid PV';
  if FBrowsePly >= 0 then
  begin
    Result += ' — browsing; Esc to resume';
    if FHasPendingData then Result += '; newer PV pending';
  end;
end;

procedure TPvBrowser.BuildMoveText(out AText: string; var AStarts,
  ALengths: TIntArray);
var
  I: Integer;
  LMoves: TStringList;
  LSegment: string;
  LStartingSide: TGameSide;
  LPosition: TGamePosition;
  LNotation,Canonical: string;
begin
  AText := '';
  SetLength(AStarts, 0);
  SetLength(ALengths, 0);

  LMoves := TStringList.Create;
  LPosition := nil;
  try
    if FBaseBoard <> nil then LPosition := FBaseBoard.Clone;
    TextToMoveList(FVariation, LMoves);
    if LMoves.Count = 0 then
    begin
      AText := 'No PV';
      Exit;
    end;

    SetLength(AStarts, LMoves.Count);
    SetLength(ALengths, LMoves.Count);
    LStartingSide := FVariant.SideFromFEN(FStartingFEN);
    for I := 0 to LMoves.Count - 1 do
    begin
      if AText <> '' then
        AText += ' ';
      LNotation := LMoves[I];
      if (I < FValidMoveCount) and (LPosition <> nil) then
      begin
        if LPosition.TryParseMove(LMoves[I],Canonical) then
        begin
          LNotation := LPosition.MoveNotation(Canonical);
          LPosition.PlayTrustedMove(Canonical);
        end;
      end;
      LSegment := MoveSegmentText(FBasePly + I + 1, I, LNotation,
        LStartingSide, FVariant.StartingMoveNumberFromFEN(FStartingFEN));
      AStarts[I] := Length(AText);
      ALengths[I] := Length(LSegment);
      AText += LSegment;
    end;
    if FInvalidMove <> '' then
      AText += LineEnding + 'Invalid PV move ' +
        IntToStr(FBasePly + FValidMoveCount + 1) + ': ' + FInvalidMove +
        '. Showing the last legal position.';
  finally
    LPosition.Free;
    LMoves.Free;
  end;
end;

procedure TPvBrowser.RenderBoard;
var
  I: Integer;
  LMoves: TStringList;
  LPly: Integer;
begin
  if FBaseBoard = nil then
  begin
    if FBoardControl <> nil then FBoardControl.SetPosition(nil);
    if Assigned(FOnBoardChanged) then FOnBoardChanged(Self);
    Exit;
  end;
  AssignGamePosition(FBoard,FBaseBoard);
  LMoves := TStringList.Create;
  try
    TextToMoveList(FVariation, LMoves);
    LPly := FBrowsePly;
    if (LPly < 0) or (LPly > FValidMoveCount) then
      LPly := FValidMoveCount;
    for I := 0 to LPly - 1 do
      FBoard.PlayMoveText(LMoves[I]);
  finally
    LMoves.Free;
  end;

  if FBoardControl <> nil then
    FBoardControl.SetPosition(FBoard);
  if Assigned(FOnBoardChanged) then
    FOnBoardChanged(Self);
end;

procedure TPvBrowser.RenderMemo(const AText: string);
begin
  if FPvMemo = nil then
    Exit;
  FPvMemo.Lines.BeginUpdate;
  try
    FPvMemo.Text := AText;
  finally
    FPvMemo.Lines.EndUpdate;
  end;
  FPvMemo.SelLength := 0;
end;

procedure TPvBrowser.ValidateVariation;
var
  Canonical: string;
  Candidate: TGamePosition;
  Moves: TStringList;
  I: Integer;
begin
  FValidMoveCount := 0;
  FInvalidMove := '';
  if FBaseBoard = nil then Exit;
  Candidate := FBaseBoard.Clone;
  Moves := TStringList.Create;
  try
    Candidate.AssignFrom(FBaseBoard);
    TextToMoveList(FVariation, Moves);
    for I := 0 to Moves.Count - 1 do
    begin
      if not Candidate.TryParseMove(Moves[I],Canonical) then
      begin
        FInvalidMove := Moves[I];
        Break;
      end;
      Candidate.PlayTrustedMove(Canonical);
      Inc(FValidMoveCount);
    end;
  finally
    Moves.Free;
    Candidate.Free;
  end;
end;

function TPvBrowser.MoveCount: Integer;
begin
  Result := FValidMoveCount;
end;

procedure TPvBrowser.HighlightSelection(AFocusMemo: Boolean);
begin
  if FPvMemo = nil then
    Exit;
  if (FBrowsePly > 0) and (FBrowsePly <= Length(FMoveStarts)) then
  begin
    FPvMemo.SelStart := FMoveStarts[FBrowsePly - 1];
    FPvMemo.SelLength := FMoveLengths[FBrowsePly - 1];
  end
  else
  begin
    FPvMemo.SelStart := 0;
    FPvMemo.SelLength := 0;
  end;
  if AFocusMemo and FPvMemo.CanFocus then
    FPvMemo.SetFocus;
end;

procedure TPvBrowser.ApplyBrowsePly(APly: Integer);
var
  LMoveCount: Integer;
begin
  LMoveCount := MoveCount;
  if APly < 0 then
    APly := 0
  else if APly > LMoveCount then
    APly := LMoveCount;
  FBrowsePly := APly;
  if FInfoLabel <> nil then FInfoLabel.Caption := FormatInfo;
  RenderBoard;
  HighlightSelection(True);
end;

procedure TPvBrowser.MemoClick(Sender: TObject);
var
  I: Integer;
  LPos: Integer;
begin
  if FPvMemo = nil then
    Exit;
  LPos := FPvMemo.SelStart;
  for I := 0 to High(FMoveStarts) do
    if (LPos >= FMoveStarts[I]) and
      (LPos <= FMoveStarts[I] + FMoveLengths[I]) then
    begin
      ApplyBrowsePly(I + 1);
      Exit;
    end;
end;

procedure TPvBrowser.MemoKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  LMoveCount: Integer;
  LPly: Integer;
begin
  if Key = VK_ESCAPE then
  begin
    UnlockUpdates;
    Key := 0;
  end
  else if Key = VK_LEFT then
  begin
    LMoveCount := MoveCount;
    if LMoveCount = 0 then
      Exit;
    if FBrowsePly < 0 then
      LPly := LMoveCount
    else
      LPly := FBrowsePly - 1;
    ApplyBrowsePly(LPly);
    Key := 0;
  end
  else if Key = VK_RIGHT then
  begin
    if MoveCount = 0 then
      Exit;
    if FBrowsePly < 0 then
      LPly := 1
    else
      LPly := FBrowsePly + 1;
    ApplyBrowsePly(LPly);
    Key := 0;
  end;
end;

procedure TPvBrowser.StorePendingData(ABaseBoard: TGamePosition;
  ABasePly: Integer; const AStartingFEN, APv, AScore, ADepth,
  ATimeText: string);
begin
  if ABaseBoard <> nil then
    AssignGamePosition(FPendingBaseBoard,ABaseBoard);
  FPendingBasePly := ABasePly;
  FPendingStartingFEN := AStartingFEN;
  FPendingVariation := Trim(APv);
  FPendingScore := Trim(AScore);
  FPendingDepth := Trim(ADepth);
  FPendingTimeText := Trim(ATimeText);
  FHasPendingData := True;
  if FInfoLabel <> nil then FInfoLabel.Caption := FormatInfo;
end;

procedure TPvBrowser.ApplyPendingData;
begin
  if not FHasPendingData then
    Exit;
  FHasPendingData := False;
  SetDataInternal(FPendingBaseBoard, FPendingBasePly, FPendingStartingFEN,
    FPendingVariation, FPendingScore, FPendingDepth, FPendingTimeText);
end;

procedure TPvBrowser.UnlockUpdates;
begin
  FBrowsePly := -1;
  if FInfoLabel <> nil then FInfoLabel.Caption := FormatInfo;
  if FHasPendingData then
    ApplyPendingData
  else
  begin
    RenderBoard;
    HighlightSelection(True);
  end;
end;

procedure TPvBrowser.SetDataInternal(ABaseBoard: TGamePosition;
  ABasePly: Integer; const AStartingFEN, APv, AScore, ADepth,
  ATimeText: string);
var
  LText: string;
begin
  if ABaseBoard <> nil then
    AssignGamePosition(FBaseBoard,ABaseBoard);
  FBasePly := ABasePly;
  FStartingFEN := AStartingFEN;
  FVariation := Trim(APv);
  FScore := Trim(AScore);
  FDepth := Trim(ADepth);
  FTimeText := Trim(ATimeText);
  ValidateVariation;

  if FInfoLabel <> nil then
    FInfoLabel.Caption := FormatInfo;
  BuildMoveText(LText, FMoveStarts, FMoveLengths);
  RenderMemo(LText);
  RenderBoard;
  HighlightSelection(False);
end;

procedure TPvBrowser.SetData(ABasePosition: TGamePosition; ABasePly: Integer;
  const AStartingFEN, APv, AScore, ADepth, ATimeText: string);
var Start: TGamePosition;
begin
  // Never retain a previous game's board when a bad/stale base arrives.
  if (ABasePosition = nil) or (ABasePosition.ClassType <> FPositionClass) then
  begin Clear; Exit; end;
  Start := nil;
  try
    try Start := FVariant.CreatePositionFromFEN(AStartingFEN);
    except on E: EConvertError do begin Clear; Exit; end; end;
  finally Start.Free; end;
  if FBrowsePly >= 0 then
    StorePendingData(ABasePosition, ABasePly, AStartingFEN, APv, AScore, ADepth, ATimeText)
  else SetDataInternal(ABasePosition, ABasePly, AStartingFEN, APv, AScore, ADepth, ATimeText);
end;

procedure TPvBrowser.SetSnapshot(ASnapshot: TPvSnapshot;
  const AStartingFEN: string);
begin
  if ASnapshot = nil then
    Clear
  else
    SetData(ASnapshot.BasePosition, ASnapshot.BasePly, AStartingFEN,
      ASnapshot.PrincipalVariation, ASnapshot.Score, ASnapshot.Depth,
      ASnapshot.TimeText);
end;

end.
