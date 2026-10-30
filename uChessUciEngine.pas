unit uChessUciEngine;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, SyncObjs, uEngineBase, uEngineRegistry, uEngineParamsJson,
  uProcessEngineWorker, uChessPosition, uGamePosition;
type
  TUciEngine=class(TGameEngine)
  private
    FWorker: TProcessEngineWorker;
    FDefinition: TExternalEngineDefinition;
    FParams,FOptions: TEngineParamArray;
    FPosition: TChessPosition;
    FCancel: LongInt;
    FSearching,FFaulted,FExpectUci,FExpectReady: Boolean;
    FStartedTick: QWord;
    FGameMode,FHasClock,FForcePonderOff,FStoppingPonder: Boolean;
    FClock,FPonderClock: TEngineGameClockState;
    FPonderActive,FHasPending: Boolean;
    FPendingRoot,FSearchRoot,FSearchMoves,FNextReply: string;
    FPendingMoves: TStringList;
    FDurationMs,FStopMs: Integer;
    FReportedName,FBestMove,FFaultText: string;
    procedure Idle;
    procedure ClearPonder;
    procedure Accepted(const Root: string; Moves: TStrings; const Clock: TEngineGameClockState);
    function ClockGo(const Clock: TEngineGameClockState; Ponder: Boolean): string;
    function SearchWaitMs: Integer;
    procedure SetAnalysisOption;
    procedure ExecuteWorkerCommand(Obj: TObject);
    function WorkerStopping: Boolean;
    procedure ProcessData(Sender: TObject; const Text: string);
    procedure ConsumeLine(const Line: string);
    procedure Fault(const Text: string);
    procedure Ready;
    function Initialize: Boolean;
    procedure SendOptions;
    procedure StopCurrentSearch(WaitLimitMs: Integer=-1);
    procedure StartSearch;
    procedure Poll;
    procedure ApplyPosition(const Fen: string; Moves: TStrings);
    procedure RequireReady;
  protected
    function DoStartThinking: string; override;
  public
    constructor Create(Definition: TExternalEngineDefinition); reintroduce;
    destructor Destroy; override;
    function ProtocolName: string; override;
    function Capabilities: TEngineCapabilities; override;
    function LaunchAndInit: Boolean; override;
    // Editor submits to the same owned runtime worker; caller owns completion.
    procedure ConfigureOptions(const Params: TEngineParamArray);
    function BeginInitialize: TProcessEngineCommand;
    function DiscoveredOptions: TEngineParamArray;
    function ReportedName: string;
    function BeginButton(const Name: string): TProcessEngineCommand;
    procedure PressButton(const Name: string);
    procedure BeginGame(const Fen: string; Side: TGameSide; Minutes: Double; Moves: Integer; Increment: Double=0); override;
    procedure SetGameClockState(const Clock: TEngineGameClockState); override;
    procedure SetGamePonderAllowed(Allowed: Boolean); override;
    procedure GameMoveAccepted(const RootFEN: string; ActualMoves: TStrings;
      const NextOwnClock: TEngineGameClockState); override;
    procedure NewGame(const Fen: string); override;
    procedure SetGamePosition(const Fen: string; Moves: TStrings); override;
    procedure SetClockInfo(MovesRemaining: Integer; Remaining,Used: Double); override;
    procedure StartAnalyzing; override;
    function StartThinking: string; override;
    procedure StopSearch; override;
    procedure PollOutput; override;
    procedure RequestStop; override;
    procedure Stop; override;
  end;
implementation
uses Math, uChessUciProtocol;
type
  TUciCommandKind=(ucInit,ucPosition,ucNewGame,ucBudget,ucAnalyze,ucThink,ucPoll,ucStopSearch,ucShutdown,ucData,ucButton,ucBegin,ucClock,ucAccepted);
  TUciCommand=class(TProcessEngineCommand)
    Operation: TUciCommandKind;
    Text: string;
    Moves: TStringList;
    Seconds,Increment: Double;
    Side: TGameSide;
    MoveCount: Integer;
    Clock: TEngineGameClockState;
    constructor Create(AKind: TUciCommandKind); reintroduce;
    destructor Destroy; override;
  end;
