unit uDraughtsHubEngine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SyncObjs, SysUtils,
  uDraughtsBoard, uDraughtsEngine, uDraughtsPosition, uGamePosition, uEngineBase, uEngineParamsJson, uEngineRegistry,
  uPlatformProcess, uThreadMessageQueue, uProcessEngineWorker;

type
  THubEngine = class(TDraughtsEngine)
  private
    FSupportsPonder,FForcePonderOff,FGameMode,FPonderActive,FHasPending,FHasClock:Boolean;
    FClock,FPonderClock:TEngineGameClockState;
    FPendingRoot,FSearchRoot,FSearchMoves,FBestMove,FNextReply:string;
    FPonderPv,FPonderScore,FPonderDepth,FPonderTime:string;
    FPendingMoves:TStringList;
    procedure Idle;
    procedure Accepted(const Root:string;Moves:TStrings;const Clock:TEngineGameClockState);
    procedure StoreClock(const Clock:TEngineGameClockState);
  private
    FEngine: TExternalEngineDefinition;
    FLevelCommand: string;
    FLastWaitFailure: string;
    FParams: TEngineParamArray;
    FProcess: TPlatformProcess;
    FStopping: Boolean;
    FStopFailed: Boolean;
    FWorker: TProcessEngineWorker;
    function WorkerStopping: Boolean;
    function BuildHubPositionCommand: string;
    function DoLaunchAndInit: Boolean;
    procedure DiscardDoneLinesBeforeNewSearch(const AReason: string);
    procedure DoRequestStop;
    procedure DoSetClockInfo(AMovesRemaining: Integer; ARemainingSeconds,
      ATotalUsedSeconds: Double);
    procedure DoStartAnalyzing;
    procedure DoStartMcts;
    procedure DoStopSearch;
    procedure DoStop;
    procedure DoPollOutput;
    procedure ExecuteWorkerCommand(ACommand: TObject);
    function ExtractDoneMove(const ALine: string): string;
    function IsWorkerThread: Boolean;
    function ParamBool(const AName: string; ADefault: Boolean): Boolean;
    procedure ParsePositionMessage(const AMessage: string);
    procedure ProcessData(Sender: TObject; const AText: string);
    procedure QueueProcessData(const AText: string);
    function QueueBoolCommand(ACommand: TObject): Boolean;
    procedure QueueProcedureCommand(ACommand: TObject);
    function QueueStringCommand(ACommand: TObject): string;
    procedure SendHubParams;
    procedure RequireSearchSynchronization;
    procedure SendLine(const ALine: string);
    function TakeReceivedLine(const APrefix: string; out ALine: string): Boolean;
    function WaitForDoneMove(ATimeoutMs: Integer; out AMove: string): Boolean;
    function DrainDoneLinesAfterStop(AQuietMs: Integer): Integer;
    procedure WaitForSearchStopped;
    function WaitForLine(const APrefix: string; ATimeoutMs: Integer;
      out ALine: string): Boolean;
  protected
    function DoStartThinking: string; override;
  public
    constructor Create(AEngine: TExternalEngineDefinition); reintroduce;
    destructor Destroy; override;
    procedure BeginGame(const AStartingFEN: string; ASide: TGameSide;
      AGameMinutes: Double; AGameMoves: Integer;
      AIncrementSeconds: Double = 0.0); override;
    procedure SetGameClockState(const Clock:TEngineGameClockState); override;
    procedure SetGamePonderAllowed(Allowed:Boolean); override;
    procedure GameMoveAccepted(const RootFEN:string;ActualMoves:TStrings;
      const NextOwnClock:TEngineGameClockState); override;
    function LaunchAndInit: Boolean; override;
    function ProtocolName: string; override;
    function ReceiveMessage(const AMessage: string): string; override;
    procedure RequestStop; override;
    procedure SetClockInfo(AMovesRemaining: Integer; ARemainingSeconds,
      ATotalUsedSeconds: Double); override;
    procedure SetClockInfoWithIncrement(AMovesRemaining: Integer;
      ARemainingSeconds, ATotalUsedSeconds, AIncrementSeconds: Double); override;
    procedure SetGamePosition(const AStartingFEN: string; AMoves: TStrings); override;
    function Capabilities: TEngineCapabilities; override;
    procedure StartAnalyzing; override;
    procedure StartMcts; override;
    function StartThinking: string; override;
    procedure PollOutput; override;
    procedure StopSearch; override;
    procedure Stop; override;
  end;

implementation
uses uHubSearchInfo,uEngineFeatureFlags;

