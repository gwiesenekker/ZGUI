program analysis_coordinator_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, uAnalysisCoordinator,
  uGameTree, uGameTreeActor, uGameTreeSearchRef, uGameOrchestrator,
  uGamePosition, uPvSnapshot, uTreeTestUtils, uDisplayedPosition, uDraughtsPosition, uChessPosition, uChessPgn;
procedure Check(Value: Boolean; const Text: string);
begin if not Value then raise Exception.Create(Text); end;
procedure Execute(Actor: TGameTreeActor; Command: TGameTreeCommand);
begin
  try Actor.ExecuteCommand(Command); Check(Command.Accepted, Command.ErrorText);
  finally Command.Free; end;
end;
procedure CheckPvState;
var Actor: TGameTreeActor; Pv: TAnalysisPvState; Display: TDisplayedPosition;
  Board, Visible: TGamePosition; Node: TGameTreePlyNode;
  BasePly: Integer; Text, Score, Depth, TimeText, Key: string;
begin
  Actor := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True); Pv := TAnalysisPvState.Create(DefaultGameVariant);
  Display := TDisplayedPosition.Create; Board := DraughtsVariant.CreatePosition;
  try
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('32-28', gmsHuman));
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('18-23', gmsHuman));
    Execute(Actor, ImportBranch(Actor, 1, '20-24 38-32 18-22', '', gmsHuman));
    Node := Actor.GameTree.FindBranchNode(0, 3);
    Check(Actor.GameTree.TryBuildPositionAtNode(Node, Board), 'PV nested board');
    Key := Board.PositionKey;
    Pv.SetAnalyzerBaseFromTree(Actor.GameTree, Node.NodeId, 1, nil, Display, Actor.Revision);
    Check((Pv.AnalyzerBaseNodeId = Node.NodeId) and (Pv.AnalyzerBasePly = Node.PlyNumber) and
      (Pv.AnalyzerBasePosition.PositionKey = Key), 'analyzer base follows nested node, not fallback ply');
    Pv.SetAnalyzerBase(Board, 99);
    Board.LoadFromFEN(DraughtsVariant.DefaultStartingFEN);
    Check((Pv.AnalyzerBaseNodeId = 0) and (Pv.AnalyzerBasePly = 99) and
      (Pv.AnalyzerBasePosition.PositionKey = Key), 'transient base copies board and clears persistent identity');
    Pv.SetAnalyzerBase(nil, 98);
    Check(Pv.AnalyzerBasePosition.PositionKey = Key, 'nil base preserves last board');
    Pv.SetAnalyzerBaseFromTree(Actor.GameTree, High(Int64), 1, nil, Display, Actor.Revision);
    Check(Actor.GameTree.TryBuildPositionAtNode(Actor.GameTree.MainlineNode[1], Board), 'fallback board');
    Check((Pv.AnalyzerBaseNodeId = 0) and (Pv.AnalyzerBasePly = 1) and
      (Pv.AnalyzerBasePosition.PositionKey = Board.PositionKey), 'missing node falls back to mainline base');
    Pv.SetAnalyzerBaseFromTree(nil, 0, -1, Board, Display, -1);
    Check((Pv.AnalyzerBasePly = -1) and (Pv.AnalyzerBaseNodeId = 0), 'unavailable tree uses supplied board');
    Execute(Actor, Actor.CreateRecordEnginePVCommand(Actor.GameTree.MainlineNode[2].NodeId,
      '0.25', '37-32 12-18', '8', '0.4'));
    Check(Pv.VisibleMainPv(Actor.GameTree, Actor.GameTree.Root, True, Display,
      Actor.Revision, Visible, BasePly, Text, Score, Depth, TimeText), 'visible latest engine PV');
    Check((BasePly = 2) and (Text = '37-32 12-18') and (Score = '0.25') and
      (Depth = '8') and (TimeText = '0.4'), 'historical display retains latest-engine-PV policy');
    Check(Actor.GameTree.TryBuildPositionAtNode(Actor.GameTree.MainlineNode[2], Board), 'latest PV base board');
    Check(Visible.PositionKey = Board.PositionKey, 'visible PV replays its actual mainline base');
    Check(not Pv.VisibleMainPv(Actor.GameTree, Node, False, Display, Actor.Revision,
      Visible, BasePly, Text, Score, Depth, TimeText) and (Text = '') and
      (BasePly = Node.PlyNumber), 'unavailable engine source leaves selected board without PV');
    Key := Visible.PositionKey;
    Pv.SetCache('12-18', '0.2', '9', '0.1', Visible.PositionKey, BasePly);
    Check(Pv.CacheMatches('12-18', '0.2', '9', '0.1', Key, BasePly), 'cache matches full display tuple');
    Check(not Pv.CacheMatches('12-18', '0.2', '10', '0.1', Key, BasePly), 'depth change invalidates PV cache');
    Check(not Pv.CacheMatches('12-18', '0.2', '9', '0.1', Key, BasePly + 1), 'base ply change invalidates PV cache');
    Check(not Pv.CacheMatches('12-18', '0.2', '9', '0.1', 'other position', BasePly), 'board identity change invalidates PV cache');
    Pv.SetCache('', '', '', '', '', 0);
    Check(Pv.CacheMatches('', '', '', '', '', 0), 'clear resets tuple including board key');
    // No visible PV: the form passes an empty key; a second update is no change.
    Pv.SetCache('', '', '', '', Visible.PositionKey, 0);
    Check(Pv.UpdateCache('', '', '', '', '', 0), 'switching to no PV is a change');
    Check(not Pv.UpdateCache('', '', '', '', '', 0), 'no PV twice is not a change');
    Check(Pv.UpdateCache('12-18', '0.2', '9', '0.1', Key, 3), 'new PV is a change');
    Check(not Pv.UpdateCache('12-18', '0.2', '9', '0.1', Key, 3), 'same PV is not a change');
  finally Board.Free; Display.Free; Pv.Free; Actor.Free; end;
