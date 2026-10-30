unit uAnalysisCoordinator;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, uGamePosition, uGameTree, uGameTreeActor, uGameTreeSearchRef,
  uGameOrchestrator, uPvSnapshot, uDisplayedPosition;
type
  // PV base positions are owned copies. Each belongs to the variant recorded
  // next to it; a tree of another game replaces it before a replay into it.
  TAnalysisPvState = class
  private
    FAnalyzerPvBase, FMainBase: TGamePosition;
    FAnalyzerPvBaseVariant, FMainBaseVariant: TGameVariant;
    FAnalyzerPvBaseNodeId: Int64;
    FAnalyzerPvBasePly: Integer;
    FPrincipalVariation, FPrincipalVariationScore, FPrincipalVariationDepth,
      FPrincipalVariationTimeText, FPvBasePositionKey: string;
    FPvBasePly: Integer;
  public
    // AVariant: the explicit game of the initial (start) positions.
    constructor Create(AVariant: TGameVariant);
    destructor Destroy; override;
    procedure SetAnalyzerBase(APosition: TGamePosition; APly: Integer);
    procedure SetAnalyzerBaseFromTree(AGameTree: TGameTree; ANodeId: Int64;
      AFallbackBasePly: Integer; AFallbackPosition: TGamePosition;
      ADisplay: TDisplayedPosition; ARevision: Int64);
    // The main base becomes ANode's position, or a copy of AFallback.
    procedure SetMainBaseFromNode(ADisplay: TDisplayedPosition; ATree: TGameTree;
      ANode: TGameTreePlyNode; ARevision: Int64; AFallback: TGamePosition);
    function VisibleMainPv(ATree: TGameTree; ANode: TGameTreePlyNode;
      AUseLatest: Boolean; ADisplay: TDisplayedPosition; ARevision: Int64;
      out ABasePosition: TGamePosition; out ABasePly: Integer;
      out APV, AScore, ADepth, ATimeText: string): Boolean;
    function CacheMatches(const APV, AScore, ADepth, ATimeText,
      ABasePositionKey: string; ABasePly: Integer): Boolean;
    procedure SetCache(const APV, AScore, ADepth, ATimeText,
      ABasePositionKey: string; ABasePly: Integer);
    // Stores the displayed PV tuple; True when it differs from the cached one.
    // Comparison and storage use the same key, so an unchanged tuple (also
    // "no PV") reports no change.
    function UpdateCache(const APV, AScore, ADepth, ATimeText,
      ABasePositionKey: string; ABasePly: Integer): Boolean;
    property AnalyzerBasePosition: TGamePosition read FAnalyzerPvBase;
    property AnalyzerBaseNodeId: Int64 read FAnalyzerPvBaseNodeId;
    property AnalyzerBasePly: Integer read FAnalyzerPvBasePly;
    property MainBasePosition: TGamePosition read FMainBase;
  end;

  TAutoPlayCoordinator = class
  private
    FActive: Boolean;
    FBasePly, FMoveCount: Integer;
    FTreeId, FNodeId: Int64;
    FSearch: TGameTreeSearchRef;
    // Optional outcome policy; the GUI enables it only for chess.
    FRules:TGameRules;
    FLinePosition:TGamePosition; // Owned current state, not a second history.
  public
    destructor Destroy;override;
    procedure BeginLine(ATree: TGameTree; ANode: TGameTreePlyNode;
      AStopsOnOutcome:Boolean=False);
    function TerminalReason(out AReason:string):Boolean;
    procedure Stop;
    procedure TrackSearch(const ASearch: TGameTreeSearchRef);
    procedure ClearSearch;
    function SearchMatches(const ASearch: TGameTreeSearchRef): Boolean;
    function CanContinue(ATree: TGameTree; AState: TGameOrchestratorState): Boolean;
    function CreateMoveCommand(AActor: TGameTreeActor; ATree: TGameTree;
      APosition: TGamePosition; const AMove: string;
      out AErrorText: string): TGameTreeCommand;
    procedure MoveStored(ACommand: TGameTreeCommand);
    property Active: Boolean read FActive;
    property Search: TGameTreeSearchRef read FSearch;
    property TreeId: Int64 read FTreeId;
    property NodeId: Int64 read FNodeId;
    property BasePly: Integer read FBasePly;
    property MoveCount: Integer read FMoveCount;
  end;

  TAnalysisPosition = record
    Tree: TGameTree;
    Node: TGameTreePlyNode;
    Position: TGamePosition; // Borrowed for this synchronous preparation only.
    Revision: Int64;
    StartingFEN, MovesText: string;
    MoveCount, BrowseBasePly: Integer;
    State: TGameOrchestratorState;
    Preview: Boolean;
  end;
  TAnalysisRequest = record
    StartingFEN, MovesText: string;
    BasePosition: TGamePosition; // Borrowed from coordinator; runners copy on posting.
    BasePly: Integer;
    Terminal, Transient: Boolean;
    Search: TGameTreeSearchRef;
  end;

  // Main-thread coordination only. Actors, trees, snapshots and runners are borrowed.
  TAnalysisCoordinator = class
  private
    FSearch: TGameTreeSearchRef;
    FPv: TAnalysisPvState;
    FAnalyzerSignature, FMctsSignature: string;
  public
    // AVariant: see TAnalysisPvState.Create.
    constructor Create(AVariant: TGameVariant);
    destructor Destroy; override;
    procedure TrackSearch(const ASearch: TGameTreeSearchRef);
    procedure ClearSearch;
    function SearchMatches(const ASearch: TGameTreeSearchRef): Boolean;
    procedure InvalidateAnalyzer;
    procedure InvalidateMcts;
    function RestartAnalyzerFor(const ASignature: string): Boolean;
    function RestartMctsFor(const ASignature: string): Boolean;
    procedure CancelTrackedSearch(AActor: TGameTreeActor);
    function PrepareAnalyzer(const APosition: TAnalysisPosition;
      APreviousActor: TGameTreeActor; ADisplay: TDisplayedPosition;
      out ARequest: TAnalysisRequest): Boolean;
    procedure StartRequestSearch(AActor: TGameTreeActor; ANode: TGameTreePlyNode;
      var ARequest: TAnalysisRequest);
    function PrepareMcts(const APosition: TAnalysisPosition;
      ADisplay: TDisplayedPosition; out ARequest: TAnalysisRequest): Boolean;
    property Pv: TAnalysisPvState read FPv;
    property Search: TGameTreeSearchRef read FSearch;
  end;