const
  HubWorkerWaitPollMs = 1000;
  HubWorkerWaitLogMs = 10000;
  HubSearchStopTimeoutMs = 10000;

type
  THubWorkerCommandKind = (
    hwcLaunchAndInit,
    hwcBeginGame,
    hwcSetGamePosition,
    hwcSetClockInfo,
    hwcGameClock,
    hwcAccepted,
    hwcStartThinking,
    hwcStartAnalyzing,
    hwcStartMcts,
    hwcPollOutput,
    hwcProcessData,
    hwcStopSearch,
    hwcStop
  );

  THubWorkerCommand = class(TProcessEngineCommand)
  private
    FClock:TEngineGameClockState;
    FGameMinutes: Double;
    FGameMoves: Integer;
    FCommandKind: THubWorkerCommandKind;
    FMoves: TStringList;
    FMovesRemaining: Integer;
    FRemainingSeconds: Double;
    FSide: TDraughtsSide;
    FStartingFEN: string;
    FTextValue: string;
    FTotalUsedSeconds: Double;
  public
    constructor Create(AKind: THubWorkerCommandKind); reintroduce;
    destructor Destroy; override;
    property Clock:TEngineGameClockState read FClock write FClock;
    property GameMinutes: Double read FGameMinutes write FGameMinutes;
    property GameMoves: Integer read FGameMoves write FGameMoves;
    property CommandKind: THubWorkerCommandKind read FCommandKind;
    property Moves: TStringList read FMoves;
    property MovesRemaining: Integer read FMovesRemaining write FMovesRemaining;
    property RemainingSeconds: Double read FRemainingSeconds write FRemainingSeconds;
    property Side: TDraughtsSide read FSide write FSide;
    property StartingFEN: string read FStartingFEN write FStartingFEN;
    property TextValue: string read FTextValue write FTextValue;
    property TotalUsedSeconds: Double read FTotalUsedSeconds write FTotalUsedSeconds;
  end;

function HubQuote(const AText: string): string;
begin
  HubParamQuote(AText); // Validate the protocol's representable character set.
  Result := '"' + AText + '"';
end;

function HubSeconds(ASeconds: Double): string;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  Result := Format('%.3f', [ASeconds], FormatSettings);
end;

constructor THubWorkerCommand.Create(AKind: THubWorkerCommandKind);
const
  CommandNames: array[THubWorkerCommandKind] of string = (
    'hub-launch-and-init',
    'hub-begin-game',
    'hub-set-game-position',
    'hub-set-clock-info',
    'hub-game-clock',
    'hub-accepted',
    'hub-start-thinking',
    'hub-start-analyzing',
    'hub-start-mcts',
    'hub-poll-output',
    'hub-process-data',
    'hub-stop-search',
    'hub-stop'
  );
begin
  inherited Create(CommandNames[AKind]);
  FCommandKind := AKind;
  FMoves := TStringList.Create;
  AutoFree := AKind=hwcProcessData;
end;

destructor THubWorkerCommand.Destroy;
begin
  FMoves.Free;
  inherited Destroy;
end;

constructor THubEngine.Create(AEngine: TExternalEngineDefinition);
begin
  inherited Create(EnginePickerDisplayName(AEngine, 0));
  FEngine := TExternalEngineDefinition.Create;
  FEngine.Assign(AEngine);
  EngineName := FEngine.IdText;
  if EngineName = '' then
    EngineName := ChangeFileExt(FEngine.ExecutableName, '');
  FPendingMoves:=TStringList.Create;
  FWorker:=TProcessEngineWorker.Create(@ExecuteWorkerCommand,@Log,@WorkerStopping,'Hub',@Idle);
  FProcess:=FWorker.Process;
  FProcess.OnData:=@ProcessData;
  FStopping := False;
  LoadEngineParamsFromJson(EngineParamsFileName(FEngine.ExePath), 'hub', FParams);
  ChangeState(esWaiting, 'hub adapter created');
end;

destructor THubEngine.Destroy;
begin
  Stop;
  FWorker.Free;
  FPendingMoves.Free;
  FEngine.Free;
  inherited Destroy;
end;

procedure THubEngine.ProcessData(Sender: TObject; const AText: string);
var
  DepthText: string;
  Line: string;
  LoggedPvText: string;
  LoggedScoreText: string;
  LoggedDepthText: string;
  LoggedTimeText: string;
  PvText: string;
  ScoreText: string;
  TimeText: string;
  Lines: TStringList;
  Index: Integer;