end;

procedure CheckAutoPlay;
var Actor, Other: TGameTreeActor; AutoPlay: TAutoPlayCoordinator;
  Board: TGamePosition; Command: TGameTreeCommand; Search: TGameTreeSearchRef;
  Node: TGameTreePlyNode; ErrorText: string;
begin
  Actor := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True); Other := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True);
  AutoPlay := TAutoPlayCoordinator.Create; Board := DraughtsVariant.CreatePosition;
  try
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('32-28', gmsHuman));
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('18-23', gmsHuman));
    Node := Actor.GameTree.MainlineNode[1];
    Check(Actor.GameTree.TryBuildPositionAtNode(Node, Board), 'historical Auto Play board');
    AutoPlay.BeginLine(Actor.GameTree,Node);
    Command:=AutoPlay.CreateMoveCommand(Actor,Actor.GameTree,Board,'18-23',ErrorText);
    Check(Command<>nil,ErrorText);
    try Actor.ExecuteCommand(Command);Check(Command.Accepted,Command.ErrorText);AutoPlay.MoveStored(Command);
    finally Command.Free;end;
    Check((AutoPlay.NodeId=Actor.GameTree.MainlineNode[2].NodeId) and
      (Actor.GameTree.MainlineCount=2),'Matching existing child is followed without duplication');
    AutoPlay.BeginLine(Actor.GameTree, Node);
    Check(AutoPlay.Active and (AutoPlay.BasePly = 1) and (AutoPlay.NodeId = Node.NodeId) and
      (AutoPlay.MoveCount = 0), 'start resets temporary line at selected node');
    Check(AutoPlay.CanContinue(Actor.GameTree, gosStopped), 'same stopped tree can continue');
    Check(not AutoPlay.CanContinue(Other.GameTree, gosStopped), 'different selected game cannot continue');
    Check(not AutoPlay.CanContinue(Actor.GameTree, gosRunning), 'resumed game cannot continue');
    Check(StartAnalysisSearch(Actor, Node, Search, ErrorText), ErrorText);
    AutoPlay.TrackSearch(Search);
    Check(AutoPlay.SearchMatches(Search), 'Auto Play tracks one-shot identity');
    Command := AutoPlay.CreateMoveCommand(Actor, Actor.GameTree, Board, '20-24', ErrorText);
    Check(Command <> nil, ErrorText);
    try
      Check((AutoPlay.MoveCount = 0) and (Node.AutoPlayPV = ''), 'preparing move changes neither preview nor tree');
      Actor.ExecuteCommand(Command); Check(Command.Accepted, Command.ErrorText);
      AutoPlay.MoveStored(Command);
    finally Command.Free; end;
    Check((AutoPlay.MoveCount = 1) and
      (Actor.GameTree.FindNodeById(AutoPlay.NodeId).MoveText='20-24') and (Node.AutoPlayPV=''), 'accepted move follows an actual variation node without changing legacy PV');
    Check((Actor.GameTree.MainlineCount = 2) and
      (Actor.GameTree.MainlineNode[2].MoveText = '18-23'), 'official continuation preserved');
    Board.PlayMove('20-24');
    Command := AutoPlay.CreateMoveCommand(Actor, Actor.GameTree, Board, '38-32', ErrorText);
    Check(Command <> nil, ErrorText);
    try
      Actor.ExecuteCommand(Command); Check(Command.Accepted, Command.ErrorText);
      AutoPlay.MoveStored(Command);
    finally Command.Free; end;
    Check((AutoPlay.MoveCount = 2) and (Actor.GameTree.FindNodeById(AutoPlay.NodeId).MoveText='38-32'), 'subsequent move extends PV in order');
    Command := AutoPlay.CreateMoveCommand(Actor, Actor.GameTree, Board, '1-50', ErrorText);
    Check((Command = nil) and (Pos('illegal move', ErrorText) > 0), 'illegal engine move creates no command');
    Check(AutoPlay.MoveCount = 2, 'illegal engine move does not advance preview');
    Command := AutoPlay.CreateMoveCommand(Actor, Other.GameTree, Board, '38-32', ErrorText);
    Check((Command = nil) and (ErrorText = 'game tree is no longer active'), 'wrong tree cannot receive Auto Play');
    Command := AutoPlay.CreateMoveCommand(Actor, Actor.GameTree, Board, '38-32', ErrorText);
    Check(Command <> nil, ErrorText);
    try
      Command.NodeId := High(Int64); // Simulate a target removed before delivery.
      Actor.ExecuteCommand(Command); Check(not Command.Accepted, 'actor rejects a missing PV target');
      AutoPlay.MoveStored(Command);
    finally Command.Free; end;
    Check((AutoPlay.MoveCount = 2) and (Node.AutoPlayPV = ''), 'rejected actor command preserves state and PV');
    AutoPlay.ClearSearch;
    Check(not AutoPlay.SearchMatches(Search), 'consumed search cannot match again');
    AutoPlay.TrackSearch(Search); AutoPlay.Stop;
    Check(not AutoPlay.Active and not AutoPlay.SearchMatches(Search) and
      (AutoPlay.TreeId = 0) and (AutoPlay.NodeId = 0), 'stopping fences late results');
    AutoPlay.BeginLine(Actor.GameTree, Actor.GameTree.Root);
    Check((AutoPlay.MoveCount = 0), 'new run discards previous temporary line');
  finally Board.Free; AutoPlay.Free; Other.Free; Actor.Free; end;