function PrepareAnalysisSnapshotCommand(AActor: TGameTreeActor;
  AFallbackTree: TGameTree; ASnapshot: TPvSnapshot;
  out ATree: TGameTree; AProtectDeeper:Boolean=False): TGameTreeCommand;
function CanDisplayTransientAnalysis(ASnapshot: TPvSnapshot;
  ACurrentBase: TGamePosition): Boolean;
function EnginePvForTree(AGameTree: TGameTree; APly: Integer;
  out APV, AScore, ADepth, ATimeText: string): Boolean;
function AnnotatorPvForTreeNode(AGameTree: TGameTree; ANodeId: Int64;
  out APV, AScore, ADepth, ATimeText: string): Boolean;
function LatestEnginePvForTree(AGameTree: TGameTree; out ABasePly: Integer;
  out APV, AScore, ADepth, ATimeText: string): Boolean;
function StartAnalysisSearch(AActor: TGameTreeActor; ANode: TGameTreePlyNode;
  out ASearch: TGameTreeSearchRef; out AErrorText: string): Boolean;
function AcceptSearchMove(AActor: TGameTreeActor; const ASearch: TGameTreeSearchRef;
  const AMoveText: string; out AErrorText: string): Boolean;
function CancelGameTreeSearch(AActor: TGameTreeActor; const ASearch: TGameTreeSearchRef): Boolean;
function ReleaseGameTreeSearch(AActor: TGameTreeActor; const ASearch: TGameTreeSearchRef): Boolean;
function ReleaseRejectedSearchIfFinished(AActor: TGameTreeActor;
  const ASearch: TGameTreeSearchRef): Boolean;
function ResolveActiveAnalysisSnapshot(AActor: TGameTreeActor; ASnapshot: TPvSnapshot;
  out AGameTree: TGameTree; out ANode: TGameTreePlyNode): Boolean;
function TryResolveAnalyzerSnapshotNode(AGameTree: TGameTree; ASnapshot: TPvSnapshot;
  out ANode: TGameTreePlyNode): Boolean;
function AnalyzerSnapshotIsTransient(ASnapshot: TPvSnapshot): Boolean;
function AnalysisSnapshotKey(ASnapshot: TPvSnapshot): string;
function DisplayedPositionSignature(AGameTree: TGameTree; ANodeId: Int64;
  const AStartingFEN, AMovesText: string; AGameState: TGameOrchestratorState): string;
function AnalysisPositionIsTerminal(AHasLegalMove, APreview: Boolean;
  ABrowseBasePly, ADisplayedMoveCount, ATotalMoveCount: Integer;
  AGameState: TGameOrchestratorState): Boolean;
implementation

// Replays ANode into APosition. APosition is replaced by a position of the
// tree's game first when it belongs to another game; otherwise it is unchanged
// on failure.
function BuildNodeBase(ADisplay: TDisplayedPosition; ATree: TGameTree;
  ANode: TGameTreePlyNode; ARevision: Int64; var APosition: TGamePosition;
  var AVariant: TGameVariant): Boolean;
