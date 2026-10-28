unit uProcessEngineWorker;
{$mode objfpc}{$H+}
{ Extracted from the existing Hub worker. Protocols retain their own commands,
  parser and completion policy; this helper owns the shared process lifecycle. }
interface
uses Classes, SysUtils, SyncObjs, uPlatformProcess, uThreadMessageQueue,
  uEngineRegistry, uEngineParamsJson;
type
  TProcessEngineCommand=class(TThreadMessage)
  private
    FCompleted: TSimpleEvent;
  public
    BoolResult: Boolean;
    StringResult,ErrorMessage: string;
    AutoFree: Boolean;
    constructor Create(const AKind: string); reintroduce;
    destructor Destroy; override;
    procedure SignalCompleted;
    property Completed: TSimpleEvent read FCompleted;
  end;
  TWorkerExecute=procedure(Command: TObject) of object;
  TWorkerLog=procedure(const Text: string) of object;
  TWorkerStopping=function: Boolean of object;
  TProcessEngineWorker=class
  private
    FQueue: TThreadMessageQueue;
    FThread: TThread;
    FThreadId: TThreadID;
    FThreadIdValid: Boolean;
    FProtocol: string;
    FExecute: TWorkerExecute;
    FLog: TWorkerLog;
    FIsStopping: TWorkerStopping;
    FBuffer: string;
    FDroppingOutputLine: Boolean;
    FLineLock: TCriticalSection;
    FReceivedLines: TStringList;
    FProcess: TPlatformProcess;
    FLastWaitFailure: string;
    procedure Log(const Text: string);
    procedure WaitForWorkerCommand(ACommand: TThreadMessage; ACompleted: TSimpleEvent; const AErrorText: string);
  public
    constructor Create(AExecute: TWorkerExecute; ALog: TWorkerLog; AStopping: TWorkerStopping; const AProtocol: string);
    destructor Destroy; override;
    function IsWorkerThread: Boolean;
    function IsClosed: Boolean;
    function Post(Command: TProcessEngineCommand): Boolean;
    function QueueBoolCommand(ACommand: TObject): Boolean;
    function QueueStringCommand(ACommand: TObject): string;
    procedure QueueProcedureCommand(ACommand: TObject);
    procedure FrameData(const AText: string; ALines: TStrings);
    procedure AddReceivedLine(const Line: string);
    function TakeReceivedLine(const APrefix: string; out ALine: string): Boolean;
    function WaitForLine(const APrefix: string; ATimeoutMs: Integer; out ALine: string): Boolean;
    procedure SendLine(const Line: string);
    procedure PrepareLaunch(Definition: TExternalEngineDefinition; const Params: TEngineParamArray; Args: TStrings);
    procedure StopProcess;
    property Process: TPlatformProcess read FProcess;
    property LastWaitFailure: string read FLastWaitFailure;
  end;
implementation
const WorkerWaitPollMs=1000; WorkerWaitLogMs=10000;
type
  TProcessWorkerThread=class(TThread)
    Owner: TProcessEngineWorker;
    procedure Execute; override;
  end;
constructor TProcessEngineCommand.Create(const AKind: string);
begin inherited Create(AKind); FCompleted:=TSimpleEvent.Create; end;
destructor TProcessEngineCommand.Destroy;
begin FCompleted.Free; inherited; end;
procedure TProcessEngineCommand.SignalCompleted;
begin FCompleted.SetEvent; end;
procedure TProcessWorkerThread.Execute;
var Obj: TObject; C: TProcessEngineCommand; Release: Boolean;
begin
  Owner.FThreadId:=System.GetCurrentThreadId; Owner.FThreadIdValid:=True;
  try
    while not Terminated and Owner.FQueue.WaitPop(Obj) do begin
      if not (Obj is TProcessEngineCommand) then Continue;
      C:=TProcessEngineCommand(Obj); Release:=C.AutoFree;
      try Owner.FExecute(C); except on E:Exception do C.ErrorMessage:=E.Message; end;
      C.SignalCompleted;
      if Release then C.Free;
    end;
  finally Owner.FThreadIdValid:=False; end;
end;
constructor TProcessEngineWorker.Create(AExecute: TWorkerExecute; ALog: TWorkerLog; AStopping: TWorkerStopping; const AProtocol: string);
var Thread: TProcessWorkerThread;
begin
  inherited Create; FExecute:=AExecute; FLog:=ALog; FIsStopping:=AStopping; FProtocol:=AProtocol;
  FProcess:=TPlatformProcess.Create; FProcess.SynchronizeData:=False;
  FReceivedLines:=TStringList.Create; FLineLock:=TCriticalSection.Create;
  FQueue:=TThreadMessageQueue.Create(False);
  Thread:=TProcessWorkerThread.Create(True); Thread.FreeOnTerminate:=False; Thread.Owner:=Self;
  FThread:=Thread; Thread.Start;