end;

procedure CheckChessAutoPlay;
var V:TChessVariant;Actor:TGameTreeActor;AutoPlay:TAutoPlayCoordinator;
  P:TGamePosition;Node:TGameTreePlyNode;C:TGameTreeCommand;
  Words:TStringList;Reason,Text:string;I:Integer;
  procedure ExpectStart(const Fen,Expected:string);
  begin
    ImportChessPgn('[SetUp "1"] [FEN "'+Fen+'"] *',Actor,nil);
    AutoPlay.BeginLine(Actor.GameTree,Actor.GameTree.Root,True);
    Check(AutoPlay.TerminalReason(Reason) and (Pos(Expected,Reason)>0),
      'Chess Auto Play start outcome '+Expected+': '+Reason);
    Check((AutoPlay.MoveCount=0) and (Actor.GameTree.Root.AutoPlayPV='') and
      (Actor.GameTree.ResultText='*'),'Terminal start changes neither PV nor game result');
  end;
begin
  V:=TChessVariant.Create;Actor:=TGameTreeActor.Create(TGameTree.Create(V),True);
  AutoPlay:=TAutoPlayCoordinator.Create;Words:=TStringList.Create;P:=V.CreatePosition;
  try
    ExpectStart('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1','checkmate');
    ExpectStart('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1','stalemate');
    ExpectStart('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1','insufficient mating material');
    ExpectStart('7k/8/6K1/8/8/8/8/R7 w - - 150 1','75-move');
    ExpectStart('7k/8/6K1/8/8/8/8/R7 w - - 100 1','50-move');
    ExpectStart('7k/8/6K1/8/8/8/8/R7 w - - 99 1','intended 50-move');
    // Feed the whole historical path, even when it is on a variation.
    ImportChessPgn('1.e4 (1.Nf3 Nf6 2.Ng1 Ng8 3.Nf3 Nf6 4.Ng1 Ng8) e5 *',Actor,nil);
    Node:=Actor.GameTree.Root.Children[1];while Node.ChildCount>0 do Node:=Node.Children[0];
    AutoPlay.BeginLine(Actor.GameTree,Node,True);
    Check(AutoPlay.TerminalReason(Reason) and (Pos('threefold repetition',Reason)>0),
      'Variation-node history is seeded from the root: '+Reason);
    Check((AutoPlay.NodeId=Node.NodeId) and (AutoPlay.BasePly=8),'Variation source identity retained');
    Text:='';for I:=1 to 4 do Text+='Nf3 Nf6 Ng1 Ng8 ';
    ImportChessPgn(Text+'*',Actor,nil);
    AutoPlay.BeginLine(Actor.GameTree,Actor.GameTree.MainlineNode[16],True);
    Check(AutoPlay.TerminalReason(Reason) and (Pos('fivefold',Reason)>0),'Fivefold history at a mainline start');
    ImportChessPgn('*',Actor,nil);AutoPlay.BeginLine(Actor.GameTree,Actor.GameTree.Root,True);
    Check(not AutoPlay.TerminalReason(Reason),'New line clears previous draw history');
    P.LoadFromFEN(ChessStartingFEN);
    ExtractStrings([' '],[],PChar('g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1'),Words);
    for I:=0 to Words.Count-1 do begin
      C:=AutoPlay.CreateMoveCommand(Actor,Actor.GameTree,P,Words[I],Reason);
      Check(C<>nil,Reason);
      try Actor.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);AutoPlay.MoveStored(C);finally C.Free;end;
      P.PlayMove(Words[I]);
      if I<Words.Count-1 then Check(not AutoPlay.TerminalReason(Reason),'Repetition does not stop early')
      else Check(AutoPlay.TerminalReason(Reason) and (Pos('intended threefold',Reason)>0),
        'Stored Auto Play moves update repetition history: '+Reason);
    end;
    Check((AutoPlay.MoveCount=7) and (Actor.GameTree.MainlineCount=7) and
      (Actor.GameTree.Root.ChildCount=1) and (Actor.GameTree.ResultText='*'),
      'Rule stopping retains real analysis moves without setting the result');
    AutoPlay.Stop;Check(not AutoPlay.TerminalReason(Reason),'Stopped line releases rules');
    ImportChessPgn('[SetUp "1"] [FEN "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1"] *',Actor,nil);
    AutoPlay.BeginLine(Actor.GameTree,Actor.GameTree.Root,True);
    P.LoadFromFEN(Actor.GameTree.StartingFEN);
    Check(not AutoPlay.TerminalReason(Reason),'Mate-in-one position is ongoing');
    C:=AutoPlay.CreateMoveCommand(Actor,Actor.GameTree,P,'f7g7',Reason);
    Check(C<>nil,Reason);
    try Actor.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);AutoPlay.MoveStored(C);finally C.Free;end;
    Check(AutoPlay.TerminalReason(Reason) and (Reason='checkmate'),'Stored mating move stops Auto Play');
    Check((Actor.GameTree.Root.AutoPlayPV='') and (Actor.GameTree.MainlineCount=1) and
      (Actor.GameTree.MainlineNode[1].MoveText='f7g7') and
      (Actor.GameTree.ResultText='*'),'Mating analysis move preserves the played tree and result');

  finally P.Free;Words.Free;AutoPlay.Free;Actor.Free;V.Free;end;