begin
  Result := False;
  if (ADisplay = nil) or (ATree = nil) or (ANode = nil) then
    Exit;
  if (APosition = nil) or (AVariant <> ATree.Variant) then
  begin
    FreeAndNil(APosition);
    AVariant := ATree.Variant;
    APosition := AVariant.CreatePosition;
  end;
  Result := ADisplay.TryBuildNodePosition(ATree, ANode, ARevision, APosition);
end;

// Copies ASource; forgets the recorded game when the copy changes class.
procedure CopyBase(var APosition: TGamePosition; var AVariant: TGameVariant;
  ASource: TGamePosition);
begin
  if ASource = nil then
    Exit;
  if (APosition = nil) or (APosition.ClassType <> ASource.ClassType) then
    AVariant := nil;
  AssignGamePosition(APosition, ASource);
end;
function ExecuteAnalysisCommand(AActor: TGameTreeActor; ACommand: TGameTreeCommand;
  out AErrorText: string): Boolean;
begin
  AErrorText := '';
  Result := False;
  if (AActor = nil) or (ACommand = nil) then
  begin AErrorText := 'game tree command is unavailable'; Exit; end;
  AActor.ExecuteCommand(ACommand);
  Result := ACommand.Accepted;
  if not Result then AErrorText := ACommand.ErrorText;
end;
function StartAnalysisSearch(AActor: TGameTreeActor; ANode: TGameTreePlyNode;
  out ASearch: TGameTreeSearchRef; out AErrorText: string): Boolean;
var Command: TGameTreeCommand;
begin
  ASearch := EmptyGameTreeSearchRef;
  AErrorText := '';
  Result := False;
  if (AActor = nil) or (ANode = nil) then
  begin AErrorText := 'no game-tree node'; Exit; end;
  Command := AActor.CreateStartSearchCommand(ANode.NodeId, ASearch);
  try
    Result := ExecuteAnalysisCommand(AActor, Command, AErrorText);
    if not Result then ASearch := EmptyGameTreeSearchRef;
  finally Command.Free; end;
end;
procedure TAnalysisCoordinator.TrackSearch(const ASearch: TGameTreeSearchRef);
begin
  if not IsValidGameTreeSearchRef(ASearch) then ClearSearch
  else FSearch := ASearch;
end;
procedure TAnalysisCoordinator.ClearSearch;
begin FSearch := EmptyGameTreeSearchRef; end;
function TAnalysisCoordinator.SearchMatches(const ASearch: TGameTreeSearchRef): Boolean;
begin
  Result := IsValidGameTreeSearchRef(ASearch) and SameGameTreeSearchRef(FSearch, ASearch);
end;
procedure TAnalysisCoordinator.InvalidateAnalyzer;
begin FAnalyzerSignature := ''; end;
procedure TAnalysisCoordinator.InvalidateMcts;
begin FMctsSignature := ''; end;
function TAnalysisCoordinator.RestartAnalyzerFor(const ASignature: string): Boolean;
begin
  Result := ASignature <> FAnalyzerSignature;
  if Result then FAnalyzerSignature := ASignature;
end;
function TAnalysisCoordinator.RestartMctsFor(const ASignature: string): Boolean;
begin
  Result := ASignature <> FMctsSignature;
  if Result then FMctsSignature := ASignature;
end;
function AnalyzerSnapshotIsTransient(ASnapshot: TPvSnapshot): Boolean;
begin Result := (ASnapshot <> nil) and ASnapshot.Transient; end;
function AnalysisSnapshotKey(ASnapshot: TPvSnapshot): string;
var Search: TGameTreeSearchRef;
begin
  Result := '';
  if ASnapshot = nil then Exit;
  Search := ASnapshot.SearchRef;
  if IsValidGameTreeSearchRef(Search) then
    Result := 'search:' + IntToStr(Search.GameTreeId) + ':' +
      IntToStr(Search.SearchId) + ':' + IntToStr(Search.NodeId)
  else Result := 'display';
end;
function AnalysisPositionIsTerminal(AHasLegalMove, APreview: Boolean;
  ABrowseBasePly, ADisplayedMoveCount, ATotalMoveCount: Integer;
  AGameState: TGameOrchestratorState): Boolean;
begin
  Result := (not AHasLegalMove) or
    ((not APreview) and (AGameState = gosGameOver) and
      ((ABrowseBasePly < 0) or (ADisplayedMoveCount >= ATotalMoveCount)));
end;
function AcceptSearchMove(AActor: TGameTreeActor;
  const ASearch: TGameTreeSearchRef; const AMoveText: string;
  out AErrorText: string): Boolean;
var
  Command: TGameTreeCommand;