begin
  if not IsWorkerThread then
  begin
    QueueProcessData(AText);
    Exit;
  end;

  LoggedPvText := '';
  LoggedScoreText := '';
  LoggedDepthText := '';
  LoggedTimeText := '';
  Lines:=TStringList.Create;
  try
    FWorker.FrameData(AText,Lines);
    for Index:=0 to Lines.Count-1 do begin
      Line:=Lines[Index];
      if Line <> '' then
      begin
        if (Pos('param ',LowerCase(Line))=1) and SameText(ExtractHubArgument(Line,'name'),'ponder') and
          SameText(ExtractHubArgument(Line,'type'),'bool') then FSupportsPonder:=True;
        if (Pos('info ', LowerCase(Line)) <> 1) and
          (Pos('info=', LowerCase(Line)) <> 1) then
        begin
          FWorker.AddReceivedLine(Line);
        end;
        MergeHubSearchInfo(Line,FParams,StartingFEN,MovesPlayed.Count,
          LoggedPvText,LoggedScoreText,LoggedDepthText,LoggedTimeText);
      end;
    end;
  finally
    Lines.Free;
  end;
  ReadSearchInfo(PvText,ScoreText,DepthText,TimeText);
  if LoggedPvText<>'' then PvText:=LoggedPvText;
  if LoggedScoreText<>'' then ScoreText:=LoggedScoreText;
  if LoggedDepthText<>'' then DepthText:=LoggedDepthText;
  if LoggedTimeText<>'' then TimeText:=LoggedTimeText;
  if FPonderActive then begin
    if LoggedPvText<>'' then FPonderPv:=LoggedPvText;
    if LoggedScoreText<>'' then FPonderScore:=LoggedScoreText;
    if LoggedDepthText<>'' then FPonderDepth:=LoggedDepthText;
    if LoggedTimeText<>'' then FPonderTime:=LoggedTimeText;
  end else PublishSearchInfo(PvText,ScoreText,DepthText,TimeText);
  // Log observers can publish throttled live snapshots. Parse the complete
  // chunk first so stdout cannot publish the previous info and consume the slot.
  Log('stdout; text=' + StringReplace(AText, LineEnding, '\n', [rfReplaceAll]));
  if LoggedPvText <> '' then
    Log('pv; text=' + LoggedPvText);
  if LoggedScoreText <> '' then
    Log('score; value=' + LoggedScoreText);
  if LoggedDepthText <> '' then
    Log('depth; value=' + LoggedDepthText);
  if LoggedTimeText <> '' then
    Log('time; value=' + LoggedTimeText);
end;

function THubEngine.QueueBoolCommand(ACommand: TObject): Boolean;
begin Result:=FWorker.QueueBoolCommand(ACommand); end;
procedure THubEngine.QueueProcedureCommand(ACommand: TObject);
begin FWorker.QueueProcedureCommand(ACommand); end;
function THubEngine.QueueStringCommand(ACommand: TObject): string;
begin Result:=FWorker.QueueStringCommand(ACommand); end;
procedure THubEngine.QueueProcessData(const AText: string);
var C: THubWorkerCommand;
begin
  if AText='' then Exit;
  C:=THubWorkerCommand.Create(hwcProcessData); C.TextValue:=AText;
  if not FWorker.Post(C) then C.Free;
end;

procedure THubEngine.ExecuteWorkerCommand(ACommand: TObject);
var
  HubCommand: THubWorkerCommand;
begin
  if not (ACommand is THubWorkerCommand) then
    Exit;
  HubCommand := THubWorkerCommand(ACommand);
  case HubCommand.CommandKind of
    hwcLaunchAndInit:
      HubCommand.BoolResult := DoLaunchAndInit;
    hwcBeginGame:
      begin
        if FPonderActive then DoStopSearch;
        FGameMode:=True;FHasClock:=False;FHasPending:=False;FNextReply:='';
        inherited BeginGame(HubCommand.StartingFEN, DraughtsSideToGameSide(HubCommand.Side),
          HubCommand.GameMinutes, HubCommand.GameMoves);
      end;
    hwcSetGamePosition:
      begin
        RequireSearchSynchronization;
        if FPonderActive then begin
          FPendingRoot:=HubCommand.StartingFEN;FPendingMoves.Assign(HubCommand.Moves);FHasPending:=True;
        end else inherited SetGamePosition(HubCommand.StartingFEN, HubCommand.Moves);
      end;
    hwcSetClockInfo:
      DoSetClockInfo(HubCommand.MovesRemaining, HubCommand.RemainingSeconds,
        HubCommand.TotalUsedSeconds);
    hwcGameClock:StoreClock(HubCommand.Clock);
    hwcAccepted:Accepted(HubCommand.StartingFEN,HubCommand.Moves,HubCommand.Clock);
    hwcStartThinking:
      begin
        RequireSearchSynchronization;
        HubCommand.StringResult := inherited StartThinking;
      end;
    hwcStartAnalyzing:
      DoStartAnalyzing;
    hwcStartMcts:
      DoStartMcts;
    hwcPollOutput:
      DoPollOutput;
    hwcProcessData:
      ProcessData(nil, HubCommand.TextValue);
    hwcStopSearch:
      DoStopSearch;
    hwcStop:
      DoStop;
  end;
