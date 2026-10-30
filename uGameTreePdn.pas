unit uGameTreePdn;

{$mode objfpc}{$H+}

interface

uses
  Classes, StrUtils, SysUtils, fgl, uGamePosition, uGameTree;

type
  TGameTreeMoveCaptionMap = specialize TFPGMap<Int64, string>;
  TGameTreePdnIntArray = array of Integer;
  TGameTreePdnNodeIdArray = array of Int64;
  TGameTreePdnBoolArray = array of Boolean;
  TGameTreePdnStringArray = array of string;
  TNotationAnalysisSource = (nasNone, nasEngine, nasAnnotator, nasAutoPlay);
  TNotationAnalysisSources = array of TNotationAnalysisSource;

  TGameFileFormat = (gffPdn, gffPgn);
  TGameTreePdnRenderOptions = record
    FileFormat: TGameFileFormat;
    LosslessPgn: Boolean;
    HideAnnotations: Boolean;
    ShowEngineScore: Boolean;
    ShowClocks: Boolean;
    ShowEnginePVMove: Boolean;
    ShowEngineFullPV: Boolean;
    ShowAnnotatorPVMove: Boolean;
    ShowAnnotatorFullPV: Boolean;
    ShowAnnotatorScore: Boolean;
  end;

  TGameTreePdnRenderResult = record
    Text: string;
    BoardMovesApplied: Integer; // Work counter: no root replay per capture caption.
    MoveStarts: TGameTreePdnIntArray;
    MoveLengths: TGameTreePdnIntArray;
    VariationStarts: TGameTreePdnIntArray;
    VariationNodeIds: TGameTreePdnNodeIdArray;
    VariationBeforeMoves: TGameTreePdnBoolArray;
    VariationAnalysisSources: TNotationAnalysisSources;
    VariationLengths: TGameTreePdnIntArray;
    VariationPlies: TGameTreePdnIntArray;
    VariationBasePlies: TGameTreePdnIntArray;
    VariationMovesTexts: TGameTreePdnStringArray;
  end;

procedure BuildGameTreeMoveCaptions(ATree: TGameTree;
  ACaptions: TGameTreeMoveCaptionMap; out ABoardMovesApplied: Integer);
function DefaultGameTreePdnRenderOptions: TGameTreePdnRenderOptions;
function GameTreeToPdnText(AGameTree: TGameTree): string;
function GameTreeToPdnTextEx(AGameTree: TGameTree;
  const AOptions: TGameTreePdnRenderOptions;
  const AEventName: string = ''): string;
procedure RenderGameTreeMovesToPdn(AGameTree: TGameTree;
  const AOptions: TGameTreePdnRenderOptions;
  out ARenderResult: TGameTreePdnRenderResult);
function GameTreeScoreAnnotationsText(AGameTree: TGameTree): string;
function GameTreeHasContent(AGameTree: TGameTree): Boolean;

implementation

uses uPdnText, uGameTreeNodeData, uGameFileMetadata, uChessPgnAnnotations;

function GameTreeHasContent(AGameTree: TGameTree): Boolean;
begin
  Result := False;
  if AGameTree = nil then
    Exit;
  Result := (AGameTree.MainlineCount > 0) or (AGameTree.BranchCount > 0) or
    (AGameTree.StartingFEN <> AGameTree.Variant.DefaultStartingFEN) or
    (AGameTree.ResultText <> '*') or (AGameTree.EventName <> '?') or
    (AGameTree.WhiteName <> 'White') or (AGameTree.BlackName <> 'Black') or
    (Length(AGameTree.ExtraTags)>0) or
    (AGameTree.Root.NodeData.BeforeCommentText<>'') or (Length(AGameTree.Root.NodeData.Nags)>0) or
    (AGameTree.Root.CommentText <> '') or (AGameTree.Root.EnginePV <> '') or
    (AGameTree.Root.AnnotatorPV <> '') or (AGameTree.Root.AutoPlayPV <> '') or
    (AGameTree.Root.EngineScore <> '') or (AGameTree.Root.AnnotatorScore <> '');
end;

function DefaultGameTreePdnRenderOptions: TGameTreePdnRenderOptions;
begin
  Result.FileFormat:=gffPdn; Result.LosslessPgn:=False;
  Result.HideAnnotations := False;
  Result.ShowEngineScore := True;
  Result.ShowClocks := True;
  Result.ShowEnginePVMove := True;
  Result.ShowEngineFullPV := True;
  Result.ShowAnnotatorPVMove := True;
  Result.ShowAnnotatorFullPV := True;
  Result.ShowAnnotatorScore := True;
end;