begin
  Result := False;
  AErrorText := '';
  if (AActor = nil) or (not IsValidGameTreeSearchRef(ASearch)) then
  begin
    AErrorText := 'invalid search';
    Exit;
  end;

  Command := AActor.CreateSearchDoneCommand(ASearch, AMoveText);
  try
    Result := ExecuteAnalysisCommand(AActor, Command, AErrorText);
  finally
    Command.Free;
  end;
end;

function CancelGameTreeSearch(AActor: TGameTreeActor;
  const ASearch: TGameTreeSearchRef): Boolean;
var
  Command: TGameTreeCommand;
  LErrorText: string;
begin
  Result := False;
  if (AActor = nil) or (not IsValidGameTreeSearchRef(ASearch)) then
    Exit;

  Command := AActor.CreateCancelSearchCommand(ASearch);
  try
    Result := ExecuteAnalysisCommand(AActor, Command, LErrorText);
  finally
    Command.Free;
  end;
end;

function ReleaseGameTreeSearch(AActor: TGameTreeActor;
  const ASearch: TGameTreeSearchRef): Boolean;
var
  Command: TGameTreeCommand;
begin
  Result := False;
  if (AActor = nil) or (not IsValidGameTreeSearchRef(ASearch)) then
    Exit;

  Command := AActor.CreateReleaseSearchCommand(ASearch);
  try
    Result := AActor.PostCommand(Command);
    Command := nil;
  finally
    Command.Free;
  end;
end;

function ReleaseRejectedSearchIfFinished(AActor: TGameTreeActor;
  const ASearch: TGameTreeSearchRef): Boolean;
var
  LSearchState: TGameTreeSearchState;
begin
  Result := False;
  if (AActor = nil) or (not IsValidGameTreeSearchRef(ASearch)) then
    Exit;
  if AActor.SearchState(ASearch, LSearchState) and
    (LSearchState in [gssCancelled, gssFailed]) then
    Result := ReleaseGameTreeSearch(AActor, ASearch);
end;
function ResolveActiveAnalysisSnapshot(AActor: TGameTreeActor; ASnapshot: TPvSnapshot; out AGameTree: TGameTree;
  out ANode: TGameTreePlyNode): Boolean;
var
  LSearch: TGameTreeSearchRef;
  LSearchState: TGameTreeSearchState;
begin
  Result := False;
  AGameTree := nil;
  ANode := nil;
  if ASnapshot = nil then
    LSearch := EmptyGameTreeSearchRef
  else
    LSearch := ASnapshot.SearchRef;
  if not IsValidGameTreeSearchRef(LSearch) then
    Exit;

  if (AActor = nil) or (AActor.GameTree.GameTreeId <> LSearch.GameTreeId) then
    Exit;
  if (not AActor.SearchState(LSearch, LSearchState)) or
    (LSearchState <> gssActive) then
  begin
    Exit;
  end;
  ANode := AActor.GameTree.FindNodeById(LSearch.NodeId);
  if ANode = nil then
  begin
    AGameTree := nil;
    Exit;
  end;

  AGameTree := AActor.GameTree;
  Result := AGameTree <> nil;
end;
function TryResolveAnalyzerSnapshotNode(AGameTree: TGameTree;
  ASnapshot: TPvSnapshot; out ANode: TGameTreePlyNode): Boolean;
var
  LSearch: TGameTreeSearchRef;
begin
  Result := False;
  ANode := nil;
  if (AGameTree = nil) or (ASnapshot = nil) then
    Exit;

  LSearch := ASnapshot.SearchRef;
  if IsValidGameTreeSearchRef(LSearch) and
    (LSearch.GameTreeId = AGameTree.GameTreeId) and (LSearch.NodeId > 0) then
    ANode := AGameTree.FindNodeById(LSearch.NodeId);

  if ANode = nil then
  begin
    if ASnapshot.BasePly <= 0 then
      ANode := AGameTree.Root
    else
      ANode := AGameTree.MainlineNode[ASnapshot.BasePly];
  end;

  Result := ANode <> nil;
end;
function DisplayedPositionSignature(AGameTree: TGameTree;
  ANodeId: Int64; const AStartingFEN, AMovesText: string;
  AGameState: TGameOrchestratorState): string;
var
  LGameTreeId: Int64;
begin
  LGameTreeId := 0;
  if AGameTree <> nil then
    LGameTreeId := AGameTree.GameTreeId;
  Result := IntToStr(LGameTreeId) + #10 + IntToStr(ANodeId) + #10 +
    AStartingFEN + #10 + AMovesText + #10 +
    IntToStr(Ord(AGameState));