end;

function THubEngine.IsWorkerThread: Boolean;
begin Result:=FWorker.IsWorkerThread; end;
function THubEngine.WorkerStopping: Boolean;
begin Result:=FStopping or StopRequested; end;
procedure THubEngine.SendLine(const ALine: string);
begin FWorker.SendLine(ALine); end;

procedure THubEngine.SendHubParams;
var
  Command: string;
  I: Integer;
begin
  for I := 0 to High(FParams) do
  begin
    if not EngineParamShouldSendToHub(FParams[I].Name) then
      Continue;
    Command := 'set-param name=' + HubParamQuote(FParams[I].Name) +
      ' value=' + HubParamQuote(FParams[I].Value);
    SendLine(Command);
  end;
end;

function THubEngine.WaitForLine(const APrefix: string; ATimeoutMs: Integer; out ALine: string): Boolean;
begin Result:=FWorker.WaitForLine(APrefix,ATimeoutMs,ALine); FLastWaitFailure:=FWorker.LastWaitFailure; end;
function THubEngine.TakeReceivedLine(const APrefix: string; out ALine: string): Boolean;
begin Result:=FWorker.TakeReceivedLine(APrefix,ALine); end;

procedure THubEngine.DiscardDoneLinesBeforeNewSearch(const AReason: string);
var
  Count: Integer;
  Line: string;
begin
  if FProcess.NeedsPolling then
    FProcess.ReadAvailable;

  Count := 0;
  while TakeReceivedLine('done', Line) do
    Inc(Count);

  if Count > 0 then
    Log('discarded pre-search done lines; count=' + IntToStr(Count) +
      '; reason=' + AReason);
end;

function THubEngine.WaitForDoneMove(ATimeoutMs: Integer;
  out AMove: string): Boolean;
var
  ElapsedMs: QWord;
  Line: string;
  MoveText: string;
  RemainingMs: Integer;
  StartTick: QWord;
begin
  Result := False;
  AMove := '';
  StartTick := GetTickCount64;
  repeat
    ElapsedMs := GetTickCount64 - StartTick;
    if ElapsedMs >= QWord(ATimeoutMs) then
      Break;
    RemainingMs := ATimeoutMs - Integer(ElapsedMs);
    if not WaitForLine('done', RemainingMs, Line) then
      Exit(False);

    MoveText := ExtractDoneMove(Line);
    if MoveText <> '' then
    begin
      AMove := NormalizeMoveText(MoveText);
      FNextReply:=NormalizeMoveText(ExtractHubArgument(Line,'ponder'));
      Exit(True);
    end;

    Log('ignored done without move while waiting for think result; line=' +
      Line);
  until False;

  FLastWaitFailure := 'timeout';
  Log('wait timeout; expected=done move; timeout_ms=' + IntToStr(ATimeoutMs));
end;

function THubEngine.DrainDoneLinesAfterStop(AQuietMs: Integer): Integer;
var
  Line: string;
  QuietStart: QWord;
  SawLine: Boolean;
begin
  Result := 0;
  QuietStart := GetTickCount64;
  repeat
    if FProcess.NeedsPolling then
      FProcess.ReadAvailable;

    SawLine := False;
    while TakeReceivedLine('done', Line) do
    begin
      Inc(Result);
      SawLine := True;
    end;

    if SawLine then
      QuietStart := GetTickCount64
    else
      Sleep(25);
  until GetTickCount64 - QuietStart >= QWord(AQuietMs);
end;

procedure THubEngine.WaitForSearchStopped;
var
  ExtraDoneCount: Integer;
  Line: string;