end;
destructor TProcessEngineWorker.Destroy;
begin
  if FQueue<>nil then FQueue.Close;
  if FThread<>nil then begin FThread.Terminate; FThread.WaitFor; end;
  FThread.Free; FQueue.Free; FProcess.Free; FLineLock.Free; FReceivedLines.Free; inherited;
end;
procedure TProcessEngineWorker.Log(const Text: string);
begin if Assigned(FLog) then FLog(Text); end;
function TProcessEngineWorker.IsWorkerThread: Boolean;
begin Result:=FThreadIdValid and (System.GetCurrentThreadId=FThreadId); end;
function TProcessEngineWorker.IsClosed: Boolean;
begin Result:=FQueue.IsClosed; end;
function TProcessEngineWorker.Post(Command: TProcessEngineCommand): Boolean;
begin Result:=FQueue.TryPost(Command); end;
procedure TProcessEngineWorker.FrameData(const AText: string; ALines: TStrings);
var DelimiterLength,LineEnd: Integer; Line: string;
begin
  FLineLock.Acquire;
  try
    FBuffer += AText;
    while True do
    begin
      DelimiterLength := Length(LineEnding);
      LineEnd := Pos(LineEnding, FBuffer);
      if LineEnd = 0 then
      begin
        LineEnd := Pos(#10, FBuffer);
        DelimiterLength := 1;
      end;
      if LineEnd = 0 then
      begin
        if Length(FBuffer) > 65536 then
        begin FBuffer := ''; FDroppingOutputLine := True; end;
        Break;
      end;
      if FDroppingOutputLine or (LineEnd > 65537) then
      begin
        Delete(FBuffer, 1, LineEnd + DelimiterLength - 1);
        FDroppingOutputLine := False;
        Continue;
      end;

      Line := Trim(Copy(FBuffer, 1, LineEnd - 1));
      Delete(FBuffer, 1, LineEnd + DelimiterLength - 1);
      if Line<>'' then ALines.Add(Line);
    end;
  finally FLineLock.Release; end;
end;
procedure TProcessEngineWorker.AddReceivedLine(const Line: string);
begin
  FLineLock.Acquire;
  try FReceivedLines.Add(Line); if FReceivedLines.Count>1024 then FReceivedLines.Delete(0);
  finally FLineLock.Release; end;
end;
procedure TProcessEngineWorker.SendLine(const Line: string);
begin Log('send; message='+Line); FProcess.WriteLine(Line); end;
procedure TProcessEngineWorker.PrepareLaunch(Definition: TExternalEngineDefinition; const Params: TEngineParamArray; Args: TStrings);
var Arguments: string;
begin
  Arguments:=EngineParamValue(Params,EngineLaunchArgumentParamName(Definition.Kind),Definition.Arguments);
  SplitLaunchArguments(ExpandEnginePlaceholders(Arguments,Definition),Args);
  Definition.IniFileName:=EngineParamValue(Params,'gui-ini-file',Definition.IniFileName);
  Definition.IniContent:=EngineParamValue(Params,'gui-ini-content',Definition.IniContent);
  WriteEngineIniFile(Definition.IniFileName,Definition.IniContent,Definition);
  if Trim(Definition.IniFileName)<>'' then Log('wrote expanded INI/config file; file='+Definition.IniFileName);
end;
procedure TProcessEngineWorker.StopProcess;
begin
  if FProcess.IsRunning then begin
    try SendLine('stop'); except on E:Exception do Log('stop command failed; message='+E.Message); end;
    if FProcess.IsRunning then begin Log('request graceful quit'); FProcess.RequestQuit('quit',1000); end;
    if FProcess.IsRunning then begin Log('terminate process after quit timeout'); FProcess.Terminate(1000); end;
  end;
  FProcess.Close;
end;
procedure TProcessEngineWorker.WaitForWorkerCommand(ACommand: TThreadMessage;
  ACompleted: TSimpleEvent; const AErrorText: string);
var
  ElapsedMs: QWord;
  LastLogTick: QWord;
  StartTick: QWord;
  WaitResult: TWaitResult;
begin
  StartTick := GetTickCount64;
  LastLogTick := StartTick;
  repeat
    WaitResult := ACompleted.WaitFor(WorkerWaitPollMs);
    if WaitResult = wrSignaled then
      Exit;
    if WaitResult = wrError then
      raise ESyncObjectException.Create(AErrorText);

    if GetTickCount64 - LastLogTick >= WorkerWaitLogMs then
    begin
      ElapsedMs := GetTickCount64 - StartTick;
      Log('worker command still waiting; command=' + ACommand.Kind +
        '; elapsed_ms=' + IntToStr(ElapsedMs) +
        '; queue_count=' + IntToStr(FQueue.Count));
      LastLogTick := GetTickCount64;
    end;
  until False;
end;

function TProcessEngineWorker.QueueBoolCommand(ACommand: TObject): Boolean;
var
  Command: TProcessEngineCommand;
begin
  Result := False;
  if not (ACommand is TProcessEngineCommand) then
    Exit;
  Command := TProcessEngineCommand(ACommand);
  try
    if IsWorkerThread then
    begin
      FExecute(Command);
      Result := Command.BoolResult;
      Exit;
    end;
    if (FQueue = nil) or (not FQueue.TryPost(Command)) then
      raise EInvalidOperation.Create(FProtocol+' worker queue is closed');
    WaitForWorkerCommand(Command, Command.Completed,
      FProtocol+' worker command wait failed');
    if Command.ErrorMessage <> '' then
      raise EInvalidOperation.Create(Command.ErrorMessage);
    Result := Command.BoolResult;
  finally
    Command.Free;
  end;
end;

procedure TProcessEngineWorker.QueueProcedureCommand(ACommand: TObject);
var
  Command: TProcessEngineCommand;
begin
  if not (ACommand is TProcessEngineCommand) then
    Exit;
  Command := TProcessEngineCommand(ACommand);
  try
    if IsWorkerThread then
    begin
      FExecute(Command);
      Exit;
    end;
    if (FQueue = nil) or (not FQueue.TryPost(Command)) then
      raise EInvalidOperation.Create(FProtocol+' worker queue is closed');
    WaitForWorkerCommand(Command, Command.Completed,
      FProtocol+' worker command wait failed');
    if Command.ErrorMessage <> '' then
      raise EInvalidOperation.Create(Command.ErrorMessage);
  finally
    Command.Free;
  end;
end;

function TProcessEngineWorker.QueueStringCommand(ACommand: TObject): string;
var
  Command: TProcessEngineCommand;
begin
  Result := '';
  if not (ACommand is TProcessEngineCommand) then
    Exit;
  Command := TProcessEngineCommand(ACommand);
  try
    if IsWorkerThread then
    begin
      FExecute(Command);
      Result := Command.StringResult;
      Exit;
    end;
    if (FQueue = nil) or (not FQueue.TryPost(Command)) then
      raise EInvalidOperation.Create(FProtocol+' worker queue is closed');
    WaitForWorkerCommand(Command, Command.Completed,
      FProtocol+' worker command wait failed');
    if Command.ErrorMessage <> '' then
      raise EInvalidOperation.Create(Command.ErrorMessage);
    Result := Command.StringResult;
  finally
    Command.Free;
  end;
end;

function TProcessEngineWorker.TakeReceivedLine(const APrefix: string; out ALine: string
  ): Boolean;
var
  I: Integer;
begin
  Result := False;
  ALine := '';
  FLineLock.Acquire;
  try
    for I := 0 to FReceivedLines.Count - 1 do
      if (APrefix = '') or (CompareText(Copy(FReceivedLines[I], 1,
        Length(APrefix)), APrefix) = 0) then
      begin
        ALine := FReceivedLines[I];
        FReceivedLines.Delete(I);
        Exit(True);
      end;
  finally
    FLineLock.Release;
  end;
end;

function TProcessEngineWorker.WaitForLine(const APrefix: string; ATimeoutMs: Integer;
  out ALine: string): Boolean;
var
  StartTick: QWord;
begin
  Result := False;
  ALine := '';
  FLastWaitFailure := '';
  StartTick := GetTickCount64;
  repeat
    if Assigned(FIsStopping) and FIsStopping() then
    begin
      FLastWaitFailure := 'stopping';
      Exit(False);
    end;
    if FProcess.NeedsPolling then
      FProcess.ReadAvailable;
    if TakeReceivedLine(APrefix, ALine) then
      Exit(True);
    if not FProcess.HasProcess then
    begin
      FLastWaitFailure := 'process missing';
      Log('wait aborted; process missing; expected=' + APrefix);
      Exit(False);
    end;
    if not FProcess.IsRunning then
    begin
      FLastWaitFailure := 'process exited';
      Log('wait aborted; process exited; expected=' + APrefix);
      Exit(False);
    end;
    Sleep(25);
  until GetTickCount64 - StartTick >= QWord(ATimeoutMs);
  FLastWaitFailure := 'timeout';
  Log('wait timeout; expected=' + APrefix + '; timeout_ms=' +
    IntToStr(ATimeoutMs));
end;

end.