end;

procedure CheckRequestsAndSnapshots;
var Actor, Previous: TGameTreeActor; Coordinator: TAnalysisCoordinator;
  Display: TDisplayedPosition; Board, OtherBoard: TGamePosition;
  Position: TAnalysisPosition; Request, Mcts: TAnalysisRequest;
  OldSearch: TGameTreeSearchRef; State: TGameTreeSearchState;
  Snapshot: TPvSnapshot; Command: TGameTreeCommand; Tree: TGameTree;
  ErrorText, Key: string;
begin
  Actor := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True); Previous := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True);
  Coordinator := TAnalysisCoordinator.Create(DefaultGameVariant); Display := TDisplayedPosition.Create;
  Board := DraughtsVariant.CreatePosition; OtherBoard := DraughtsVariant.CreatePosition;
  Snapshot := TPvSnapshot.Create;
  try
    Position := Default(TAnalysisPosition);
    Check(not Coordinator.PrepareAnalyzer(Position, nil, Display, Request), 'missing analysis position rejected');
    Position.Tree := Actor.GameTree; Position.Node := Actor.GameTree.Root;
    Position.Position := Board; Position.StartingFEN := Actor.GameTree.StartingFEN;
    Position.BrowseBasePly := -1; Position.State := gosStopped;
    Check(StartAnalysisSearch(Previous, Previous.GameTree.Root, OldSearch, ErrorText), ErrorText);
    Coordinator.TrackSearch(OldSearch);
    Check(Coordinator.PrepareAnalyzer(Position, Previous, Display, Request), 'prepare analyzer position');
    Check(Previous.SearchState(OldSearch, State) and (State = gssCancelled), 'switching games cancels old actor search');
    Previous.ProcessCommands;
    Check(not Previous.SearchState(OldSearch, State), 'old game search queued for release');
    Check(not Request.Terminal and not Request.Transient and
      (Request.BasePosition.PositionKey = Board.PositionKey), 'ordinary request uses selected base');
    Coordinator.StartRequestSearch(Actor, Position.Node, Request);
    Check(IsValidGameTreeSearchRef(Request.Search) and Coordinator.SearchMatches(Request.Search), 'ordinary request starts tracked actor search');
    Check(not Coordinator.PrepareAnalyzer(Position, Actor, Display, Mcts), 'unchanged position suppressed');
    Check(Actor.SearchState(Request.Search, State) and (State = gssActive), 'suppressed request retains active search');
    Check(Coordinator.PrepareMcts(Position, Display, Mcts) and
      not IsValidGameTreeSearchRef(Mcts.Search), 'MCTS request is independent and unscoped');
    Snapshot.SetDataWithSearch(Board, 99, '32-28 18-23', '0.25', '8', '0.4', Request.Search, False);
    Command := PrepareAnalysisSnapshotCommand(Actor, Previous.GameTree, Snapshot, Tree);
    Check((Command <> nil) and (Tree = Actor.GameTree), 'snapshot targets search tree, not current fallback game');
    try
      Check(Command.NodeId = Position.Node.NodeId, 'scoped snapshot ignores conflicting fallback ply');
      Actor.ExecuteCommand(Command); Check(Command.Accepted, Command.ErrorText);
    finally Command.Free; end;
    Check(Actor.GameTree.Root.AnnotatorPV = '32-28 18-23', 'snapshot stores metadata on exact search node');
    Coordinator.CancelTrackedSearch(Actor);
    Command := PrepareAnalysisSnapshotCommand(Actor, Actor.GameTree, Snapshot, Tree);
    Check(Command = nil, 'late snapshot cannot publish after cancel');
    Actor.ProcessCommands;
    Board.PlayMove('32-28');
    Position.MovesText := '32-28'; Position.MoveCount := 1;
    Position.Preview := True; Position.BrowseBasePly := 0;
    Check(Coordinator.PrepareAnalyzer(Position, Actor, Display, Request), 'prepare preview request');
    Coordinator.StartRequestSearch(Actor, Position.Node, Request);
    Check(Request.Transient and not Request.Terminal and
      not IsValidGameTreeSearchRef(Request.Search), 'preview request never owns a persistent search');
    Key := Request.BasePosition.PositionKey;
    Board.PlayMove('18-23');
    Check(Request.BasePosition.PositionKey = Key, 'request base is copied before caller changes input board');
    Check(Coordinator.PrepareMcts(Position, Display, Mcts), 'MCTS preview request');
    Check(Mcts.BasePosition.PositionKey = OtherBoard.PositionKey,
      'MCTS retains selected-node base policy when displaying a preview');
    Snapshot.SetDataWithSearch(Request.BasePosition, 1, '18-23', '0.1', '2', '', EmptyGameTreeSearchRef, False, True);
    Check(CanDisplayTransientAnalysis(Snapshot, Request.BasePosition), 'matching transient base accepted');
    Check(not CanDisplayTransientAnalysis(Snapshot, Board), 'unrelated transient base ignored');
    Command := PrepareAnalysisSnapshotCommand(Actor, Actor.GameTree, Snapshot, Tree);
    Check(Command = nil, 'transient snapshot never persists');
    Position.Preview := False; Position.MovesText := ''; Position.MoveCount := 0;
    Position.State := gosGameOver; Position.BrowseBasePly := -1;
    Board.LoadFromFEN(DraughtsVariant.DefaultStartingFEN);
    Check(Coordinator.PrepareAnalyzer(Position, Actor, Display, Request) and Request.Terminal,
      'completed following position prepares terminal request');
    Coordinator.StartRequestSearch(Actor, Position.Node, Request);
    Check(not IsValidGameTreeSearchRef(Request.Search), 'terminal request never starts search');
    Snapshot.SetDataWithSearch(Board, 0, '32-28', '', '2', '', EmptyGameTreeSearchRef, False);
    Command := PrepareAnalysisSnapshotCommand(Actor, Actor.GameTree, Snapshot, Tree);
    Check(Command = nil, 'scoreless snapshot does not publish');
    Snapshot.SetDataWithSearch(Board, 0, '32-28', '0.1', '2', '', EmptyGameTreeSearchRef, False);
    Command := PrepareAnalysisSnapshotCommand(Actor, Actor.GameTree, Snapshot, Tree);
    Check((Command <> nil) and (Command.NodeId = Actor.GameTree.Root.NodeId), 'legacy unscoped snapshot retains base-ply fallback');
    Command.Free;
    Execute(Actor,Actor.CreateRecordAnnotatorPVCommand(Actor.GameTree.Root.NodeId,'0.9','32-28','40','8'));
    Command:=PrepareAnalysisSnapshotCommand(Actor,Actor.GameTree,Snapshot,Tree,True);
    Check(Command=nil,'Auto Play cannot overwrite deeper stored annotation');
    Snapshot.SetDataWithSearch(Board,0,'32-28','0.2','', '',EmptyGameTreeSearchRef,True);
    Command:=PrepareAnalysisSnapshotCommand(Actor,Actor.GameTree,Snapshot,Tree,True);
    Check(Command=nil,'Unknown incoming depth cannot overwrite known deeper annotation');
    Snapshot.SetDataWithSearch(Board,0,'32-28','0.2','40','1',EmptyGameTreeSearchRef,True);
    Command:=PrepareAnalysisSnapshotCommand(Actor,Actor.GameTree,Snapshot,Tree,True);
    Check(Command<>nil,'Equal-depth exact annotation can replace the existing tuple');Command.Free;
    Snapshot.SetDataWithSearch(Board,0,'32-28','0.2','41','1',EmptyGameTreeSearchRef,True);
    Command:=PrepareAnalysisSnapshotCommand(Actor,Actor.GameTree,Snapshot,Tree,True);
    Check(Command<>nil,'Deeper exact annotation can replace the existing tuple');Command.Free;
    Snapshot.SetDataWithSearch(Board,0,'32-28','0.2','2','1',EmptyGameTreeSearchRef,True);
    Command:=PrepareAnalysisSnapshotCommand(Actor,Actor.GameTree,Snapshot,Tree);
    Check(Command<>nil,'Normal live annotation retains its previous depth policy');Command.Free;
  finally Snapshot.Free; OtherBoard.Free; Board.Free; Display.Free;
    Coordinator.Free; Previous.Free; Actor.Free; end;