begin
  if WaitForLine('done', HubSearchStopTimeoutMs, Line) then
  begin
    Log('search stop acknowledged; line=' + Line);
    ExtraDoneCount := DrainDoneLinesAfterStop(100);
    if ExtraDoneCount > 0 then
      Log('discarded post-stop done lines; count=' + IntToStr(ExtraDoneCount));
  end
  else
    raise EInvalidOperation.Create(
      'search stop acknowledgement not received; reason=' + FLastWaitFailure);
end;

procedure THubEngine.RequireSearchSynchronization;
begin
  if FStopFailed then
    raise EInvalidOperation.Create(
      'Hub search is not synchronized; relaunch the engine before continuing');
end;

function THubEngine.DoLaunchAndInit: Boolean;
var
  Args: TStringList;
  Line: string;
begin
  Result := False;
  if StopRequested then Exit;
  Args := TStringList.Create;
  try
    FWorker.PrepareLaunch(FEngine,FParams,Args);
    FStopping := False;
    if StopRequested then Exit;
    Log('launch; executable=' + FEngine.ExePath);
    ChangeState(esLaunching, 'starting hub process');
    FProcess.Start(FEngine.ExePath, Args, ExtractFilePath(FEngine.ExePath),FEngine.EnvironmentJson);
    ChangeState(esInitializing, 'process launched; sending hub handshake');

    SendLine('hub');
    if not WaitForLine('wait', EngineStartupTimeoutMs(FParams), Line) then
      Log('hub wait not received before init; reason=' + FLastWaitFailure);
    SendHubParams;

    SendLine('init');

    ChangeState(esWaitingForReady, 'init sent; waiting for ready');
    Result := WaitForLine('ready', EngineStartupTimeoutMs(FParams), Line);
    if Result then
    begin
      FStopFailed := False;
      Log('launch check passed; ready received');
      ChangeState(esReady, 'hub ready');
    end
    else
    begin
      Log('launch check failed; ready not received; reason=' + FLastWaitFailure);
      ChangeState(esError, 'hub ready failed; reason=' + FLastWaitFailure);
      if FProcess.IsRunning then
        FProcess.RequestQuit('quit', 800);
      if FProcess.IsRunning then
        FProcess.Terminate(1000);
      FProcess.Close;
    end;
  finally
    Args.Free;
  end;
end;

function THubEngine.ParamBool(const AName: string; ADefault: Boolean): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(EngineParamValue(FParams, AName, '')));
  if Value = '' then
    Exit(ADefault);
  Result := (Value = 'true') or (Value = '1') or (Value = 'yes') or
    (Value = 'on');
end;

procedure THubEngine.ParsePositionMessage(const AMessage: string);
var
  LowerMessage: string;
  MovesPos: SizeInt;
  MovesText: string;
  MoveList: TStringList;
  I: Integer;
begin
  LowerMessage := LowerCase(Trim(AMessage));
  MovesPlayed.Clear;
  if Pos('pos=', LowerMessage) <> 1 then
    Exit;

  MovesPos := Pos(' moves=', LowerMessage);
  if MovesPos = 0 then
    NewGame(Trim(Copy(AMessage, 5, MaxInt)))
  else
  begin
    NewGame(Trim(Copy(AMessage, 5, MovesPos - 5)));
    MovesText := Trim(Copy(AMessage, MovesPos + Length(' moves='), MaxInt));
    if (Length(MovesText) >= 2) and (MovesText[1] = '"') and
      (MovesText[Length(MovesText)] = '"') then
      MovesText := Copy(MovesText, 2, Length(MovesText) - 2);
    MoveList := TStringList.Create;
    try
      ExtractStrings([' '], [], PChar(MovesText), MoveList);
      for I := 0 to MoveList.Count - 1 do
        if Trim(MoveList[I]) <> '' then
          MovesPlayed.Add(NormalizeMoveNotation(MoveList[I]));
      Log('position received; move_count=' + IntToStr(MovesPlayed.Count));
    finally
      MoveList.Free;
    end;
  end;
end;

function THubEngine.BuildHubPositionCommand: string;
var
  Board: TDraughtsBoard;
  MoveText: string;
  I: Integer;
  SendStartingPosition: Boolean;
begin
  SendStartingPosition := ParamBool('gui-send-starting-position', True);
  Board := TDraughtsBoard.Create;
  try
    Board.LoadFromFEN(StartingFEN);
    if SendStartingPosition then
    begin
      Result := 'pos pos=' + Board.HubPosition;
      MoveText := '';
      for I := 0 to MovesPlayed.Count - 1 do
      begin
        Board.PlayMove(MovesPlayed[I], False);
        if MoveText <> '' then
          MoveText += ' ';
        MoveText += MovesPlayed[I];
      end;
    end
    else
    begin
      for I := 0 to MovesPlayed.Count - 1 do
        Board.PlayMove(MovesPlayed[I], False);
      Result := 'pos pos=' + Board.HubPosition;
      MoveText := '';
    end;
    if MoveText <> '' then
      Result += ' moves=' + HubQuote(MoveText);
  finally
    Board.Free;
  end;
