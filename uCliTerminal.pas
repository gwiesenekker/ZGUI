unit uCliTerminal;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,SyncObjs,uThreadMessageQueue;
type
  TCliLineRequest=class
  private
    FReferences:LongInt;
    FEvent:TSimpleEvent;
    FLock:TCriticalSection;
    FReply:string;
  public
    Line:string;
    constructor Create(const Text:string);
    destructor Destroy;override;
    procedure AddRef;
    procedure Release;
    procedure Reply(const Text:string);
    function Await(out Text:string;Timeout:Cardinal):Boolean;
  end;
  TCliTerminal=class(TThread)
  private
    FQueue:TThreadMessageQueue;
    FInput,FOutput,FError:THandle;
    FConsoleInput,FConsoleOutput,FInteractive:Boolean;
    FOldOutputFlags,FOldErrorFlags:LongInt;
    FSignalsInstalled,FStarted,FNewConsole,FOwnOutput,FOwnError:Boolean;
    FPendingInput:string;
    FWideCarry:UnicodeString;
    function WriteResponse(const Text:string;Prompt:Boolean=False):Boolean;
    function ReadByte(out C:Char):Integer;
    function ProcessLine(const Line:string):Boolean;
  protected
    procedure Execute;override;
  public
    constructor Create;
    destructor Destroy;override;
    procedure Start;reintroduce;
    procedure Stop;
    function TryPop(out Request:TCliLineRequest):Boolean;
  end;
implementation
uses uInteractiveProtocol
 {$IFDEF UNIX},BaseUnix,Unix,Termio{$ENDIF}{$IFDEF LINUX},Linux{$ENDIF}
 {$IFDEF MSWINDOWS},Windows{$ENDIF};
{$IFDEF UNIX}
var InterruptGeneration:LongInt=0;
    OldInt,OldPipe,OldTtin,OldTtou:SignalHandler;
procedure InterruptLine(Sig:LongInt);cdecl;
begin Inc(InterruptGeneration);end;
{$ENDIF}
{$IFDEF MSWINDOWS}
function CancelThreadIo(ThreadHandle:THandle):LongBool;stdcall;external 'kernel32.dll' name 'CancelSynchronousIo';
function AttachParentConsole(ProcessId:DWORD):BOOL;stdcall;external 'kernel32.dll' name 'AttachConsole';
var InterruptGeneration:LongInt=0;
function ConsoleControl(Code:DWORD):BOOL;stdcall;
begin Result:=Code=CTRL_C_EVENT;if Result then InterlockedIncrement(InterruptGeneration);end;
{$ENDIF}
constructor TCliLineRequest.Create(const Text:string);
begin inherited Create;FReferences:=1;Line:=Text;FEvent:=TSimpleEvent.Create;FLock:=SyncObjs.TCriticalSection.Create;end;
destructor TCliLineRequest.Destroy;
begin FLock.Free;FEvent.Free;inherited Destroy;end;
procedure TCliLineRequest.AddRef;
begin InterlockedIncrement(FReferences);end;
procedure TCliLineRequest.Release;
begin if InterlockedDecrement(FReferences)=0 then Free;end;
procedure TCliLineRequest.Reply(const Text:string);
begin FLock.Acquire;try FReply:=Text;FEvent.SetEvent;finally FLock.Release;end;end;
function TCliLineRequest.Await(out Text:string;Timeout:Cardinal):Boolean;
begin
 Result:=FEvent.WaitFor(Timeout)=wrSignaled;if not Result then Exit;
 FLock.Acquire;try Text:=FReply;finally FLock.Release;end;
end;
{$IFDEF UNIX}
function IndependentOutput(Fd:Integer):Integer;
var Name:string;Info:Stat;
begin
  // Preserve inherited offsets and append semantics for ordinary files.
  if (fpFStat(Fd,Info)=0) and ((Info.st_mode and S_IFMT)=S_IFREG) then Exit(-1);
  {$IFDEF LINUX}Name:='/proc/self/fd/'+IntToStr(Fd);
  {$ELSE}if IsATTY(Fd)=1 then Name:=TTYname(Fd) else Name:='/dev/fd/'+IntToStr(Fd);{$ENDIF}
  Result:=fpOpen(PChar(Name),O_WRONLY or O_NONBLOCK {$IFDEF LINUX}or Linux.O_CLOEXEC{$ENDIF});
  {$IFNDEF LINUX}if Result>=0 then if fpFcntl(Result,F_SETFD,1)<0 then begin fpClose(Result);Result:=-1;end;{$ENDIF}