end;
destructor TAutoPlayCoordinator.Destroy;
begin Stop;inherited Destroy;end;
procedure TAutoPlayCoordinator.BeginLine(ATree: TGameTree; ANode: TGameTreePlyNode;
  AStopsOnOutcome:Boolean);
var Moves:TStringList;After:TGamePosition;I:Integer;
begin
  Stop;
  if AStopsOnOutcome then begin
    Moves:=TStringList.Create;After:=nil;
    try
      try
        FLinePosition:=ATree.Variant.CreatePositionFromFEN(ATree.StartingFEN);
        FRules:=ATree.Variant.CreateRules;FRules.Reset(FLinePosition);
        if not ATree.CopyNodeMovesTo(ANode,Moves) then
          raise EGamePositionError.Create('Auto Play start node is no longer in the tree');
        // Seed once from the actual root-to-node path, including variations.
        After:=FLinePosition.Clone;
        for I:=0 to Moves.Count-1 do begin
          After.AssignFrom(FLinePosition);After.PlayMove(Moves[I]);
          FRules.MovePlayed(FLinePosition,Moves[I],After);
          FLinePosition.AssignFrom(After);
        end;
      except Stop;raise;end;
    finally After.Free;Moves.Free;end;
  end;
  FBasePly := ANode.PlyNumber;
  FNodeId := ANode.NodeId;
  FMoveCount := 0;
  FActive := True;
  FTreeId := ATree.GameTreeId;
  FSearch := EmptyGameTreeSearchRef;
end;
procedure TAutoPlayCoordinator.Stop;
begin
  FreeAndNil(FRules);FreeAndNil(FLinePosition);
  FActive := False;
  FSearch := EmptyGameTreeSearchRef;
  FTreeId := 0;
  FNodeId := 0;
end;
function TAutoPlayCoordinator.TerminalReason(out AReason:string):Boolean;
begin
  AReason:='';Result:=False;
  if FActive and (FRules<>nil) then
    Result:=FRules.Outcome(FLinePosition,AReason)<>goOngoing;
end;
procedure TAutoPlayCoordinator.TrackSearch(const ASearch: TGameTreeSearchRef);
begin FSearch := ASearch; end;
procedure TAutoPlayCoordinator.ClearSearch;
begin FSearch := EmptyGameTreeSearchRef; end;
function TAutoPlayCoordinator.SearchMatches(const ASearch: TGameTreeSearchRef): Boolean;
begin
  Result := FActive and IsValidGameTreeSearchRef(ASearch) and
    SameGameTreeSearchRef(FSearch, ASearch);
end;
function TAutoPlayCoordinator.CanContinue(ATree: TGameTree;
  AState: TGameOrchestratorState): Boolean;
begin
  Result := (ATree <> nil) and (ATree.GameTreeId = FTreeId) and (AState = gosStopped);
end;
function TAutoPlayCoordinator.CreateMoveCommand(AActor: TGameTreeActor;
  ATree: TGameTree; APosition: TGamePosition; const AMove: string;
  out AErrorText: string): TGameTreeCommand;
var Move: string; Node:TGameTreePlyNode;
begin
  Result := nil;
  AErrorText := '';
  if (ATree = nil) or (AActor = nil) or (ATree.GameTreeId <> FTreeId) then
  begin AErrorText := 'game tree is no longer active'; Exit; end;
  if (APosition = nil) or not APosition.TryParseMove(AMove, Move) then
  begin AErrorText := 'engine returned an illegal move: ' + Trim(AMove); Exit; end;
  Node:=ATree.FindNodeById(FNodeId);
  if Node=nil then begin AErrorText:='Auto Play node is no longer in the tree';Exit;end;
  if (ATree.FindChildByMove(Node,Move)=nil) and
    (((ATree.MainlineCount=0) and (Node=ATree.Root)) or
     ((ATree.MainlineCount>0) and (Node=ATree.MainlineNode[ATree.MainlineCount]))) then
    Result:=AActor.CreateAppendMainlineMoveCommand(Move,gmsUnknown)
  else Result:=AActor.CreateStoreMoveVariationCommand(FNodeId,Move,gmsUnknown);
end;
procedure TAutoPlayCoordinator.MoveStored(ACommand: TGameTreeCommand);
var After:TGamePosition;Move:string;
begin
  // Advance only after the existing actor has accepted a real move.
  if (ACommand = nil) or not ACommand.Accepted then Exit;
  if FRules<>nil then begin
    Move:=ACommand.MoveText;
    After:=FLinePosition.Clone;
    try
      After.PlayMove(Move);FRules.MovePlayed(FLinePosition,Move,After);
      FLinePosition.AssignFrom(After);
    finally After.Free;end;
  end;
  FNodeId:=ACommand.CreatedNodeId;
  Inc(FMoveCount);
end;