end;

function THubEngine.ExtractDoneMove(const ALine: string): string;
begin
  Result := ExtractHubArgument(ALine, 'move');
end;

procedure THubEngine.Idle;
begin
  if not FPonderActive or WorkerStopping then Exit;
  DoPollOutput;
end;

procedure THubEngine.StoreClock(const Clock:TEngineGameClockState);
begin
  FClock:=Clock;FHasClock:=True;
  DoSetClockInfo(Clock.MovesRemaining,Clock.Remaining[Clock.SideToMove],Clock.Used[Clock.SideToMove]);
  if Clock.Increment[Clock.SideToMove]>0 then FLevelCommand+=' inc='+HubSeconds(Clock.Increment[Clock.SideToMove]);
end;

procedure THubEngine.Accepted(const Root:string;Moves:TStrings;const Clock:TEngineGameClockState);
var Trial:TGamePosition;I:Integer;Reply:string;
begin
  if WorkerStopping or FStopFailed or FForcePonderOff or not FGameMode or not FSupportsPonder or
    not ParamBool('ponder',False) or EngineHasFeatureFlag(FParams,FeatureNoPondering) or (FNextReply='') then Exit;
  if (Root<>FSearchRoot) or (Moves.Text<>FSearchMoves+FBestMove+LineEnding) then Exit;
  Trial:=TDraughtsPosition.Create;
  try
    Trial.LoadFromFEN(Root);for I:=0 to Moves.Count-1 do Trial.PlayMoveText(Moves[I]);
    Reply:=FNextReply;FNextReply:='';if not Trial.IsLegal(Reply) then Exit;
    Trial.PlayMoveText(Reply);if Trial.LegalMoveCount=0 then Exit;
    inherited SetGamePosition(Root,Moves);MovesPlayed.Add(Reply);
    FSearchRoot:=Root;FSearchMoves:=MovesPlayed.Text;FPonderClock:=Clock;FHasPending:=False;FHasClock:=False;
    StoreClock(Clock);FHasClock:=False;
    SendLine(BuildHubPositionCommand);SendLine(FLevelCommand);
    DiscardDoneLinesBeforeNewSearch('before go ponder');
    FPonderPv:='';FPonderScore:='';FPonderDepth:='';FPonderTime:='';
    FPonderActive:=True;SendLine('go ponder');ChangeState(esThinking,'ponder started');
  finally Trial.Free;end;
end;

function THubEngine.DoStartThinking: string;
var Failure:string;Hit:Boolean;Own:TGameSide;Started,Elapsed:QWord;Budget:Integer;
begin
  Started:=GetTickCount64;Budget:=MoveTimeLimitMs;Hit:=False;
  if FPonderActive then begin
    if not FHasPending or not FHasClock then raise EInvalidOperation.Create('Fresh actual position and clocks required after Hub pondering');
    Own:=FPonderClock.SideToMove;
    Hit:=not EngineHasFeatureFlag(FParams,FeatureNoPonderHit) and (FPendingRoot=FSearchRoot) and (FPendingMoves.Text=FSearchMoves) and
      (FClock.SideToMove=Own) and (FClock.Remaining[Own]=FPonderClock.Remaining[Own]) and
      (FClock.Increment[Own]=FPonderClock.Increment[Own]) and (FClock.MovesRemaining=FPonderClock.MovesRemaining);
    // Hub may finish early. Its queued done is reusable only for the exact prediction.
    DoPollOutput;
    if Hit then begin
      inherited SetGamePosition(FPendingRoot,FPendingMoves);
      if WaitForDoneMove(1,Result) then begin
        FPonderActive:=False;FHasPending:=False;FBestMove:=Result;
        Log('ponder early result reused');
        PublishSearchInfo(FPonderPv,FPonderScore,FPonderDepth,FPonderTime);Exit;
      end;
      FPonderActive:=False;SendLine('ponder-hit');Log('ponder hit');
    end else begin
      // Keep the adapter's existing stop/acknowledgement fence on misses.
      DoStopSearch;
      inherited SetGamePosition(FPendingRoot,FPendingMoves);Log('ponder miss; previous result discarded');
      Elapsed:=GetTickCount64-Started;
      if Elapsed>=QWord(Budget) then begin MarkMoveTimedOut;Exit('');end;
      Dec(Budget,Integer(Elapsed));
      FClock.Remaining[Own]:=FClock.Remaining[Own]-Elapsed/1000;
      if FClock.Remaining[Own]<0 then FClock.Remaining[Own]:=0;StoreClock(FClock);
    end;
  end;
  FHasPending:=False;FHasClock:=False;FNextReply:='';
  PublishSearchInfo('','','','');
  FSearchRoot:=StartingFEN;FSearchMoves:=MovesPlayed.Text;
  if not Hit then begin
    SendLine(BuildHubPositionCommand);
    if FLevelCommand<>'' then SendLine(FLevelCommand);
    DiscardDoneLinesBeforeNewSearch('before go think');SendLine('go think');
  end;
  ChangeState(esWaitingForDone,'search started; waiting for done');
  if not WaitForDoneMove(Budget,Result) then begin
    Failure:=FLastWaitFailure;
    if Failure='timeout' then begin
      MarkMoveTimedOut;
      try DoStopSearch;except on E:Exception do Log('timed-out search could not be stopped; message='+E.Message);end;
    end;
    ChangeState(esError,'waiting for done move failed; reason='+Failure);Result:='';
  end;
  FBestMove:=Result;