end;

var Actor, Other: TGameTreeActor; Coordinator: TAnalysisCoordinator;
  Snapshot: TPvSnapshot; Board: TGamePosition; Tree: TGameTree;
  Node, ResolvedNode: TGameTreePlyNode; Search, NewSearch: TGameTreeSearchRef;
  ErrorText, Key, Signature: string; State: TGameTreeSearchState;
begin
  RegisterDefaultGameVariant(DraughtsVariant);
  CheckAutoPlay;
  CheckChessAutoPlay;
  CheckPvState;
  CheckRequestsAndSnapshots;
  Actor := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True); Other := TGameTreeActor.Create(TGameTree.Create(DefaultGameVariant),True);
  Coordinator := TAnalysisCoordinator.Create(DefaultGameVariant);
  Snapshot := TPvSnapshot.Create; Board := DraughtsVariant.CreatePosition;
  try
    Tree := Actor.GameTree;
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('32-28', gmsHuman));
    Execute(Actor, Actor.CreateAppendMainlineMoveCommand('18-23', gmsHuman));
    Execute(Actor, ImportBranch(Actor, 1, '20-24 38-32 18-22', '', gmsHuman));
    Node := Tree.FindBranchNode(0, 3);
    Check(Tree.TryBuildPositionAtNode(Node, Board), 'nested analysis position');
    Check(not StartAnalysisSearch(nil, Node, Search, ErrorText) and
      not IsValidGameTreeSearchRef(Search), 'missing actor cannot start a search');
    Check(StartAnalysisSearch(Actor, Node, Search, ErrorText), ErrorText);
    Coordinator.TrackSearch(Search);
    Check(Coordinator.SearchMatches(Search), 'tracked search matches full identity');
    NewSearch := Search; Inc(NewSearch.SearchId);
    Check(not Coordinator.SearchMatches(NewSearch), 'different search ID does not match');
    Snapshot.SetDataWithSearch(Board, 1, '12-18', '0.2', '9', '0.1', Search, False);
    Key := AnalysisSnapshotKey(Snapshot);
    Check(ResolveActiveAnalysisSnapshot(Actor, Snapshot, Tree, ResolvedNode) and
      (ResolvedNode = Node), 'active snapshot resolves by node identity, not mismatched base ply');
    Check(not ResolveActiveAnalysisSnapshot(Other, Snapshot, Tree, ResolvedNode) and
      (Tree = nil) and (ResolvedNode = nil), 'foreign actor cannot resolve snapshot');
    Tree := Actor.GameTree;
    Check(TryResolveAnalyzerSnapshotNode(Tree, Snapshot, ResolvedNode) and
      (ResolvedNode = Node), 'browser snapshot uses nested identity');
    Check(CancelGameTreeSearch(Actor, Search), 'cancel search');
    Check(not ResolveActiveAnalysisSnapshot(Actor, Snapshot, Tree, ResolvedNode),
      'cancelled search snapshot is stale');
    Check(not AcceptSearchMove(Actor, Search, '12-18', ErrorText), 'late done rejected after cancellation');
    Check(ReleaseRejectedSearchIfFinished(Actor, Search), 'cancelled search queues release');
    Actor.ProcessCommands;
    Check(not Actor.SearchState(Search, State), 'release removes cancelled registration');
    Tree := Actor.GameTree;
    Coordinator.ClearSearch;
    Check(not Coordinator.SearchMatches(Search), 'clearing UI tracking rejects old identity');
    Check(StartAnalysisSearch(Actor, Node, NewSearch, ErrorText), ErrorText);
    Snapshot.SetDataWithSearch(Board, 1, '12-18', '0.2', '9', '0.1', NewSearch, False);
    Check(AnalysisSnapshotKey(Snapshot) <> Key, 'queue keys distinguish searches at the same node');
    Check(not ReleaseRejectedSearchIfFinished(Actor, NewSearch), 'active search must not release on unrelated rejection');
    Check(AcceptSearchMove(Actor, NewSearch, '12-18', ErrorText), ErrorText);
    Check(not ResolveActiveAnalysisSnapshot(Actor, Snapshot, Tree, ResolvedNode), 'done search snapshot is stale');
    Check(ReleaseGameTreeSearch(Actor, NewSearch), 'accepted search queues release');
    Actor.ProcessCommands;
    Check(not Actor.SearchState(NewSearch, State), 'done registration released');
    Tree := Actor.GameTree;
    Check(Tree.MainlineCount = 2, 'search completion does not append an official move');
    Snapshot.SetDataWithSearch(Board, 1, '20-24', '0.1', '1', '', EmptyGameTreeSearchRef, False, True);
    Check(AnalyzerSnapshotIsTransient(Snapshot) and
      (AnalysisSnapshotKey(Snapshot) = 'display'), 'transient snapshots coalesce as display updates');
    Check(TryResolveAnalyzerSnapshotNode(Tree, Snapshot, ResolvedNode) and
      (ResolvedNode = Tree.MainlineNode[1]), 'unscoped browser fallback preserves base ply');
    Check(AnalysisSnapshotKey(nil) = '', 'nil snapshot key');
    Check(not AnalyzerSnapshotIsTransient(nil), 'nil is not transient');
    Coordinator.TrackSearch(EmptyGameTreeSearchRef);
    Check(not IsValidGameTreeSearchRef(Coordinator.Search), 'invalid tracking clears identity');
    Signature := DisplayedPositionSignature(Tree, Node.NodeId, Tree.StartingFEN, '32-28 20-24 38-32 18-22', gosStopped);
    Check(Coordinator.RestartAnalyzerFor(Signature), 'first analyzer position restarts');
    Check(not Coordinator.RestartAnalyzerFor(Signature), 'same position does not restart');
    Check(Coordinator.RestartMctsFor(Signature), 'MCTS signature is independent');
    Coordinator.InvalidateAnalyzer;
    Check(Coordinator.RestartAnalyzerFor(Signature), 'invalidation forces analyzer restart');
    Check(not Coordinator.RestartMctsFor(Signature), 'analyzer invalidation preserves MCTS deduplication');
    Coordinator.InvalidateMcts;
    Check(Coordinator.RestartMctsFor(Signature), 'MCTS invalidation forces restart');
    Check(Signature <> DisplayedPositionSignature(Tree, Tree.Root.NodeId,
      Tree.StartingFEN, '32-28 20-24 38-32 18-22', gosStopped), 'node identity affects signature');
    Check(AnalysisPositionIsTerminal(False, True, 1, 2, 3, gosStopped), 'no legal moves is always terminal');
    Check(AnalysisPositionIsTerminal(True, False, -1, 3, 3, gosGameOver), 'following completed tip is terminal');
    Check(not AnalysisPositionIsTerminal(True, False, 1, 1, 3, gosGameOver), 'completed game historical position can analyze');
    Check(not AnalysisPositionIsTerminal(True, True, 3, 4, 3, gosGameOver), 'legal preview can analyze beyond completed tip');
  finally Board.Free; Snapshot.Free; Coordinator.Free; Other.Free; Actor.Free; end;
  Writeln('Analysis coordinator checks passed');
end.