constructor TAnalysisCoordinator.Create(AVariant: TGameVariant);
begin
  inherited Create;
  FPv := TAnalysisPvState.Create(AVariant);
end;
destructor TAnalysisCoordinator.Destroy;
begin
  FPv.Free;
  inherited Destroy;
end;
constructor TAnalysisPvState.Create(AVariant: TGameVariant);
begin
  inherited Create;
  if AVariant = nil then
    raise EGamePositionError.Create('Missing game variant');
  FAnalyzerPvBaseVariant := AVariant;
  FMainBaseVariant := AVariant;
  FAnalyzerPvBase := AVariant.CreatePosition;
  FMainBase := AVariant.CreatePosition;
end;
destructor TAnalysisPvState.Destroy;
begin
  FMainBase.Free;
  FAnalyzerPvBase.Free;
  inherited Destroy;
end;
procedure TAnalysisPvState.SetAnalyzerBase(APosition: TGamePosition; APly: Integer);
begin
  CopyBase(FAnalyzerPvBase, FAnalyzerPvBaseVariant, APosition);
  FAnalyzerPvBaseNodeId := 0;
  FAnalyzerPvBasePly := APly;
end;

procedure TAnalysisPvState.SetAnalyzerBaseFromTree(AGameTree: TGameTree;
  ANodeId: Int64; AFallbackBasePly: Integer; AFallbackPosition: TGamePosition;
  ADisplay: TDisplayedPosition; ARevision: Int64);
var
  LNode, FallbackNode: TGameTreePlyNode;
begin
  LNode := nil;
  if (AGameTree <> nil) and (ANodeId > 0) then
    LNode := AGameTree.FindNodeById(ANodeId);

  if (LNode <> nil) and BuildNodeBase(ADisplay, AGameTree, LNode, ARevision,
    FAnalyzerPvBase, FAnalyzerPvBaseVariant) then
  begin
    FAnalyzerPvBaseNodeId := LNode.NodeId;
    FAnalyzerPvBasePly := LNode.PlyNumber;
    Exit;
  end;

  FallbackNode := nil;
  if AGameTree <> nil then
    if AFallbackBasePly = 0 then FallbackNode := AGameTree.Root
    else if AFallbackBasePly > 0 then FallbackNode := AGameTree.MainlineNode[AFallbackBasePly];
  if (FallbackNode <> nil) and BuildNodeBase(ADisplay, AGameTree, FallbackNode,
    ARevision, FAnalyzerPvBase, FAnalyzerPvBaseVariant) then
  begin
    FAnalyzerPvBaseNodeId := 0;
    FAnalyzerPvBasePly := AFallbackBasePly;
    Exit;
  end;

  SetAnalyzerBase(AFallbackPosition, AFallbackBasePly);
end;
procedure TAnalysisPvState.SetMainBaseFromNode(ADisplay: TDisplayedPosition;
  ATree: TGameTree; ANode: TGameTreePlyNode; ARevision: Int64;
  AFallback: TGamePosition);
begin
  if not BuildNodeBase(ADisplay, ATree, ANode, ARevision, FMainBase, FMainBaseVariant) then
    CopyBase(FMainBase, FMainBaseVariant, AFallback);
end;
function TAnalysisPvState.CacheMatches(const APV, AScore, ADepth,
  ATimeText, ABasePositionKey: string; ABasePly: Integer): Boolean;
begin
  Result := (FPrincipalVariation = APV) and
    (FPrincipalVariationScore = AScore) and
    (FPrincipalVariationDepth = ADepth) and
    (FPrincipalVariationTimeText = ATimeText) and
    (FPvBasePly = ABasePly) and
    (FPvBasePositionKey = ABasePositionKey);
end;

procedure TAnalysisPvState.SetCache(const APV, AScore, ADepth,
  ATimeText, ABasePositionKey: string; ABasePly: Integer);
begin
  FPrincipalVariation := APV;
  FPrincipalVariationScore := AScore;
  FPrincipalVariationDepth := ADepth;
  FPrincipalVariationTimeText := ATimeText;
  FPvBasePositionKey := ABasePositionKey;
  FPvBasePly := ABasePly;
end;
function TAnalysisPvState.UpdateCache(const APV, AScore, ADepth, ATimeText,
  ABasePositionKey: string; ABasePly: Integer): Boolean;
begin
  Result := not CacheMatches(APV, AScore, ADepth, ATimeText, ABasePositionKey,
    ABasePly);
  if Result then
    SetCache(APV, AScore, ADepth, ATimeText, ABasePositionKey, ABasePly);
end;
function EnginePvForTree(AGameTree: TGameTree; APly: Integer;
  out APV, AScore, ADepth, ATimeText: string): Boolean;
var
  LNode: TGameTreePlyNode;