end;

procedure THubEngine.DoStopSearch;
var
  SearchWasActive: Boolean;
begin
  RequireSearchSynchronization;
  SearchWasActive := FPonderActive or (CurrentState in [esThinking, esWaitingForDone, esStopping]);
  try
    SendLine('stop');
    if SearchWasActive and (CurrentState <> esStopping) then
      ChangeState(esStopping, 'stop sent; waiting for done');
    if SearchWasActive then
      WaitForSearchStopped;
  except
    on E: Exception do
    begin
      FStopFailed := True;
      ChangeState(esError, 'search stop failed; message=' + E.Message);
      Log('stop search command failed; message=' + E.Message);
      raise;
    end;
  end;
  FPonderActive:=False;FNextReply:='';
  if SearchWasActive and (CurrentState <> esError) then
    ChangeState(esReady, 'search stopped');
end;

procedure THubEngine.DoStartAnalyzing;
begin
  FGameMode:=False;
  RequireSearchSynchronization;
  DoStopSearch;
  SendLine(BuildHubPositionCommand);
  if FLevelCommand <> '' then
    SendLine(FLevelCommand)
  else
    SendLine('level time=1000');
  DiscardDoneLinesBeforeNewSearch('before go analyze');
  SendLine('go analyze');
  ChangeState(esThinking, 'analysis started');
end;

procedure THubEngine.DoStartMcts;
begin
  FGameMode:=False;
  RequireSearchSynchronization;
  DoStopSearch;
  SendLine(BuildHubPositionCommand);
  SendLine('level time=1000');
  DiscardDoneLinesBeforeNewSearch('before go mcts');
  SendLine('go mcts');
  ChangeState(esThinking, 'MCTS started');
end;

procedure THubEngine.DoPollOutput;
begin
  if (FProcess <> nil) and FProcess.NeedsPolling then
    FProcess.ReadAvailable;
end;

procedure THubEngine.DoSetClockInfo(AMovesRemaining: Integer; ARemainingSeconds,
  ATotalUsedSeconds: Double);
begin
  FLevelCommand := 'level';
  if AMovesRemaining > 0 then FLevelCommand += ' moves=' + IntToStr(AMovesRemaining);
  FLevelCommand += ' time=' + HubSeconds(ARemainingSeconds);
  Log('level stored; message=' + FLevelCommand);
end;

procedure THubEngine.BeginGame(const AStartingFEN: string; ASide: TGameSide;
  AGameMinutes: Double; AGameMoves: Integer; AIncrementSeconds: Double);
var
  Command: THubWorkerCommand;
begin
  Command := THubWorkerCommand.Create(hwcBeginGame);
  Command.StartingFEN := AStartingFEN;
  Command.Side := GameSideToDraughtsSide(ASide);
  Command.GameMinutes := AGameMinutes;
  Command.GameMoves := AGameMoves;
  QueueProcedureCommand(Command);
end;

function THubEngine.ProtocolName: string;
begin
  Result := 'Hub';
end;

function THubEngine.LaunchAndInit: Boolean;
begin
  Result := QueueBoolCommand(THubWorkerCommand.Create(hwcLaunchAndInit));
end;