constructor TUciCommand.Create(AKind: TUciCommandKind);
begin inherited Create('uci-'+IntToStr(Ord(AKind))); Operation:=AKind; Moves:=TStringList.Create; AutoFree:=AKind in [ucData,ucAccepted]; end;
destructor TUciCommand.Destroy;
begin Moves.Free; inherited; end;
constructor TUciEngine.Create(Definition: TExternalEngineDefinition);
begin
  inherited Create(EnginePickerDisplayName(Definition,0));
  FDefinition:=TExternalEngineDefinition.Create; FDefinition.Assign(Definition);
  FPendingMoves:=TStringList.Create; FPosition:=TChessPosition.Create; FDurationMs:=1000; FStopMs:=1500;
  LoadEngineParamsFromJson(EngineParamsFileName(Definition.ExePath),'uci',FParams);
  FStopMs:=StrToIntDef(EngineParamValue(FParams,'gui-stop-timeout-ms','1500'),1500);
  FStopMs:=Max(100,Min(10000,FStopMs));
  FWorker:=TProcessEngineWorker.Create(@ExecuteWorkerCommand,@Log,@WorkerStopping,'UCI',@Idle);
  FWorker.Process.OnData:=@ProcessData;
end;
destructor TUciEngine.Destroy;
begin
  try Stop; finally FWorker.Free; FPendingMoves.Free; FPosition.Free; FDefinition.Free; inherited; end;
end;
function TUciEngine.ProtocolName: string;
begin Result:='UCI'; end;
function TUciEngine.Capabilities: TEngineCapabilities;
begin Result:=[ecAnalysis]; end;
function TUciEngine.WorkerStopping: Boolean;
begin Result:=(InterlockedCompareExchange(FCancel,0,0)<>0) or StopRequested; end;
procedure TUciEngine.RequestStop;
begin InterlockedExchange(FCancel,1); end;
procedure TUciEngine.Fault(const Text: string);
begin
  InterlockedExchange(FCancel,1); FFaulted:=True; FSearching:=False; FFaultText:=Text;
  ClearPonder; SetLastError(Text); ChangeState(esError,Text); Log('error; '+Text);
end;
procedure TUciEngine.RequireReady;
begin
  if FFaulted then raise EInvalidOperation.Create(FFaultText);
  if WorkerStopping or not FWorker.Process.IsRunning then raise EInvalidOperation.Create('UCI session is not synchronized; reopen the engine');
end;
procedure TUciEngine.Ready;
var Line: string;
begin
  FExpectReady:=True; FWorker.SendLine('isready');
  if not FWorker.WaitForLine('readyok',EngineStartupTimeoutMs(FParams),Line) then
    begin Fault('UCI readyok not received: '+FWorker.LastWaitFailure); FWorker.StopProcess; raise EInvalidOperation.Create(LastError); end;
end;
procedure TUciEngine.SendOptions;
var I,J: Integer; P: TEngineParam; Value,Line: string; Found: Boolean;
begin
  for I:=0 to High(FOptions) do begin
    P:=FOptions[I]; Value:=EngineParamValue(FParams,P.Name,P.DefaultValue);
    if SameText(P.Name,'Ponder') or SameText(P.Name,'UCI_Chess960') then Value:='false';
    if SameText(P.Name,'MultiPV') then Value:='1';
    if SameText(P.Name,'UCI_AnalyseMode') then Value:='true';
    if SameText(P.Name,'OwnBook') and (P.ParamType='check') then Value:='false';
    FOptions[I].Value:=Value;
    if P.ParamType='button' then Continue;
    ValidateUciValue(P,Value); if P.ParamType='check' then Value:=LowerCase(Value);
    Line:='setoption name '+P.Name+' value '+Value; FWorker.SendLine(Line);
  end;
  for I:=0 to High(FParams) do if Copy(LowerCase(FParams[I].Name),1,4)<>'gui-' then begin
    Found:=False;
    for J:=0 to High(FOptions) do if SameText(FParams[I].Name,FOptions[J].Name) then Found:=True;
    if not Found then Log('saved option not advertised; retained without sending: '+FParams[I].Name);
  end;