begin
  APV := '';
  AScore := '';
  ADepth := '';
  ATimeText := '';
  Result := False;
  if AGameTree = nil then
    Exit;

  if APly <= 0 then
    LNode := AGameTree.Root
  else
    LNode := AGameTree.MainlineNode[APly];
  if LNode = nil then
    Exit;

  APV := Trim(LNode.EnginePV);
  AScore := Trim(LNode.EngineScore);
  ADepth := Trim(LNode.EnginePVDepth);
  ATimeText := Trim(LNode.EnginePVTimeText);
  Result := APV <> '';
end;

function AnnotatorPvForTreeNode(AGameTree: TGameTree;
  ANodeId: Int64; out APV, AScore, ADepth, ATimeText: string): Boolean;
var
  LNode: TGameTreePlyNode;
begin
  APV := '';
  AScore := '';
  ADepth := '';
  ATimeText := '';
  Result := False;
  if (AGameTree = nil) or (ANodeId <= 0) then
    Exit;

  LNode := AGameTree.FindNodeById(ANodeId);
  if LNode = nil then
    Exit;

  APV := Trim(LNode.AnnotatorPV);
  AScore := Trim(LNode.AnnotatorScore);
  ADepth := Trim(LNode.AnnotatorPVDepth);
  ATimeText := Trim(LNode.AnnotatorPVTimeText);
  Result := APV <> '';
end;

function LatestEnginePvForTree(AGameTree: TGameTree;
  out ABasePly: Integer; out APV, AScore, ADepth, ATimeText: string): Boolean;
var
  Ply: Integer;
begin
  ABasePly := 0;
  APV := '';
  AScore := '';
  ADepth := '';
  ATimeText := '';
  Result := False;
  if AGameTree = nil then
    Exit;

  for Ply := AGameTree.MainlineCount downto 0 do
    if EnginePvForTree(AGameTree, Ply, APV, AScore, ADepth, ATimeText) then
    begin
      ABasePly := Ply;
      Exit(True);
    end;
end;

function AnalysisStartingFen(ATree: TGameTree): string;
begin
  Result := '';
  if ATree <> nil then Result := Trim(ATree.StartingFEN);
end;
function TAnalysisPvState.VisibleMainPv(ATree: TGameTree; ANode: TGameTreePlyNode;
  AUseLatest: Boolean; ADisplay: TDisplayedPosition; ARevision: Int64;
  out ABasePosition: TGamePosition; out ABasePly: Integer;
  out APV, AScore, ADepth, ATimeText: string): Boolean;
var BaseNode: TGameTreePlyNode;
  procedure LoadStart;
  begin
    if (ATree <> nil) and (ATree.Variant <> FMainBaseVariant) then
    begin
      FreeAndNil(FMainBase);
      FMainBaseVariant := ATree.Variant;
      FMainBase := FMainBaseVariant.CreatePosition;
    end;
    FMainBase.LoadFromFEN(AnalysisStartingFen(ATree));
  end;
begin
  APV := ''; AScore := ''; ADepth := ''; ATimeText := '';
  ABasePly := 0;
  if ANode <> nil then
  begin
    ABasePly := ANode.PlyNumber;
    if not BuildNodeBase(ADisplay, ATree, ANode, ARevision, FMainBase, FMainBaseVariant) then
    begin
      ABasePly := 0;
      LoadStart;
    end;
  end
  else LoadStart;
  ABasePosition := FMainBase;
  if AUseLatest and LatestEnginePvForTree(ATree, ABasePly, APV, AScore, ADepth, ATimeText) then
  begin
    if ABasePly = 0 then BaseNode := ATree.Root else BaseNode := ATree.MainlineNode[ABasePly];
    BuildNodeBase(ADisplay, ATree, BaseNode, ARevision, FMainBase, FMainBaseVariant);
    ABasePosition := FMainBase;
    Exit(True);
  end;
  Result := Trim(APV) <> '';
end;

procedure TAnalysisCoordinator.CancelTrackedSearch(AActor: TGameTreeActor);
begin
  if not IsValidGameTreeSearchRef(FSearch) then Exit;
  if CancelGameTreeSearch(AActor, FSearch) then ReleaseGameTreeSearch(AActor, FSearch);
  ClearSearch;
end;
function TAnalysisCoordinator.PrepareAnalyzer(const APosition: TAnalysisPosition;
  APreviousActor: TGameTreeActor; ADisplay: TDisplayedPosition;
  out ARequest: TAnalysisRequest): Boolean;