end;
{$ENDIF}
constructor TCliTerminal.Create;
{$IFDEF UNIX}var CopyFd:Integer;{$ENDIF}
{$IFDEF MSWINDOWS}var Mode:DWORD;OriginalOut,OriginalErr:THandle;RedirectedInput:Boolean;{$ENDIF}
begin
 inherited Create(True);FreeOnTerminate:=False;FOldOutputFlags:=-1;
 FOldErrorFlags:=-1;FQueue:=TThreadMessageQueue.Create(False);
 {$IFDEF UNIX}
 FInput:=0;FOutput:=1;FError:=2;
 // Reopen output descriptors rather than changing a shell's shared tty flags.
 CopyFd:=IndependentOutput(1);if CopyFd>=0 then begin FOutput:=CopyFd;FOwnOutput:=True;end;
 CopyFd:=IndependentOutput(2);if CopyFd>=0 then begin FError:=CopyFd;FOwnError:=True;end;
 FConsoleInput:=IsATTY(FInput)=1;FConsoleOutput:=IsATTY(FOutput)=1;
 FOldOutputFlags:=fpFcntl(FOutput,F_GETFL);FOldErrorFlags:=fpFcntl(FError,F_GETFL);
 if FOldOutputFlags<0 then raise EInOutError.Create('CLI needs a writable stdout handle');
 if fpFcntl(FOutput,F_SETFL,FOldOutputFlags or O_NONBLOCK)<0 then RaiseLastOSError;
 if FOldErrorFlags>=0 then fpFcntl(FError,F_SETFL,FOldErrorFlags or O_NONBLOCK);
 OldInt:=fpSignal(SIGINT,@InterruptLine);OldPipe:=fpSignal(SIGPIPE,SignalHandler(SIG_IGN));
 OldTtin:=fpSignal(SIGTTIN,SignalHandler(SIG_IGN));OldTtou:=fpSignal(SIGTTOU,SignalHandler(SIG_IGN));FSignalsInstalled:=True;
 {$ELSE}
 FInput:=GetStdHandle(STD_INPUT_HANDLE);OriginalOut:=GetStdHandle(STD_OUTPUT_HANDLE);OriginalErr:=GetStdHandle(STD_ERROR_HANDLE);
 RedirectedInput:=(GetFileType(FInput) in [FILE_TYPE_PIPE,FILE_TYPE_DISK]);
 if not RedirectedInput then begin
   FreeConsole;
   if not AllocConsole then RaiseLastOSError;FNewConsole:=True;
   // A console close would bypass GUI save/stop handling; close ZGUI via its GUI.
   DeleteMenu(GetSystemMenu(GetConsoleWindow,False),SC_CLOSE,MF_BYCOMMAND);
   FInput:=GetStdHandle(STD_INPUT_HANDLE);
 end;
 if RedirectedInput and (GetFileType(OriginalOut)=FILE_TYPE_CHAR) then
   AttachParentConsole(DWORD(-1)); // read only the pipe, never the shell keyboard
 FOutput:=OriginalOut;
 if not (GetFileType(FOutput) in [FILE_TYPE_PIPE,FILE_TYPE_DISK]) then FOutput:=GetStdHandle(STD_OUTPUT_HANDLE);
 FError:=OriginalErr;if not (GetFileType(FError) in [FILE_TYPE_PIPE,FILE_TYPE_DISK]) then FError:=GetStdHandle(STD_ERROR_HANDLE);
 if (FInput=0) or (FInput=INVALID_HANDLE_VALUE) or (FOutput=0) or (FOutput=INVALID_HANDLE_VALUE) then
   raise EInOutError.Create('CLI needs usable stdin and stdout handles');
 FConsoleInput:=GetConsoleMode(FInput,Mode);FConsoleOutput:=GetConsoleMode(FOutput,Mode);
 SetConsoleCtrlHandler(@ConsoleControl,True);FSignalsInstalled:=True;
 {$ENDIF}
 FInteractive:=FConsoleInput and FConsoleOutput;