end;
function TUciEngine.Initialize: Boolean;
var Args,Init: TStringList; Line: string; I: Integer;
begin
  Result:=False; Args:=TStringList.Create; Init:=TStringList.Create;
  try
    try
      if WorkerStopping then Exit;
      Init.Text:=FDefinition.InitText;
      for I:=0 to Init.Count-1 do begin
        Line:=Trim(Init[I]);
        if (Line<>'') and (Line<>'debug on') and (Line<>'debug off') and (Line<>'register later') then
          raise EConvertError.Create('UCI initialization accepts only debug on/off or register later; use the option grid for settings');
      end;
      FOptions:=nil; FWorker.PrepareLaunch(FDefinition,FParams,Args);
      ChangeState(esLaunching,'starting UCI process');
      FWorker.Process.Start(FDefinition.ExePath,Args,ExtractFilePath(FDefinition.ExePath));
      ChangeState(esInitializing,'UCI handshake'); FExpectUci:=True; FWorker.SendLine('uci');
      if not FWorker.WaitForLine('uciok',EngineStartupTimeoutMs(FParams),Line) then
        raise EInvalidOperation.Create('UCI uciok not received: '+FWorker.LastWaitFailure);
      SendOptions;
      for I:=0 to Init.Count-1 do if Trim(Init[I])<>'' then FWorker.SendLine(Trim(Init[I]));
      ChangeState(esWaitingForReady,'waiting for readyok'); Ready;
      FFaulted:=False; ChangeState(esReady,'UCI ready'); Result:=True;
    except on E:Exception do begin Fault(E.Message); FWorker.StopProcess; end; end;
  finally Args.Free; Init.Free; end;
end;
procedure TUciEngine.ProcessData(Sender: TObject; const Text: string);
var C: TUciCommand; Lines: TStringList; I: Integer;
  BeforePV,BeforeScore,BeforeDepth,BeforeTime,PV,Score,Depth,TimeText: string;
begin
  if not FWorker.IsWorkerThread then begin
    C:=TUciCommand.Create(ucData); C.Text:=Text; if not FWorker.Post(C) then C.Free; Exit;
  end;
  ReadSearchInfo(BeforePV,BeforeScore,BeforeDepth,BeforeTime);
  Lines:=TStringList.Create;
  try
    FWorker.FrameData(Text,Lines);
    for I:=0 to Lines.Count-1 do ConsumeLine(Lines[I]);
  finally Lines.Free; end;
  // Publish only after parsing the complete chunk, as in the existing Hub path.
  Log('stdout; text='+StringReplace(Text,LineEnding,'\n',[rfReplaceAll]));
  ReadSearchInfo(PV,Score,Depth,TimeText);
  // The game runner can hide raw stdout while retaining live analysis updates.
  if (PV<>'') and ((PV<>BeforePV) or (Score<>BeforeScore) or (Depth<>BeforeDepth) or (TimeText<>BeforeTime)) then
    Log('search-info; pv='+PV+'; score='+Score+'; depth='+Depth+'; time='+TimeText);
end;
procedure TUciEngine.ConsumeLine(const Line: string);
var P: TEngineParam; Info: TUciInfo; Trial: TChessPosition; Moves: TStringList;
  I: Integer; Canonical,PV,Score: string; Value: Int64; FS: TFormatSettings;