begin
  ARequest := Default(TAnalysisRequest);
  Result := False;
  if (APosition.Tree = nil) or (APosition.Node = nil) or (APosition.Position = nil) then Exit;
  if not RestartAnalyzerFor(DisplayedPositionSignature(APosition.Tree,
    APosition.Node.NodeId, APosition.StartingFEN, APosition.MovesText, APosition.State)) then Exit;
  CancelTrackedSearch(APreviousActor);
  if APosition.Preview then FPv.SetAnalyzerBase(APosition.Position, APosition.MoveCount)
  else FPv.SetAnalyzerBaseFromTree(APosition.Tree, APosition.Node.NodeId,
    APosition.MoveCount, APosition.Position, ADisplay, APosition.Revision);
  ARequest.StartingFEN := APosition.StartingFEN;
  ARequest.MovesText := APosition.MovesText;
  ARequest.BasePosition := FPv.AnalyzerBasePosition;
  ARequest.BasePly := FPv.AnalyzerBasePly;
  ARequest.Terminal := AnalysisPositionIsTerminal(APosition.Position.LegalMoveCount > 0,
    APosition.Preview, APosition.BrowseBasePly, APosition.MoveCount,
    APosition.Tree.MainlineCount, APosition.State);
  ARequest.Transient := APosition.Preview;
  Result := True;
end;
procedure TAnalysisCoordinator.StartRequestSearch(AActor: TGameTreeActor;
  ANode: TGameTreePlyNode; var ARequest: TAnalysisRequest);
var ErrorText: string;
begin
  if ARequest.Terminal or ARequest.Transient then Exit;
  if StartAnalysisSearch(AActor, ANode, ARequest.Search, ErrorText) then
    TrackSearch(ARequest.Search);
end;
function TAnalysisCoordinator.PrepareMcts(const APosition: TAnalysisPosition;
  ADisplay: TDisplayedPosition; out ARequest: TAnalysisRequest): Boolean;
begin
  ARequest := Default(TAnalysisRequest);
  Result := False;
  if (APosition.Tree = nil) or (APosition.Node = nil) or (APosition.Position = nil) then Exit;
  if not RestartMctsFor(DisplayedPositionSignature(APosition.Tree,
    APosition.Node.NodeId, APosition.StartingFEN, APosition.MovesText, APosition.State)) then Exit;
  ARequest.StartingFEN := APosition.StartingFEN;
  ARequest.MovesText := APosition.MovesText;
  ARequest.BasePly := APosition.MoveCount;
  ARequest.Terminal := AnalysisPositionIsTerminal(APosition.Position.LegalMoveCount > 0,
    APosition.Preview, APosition.BrowseBasePly, APosition.MoveCount,
    APosition.Tree.MainlineCount, APosition.State);
  FPv.SetMainBaseFromNode(ADisplay, APosition.Tree, APosition.Node,
    APosition.Revision, APosition.Position);
  ARequest.BasePosition := FPv.MainBasePosition;
  Result := True;
end;
function PrepareAnalysisSnapshotCommand(AActor: TGameTreeActor;
  AFallbackTree: TGameTree; ASnapshot: TPvSnapshot;
  out ATree: TGameTree; AProtectDeeper:Boolean=False): TGameTreeCommand;
var Node: TGameTreePlyNode;StoredDepth,NewDepth:Int64;
begin
  Result := nil;
  ATree := nil;
  if (ASnapshot = nil) or AnalyzerSnapshotIsTransient(ASnapshot) then Exit;
  if (Trim(ASnapshot.Score) = '') or (Trim(ASnapshot.PrincipalVariation) = '') then Exit;
  Node := nil;
  if IsValidGameTreeSearchRef(ASnapshot.SearchRef) then
  begin
    if not ResolveActiveAnalysisSnapshot(AActor, ASnapshot, ATree, Node) then Exit;
  end
  else ATree := AFallbackTree;
  if (ATree = nil) or (AActor = nil) then Exit;
  if (Node = nil) and not TryResolveAnalyzerSnapshotNode(ATree, ASnapshot, Node) then Exit;
  if AProtectDeeper then begin
    if not TryStrToInt64(ASnapshot.Depth,NewDepth) or (NewDepth<0) then NewDepth:=-1;
    if TryStrToInt64(Node.AnnotatorPVDepth,StoredDepth) and (StoredDepth>=0) and
      (StoredDepth>NewDepth) then Exit;
  end;
  Result := AActor.CreateRecordAnnotatorPVCommand(Node.NodeId, ASnapshot.Score,
    ASnapshot.PrincipalVariation, ASnapshot.Depth, ASnapshot.TimeText);
end;
function CanDisplayTransientAnalysis(ASnapshot: TPvSnapshot;
  ACurrentBase: TGamePosition): Boolean;
begin
  Result := (ASnapshot <> nil) and (ACurrentBase <> nil) and
    (ASnapshot.BasePosition <> nil) and
    (ASnapshot.BasePosition.PositionKey = ACurrentBase.PositionKey);
end;

end.