function PdnQuote(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
end;

function PdnExportResult(const AText: string): string;
begin
  Result := Trim(AText);
  if SameText(Result, '2-0') then
    Result := '1-0'
  else if SameText(Result, '1-1') then
    Result := '1/2-1/2'
  else if SameText(Result, '0-2') then
    Result := '0-1'
  else if not SameText(Result, '*') and not SameText(Result, '0-0') then
    Result := '*';
end;

function NodeMoveCaption(APosition: TGamePosition; ANode: TGameTreePlyNode; AForceMoveNumber: Boolean;
  ACompact: Boolean; out MoveText: string): string;
begin
  Result := '';
  if ANode = nil then
    Exit;

  if (ANode.SideToMove = gsWhite) or AForceMoveNumber then
  begin
    Result := IntToStr(ANode.MoveNumber);
    if ANode.SideToMove = gsWhite then
      Result += '.'
    else
      Result += '...';
    if not ACompact then
      Result += ' ';
  end;
  MoveText := ANode.MoveText;
  // Record notation is decided in the position before the move (SAN needs it).
  if APosition <> nil then
    MoveText := APosition.MoveNotation(MoveText);
  Result += MoveText;
end;

function ClockSecondsCaption(ASeconds: Double): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  Result := FormatFloat('0.000', ASeconds, FS);
end;

function NodeClockAnnotation(ANode: TGameTreePlyNode): string;
begin
  Result := '';
  if (ANode = nil) or (not ANode.HasClockInfo) then
    Exit;
  Result := 'clk: W=' + ClockSecondsCaption(ANode.WhiteRemainingSeconds) +
    ', B=' + ClockSecondsCaption(ANode.BlackRemainingSeconds) +
    '; used: W=' + ClockSecondsCaption(ANode.WhiteUsedSeconds) +
    ', B=' + ClockSecondsCaption(ANode.BlackUsedSeconds);
  if ANode.HasMoveTime then
    Result += '; emt: ' + ClockSecondsCaption(ANode.SecondsUsed);
end;

function FirstPvMove(AVariant: TGameVariant; const APv: string): string;
var
  Moves: TStringList;
begin
  Result := '';
  Moves := TStringList.Create;
  try
    ExtractStrings([' ', #9, #10, #13], [], PChar(Trim(APv)), Moves);
    if Moves.Count > 0 then
      Result := AVariant.NormalizeMove(Moves[0]);
  finally
    Moves.Free;
  end;
end;

function NodeAnnotation(AVariant: TGameVariant; ANode: TGameTreePlyNode;
  const AOptions: TGameTreePdnRenderOptions; AForFile: Boolean = False): string;
var
  LClockText, Projection, Encoded: string;
  Data: TGameTreeNodeData;
  N: Byte;
  procedure FilterFileData;
  begin
    if not AOptions.ShowEngineScore then Data.EngineScore := '';
    if not AOptions.ShowAnnotatorScore then Data.AnnotatorScore := '';
    if not AOptions.ShowEngineFullPV then
      if AOptions.ShowEnginePVMove then Data.EnginePV := FirstPvMove(AVariant, Data.EnginePV)
      else Data.EnginePV := '';
    if not AOptions.ShowAnnotatorFullPV then
      if AOptions.ShowAnnotatorPVMove then Data.AnnotatorPV := FirstPvMove(AVariant, Data.AnnotatorPV)
      else Data.AnnotatorPV := '';
    if not AOptions.ShowEngineFullPV and not AOptions.ShowEnginePVMove then
    begin Data.EnginePVDepth := ''; Data.EnginePVTimeText := ''; end;
    if not AOptions.ShowAnnotatorFullPV and not AOptions.ShowAnnotatorPVMove then
    begin Data.AnnotatorPVDepth := ''; Data.AnnotatorPVTimeText := ''; end;
    if not AOptions.ShowClocks then
    begin
      Data.HasClockInfo := False; Data.HasMoveTime := False; Data.SecondsUsed := 0;
      Data.WhiteRemainingSeconds := 0; Data.BlackRemainingSeconds := 0;
      Data.WhiteUsedSeconds := 0; Data.BlackUsedSeconds := 0;
    end;
  end;
begin
  Result := '';
  if ANode = nil then
    Exit;
  if AOptions.HideAnnotations then
    Exit;
  Data:=ANode.NodeData;
  if AForFile then FilterFileData;
  if AForFile and (AOptions.FileFormat=gffPgn) then begin
    for N in Data.Nags do Result+=' $'+IntToStr(N);
    Encoded:=PgnNodeComment(Data,ANode.SideToMove,AOptions.ShowEngineScore or AOptions.ShowAnnotatorScore,
      AOptions.ShowClocks,AOptions.LosslessPgn);
    if Encoded<>'' then Result+=' '+Encoded;
    Exit;
  end;
  if Trim(ANode.CommentText) <> '' then
    Result := Trim(ANode.CommentText);
  if not AForFile and (Copy(ANode.OriginText,1,10)='Auto Play:') then begin
    if Result<>'' then Result+='; ';
    Result+=ANode.OriginText;
  end;
  if AOptions.ShowEngineScore and (Trim(ANode.EngineScore) <> '') then
  begin
    if Result <> '' then
      Result += '; ';
    Result += 'E: ' + Trim(ANode.EngineScore);
  end;
  if AOptions.ShowAnnotatorScore and (Trim(ANode.AnnotatorScore) <> '') then
  begin
    if Result <> '' then
      Result += '; ';
    Result += 'A: ' + Trim(ANode.AnnotatorScore);
  end;
  if AOptions.ShowClocks then
  begin
    LClockText := NodeClockAnnotation(ANode);
    if LClockText <> '' then
    begin
      if Result <> '' then
        Result += '; ';
      Result += LClockText;
    end;
  end;
  if not AForFile then begin
    Encoded:=''; for N in Data.Nags do
      case N of
        1:Encoded+=' !'; 2:Encoded+=' ?'; 3:Encoded+=' !!';
        4:Encoded+=' ??'; 5:Encoded+=' !?'; 6:Encoded+=' ?!';
        else Encoded+=' $'+IntToStr(N);
      end;
  end else Encoded:='';
  Projection := Result;
  if Result <> '' then
    if AForFile then Result := ' {' + EscapePdnLiteralComment(Result) + '}'
    else Result := ' {' + EscapePdnComment(Result) + '}';
  Result:=Encoded+Result;
  if AForFile then
  begin
    Encoded := EncodeNodeData(Data, Projection);
    if Encoded <> '' then Result += ' {' + EscapePdnComment(Encoded) + '}';
  end;
end;

function BeforeNode(ANode: TGameTreePlyNode; const Options: TGameTreePdnRenderOptions): string;
begin
  Result:='';
  if (ANode=nil) or Options.HideAnnotations or
    ((Options.FileFormat=gffPgn) and Options.LosslessPgn) then Exit;
  Result:=PgnBraceComment(ANode.NodeData.BeforeCommentText);
  if Result<>'' then Result+=' ';
end;

function NodeIsAnnotatorAlternative(AVariant: TGameVariant; APrevious, ANode: TGameTreePlyNode): Boolean;
var
  LPvMove: string;
begin
  Result := False;
  if (APrevious = nil) or (ANode = nil) then
    Exit;
  if Trim(APrevious.AnnotatorPV) = '' then
    Exit;
  LPvMove := FirstPvMove(AVariant, APrevious.AnnotatorPV);
  Result := (LPvMove <> '') and
    (not SameText(LPvMove, AVariant.NormalizeMove(ANode.MoveText)));
end;

function SideForNextPly(ASide: TGameSide): TGameSide;
begin
  Result := OppositeGameSide(ASide);
end;

function PreviousPositionAnnotation(APrevious, APlayedMove: TGameTreePlyNode;
  const AOptions: TGameTreePdnRenderOptions): string;
begin
  Result := '';
  if (APrevious = nil) or (APlayedMove = nil) then
    Exit;
  if AOptions.HideAnnotations or (not AOptions.ShowAnnotatorScore) then
    Exit;
  if Trim(APrevious.AnnotatorScore) = '' then
    Exit;
  if Trim(APlayedMove.AnnotatorScore) <> '' then
    Exit;
  if Trim(APrevious.AnnotatorPV) <> '' then
    Exit;
  Result := ' {A: ' + Trim(APrevious.AnnotatorScore) + '}';
end;

function PlyMoveCaption(AMoveNumber: Integer; ASideToMove: TGameSide;
  const AMoveText: string; AForceMoveNumber, ACompact: Boolean): string;
begin
  Result := '';
  if (ASideToMove = gsWhite) or AForceMoveNumber then
  begin
    Result := IntToStr(AMoveNumber);
    if ASideToMove = gsWhite then
      Result += '.'
    else
      Result += '...';
    if not ACompact then
      Result += ' ';
  end;
  Result += AMoveText;
end;

procedure AddNodeHit(var AResult: TGameTreePdnRenderResult; ANodeId: Int64;
  ABeforeMove: Boolean; ASource: TNotationAnalysisSource = nasNone); forward;
procedure AddInt(var AValues: TGameTreePdnIntArray; AValue: Integer); forward;
procedure AddString(var AValues: TGameTreePdnStringArray;
  const AValue: string); forward;

function RenderAnalysisVariation(ABaseNode: TGameTreePlyNode;
  const APv, AScore, AScorePrefix: string; ASource: TNotationAnalysisSource; AShowFullPv, AShowScore: Boolean;
  const AOptions: TGameTreePdnRenderOptions; ACompact: Boolean;
  var ARenderResult: TGameTreePdnRenderResult; ABaseOffset: Integer): string;
var
  I: Integer;
  LLimit: Integer;
  LMoveStart: Integer;
  LMoves: TStringList;
  LMoveNumber: Integer;
  LSegment: string;
  LSegmentOffset: Integer;
  LSide: TGameSide;
begin
  Result := '';
  if (ABaseNode = nil) or (Trim(APv) = '') then
    Exit;

  LMoves := TStringList.Create;
  try
    ExtractStrings([' ', #9, #10, #13], [], PChar(Trim(APv)),
      LMoves);
    if LMoves.Count = 0 then
      Exit;
    LLimit := 1;
    if AShowFullPv then
      LLimit := LMoves.Count;
    // The root carries the side to move and the number of the first move; a
    // move node carries the side that moved and that move's number.
    LSide := SideForNextPly(ABaseNode.SideToMove);
    LMoveNumber := ABaseNode.MoveNumber;
    if ABaseNode.PlyNumber = 0 then
      LSide := ABaseNode.SideToMove
    else if ABaseNode.SideToMove = gsBlack then
      Inc(LMoveNumber);
    for I := 0 to LLimit - 1 do
    begin
      if (I > 0) and (LSide = gsWhite) then
        Inc(LMoveNumber);
      LSegment := PlyMoveCaption(LMoveNumber, LSide, LMoves[I], I = 0,
        ACompact);
      if (I = 0) and (ABaseNode.PlyNumber = 0) and
        AShowScore and
        (not AOptions.HideAnnotations) and
        (Trim(AScore) <> '') then
        LSegment += ' {' + AScorePrefix + ': ' + Trim(AScore) + '}';
      if Result <> '' then
        Result += ' ';
      LSegmentOffset := Length(Result);
      Result += LSegment;
      LMoveStart := Pos(LMoves[I], LSegment);
      if LMoveStart > 0 then
      begin
        AddNodeHit(ARenderResult, 0, False, ASource);
        AddInt(ARenderResult.VariationStarts,
          ABaseOffset + 1 + LSegmentOffset + LMoveStart - 1);
        AddInt(ARenderResult.VariationLengths, Length(LMoves[I]));

        AddInt(ARenderResult.VariationPlies, I + 1);
        AddInt(ARenderResult.VariationBasePlies, ABaseNode.PlyNumber);
        AddString(ARenderResult.VariationMovesTexts, Trim(APv));
      end;
      LSide := SideForNextPly(LSide);
    end;
    if Result <> '' then
    begin
      Result := '(' + Result + ')';
      AddNodeHit(ARenderResult, 0, False, ASource);
      AddInt(ARenderResult.VariationStarts, ABaseOffset);
      AddInt(ARenderResult.VariationLengths,
        Pos(LMoves[0], Result) - 1);

      AddInt(ARenderResult.VariationPlies, 0);
      AddInt(ARenderResult.VariationBasePlies, ABaseNode.PlyNumber);
      AddString(ARenderResult.VariationMovesTexts, Trim(APv));
    end;
  finally
    LMoves.Free;
  end;
end;

function FindContinuationChild(ANode: TGameTreePlyNode): TGameTreePlyNode;
begin
  Result := nil;
  if (ANode <> nil) and (ANode.ChildCount > 0) then Result := ANode.Children[0];
end;

procedure AddInt(var AValues: TGameTreePdnIntArray; AValue: Integer);
var
  LIndex: Integer;
begin
  LIndex := Length(AValues);
  SetLength(AValues, LIndex + 1);
  AValues[LIndex] := AValue;
end;

procedure AddString(var AValues: TGameTreePdnStringArray;
  const AValue: string);
var
  LIndex: Integer;
begin
  LIndex := Length(AValues);
  SetLength(AValues, LIndex + 1);
  AValues[LIndex] := AValue;
end;

procedure AddNodeHit(var AResult: TGameTreePdnRenderResult; ANodeId: Int64;
  ABeforeMove: Boolean; ASource: TNotationAnalysisSource);
var
  N: Integer;
begin
  N := Length(AResult.VariationNodeIds);
  SetLength(AResult.VariationNodeIds, N + 1);
  SetLength(AResult.VariationBeforeMoves, N + 1);
  SetLength(AResult.VariationAnalysisSources, N + 1);
  AResult.VariationNodeIds[N] := ANodeId;
  AResult.VariationBeforeMoves[N] := ABeforeMove;
  AResult.VariationAnalysisSources[N] := ASource;
end;

procedure ClearRenderResult(out ARenderResult: TGameTreePdnRenderResult);
begin
  ARenderResult.Text := '';
  SetLength(ARenderResult.MoveStarts, 0);
  SetLength(ARenderResult.MoveLengths, 0);
  ARenderResult.BoardMovesApplied := 0;
  SetLength(ARenderResult.VariationStarts, 0);
  SetLength(ARenderResult.VariationNodeIds, 0);
  SetLength(ARenderResult.VariationBeforeMoves, 0);
  SetLength(ARenderResult.VariationAnalysisSources, 0);
  SetLength(ARenderResult.VariationLengths, 0);
  SetLength(ARenderResult.VariationPlies, 0);
  SetLength(ARenderResult.VariationBasePlies, 0);
  SetLength(ARenderResult.VariationMovesTexts, 0);
end;

procedure AdvanceRenderBoard(var ABoard: TGamePosition; const AMove: string;
  var AResult: TGameTreePdnRenderResult);
begin
  if ABoard = nil then Exit;
  Inc(AResult.BoardMovesApplied);
  try ABoard.PlayMoveText(AMove);
  except FreeAndNil(ABoard); end; // Preserve raw captions beyond invalid legacy paths.
end;

procedure BuildGameTreeMoveCaptions(ATree: TGameTree;
  ACaptions: TGameTreeMoveCaptionMap; out ABoardMovesApplied: Integer);
var Board: TGamePosition; Work: TGameTreePdnRenderResult;
  procedure AddMove(Node: TGameTreePlyNode; var Position: TGamePosition);
  var Caption: string;
  begin
    Caption := Node.MoveText;
    if Position <> nil then
      Caption := Position.MoveNotation(Caption);
    ACaptions.Add(Node.NodeId, Caption);
    AdvanceRenderBoard(Position, Node.MoveText, Work);
  end;
  procedure Walk(Parent: TGameTreePlyNode; var Position: TGamePosition);
  var I: Integer; Branch: TGamePosition;
  begin
    if Parent.ChildCount = 0 then Exit;
    for I := 1 to Parent.ChildCount - 1 do
    begin
      Branch := nil;
      if Position <> nil then
        Branch := Position.Clone;
      try
        AddMove(Parent.Children[I], Branch);
        Walk(Parent.Children[I], Branch);
      finally Branch.Free; end;
    end;
    AddMove(Parent.Children[0], Position);
    Walk(Parent.Children[0], Position);
  end;
begin
  ACaptions.Clear;
  ACaptions.Sorted := True;
  ABoardMovesApplied := 0;
  if ATree = nil then Exit;
  Work.BoardMovesApplied := 0;
  Board := nil;
  try
    try Board := ATree.Variant.CreatePositionFromFEN(ATree.StartingFEN);
    except Board := nil; end;
    Walk(ATree.Root, Board);
    ABoardMovesApplied := Work.BoardMovesApplied;
  finally Board.Free; end;
end;

function RenderVariationLine(AGameTree: TGameTree; ANode, APreviousPosition: TGameTreePlyNode;
  const AOptions: TGameTreePdnRenderOptions; ACompact: Boolean;
  var ARenderResult: TGameTreePdnRenderResult; ABaseOffset: Integer;
  var ABoard: TGamePosition; AIncludeSiblings: Boolean = False; AForceMoveNumber: Boolean = True): string; forward;

function RenderChildVariations(AGameTree: TGameTree; ANode, AContinuation: TGameTreePlyNode;
  const AOptions: TGameTreePdnRenderOptions; ACompact: Boolean;
  var ARenderResult: TGameTreePdnRenderResult; ABaseOffset: Integer;
  AParentBoard: TGamePosition; ABasePlyFilter: Integer = -1): string;
var
  I: Integer;
  LBasePlyNumber: Integer;
  LChild: TGameTreePlyNode;
  LLineOffset: Integer;
  LText: string;
  LVariationPlyNumber: Integer;
  VariationBoard: TGamePosition;
begin
  Result := '';
  if ANode = nil then
    Exit;

  for I := 0 to ANode.ChildCount - 1 do
  begin
    LChild := ANode.Children[I];
    if (LChild = nil) or (LChild = AContinuation) then
      Continue;
    if (ABasePlyFilter >= 0) and (ANode.PlyNumber <> ABasePlyFilter) then
      Continue;
    if ACompact and NodeIsAnnotatorAlternative(AGameTree.Variant, ANode, LChild) and
      (not AOptions.ShowAnnotatorPVMove) and
      (not AOptions.ShowAnnotatorFullPV) then
      Continue;
    LLineOffset := ABaseOffset + Length(Result);
    if Result <> '' then
      Inc(LLineOffset);
    Inc(LLineOffset);
    VariationBoard := nil;
    if AParentBoard <> nil then
      VariationBoard := AParentBoard.Clone;
    try
      LText := RenderVariationLine(AGameTree, LChild, ANode, AOptions, ACompact,
        ARenderResult, LLineOffset, VariationBoard);
    finally VariationBoard.Free; end;
    if LText = '' then
      Continue;
    LBasePlyNumber := ANode.PlyNumber;
    LVariationPlyNumber := 1;
    begin
      AddNodeHit(ARenderResult, LChild.NodeId, True);
      AddInt(ARenderResult.VariationStarts, LLineOffset - 1);
      AddInt(ARenderResult.VariationLengths, Pos(LChild.MoveText, LText));

      AddInt(ARenderResult.VariationPlies, LVariationPlyNumber - 1);
      AddInt(ARenderResult.VariationBasePlies, LBasePlyNumber);
      AddString(ARenderResult.VariationMovesTexts, '');
    end;
    if Result <> '' then
      Result += ' ';
    Result += '(' + LText + ')';
  end;
end;

function RenderVariationLine(AGameTree: TGameTree; ANode, APreviousPosition: TGameTreePlyNode;
  const AOptions: TGameTreePdnRenderOptions; ACompact: Boolean;
  var ARenderResult: TGameTreePdnRenderResult; ABaseOffset: Integer;
  var ABoard: TGamePosition; AIncludeSiblings, AForceMoveNumber: Boolean): string;
var
  LBasePlyNumber: Integer;
  LContinuation: TGameTreePlyNode;
  LMoveStart: Integer;
  LRenderedMove: string;
  LNested: string;
  LVariationPlyNumber: Integer;
begin
  Result := '';
  if ANode = nil then
    Exit;

  LNested:='';
  LContinuation := FindContinuationChild(ANode);
  if APreviousPosition <> nil then
    if ACompact and NodeIsAnnotatorAlternative(AGameTree.Variant, APreviousPosition, ANode) and
      (not AOptions.ShowAnnotatorFullPV) then
      LContinuation := nil;

  Result := BeforeNode(ANode,AOptions)+NodeMoveCaption(ABoard, ANode, AForceMoveNumber or
    (ANode.NodeData.BeforeCommentText<>''), ACompact, LRenderedMove) +
    NodeAnnotation(AGameTree.Variant, ANode, AOptions, not ACompact);
  if APreviousPosition <> nil then
    if ACompact and NodeIsAnnotatorAlternative(AGameTree.Variant, APreviousPosition, ANode) and
      AOptions.ShowAnnotatorScore and (not AOptions.HideAnnotations) and
      (Trim(APreviousPosition.AnnotatorScore) <> '') and
      (Trim(ANode.AnnotatorScore) = '') then
      Result += ' {A: ' + Trim(APreviousPosition.AnnotatorScore) + '}';

  LBasePlyNumber := APreviousPosition.PlyNumber;
  LVariationPlyNumber := 1;
  begin
    LMoveStart := PosEx(LRenderedMove, Result,Length(BeforeNode(ANode,AOptions))+1);
    if LMoveStart > 0 then
    begin
      AddNodeHit(ARenderResult, ANode.NodeId, False);
      AddInt(ARenderResult.VariationStarts, ABaseOffset + LMoveStart - 1);
      AddInt(ARenderResult.VariationLengths, Length(LRenderedMove));

      AddInt(ARenderResult.VariationPlies, LVariationPlyNumber);
      AddInt(ARenderResult.VariationBasePlies, LBasePlyNumber);
      AddString(ARenderResult.VariationMovesTexts, '');
    end;
  end;

  // PDN alternatives follow the move they replace, at its parent position.
  if AIncludeSiblings then
  begin
    LNested := RenderChildVariations(AGameTree, APreviousPosition, ANode, AOptions,
      ACompact, ARenderResult, ABaseOffset + Length(Result) + 1, ABoard);
    if LNested <> '' then
      Result += ' ' + LNested;
  end;
  AdvanceRenderBoard(ABoard, ANode.MoveText, ARenderResult);
  if LContinuation <> nil then
  begin
    if Result <> '' then
      Result += ' ';
    Result += RenderVariationLine(AGameTree, LContinuation, ANode, AOptions,
      ACompact, ARenderResult, ABaseOffset + Length(Result), ABoard, True,
      (AOptions.FileFormat=gffPgn) and ((ANode.CommentText<>'') or (LNested<>'')));
  end;
end;

function RenderMainline(AGameTree: TGameTree; const AResultText: string;
  const AOptions: TGameTreePdnRenderOptions; ACompact: Boolean;
  var ARenderResult: TGameTreePdnRenderResult): string;
var
  I: Integer;
  LChild: TGameTreePlyNode;
  LMoveStart: Integer;
  LNested: string;
  LPreviousPosition: TGameTreePlyNode;
  LResultText: string;
  LSegment, LRenderedMove: string;
  Board: TGamePosition;
  ForceNext: Boolean;

  procedure AppendAnalysisVariation(ABaseNode: TGameTreePlyNode;
    const APv, AScore, AScorePrefix: string; ASource: TNotationAnalysisSource; AShowMove, AShowFull,
    AShowScore: Boolean);
  var
    LBaseOffset: Integer;
    LVariationText: string;
  begin
    if not ACompact then Exit; // File exports store analysis as node data, never as real RAVs.
    if (not AShowMove) and (not AShowFull) then
      Exit;
    if Result = '' then
      LBaseOffset := 0
    else
      LBaseOffset := Length(Result) + 1;
    LVariationText := RenderAnalysisVariation(ABaseNode, APv, AScore,
      AScorePrefix, ASource, AShowFull, AShowScore, AOptions, ACompact,
      ARenderResult, LBaseOffset);
    if LVariationText = '' then
      Exit;
    if Result <> '' then
      Result += ' ';
    Result += LVariationText;
  end;
  procedure AppendPositionAnalysis(ANode: TGameTreePlyNode);
  begin
    if ANode = nil then Exit;
    AppendAnalysisVariation(ANode, ANode.EnginePV, ANode.EngineScore, 'E', nasEngine,
      AOptions.ShowEnginePVMove, AOptions.ShowEngineFullPV, AOptions.ShowEngineScore);
    AppendAnalysisVariation(ANode, ANode.AnnotatorPV, ANode.AnnotatorScore, 'A', nasAnnotator,
      AOptions.ShowAnnotatorPVMove, AOptions.ShowAnnotatorFullPV, AOptions.ShowAnnotatorScore);
    AppendAnalysisVariation(ANode, ANode.AutoPlayPV, '', '', nasAutoPlay, True, True, False);
  end;
begin
  Result := '';
  if (AGameTree = nil) or (AGameTree.Root = nil) then
    Exit;

  Board := nil;
  try
    try Board := AGameTree.Variant.CreatePositionFromFEN(AGameTree.StartingFEN);
    except Board := nil; end;
  Result := Trim(NodeAnnotation(AGameTree.Variant, AGameTree.Root, AOptions, not ACompact));
  ForceNext:=True;
  for I := 1 to AGameTree.MainlineCount do
  begin
    LChild := AGameTree.MainlineNode[I];
    if LChild = nil then
      Continue;

    if Result <> '' then
      Result += ' ';
    LPreviousPosition := AGameTree.Root;
    if LChild.PlyNumber > 1 then
      LPreviousPosition := AGameTree.MainlineNode[LChild.PlyNumber - 1];
    // The first move always carries its number, also after a root comment
    // ('{...} 37... e5' for a Black-to-move start).
    LSegment := BeforeNode(LChild,AOptions)+NodeMoveCaption(Board, LChild, (I = 1) or (Result = '') or
      ((AOptions.FileFormat=gffPgn) and (ForceNext or (LChild.NodeData.BeforeCommentText<>''))), ACompact,
      LRenderedMove) +
      NodeAnnotation(AGameTree.Variant, LChild, AOptions, not ACompact);
    if ACompact or (AOptions.FileFormat<>gffPgn) then
      LSegment+=PreviousPositionAnnotation(LPreviousPosition,LChild,AOptions);
    LMoveStart := PosEx(LRenderedMove, LSegment,Length(BeforeNode(LChild,AOptions))+1);
    if LMoveStart > 0 then
    begin
      AddInt(ARenderResult.MoveStarts, Length(Result) + LMoveStart - 1);
      AddInt(ARenderResult.MoveLengths, Length(LRenderedMove));
    end;
    Result += LSegment;
    LNested := RenderChildVariations(AGameTree, LPreviousPosition, LChild, AOptions, ACompact,
      ARenderResult, Length(Result) + 1, Board);
    if LNested <> '' then
      Result += ' ' + LNested;
    // Analysis belongs to the position before this played move. Present it
    // after that move, while retaining its original base for preview navigation.
    ForceNext:=(LNested<>'') or (NodeAnnotation(AGameTree.Variant,LChild,AOptions,not ACompact)<>'');
    AppendPositionAnalysis(LPreviousPosition);
    AdvanceRenderBoard(Board, LChild.MoveText, ARenderResult);
  end;

  if AGameTree.MainlineCount = 0 then
    LChild := AGameTree.Root
  else
    LChild := AGameTree.MainlineNode[AGameTree.MainlineCount];
  LNested := RenderChildVariations(AGameTree, LChild, nil, AOptions, ACompact,
    ARenderResult, Length(Result) + 1, Board, AGameTree.MainlineCount);
  if LNested <> '' then
  begin
    if Result <> '' then
      Result += ' ';
    Result += LNested;
  end;

  // At the tip (or in an empty game), no played continuation exists yet.
  AppendPositionAnalysis(LChild);

  if AOptions.FileFormat=gffPgn then LResultText:=AResultText
  else LResultText := PdnExportResult(AResultText);
  if (AOptions.FileFormat=gffPgn) or (LResultText <> '*') then
  begin
    if Result <> '' then
      Result += ' ';
    Result += LResultText;
  end;
  finally Board.Free; end;
end;

// Wrap at PGN token boundaries. Never split a symbol, an embedded command or
// a comment word. As with common PGN writers, an indivisible item may exceed
// the column limit; silently changing a literal comment is worse than that.
function WrapPgnMoves(const Text: string): string;
var I,Start,Column: Integer; Brace,LineComment: Boolean; Chunk: string;
  procedure Add(const S: string);
  var J: Integer;
  begin
    if S='' then Exit;
    if (Column>0) and (Column+1+Length(S)>80) then begin Result+=LineEnding; Column:=0; end;
    if Column>0 then begin Result+=' '; Inc(Column); end;
    Result+=S;
    for J:=1 to Length(S) do
      if S[J] in [#10,#13] then Column:=0 else Inc(Column);
  end;
begin
  Result:=''; I:=1; Column:=0;
  while I<=Length(Text) do begin
    while (I<=Length(Text)) and (Text[I] in [' ',#9,#10,#13]) do Inc(I);
    if I>Length(Text) then Break;
    Start:=I; Brace:=Text[I]='{'; LineComment:=Text[I]=';';
    if Text[I] in ['(',')'] then Inc(I)
    else if Brace then begin
      Inc(I); while (I<=Length(Text)) and (Text[I]<>'}') do Inc(I);
      if I<=Length(Text) then Inc(I);
    end else if LineComment then begin
      while (I<=Length(Text)) and not (Text[I] in [#10,#13]) do Inc(I);
      if I<=Length(Text) then Inc(I);
    end else while (I<=Length(Text)) and not (Text[I] in [' ',#9,#10,#13,'(',')','{',';']) do Inc(I);
    Chunk:=Copy(Text,Start,I-Start); Add(Chunk);
  end;
end;

function GameTreeToPdnTextEx(AGameTree: TGameTree;
  const AOptions: TGameTreePdnRenderOptions; const AEventName: string): string;
var
  Lines: TStringList;
  RenderResult: TGameTreePdnRenderResult;
  Tags: TGameFileTags; Tag: TGameFileTag; Name,Value: string; RosterIndex: Integer;
  const Roster: array[0..6] of string=('Event','Site','Date','Round','White','Black','Result');
  function Quote(const S: string): string;
  begin
    Result:=PgnQuoteTag(S);
  end;
begin
  Result := '';
  if AGameTree = nil then
    Exit;

  Lines := TStringList.Create;
  try
    if AOptions.FileFormat=gffPgn then begin
      Tags:=AGameTree.ExtraTags;
      for RosterIndex:=0 to High(Roster) do begin
        Name:=Roster[RosterIndex];
        if Name='Event' then begin Value:=AGameTree.EventName; if AEventName<>'' then Value:=AEventName; end
        else if Name='White' then Value:=AGameTree.WhiteName
        else if Name='Black' then Value:=AGameTree.BlackName
        else if Name='Result' then Value:=AGameTree.ResultText
        else if Name='Date' then Value:=GameFileTagValue(Tags,Name,'????.??.??')
        else Value:=GameFileTagValue(Tags,Name,'?');
        Lines.Add('['+Name+' "'+Quote(Value)+'"]');
      end;
      for Tag in Tags do
        if (Tag.Name<>'Site') and (Tag.Name<>'Date') and (Tag.Name<>'Round') and
          (Tag.Name<>'Event') and (Tag.Name<>'White') and (Tag.Name<>'Black') and
          (Tag.Name<>'Result') and (Tag.Name<>'FEN') and (Tag.Name<>'SetUp') then
          Lines.Add('['+Tag.Name+' "'+Quote(Tag.Value)+'"]');
      if AGameTree.StartingFEN<>AGameTree.Variant.DefaultStartingFEN then begin
        Lines.Add('[SetUp "1"]'); Lines.Add('[FEN "'+Quote(AGameTree.StartingFEN)+'"]');
      end;
    end else begin
    if Trim(AEventName) <> '' then
      Lines.Add('[Event "' + PdnQuote(AEventName) + '"]')
    else
      Lines.Add('[Event "' + PdnQuote(AGameTree.EventName) + '"]');
    Lines.Add('[White "' + PdnQuote(AGameTree.WhiteName) + '"]');
    Lines.Add('[Black "' + PdnQuote(AGameTree.BlackName) + '"]');
    Lines.Add('[Result "' + PdnQuote(PdnExportResult(AGameTree.ResultText)) + '"]');
    if AGameTree.StartingFEN <> AGameTree.Variant.DefaultStartingFEN then Lines.Add('[SetUp "1"]');
    Lines.Add('[FEN "' + PdnQuote(AGameTree.StartingFEN) + '"]');
    end;
    Lines.Add('');
    ClearRenderResult(RenderResult);
    Value:=RenderMainline(AGameTree, AGameTree.ResultText,AOptions,False,RenderResult);
    if AOptions.FileFormat=gffPgn then Value:=WrapPgnMoves(Value);
    Lines.Text := Lines.Text + Value;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function GameTreeToPdnText(AGameTree: TGameTree): string;
begin
  Result := GameTreeToPdnTextEx(AGameTree, DefaultGameTreePdnRenderOptions);
end;

procedure RenderGameTreeMovesToPdn(AGameTree: TGameTree;
  const AOptions: TGameTreePdnRenderOptions;
  out ARenderResult: TGameTreePdnRenderResult);
begin
  ClearRenderResult(ARenderResult);
  if AGameTree = nil then
  begin
    ARenderResult.Text := '(none)';
    Exit;
  end;
  ARenderResult.Text := RenderMainline(AGameTree, AGameTree.ResultText,
    AOptions, True, ARenderResult);
  if Trim(ARenderResult.Text) = '' then
    ARenderResult.Text := '(none)';
end;

function ScoreAnnotationLine(const AEngineScore, AAnnotatorScore: string): string;
begin
  Result := '';
  if Trim(AEngineScore) <> '' then
    Result := 'E: ' + Trim(AEngineScore);
  if Trim(AAnnotatorScore) <> '' then
  begin
    if Result <> '' then
      Result += '; ';
    Result += 'A: ' + Trim(AAnnotatorScore);
  end;
end;

function GameTreeScoreAnnotationsText(AGameTree: TGameTree): string;
var
  I: Integer;
  LAnnotatorScore: string;
  LLine: string;
  LNode: TGameTreePlyNode;
  Lines: TStringList;
begin
  Result := '';
  if AGameTree = nil then
    Exit;

  Lines := TStringList.Create;
  try
    I := 1;
    while AGameTree.MainlineNode[I] <> nil do
    begin
      LNode := AGameTree.MainlineNode[I];
      LAnnotatorScore := LNode.AnnotatorScore;
      LLine := ScoreAnnotationLine(LNode.EngineScore, LAnnotatorScore);
      Lines.Add(LLine);
      Inc(I);
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.