begin
  if FExpectUci and ParseUciOption(Line,P) then begin
    for I:=0 to High(FOptions) do if SameText(FOptions[I].Name,P.Name) then begin FOptions[I]:=P; Exit; end;
    if Length(FOptions)>=4096 then raise EConvertError.Create('Too many UCI options');
    SetLength(FOptions,Length(FOptions)+1); FOptions[High(FOptions)]:=P; Exit;
  end;
  if FExpectUci and (Copy(Line,1,8)='id name ') then begin FReportedName:=Copy(Line,9,MaxInt); Exit; end;
  if Copy(Line,1,9)='bestmove ' then begin
    if not FSearching then begin if not WorkerStopping then Fault('Unexpected/duplicate UCI bestmove'); Exit; end;
    FSearching:=False; FNextReply:='';
    Moves:=TStringList.Create;
    try
      ExtractStrings([' ',#9],[],PChar(Line),Moves);
      FBestMove:=LowerCase(Moves[1]);
      if (FBestMove='0000') or (FBestMove='(none)') then begin
        if FPosition.LegalMoveCount>0 then Fault('UCI returned no move in a playable position'); FBestMove:='';
      end else if not FPosition.IsLegal(FBestMove) then begin Fault('Illegal UCI bestmove '+FBestMove); FBestMove:=''; end;
      if not FFaulted and (FBestMove<>'') and (Moves.Count=4) and (Moves[2]='ponder') then begin
        Trial:=TChessPosition(FPosition.Clone);
        try
          Trial.PlayMove(FBestMove);
          if Trial.IsLegal(LowerCase(Moves[3])) then FNextReply:=LowerCase(Moves[3])
          else Log('ignored illegal optional ponder reply');
        finally Trial.Free; end;
      end;
    finally Moves.Free; end;
    if FPonderActive and not FFaulted then begin
      if FStoppingPonder then Log('ponder miss acknowledged')
      else Log('early ponder bestmove retained');
    end;
    if not FFaulted then ChangeState(esReady,'UCI search completed');
    FWorker.AddReceivedLine(Line); Exit;
  end;
  if Line='uciok' then begin if FExpectUci then begin FExpectUci:=False; FWorker.AddReceivedLine(Line); end; Exit; end;
  // Readiness fences option/new-game processing; it never acknowledges stop.
  if Line='readyok' then begin if FExpectReady then begin FExpectReady:=False; FWorker.AddReceivedLine(Line); end; Exit; end;
  // A bound is not an exact evaluation of the published line. Preserve the
  // last complete exact tuple, including its depth, instead of mixing updates.
  if FPonderActive or not FSearching or WorkerStopping or FFaulted then Exit;
  if not ParseUciInfo(Line,Info) or Info.Bounded or (Info.MultiPV<>1) or
    not Info.HasScore or (Info.PV='') then Exit;
  Trial:=TChessPosition(FPosition.Clone); Moves:=TStringList.Create; PV:='';
  try
    ExtractStrings([' ',#9],[],PChar(Info.PV),Moves);
    for I:=0 to Min(Moves.Count-1,255) do begin
      Canonical:=LowerCase(Moves[I]);
      if ((Length(Canonical)<>4) and (Length(Canonical)<>5)) or not Trial.IsLegal(Canonical) then Break;
      if PV<>'' then PV+=' '; PV+=Canonical; Trial.PlayMove(Canonical);
    end;
  finally Trial.Free; Moves.Free; end;
  if PV='' then Exit;
  Score:=Info.Score;
  if Copy(Score,1,1)='#' then begin
    Value:=StrToInt64(Copy(Score,2,MaxInt)); if FPosition.SideToMove=gsBlack then Value:=-Value;
    Score:='#'+IntToStr(Value);
  end else begin
    Value:=StrToInt64(Score); if FPosition.SideToMove=gsBlack then Value:=-Value;
    FS:=DefaultFormatSettings; FS.DecimalSeparator:='.'; Score:=FormatFloat('0.00',Value/100,FS);
  end;
  if Info.TimeText<>'' then begin
    FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
    Info.TimeText:=FormatFloat('0.###',StrToInt64(Info.TimeText)/1000,FS);
  end;
  PublishSearchInfo(PV,Score,Info.Depth,Info.TimeText);
end;
procedure TUciEngine.ApplyPosition(const Fen: string; Moves: TStrings);
var Trial: TChessPosition; I: Integer;
begin
  RequireReady;
  Trial:=TChessPosition.Create;
  try
    Trial.LoadFromFEN(Fen); if Moves<>nil then for I:=0 to Moves.Count-1 do Trial.PlayMove(Moves[I]);
    FHasClock:=False;
    if FPonderActive then begin
      FPendingRoot:=Fen; FPendingMoves.Clear;
      if Moves<>nil then FPendingMoves.Assign(Moves);
      FHasPending:=True; Exit;
    end;
    if FSearching then StopCurrentSearch;
    ClearPonder;
    inherited SetGamePosition(Fen,Moves); FPosition.AssignFrom(Trial);
  finally Trial.Free; end;
end;
procedure TUciEngine.ClearPonder;
begin
  FPonderActive:=False; FStoppingPonder:=False; FNextReply:=''; FHasPending:=False; FPendingMoves.Clear;
end;
procedure TUciEngine.Idle;
begin
  if not FPonderActive or FFaulted then Exit;
  try
    if WorkerStopping then begin
      FSearching:=False; ClearPonder; FWorker.StopProcess; Exit;
    end;
    if FWorker.Process.NeedsPolling then FWorker.Process.ReadAvailable;
    if not FWorker.Process.IsRunning then Fault('UCI process exited while pondering');
  except on E:Exception do Fault('UCI ponder idle service: '+E.Message); end;
end;
procedure TUciEngine.Accepted(const Root: string; Moves: TStrings; const Clock: TEngineGameClockState);
var I: Integer; Enabled: Boolean; Trial: TChessPosition; Reply,Line: string;
begin
  if WorkerStopping or FFaulted or FForcePonderOff or not FGameMode or (FNextReply='') then Exit;
  Enabled:=False;
  for I:=0 to High(FOptions) do if SameText(FOptions[I].Name,'Ponder') and
    (FOptions[I].ParamType='check') and SameText(FOptions[I].Value,'true') then Enabled:=True;
  if not Enabled or (Root<>FSearchRoot) or (Moves.Text<>FSearchMoves+FBestMove+LineEnding) then Exit;
  Trial:=TChessPosition.Create;
  try
    Trial.LoadFromFEN(Root);
    for I:=0 to Moves.Count-1 do Trial.PlayMove(Moves[I]);
    Reply:=FNextReply; FNextReply:='';
    if not Trial.IsLegal(Reply) then Exit;
    Trial.PlayMove(Reply);
    if Trial.LegalMoveCount=0 then Exit;
    inherited SetGamePosition(Root,Moves); MovesPlayed.Add(Reply);
    FPosition.AssignFrom(Trial); FPonderClock:=Clock;
    FSearchRoot:=Root; FSearchMoves:=MovesPlayed.Text;
    while FWorker.TakeReceivedLine('bestmove',Line) do ;
    if Root=ChessStartingFEN then Line:='position startpos' else Line:='position fen '+Root;
    Line+=' moves'; for I:=0 to MovesPlayed.Count-1 do Line+=' '+MovesPlayed[I];
    FWorker.SendLine(Line); FBestMove:=''; FPonderActive:=True;FSearching:=True;
    FWorker.SendLine(ClockGo(Clock,True)); Log('ponder started');
  finally Trial.Free; end;
end;
function TUciEngine.SearchWaitMs: Integer;
begin
  if FGameMode then Result:=MoveTimeLimitMs else Result:=Min(MoveTimeLimitMs,FDurationMs+FStopMs);
end;
procedure TUciEngine.SetAnalysisOption;
var I: Integer; Value: string; Changed: Boolean;
begin
  Changed:=False;
  for I:=0 to High(FOptions) do begin
    if SameText(FOptions[I].Name,'UCI_AnalyseMode') then begin
      if FGameMode then Value:='false' else Value:='true';
    end else if SameText(FOptions[I].Name,'OwnBook') and (FOptions[I].ParamType='check') then begin
      // A book reply may have no score/PV (e.g. Arasan). Analysis must search;
      // actual games retain the saved book preference or advertised default.
      Value:='false';
      if FGameMode then Value:=LowerCase(EngineParamValue(FParams,
        FOptions[I].Name,FOptions[I].DefaultValue));
    end else if SameText(FOptions[I].Name,'Ponder') and (FOptions[I].ParamType='check') then begin
      Value:='false';
      if FGameMode and not FForcePonderOff and SameText(EngineParamValue(FParams,'Ponder','false'),'true') then Value:='true';
    end else Continue;
    if FOptions[I].Value=Value then Continue;
    FWorker.SendLine('setoption name '+FOptions[I].Name+' value '+Value);
    FOptions[I].Value:=Value; Changed:=True;
  end;
  if Changed then Ready;
end;
function UciMilliseconds(Seconds: Double): string;
begin
  if IsNan(Seconds) or IsInfinite(Seconds) or (Seconds<0) or (Seconds>=9.22e15) then
    raise EConvertError.Create('Invalid UCI clock seconds');
  Result:=IntToStr(Trunc(Seconds*1000));
end;
function TUciEngine.ClockGo(const Clock: TEngineGameClockState; Ponder: Boolean): string;
begin
  Result:='go'; if Ponder then Result+=' ponder';
  Result+=' wtime '+UciMilliseconds(Clock.Remaining[gsWhite])+' btime '+UciMilliseconds(Clock.Remaining[gsBlack])+
    ' winc '+UciMilliseconds(Clock.Increment[gsWhite])+' binc '+UciMilliseconds(Clock.Increment[gsBlack]);
  if Clock.MovesRemaining>0 then Result+=' movestogo '+IntToStr(Clock.MovesRemaining);
end;
procedure TUciEngine.StartSearch;
var Line: string; I: Integer;
begin
  RequireReady; StopCurrentSearch;
  while FWorker.TakeReceivedLine('bestmove',Line) do ;
  if FPosition.LegalMoveCount=0 then Exit;
  if FGameMode and (not FHasClock or (FClock.SideToMove<>FPosition.SideToMove)) then raise EInvalidOperation.Create('Fresh game clocks required for current position');
  SetAnalysisOption;
  PublishSearchInfo('','','','');
  if StartingFEN=ChessStartingFEN then Line:='position startpos' else Line:='position fen '+StartingFEN;
  if MovesPlayed.Count>0 then begin Line+=' moves'; for I:=0 to MovesPlayed.Count-1 do Line+=' '+MovesPlayed[I]; end;
  FSearchRoot:=StartingFEN; FSearchMoves:=MovesPlayed.Text; FNextReply:='';
  FWorker.SendLine(Line); FBestMove:=''; FSearching:=True;FStartedTick:=GetTickCount64;
  if FGameMode then begin
    Line:=ClockGo(FClock,False);
    FHasClock:=False;
  end else Line:='go movetime '+IntToStr(FDurationMs);
  ChangeState(esThinking,'UCI search started'); FWorker.SendLine(Line);
end;
procedure TUciEngine.StopCurrentSearch(WaitLimitMs: Integer);
var Line: string; TimeoutMs: Integer;
begin
  RequireReady;
  if FSearching then begin
    FStoppingPonder:=FPonderActive;
    TimeoutMs:=FStopMs;
    if WaitLimitMs>=0 then TimeoutMs:=Max(1,Min(TimeoutMs,WaitLimitMs));
    FWorker.SendLine('stop'); ChangeState(esStopping,'waiting for bestmove');
    // UCI has no search IDs. Do not send another position/go until this search
    // completes; a missing bestmove makes the process unusable.
    if not FWorker.WaitForLine('bestmove',TimeoutMs,Line) then begin
      if (WaitLimitMs>=0) and (WaitLimitMs<=FStopMs) and
        (FWorker.LastWaitFailure='timeout') and not StopRequested and not FFaulted then
        MarkMoveTimedOut;
      Fault('UCI stop acknowledgement missing: '+FWorker.LastWaitFailure); FWorker.StopProcess;
      raise EInvalidOperation.Create(LastError);
    end;
  end;
  if FFaulted then raise EInvalidOperation.Create(LastError);
  ClearPonder;
end;
procedure TUciEngine.Poll;
begin
  if FWorker.Process.NeedsPolling then FWorker.Process.ReadAvailable;
  if FFaulted then raise EInvalidOperation.Create(LastError);
  if not WorkerStopping then begin
    if not FWorker.Process.IsRunning then begin Fault('UCI process exited'); raise EInvalidOperation.Create(LastError); end;
    if FFaulted then raise EInvalidOperation.Create(LastError);
    if FSearching and not FPonderActive and (GetTickCount64-FStartedTick>QWord(SearchWaitMs)) then begin
      Fault('UCI search exceeded its finite budget'); FWorker.StopProcess; raise EInvalidOperation.Create(LastError);
    end;
  end;
end;
function TUciEngine.DoStartThinking: string;
var Line: string; StartTick,Elapsed: QWord; WaitMs: Integer;
  Own: TGameSide; Hit: Boolean; Root: string; Moves: TStringList;
begin
  StartTick:=GetTickCount64;
  RequireReady;
  if FPonderActive then begin
    if not FHasPending or not FHasClock then raise EInvalidOperation.Create('Fresh actual position and game clocks required after pondering');
    // Drain before changing phase: an early result belongs to the predicted position.
    if FWorker.Process.NeedsPolling then FWorker.Process.ReadAvailable;
    RequireReady;
    Own:=FPonderClock.SideToMove;
    // M5: the opponent's clocks are stale by design. Only our own budget
    // and the complete actual history determine whether this search is reusable.
    Hit:=(FPendingRoot=FSearchRoot) and (FPendingMoves.Text=FSearchMoves) and
      (FClock.SideToMove=Own) and (FClock.Remaining[Own]=FPonderClock.Remaining[Own]) and
      (FClock.Increment[Own]=FPonderClock.Increment[Own]) and
      (FClock.MovesRemaining=FPonderClock.MovesRemaining);
    Root:=FPendingRoot; Moves:=TStringList.Create;
    try
      Moves.Assign(FPendingMoves);
      if Hit then begin
        inherited SetGamePosition(Root,Moves); FHasPending:=False; FHasClock:=False;
        PublishSearchInfo('','','','');
        if not FSearching then begin
          // M4: already completed. Never send ponderhit and invite another reply.
          FPonderActive:=False;
          while FWorker.TakeReceivedLine('bestmove',Line) do ;
          Exit(FBestMove);
        end;
        FWorker.SendLine('ponderhit'); FPonderActive:=False; FStartedTick:=StartTick;
        Log('ponder hit');
      end else begin
        Elapsed:=GetTickCount64-StartTick;
        StopCurrentSearch(Max(1,SearchWaitMs-Integer(Min(Elapsed,QWord(High(Integer))))));
        inherited SetGamePosition(Root,Moves);
        FPosition.LoadFromFEN(Root);
        for WaitMs:=0 to Moves.Count-1 do FPosition.PlayMove(Moves[WaitMs]);
        Elapsed:=GetTickCount64-StartTick;
        if Elapsed>=QWord(SearchWaitMs) then begin MarkMoveTimedOut; Exit(''); end;
        FClock.Remaining[FClock.SideToMove]:=Max(0,FClock.Remaining[FClock.SideToMove]-Elapsed/1000);
        Log('ponder miss; previous result discarded');
        StartSearch;
      end;
    finally Moves.Free; end;
  end else StartSearch;
  if not FSearching then Exit('');
  Elapsed:=GetTickCount64-StartTick;
  WaitMs:=Max(1,SearchWaitMs-Integer(Min(Elapsed,QWord(High(Integer)))));
  if (Elapsed>=QWord(SearchWaitMs)) or not FWorker.WaitForLine('bestmove',WaitMs,Line) then begin
    if StopRequested then Exit('');
    if FFaulted then raise EInvalidOperation.Create(LastError);
    if FWorker.LastWaitFailure='stopping' then Exit('');
    if (Elapsed>=QWord(SearchWaitMs)) or (FWorker.LastWaitFailure='timeout') then MarkMoveTimedOut;
    Line:='UCI bestmove not received: '+FWorker.LastWaitFailure;
    Fault(Line); FWorker.StopProcess;
    if MoveTimedOut then Exit('');
    raise EInvalidOperation.Create(Line);
  end;
  if FFaulted then raise EInvalidOperation.Create(LastError); Result:=FBestMove;
end;
procedure TUciEngine.ExecuteWorkerCommand(Obj: TObject);
var C: TUciCommand; I: Integer; Found: Boolean; Side: TGameSide;
begin
  C:=TUciCommand(Obj);
  case C.Operation of
    ucInit:C.BoolResult:=Initialize;
    ucPosition:ApplyPosition(C.Text,C.Moves);
    ucNewGame:begin StopCurrentSearch; inherited NewGame(C.Text); FWorker.SendLine('ucinewgame'); Ready; end;
    ucBegin:begin
      FGameMode:=True; FHasClock:=False;
      inherited BeginGame(C.Text,C.Side,C.Seconds,C.MoveCount,C.Increment); SetAnalysisOption;
    end;
    ucClock:begin
      for Side:=Low(TGameSide) to High(TGameSide) do begin
        UciMilliseconds(C.Clock.Remaining[Side]); UciMilliseconds(C.Clock.Increment[Side]);
      end;
      if C.Clock.MovesRemaining<0 then raise EConvertError.Create('Negative moves remaining');
      FClock:=C.Clock; FGameMode:=True; FHasClock:=True;
    end;
    ucBudget:begin
      C.BoolResult:=FHasPending;
      if FHasPending then begin C.Text:=FPendingRoot; C.Moves.Assign(FPendingMoves); end;
      StopCurrentSearch;
      if C.BoolResult then ApplyPosition(C.Text,C.Moves);
      FGameMode:=False; FHasClock:=False; SetAnalysisOption;
      if IsNan(C.Seconds) or IsInfinite(C.Seconds) or (C.Seconds<=0) or (C.Seconds>86400) then raise EConvertError.Create('Invalid analysis duration');
      FDurationMs:=Max(1,Round(C.Seconds*1000));
    end;
    ucAccepted:begin
      try Accepted(C.Text,C.Moves,C.Clock);
      except on E:Exception do Fault('Ponder setup failed: '+E.Message); end;
    end;
    ucAnalyze:begin FGameMode:=False;FHasClock:=False;StartSearch;end;
    ucThink:C.StringResult:=inherited StartThinking;
    ucPoll:Poll;
    ucStopSearch:StopCurrentSearch;
    ucData:ProcessData(nil,C.Text);
    ucButton:begin
      RequireReady; StopCurrentSearch; Found:=False;
      for I:=0 to High(FOptions) do if SameText(C.Text,FOptions[I].Name) and (FOptions[I].ParamType='button') then begin
        FWorker.SendLine('setoption name '+FOptions[I].Name); Found:=True; Break;
      end;
      if not Found then raise EConvertError.Create('Unknown UCI button '+C.Text); Ready;
    end;
    ucShutdown:begin inherited Stop; FSearching:=False; ClearPonder; FWorker.StopProcess; end;
  end;
end;
procedure TUciEngine.ConfigureOptions(const Params: TEngineParamArray);
begin
  if State<>esWaiting then raise EInvalidOperation.Create('Options must be set before initialization');
  FParams:=Copy(Params);
  FStopMs:=Max(100,Min(10000,StrToIntDef(EngineParamValue(FParams,'gui-stop-timeout-ms','1500'),1500)));
end;
function TUciEngine.BeginInitialize: TProcessEngineCommand;
begin
  Result:=TUciCommand.Create(ucInit);
  if not FWorker.Post(Result) then begin Result.Free; raise EInvalidOperation.Create('UCI worker closed'); end;
end;
function TUciEngine.LaunchAndInit: Boolean;
begin Result:=FWorker.QueueBoolCommand(TUciCommand.Create(ucInit)); end;
function TUciEngine.DiscoveredOptions: TEngineParamArray;
begin Result:=Copy(FOptions); end;
function TUciEngine.ReportedName: string;
begin Result:=FReportedName; end;
function TUciEngine.BeginButton(const Name: string): TProcessEngineCommand;
var C: TUciCommand;
begin
  C:=TUciCommand.Create(ucButton); C.Text:=Name;
  if not FWorker.Post(C) then begin C.Free; raise EInvalidOperation.Create('UCI worker closed'); end;
  Result:=C;
end;
procedure TUciEngine.PressButton(const Name: string);
var C: TUciCommand;
begin C:=TUciCommand.Create(ucButton); C.Text:=Name; FWorker.QueueProcedureCommand(C); end;
procedure TUciEngine.BeginGame(const Fen: string; Side: TGameSide; Minutes: Double; Moves: Integer; Increment: Double);
var C: TUciCommand;
begin
  C:=TUciCommand.Create(ucBegin); C.Text:=Fen; C.Side:=Side; C.Seconds:=Minutes; C.MoveCount:=Moves; C.Increment:=Increment;
  FWorker.QueueProcedureCommand(C);
end;
procedure TUciEngine.SetGameClockState(const Clock: TEngineGameClockState);
var C: TUciCommand;
begin C:=TUciCommand.Create(ucClock); C.Clock:=Clock; FWorker.QueueProcedureCommand(C); end;
procedure TUciEngine.SetGamePonderAllowed(Allowed: Boolean);
begin
  if State<>esWaiting then raise EInvalidOperation.Create('Game policy must be set before initialization');
  FForcePonderOff:=not Allowed;
end;
procedure TUciEngine.GameMoveAccepted(const RootFEN: string; ActualMoves: TStrings;
  const NextOwnClock: TEngineGameClockState);
var C: TUciCommand;
begin
  if WorkerStopping then Exit;
  C:=TUciCommand.Create(ucAccepted); C.Text:=RootFEN;
  C.Moves.Assign(ActualMoves); C.Clock:=NextOwnClock;
  if not FWorker.Post(C) then C.Free;
end;
procedure TUciEngine.NewGame(const Fen: string);
var C: TUciCommand;
begin C:=TUciCommand.Create(ucNewGame); C.Text:=Fen; FWorker.QueueProcedureCommand(C); end;
procedure TUciEngine.SetGamePosition(const Fen: string; Moves: TStrings);
var C: TUciCommand;
begin C:=TUciCommand.Create(ucPosition); C.Text:=Fen; if Moves<>nil then C.Moves.Assign(Moves); FWorker.QueueProcedureCommand(C); end;
procedure TUciEngine.SetClockInfo(MovesRemaining: Integer; Remaining,Used: Double);
var C: TUciCommand;
begin C:=TUciCommand.Create(ucBudget); C.Seconds:=Remaining; FWorker.QueueProcedureCommand(C); end;
procedure TUciEngine.StartAnalyzing;
begin FWorker.QueueProcedureCommand(TUciCommand.Create(ucAnalyze)); end;
function TUciEngine.StartThinking: string;
begin Result:=FWorker.QueueStringCommand(TUciCommand.Create(ucThink)); end;
procedure TUciEngine.StopSearch;
begin FWorker.QueueProcedureCommand(TUciCommand.Create(ucStopSearch)); end;
procedure TUciEngine.PollOutput;
begin FWorker.QueueProcedureCommand(TUciCommand.Create(ucPoll)); end;
procedure TUciEngine.Stop;
begin
  RequestStop;
  if FWorker<>nil then FWorker.QueueProcedureCommand(TUciCommand.Create(ucShutdown));
end;
function CreateUci(Definition: TExternalEngineDefinition): TGameEngine;
begin Result:=TUciEngine.Create(Definition); end;
initialization RegisterGameEngineFactory(eekUci,@CreateUci);
end.
