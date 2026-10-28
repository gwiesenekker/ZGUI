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
    function NormalizeScoreToWhitePerspective(const AScore: string): string;
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

function ScoreText(AValue: Double): string;
var
  FormatSettings: TFormatSettings;
begin
  if Abs(AValue) < 0.0000005 then
    AValue := 0.0;
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  Result := FormatFloat('0.###', AValue, FormatSettings);
end;

function TryHubFloat(const AText: string; out AValue: Double): Boolean;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  Result := TryStrToFloat(StringReplace(Trim(AText), ',', '.', []), AValue,
    FormatSettings);
end;

function SideToMoveFromPosition(const AStartingFEN: string;
  AMoveCount: Integer): TDraughtsSide;
begin
  if (Trim(AStartingFEN) <> '') and (UpCase(Trim(AStartingFEN)[1]) = 'B') then
    Result := dsBlack
  else
    Result := dsWhite;
  if Odd(AMoveCount) then
  begin
    if Result = dsWhite then
      Result := dsBlack
    else
      Result := dsWhite;
  end;
end;

constructor THubWorkerCommand.Create(AKind: THubWorkerCommandKind);
const
  CommandNames: array[THubWorkerCommandKind] of string = (
    'hub-launch-and-init',
    'hub-begin-game',
    'hub-set-game-position',
    'hub-set-clock-info',
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
  FWorker:=TProcessEngineWorker.Create(@ExecuteWorkerCommand,@Log,@WorkerStopping,'Hub');
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
  FEngine.Free;
  inherited Destroy;
end;

procedure THubEngine.ProcessData(Sender: TObject; const AText: string);
var
  DepthText: string;
  InfoLine: string;
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
        if (Pos('info ', LowerCase(Line)) <> 1) and
          (Pos('info=', LowerCase(Line)) <> 1) then
        begin
          FWorker.AddReceivedLine(Line);
        end;
        if (Pos('info ', LowerCase(Line)) = 1) or
          (Pos('info=', LowerCase(Line)) = 1) then
        begin
          if Pos('info=', LowerCase(Line)) = 1 then
            InfoLine := 'info ' + Copy(Line, Length('info=') + 1, MaxInt)
          else
            InfoLine := Line;
          PvText := ExtractHubArgument(InfoLine, 'pv');
          if PvText <> '' then
          begin
            LoggedPvText := PvText;
          end;
          ScoreText := ExtractHubArgument(InfoLine, 'score');
          if ScoreText <> '' then
          begin
            LoggedScoreText := NormalizeScoreToWhitePerspective(ScoreText);
          end;
          DepthText := ExtractHubArgument(InfoLine, 'depth');
          if DepthText <> '' then
          begin
            LoggedDepthText := DepthText;
          end;
          TimeText := ExtractHubArgument(InfoLine, 'time');
          if TimeText <> '' then
          begin
            LoggedTimeText := TimeText;
          end;
        end;
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
  PublishSearchInfo(PvText,ScoreText,DepthText,TimeText);
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
      inherited BeginGame(HubCommand.StartingFEN, DraughtsSideToGameSide(HubCommand.Side),
        HubCommand.GameMinutes, HubCommand.GameMoves);
    hwcSetGamePosition:
      begin
        RequireSearchSynchronization;
        inherited SetGamePosition(HubCommand.StartingFEN, HubCommand.Moves);
      end;
    hwcSetClockInfo:
      DoSetClockInfo(HubCommand.MovesRemaining, HubCommand.RemainingSeconds,
        HubCommand.TotalUsedSeconds);
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
      AMove := MoveText;
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
  InitLines: TStringList;
  I: Integer;
  Line: string;
begin
  Result := False;
  if StopRequested then Exit;
  Args := TStringList.Create;
  InitLines := TStringList.Create;
  try
    FWorker.PrepareLaunch(FEngine,FParams,Args);
    FStopping := False;
    if StopRequested then Exit;
    Log('launch; executable=' + FEngine.ExePath);
    ChangeState(esLaunching, 'starting hub process');
    FProcess.Start(FEngine.ExePath, Args, ExtractFilePath(FEngine.ExePath));
    ChangeState(esInitializing, 'process launched; sending hub handshake');

    SendLine('hub');
    if not WaitForLine('wait', EngineStartupTimeoutMs(FParams), Line) then
      Log('hub wait not received before init; reason=' + FLastWaitFailure);
    SendHubParams;

    InitLines.Text := ExpandEnginePlaceholders(FEngine.InitText, FEngine);
    for I := 0 to InitLines.Count - 1 do
      if Trim(InitLines[I]) <> '' then
        SendLine(InitLines[I]);

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
    InitLines.Free;
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

function THubEngine.NormalizeScoreToWhitePerspective(
  const AScore: string): string;
var
  Perspective: string;
  ScoreValue: Double;
begin
  Result := Trim(AScore);
  if (Result = '') or (not TryHubFloat(Result, ScoreValue)) then
    Exit;

  Perspective := LowerCase(Trim(EngineParamValue(FParams,
    'gui-score-perspective', 'side-to-move')));
  if Perspective = '' then
    Perspective := 'side-to-move';

  if (Perspective = 'black') or (Perspective = 'b') then
    ScoreValue := -ScoreValue
  else if (Perspective = 'side-to-move') or (Perspective = 'stm') or
    (Perspective = 'side') then
  begin
    if SideToMoveFromPosition(StartingFEN, MovesPlayed.Count) = dsBlack then
      ScoreValue := -ScoreValue;
  end;

  Result := ScoreText(ScoreValue);
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

function THubEngine.DoStartThinking: string;
var
  Failure: string;
begin
  SendLine(BuildHubPositionCommand);
  if FLevelCommand <> '' then
    SendLine(FLevelCommand);
  DiscardDoneLinesBeforeNewSearch('before go think');
  SendLine('go think');
  ChangeState(esWaitingForDone, 'search started; waiting for done');

  if not WaitForDoneMove(MoveTimeLimitMs, Result) then
  begin
    Failure := FLastWaitFailure;
    if Failure = 'timeout' then
    begin
      MarkMoveTimedOut;
      // Fence the timed-out search before another game can reuse this engine.
      try
        DoStopSearch;
      except
        on E: Exception do
          Log('timed-out search could not be stopped; message=' + E.Message);
      end;
    end;
    ChangeState(esError, 'waiting for done move failed; reason=' +
      Failure);
    Result := '';
  end;
end;

procedure THubEngine.DoStopSearch;
var
  SearchWasActive: Boolean;
begin
  RequireSearchSynchronization;
  SearchWasActive := CurrentState in [esThinking, esWaitingForDone, esStopping];
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
  if SearchWasActive and (CurrentState <> esError) then
    ChangeState(esReady, 'search stopped');
end;

procedure THubEngine.DoStartAnalyzing;
begin
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