procedure THubEngine.SetClockInfo(AMovesRemaining: Integer; ARemainingSeconds,
  ATotalUsedSeconds: Double);
var
  Command: THubWorkerCommand;
begin
  Command := THubWorkerCommand.Create(hwcSetClockInfo);
  Command.MovesRemaining := AMovesRemaining;
  Command.RemainingSeconds := ARemainingSeconds;
  Command.TotalUsedSeconds := ATotalUsedSeconds;
  QueueProcedureCommand(Command);
end;

procedure THubEngine.SetClockInfoWithIncrement(AMovesRemaining: Integer;
  ARemainingSeconds, ATotalUsedSeconds, AIncrementSeconds: Double);
begin
  SetClockInfo(AMovesRemaining, ARemainingSeconds, ATotalUsedSeconds);
  if AIncrementSeconds > 0 then
    ReceiveMessage(FLevelCommand + ' inc=' + HubSeconds(AIncrementSeconds));
end;

procedure THubEngine.SetGameClockState(const Clock:TEngineGameClockState);
var Command:THubWorkerCommand;
begin Command:=THubWorkerCommand.Create(hwcGameClock);Command.Clock:=Clock;QueueProcedureCommand(Command);end;
procedure THubEngine.SetGamePonderAllowed(Allowed:Boolean);
begin FForcePonderOff:=not Allowed;end;
procedure THubEngine.GameMoveAccepted(const RootFEN:string;ActualMoves:TStrings;
  const NextOwnClock:TEngineGameClockState);
var Command:THubWorkerCommand;
begin
  Command:=THubWorkerCommand.Create(hwcAccepted);Command.StartingFEN:=RootFEN;
  Command.Moves.Assign(ActualMoves);Command.Clock:=NextOwnClock;QueueProcedureCommand(Command);
end;

procedure THubEngine.SetGamePosition(const AStartingFEN: string; AMoves: TStrings);
var
  Command: THubWorkerCommand;
begin
  Command := THubWorkerCommand.Create(hwcSetGamePosition);
  Command.StartingFEN := AStartingFEN;
  if AMoves <> nil then
    Command.Moves.Assign(AMoves);
  QueueProcedureCommand(Command);
end;

function THubEngine.StartThinking: string;
begin
  Result := QueueStringCommand(THubWorkerCommand.Create(hwcStartThinking));
end;

function THubEngine.Capabilities: TEngineCapabilities;
begin Result:=[ecAnalysis,ecHubMcts]; end;
procedure THubEngine.StartAnalyzing;
begin
  QueueProcedureCommand(THubWorkerCommand.Create(hwcStartAnalyzing));
end;

procedure THubEngine.StartMcts;
begin
  QueueProcedureCommand(THubWorkerCommand.Create(hwcStartMcts));
end;

procedure THubEngine.PollOutput;
begin
  QueueProcedureCommand(THubWorkerCommand.Create(hwcPollOutput));
end;

procedure THubEngine.StopSearch;
begin
  QueueProcedureCommand(THubWorkerCommand.Create(hwcStopSearch));
end;

function THubEngine.ReceiveMessage(const AMessage: string): string;
begin
  Result := '';
  if Pos('pos=', LowerCase(Trim(AMessage))) = 1 then
  begin
    ParsePositionMessage(AMessage);
    Exit;
  end;

  if Pos('level ', LowerCase(Trim(AMessage))) = 1 then
  begin
    FLevelCommand := Trim(AMessage);
    Log('level stored; message=' + FLevelCommand);
    Exit;
  end;

  if CompareText(Trim(AMessage), 'go think') = 0 then
  begin
    Result := StartThinking;
    if Result <> '' then
      Result := 'done move=' + Result
    else
      Result := 'done';
    Exit;
  end;
end;

procedure THubEngine.DoRequestStop;
begin
  FStopping := True;
end;

procedure THubEngine.RequestStop;
begin
  DoRequestStop;
end;

procedure THubEngine.DoStop;
begin
  inherited Stop;
  FStopping := True;
  if FWorker<>nil then FWorker.StopProcess;
end;

procedure THubEngine.Stop;
begin
  DoRequestStop;
  if (FWorker = nil) or FWorker.IsClosed then
    DoStop
  else
    QueueProcedureCommand(THubWorkerCommand.Create(hwcStop));
end;

function CreateHubEngine(ADefinition: TExternalEngineDefinition): TGameEngine;
begin
  Result := THubEngine.Create(ADefinition);
end;

initialization
  RegisterGameEngineFactory(eekHub, @CreateHubEngine);
end.