end;
procedure TCliTerminal.Start;
begin FStarted:=True;inherited Start;end;
procedure TCliTerminal.Stop;
begin
 if not FStarted then Exit;
 Terminate;
 {$IFDEF MSWINDOWS}
 while not Finished do begin CancelThreadIo(Handle);Sleep(10);end;
 {$ENDIF}
 WaitFor;
end;
destructor TCliTerminal.Destroy;
var Obj:TObject;
begin
 Stop;
 if FQueue<>nil then while FQueue.TryPop(Obj) do TCliLineRequest(Obj).Release;
 FQueue.Free;
 {$IFDEF UNIX}
 if FOldOutputFlags>=0 then fpFcntl(FOutput,F_SETFL,FOldOutputFlags);
 if FOldErrorFlags>=0 then fpFcntl(FError,F_SETFL,FOldErrorFlags);
 if FOwnOutput then fpClose(FOutput);if FOwnError then fpClose(FError);
 if FSignalsInstalled then begin
   fpSignal(SIGINT,OldInt);fpSignal(SIGPIPE,OldPipe);fpSignal(SIGTTIN,OldTtin);fpSignal(SIGTTOU,OldTtou);
 end;
 {$ELSE}
 if FSignalsInstalled then SetConsoleCtrlHandler(@ConsoleControl,False);
 if FNewConsole then FreeConsole;
 {$ENDIF}
 inherited Destroy;
end;
function TCliTerminal.TryPop(out Request:TCliLineRequest):Boolean;
var Obj:TObject;
begin Result:=FQueue.TryPop(Obj);if Result then Request:=TCliLineRequest(Obj) else Request:=nil;end;
function TCliTerminal.WriteResponse(const Text:string;Prompt:Boolean):Boolean;
var Bytes:RawByteString;Offset,Count,Size:Integer;H:THandle;
 {$IFDEF UNIX}P:TPollFD;{$ENDIF}
 {$IFDEF MSWINDOWS}Written:DWORD;Wide:UnicodeString;{$ENDIF}
begin
 Result:=False;H:=FOutput;if Prompt then H:=FError;Bytes:=Text;
 {$IFDEF MSWINDOWS}
 if (not Prompt and FConsoleOutput) or (Prompt and FInteractive) then begin
   Wide:=UTF8Decode(Bytes);if Terminated then Exit;
   Result:=WriteConsoleW(H,PWideChar(Wide),Length(Wide),Written,nil);Exit;
 end;
 {$ENDIF}
 Offset:=1;
 while (Offset<=Length(Bytes)) and not Terminated do begin
   Size:=Length(Bytes)-Offset+1;if Size>4096 then Size:=4096;
   {$IFDEF UNIX}
   P.fd:=H;P.events:=POLLOUT;P.revents:=0;
   if fpPoll(@P,1,50)<=0 then Continue;
   if (P.revents and (POLLERR or POLLHUP or POLLNVAL))<>0 then Exit;
   Count:=fpWrite(H,Bytes[Offset],Size);
   if Count<0 then begin if fpGetErrno in [ESysEAGAIN,ESysEINTR] then Continue else Exit;end;
   {$ELSE}
   if not WriteFile(H,Bytes[Offset],Size,Written,nil) then Exit;Count:=Written;
   {$ENDIF}
   if Count=0 then Exit;Inc(Offset,Count);
 end;
 Result:=Offset>Length(Bytes);
