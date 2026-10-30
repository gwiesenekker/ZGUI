unit uGameGuiMessages;

{$mode objfpc}{$H+}

interface

uses
  uThreadMessageQueue, uGameRunnerThread, uPvSnapshot,
  uGameTreeSearchRef, uAnalyzerRunnerThread;

type
  TRunnerSnapshotGuiMessage = class(TThreadMessage)
  private
    FGameId: Integer;
    FSnapshot: TGameRunnerSnapshot;
  public
    constructor Create(AGameId: Integer; ASnapshot: TGameRunnerSnapshot);
      reintroduce;
    destructor Destroy; override;
    property GameId: Integer read FGameId;
    property Snapshot: TGameRunnerSnapshot read FSnapshot;
  end;

  TRunnerFinishedGuiMessage = class(TThreadMessage)
  private
    FGameId: Integer;
  public
    constructor Create(AGameId: Integer); reintroduce;
    property GameId: Integer read FGameId;
  end;

  // Immutable identity is copied at posting time; dispatch never dereferences a
  // retired runner or chooses its destination from the currently visible game.
  TAnalysisGuiMessage=class(TThreadMessage)
  public
    SessionId:Int64;
    SlotId:string;
    constructor Create(const AKind:string;Source:TAnalyzerRunnerThread=nil);reintroduce;
  end;

  TAnalyzerLogGuiMessage = class(TAnalysisGuiMessage)
  private
    FMessage: string;
  public
    constructor Create(const AMessage: string;Source:TAnalyzerRunnerThread=nil); reintroduce;
    property Message: string read FMessage;
  end;

  TAnalyzerSnapshotGuiMessage = class(TAnalysisGuiMessage)
  private
    FSnapshot: TPvSnapshot;
  public
    constructor Create(ASnapshot: TPvSnapshot;Source:TAnalyzerRunnerThread=nil); reintroduce;
    destructor Destroy; override;
    property Snapshot: TPvSnapshot read FSnapshot;
  end;

  TAnalyzerMoveGuiMessage = class(TAnalysisGuiMessage)
  private
    FMoveText: string;
    FSearch: TGameTreeSearchRef;
  public
    constructor Create(const ASearch: TGameTreeSearchRef;
      const AMoveText: string;Source:TAnalyzerRunnerThread=nil); reintroduce;
    property MoveText: string read FMoveText;
    property Search: TGameTreeSearchRef read FSearch;
  end;

  TAnalyzerFinishedGuiMessage = class(TAnalysisGuiMessage)
  private
    FRunner: TAnalyzerRunnerThread;
  public
    constructor Create(ARunner: TAnalyzerRunnerThread); reintroduce;
    property Runner: TAnalyzerRunnerThread read FRunner;
  end;

  TMctsLogGuiMessage = class(TAnalysisGuiMessage)
  private
    FMessage: string;
  public
    constructor Create(const AMessage: string;Source:TAnalyzerRunnerThread=nil); reintroduce;
    property Message: string read FMessage;
  end;

  TMctsFinishedGuiMessage = class(TAnalysisGuiMessage)
  private
    FRunner: TAnalyzerRunnerThread;
  public
    constructor Create(ARunner: TAnalyzerRunnerThread); reintroduce;
    property Runner: TAnalyzerRunnerThread read FRunner;
  end;

implementation

uses SysUtils;

constructor TAnalysisGuiMessage.Create(const AKind:string;Source:TAnalyzerRunnerThread);
begin
  inherited Create(AKind);
  if Source<>nil then begin SessionId:=Source.SessionId;SlotId:=Source.SlotId;end;
end;

constructor TRunnerSnapshotGuiMessage.Create(AGameId: Integer;
  ASnapshot: TGameRunnerSnapshot);
begin
  inherited Create('runner-snapshot');
  FGameId := AGameId;
  FSnapshot := ASnapshot;
end;

destructor TRunnerSnapshotGuiMessage.Destroy;
begin
  FSnapshot.Free;
  inherited Destroy;
end;

constructor TRunnerFinishedGuiMessage.Create(AGameId: Integer);
begin
  inherited Create('runner-finished');
  FGameId := AGameId;
end;

constructor TAnalyzerLogGuiMessage.Create(const AMessage: string;Source:TAnalyzerRunnerThread);
begin
  inherited Create('analyzer-log',Source);
  FMessage := AMessage;
end;

constructor TAnalyzerSnapshotGuiMessage.Create(ASnapshot: TPvSnapshot;Source:TAnalyzerRunnerThread);
begin
  inherited Create('analyzer-snapshot',Source);
  FSnapshot := ASnapshot;
end;

destructor TAnalyzerSnapshotGuiMessage.Destroy;
begin
  FSnapshot.Free;
  inherited Destroy;
end;

constructor TAnalyzerMoveGuiMessage.Create(const ASearch: TGameTreeSearchRef;
  const AMoveText: string;Source:TAnalyzerRunnerThread);
begin
  inherited Create('analyzer-move',Source);
  FSearch := ASearch;
  FMoveText := Trim(AMoveText);
end;

constructor TAnalyzerFinishedGuiMessage.Create(ARunner: TAnalyzerRunnerThread);
begin
  inherited Create('analyzer-finished',ARunner);
  FRunner := ARunner;
end;

constructor TMctsLogGuiMessage.Create(const AMessage: string;Source:TAnalyzerRunnerThread);
begin
  inherited Create('mcts-log',Source);
  FMessage := AMessage;
end;

constructor TMctsFinishedGuiMessage.Create(ARunner: TAnalyzerRunnerThread);
begin
  inherited Create('mcts-finished',ARunner);
  FRunner := ARunner;
end;

end.