end;
function TCliTerminal.ReadByte(out C:Char):Integer;
{$IFDEF UNIX}var P:TPollFD;GroupId:cint;{$ENDIF}
{$IFDEF MSWINDOWS}var Count,Available:DWORD;Buffer:array[0..255] of WideChar;Wide:UnicodeString;{$ENDIF}
begin
 Result:=-1;if Terminated then Exit;
 {$IFDEF UNIX}
 if FConsoleInput then begin
   if (TCGetPGrp(FInput,GroupId)<>0) or (GroupId<>fpGetPGrp) then begin Sleep(50);Exit(0);end;
 end;
 P.fd:=FInput;P.events:=POLLIN;P.revents:=0;
 if fpPoll(@P,1,50)<=0 then Exit(0);
 if (P.revents and POLLNVAL)<>0 then Exit;
 Result:=fpRead(FInput,C,1);
 if Result=0 then Exit(-1);
 if Result<0 then begin if fpGetErrno in [ESysEINTR,ESysEAGAIN,ESysEIO] then Exit(0) else Exit(-1);end;
 {$ELSE}
 if FConsoleInput then begin
   if FPendingInput='' then begin
     if not ReadConsoleW(FInput,@Buffer[0],Length(Buffer),Count,nil) then begin
       if GetLastError=ERROR_OPERATION_ABORTED then Exit(0);Exit;
     end;
     if Count=0 then Exit;
     SetString(Wide,PWideChar(@Buffer[0]),Count);Wide:=FWideCarry+Wide;FWideCarry:='';
     if (Length(Wide)>0) and (Ord(Wide[Length(Wide)])>=$D800) and (Ord(Wide[Length(Wide)])<=$DBFF) then begin
       FWideCarry:=Wide[Length(Wide)];Delete(Wide,Length(Wide),1);
     end;
     FPendingInput:=UTF8Encode(Wide);
   end;
   if FPendingInput='' then Exit(0);
   C:=FPendingInput[1];Delete(FPendingInput,1,1);if C=#26 then Exit(-1);Exit(1);
 end else begin
   if GetFileType(FInput)=FILE_TYPE_PIPE then begin
     if not PeekNamedPipe(FInput,nil,0,nil,@Available,nil) then Exit;
     if Available=0 then begin Sleep(25);Exit(0);end;
   end;
   if not ReadFile(FInput,C,1,Count,nil) then Exit;
 end;
 if Count=0 then Exit;Result:=1;
 {$ENDIF}
end;
function TCliTerminal.ProcessLine(const Line:string):Boolean;
var Request:TCliLineRequest;Response:string;
begin
 if Trim(Line)='' then Exit(True);
 if not ValidCliUtf8(Line) or (Pos(#0,Line)>0) then
   Exit(WriteResponse(ProtocolError('BAD_ARGUMENT','Invalid UTF-8 or NUL byte')+#10));
 Request:=TCliLineRequest.Create(Line);
 try
   Request.AddRef;
   if not FQueue.TryPost(Request) then begin Request.Release;Exit(False);end;
   while not Terminated do
     if Request.Await(Response,50) then Exit(WriteResponse(Response+#10));
   Result:=False;
 finally Request.Release;end;
end;
procedure TCliTerminal.Execute;
var Line:string;C:Char;Status:Integer;Overflow:Boolean;Generation:LongInt;
begin
 Line:='';Overflow:=False;Generation:=InterruptGeneration;
 try
   if FInteractive and not WriteResponse('zgui> ',True) then Exit;
   while not Terminated do begin
     if Generation<>InterruptGeneration then begin
       Generation:=InterruptGeneration;Line:='';Overflow:=False;FPendingInput:='';FWideCarry:='';
       {$IFDEF UNIX}if FConsoleInput then TCFlush(FInput,TCIFLUSH);{$ENDIF}
       if FInteractive then WriteResponse(#10+'zgui> ',True);
     end;
     Status:=ReadByte(C);if Status=0 then Continue;
     if Status<0 then begin
       if Overflow then WriteResponse(ProtocolError('BAD_ARGUMENT','Command exceeds 64 KiB')+#10)
       else if Line<>'' then ProcessLine(Line);
       Exit;
     end;
     if C=#10 then begin
       if (Line<>'') and (Line[Length(Line)]=#13) then Delete(Line,Length(Line),1);
       if Overflow then begin if not WriteResponse(ProtocolError('BAD_ARGUMENT','Command exceeds 64 KiB')+#10) then Exit;end
       else if not ProcessLine(Line) then Exit;
       Line:='';Overflow:=False;
       if FInteractive and not WriteResponse('zgui> ',True) then Exit;
     end else if Length(Line)<65536 then Line+=C else Overflow:=True;
   end;
 except on E:Exception do WriteResponse(ProtocolError('TRANSPORT',E.Message)+#10);end;
end;
end.
