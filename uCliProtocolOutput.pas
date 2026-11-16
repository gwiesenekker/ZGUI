unit uCliProtocolOutput;
{$mode objfpc}{$H+}
{ Initialize before Interfaces in zgui.lpr. Protocol owns a private stdout;
  ordinary RTL/LCL diagnostics stay on stderr through unit finalization. }
interface
uses Classes,SysUtils;
procedure PrepareCliProtocolOutput;
procedure RedirectCliDiagnostics(Handle:THandle);
function CliProtocolOutputHandle:THandle;
{$IFDEF MSWINDOWS}procedure ReleaseCliConsole;{$ENDIF}
implementation
uses uStartupCommand
 {$IFDEF UNIX},BaseUnix{$ENDIF}{$IFDEF LINUX},Linux{$ENDIF}
 {$IFDEF MSWINDOWS},Windows{$ENDIF};
{$IFDEF LINUX}
// Linux fcntl command; FPC 3.2.x does not expose this constant.
const DupFdCloseOnExec = 1030;
{$ENDIF}
var Prepared:Boolean=False;ProtocolHandle:THandle=THandle(-1);
{$IFDEF MSWINDOWS}
var NullDiagnostics:THandle=INVALID_HANDLE_VALUE;
function NullDiagnosticHandle:THandle;
begin
 // Process-lifetime sink: keep late RTL/LCL diagnostics valid after console
 // retirement. Windows closes this noninheritable handle at process exit.
 if NullDiagnostics=INVALID_HANDLE_VALUE then
   NullDiagnostics:=CreateFile('NUL',GENERIC_WRITE,FILE_SHARE_READ or FILE_SHARE_WRITE,
     nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
 if NullDiagnostics=INVALID_HANDLE_VALUE then RaiseLastOSError;
 Result:=NullDiagnostics;
end;
procedure ReleaseCliConsole;
var Sink:THandle;
begin
 Sink:=NullDiagnosticHandle;
 RedirectCliDiagnostics(Sink);SetStdHandle(STD_ERROR_HANDLE,Sink);
 TextRec(StdErr).Handle:=Sink;
 FreeConsole;
end;
{$ENDIF}
procedure RedirectCliDiagnostics(Handle:THandle);
begin
 {$IFDEF UNIX}
 if fpDup2(Handle,1)<0 then RaiseLastOSError;
 {$ELSE}
 if not SetStdHandle(STD_OUTPUT_HANDLE,Handle) then RaiseLastOSError;
 {$ENDIF}
 // Change the destination before flushing any previously buffered diagnostics.
 TextRec(Output).Handle:=Handle;
 {$I-}Flush(Output);{$I+}
 if IOResult<>0 then ;
end;
procedure PrepareCliProtocolOutput;
{$IFDEF UNIX}var Diagnostics:Integer;{$ENDIF}
{$IFDEF MSWINDOWS}var Original,Diagnostics:THandle;{$ENDIF}
begin
 if Prepared then Exit;
 {$IFDEF UNIX}
 {$IFDEF LINUX}
 ProtocolHandle:=fpFcntl(1,DupFdCloseOnExec,3);
 {$ELSE}
 ProtocolHandle:=fpDup(1);
 if ProtocolHandle<>THandle(-1) then
   if fpFcntl(ProtocolHandle,F_SETFD,1)<0 then begin fpClose(ProtocolHandle);ProtocolHandle:=THandle(-1);end;
 {$ENDIF}
 if ProtocolHandle=THandle(-1) then RaiseLastOSError;
 Diagnostics:=2;
 if fpFcntl(2,F_GETFD)<0 then begin
   Diagnostics:=fpOpen('/dev/null',O_WRONLY {$IFDEF LINUX}or O_CLOEXEC{$ENDIF});
   if Diagnostics<0 then begin fpClose(ProtocolHandle);ProtocolHandle:=THandle(-1);RaiseLastOSError;end;
   if Diagnostics<>2 then begin fpDup2(Diagnostics,2);fpClose(Diagnostics);end;
   Diagnostics:=2;
 end;
 {$ELSE}
 Original:=GetStdHandle(STD_OUTPUT_HANDLE);Diagnostics:=GetStdHandle(STD_ERROR_HANDLE);
 if (Diagnostics=0) or (Diagnostics=INVALID_HANDLE_VALUE) then begin
   Diagnostics:=NullDiagnosticHandle;
   if not SetStdHandle(STD_ERROR_HANDLE,Diagnostics) then RaiseLastOSError;
   TextRec(StdErr).Handle:=Diagnostics;
 end;
 if (Original<>0) and (Original<>INVALID_HANDLE_VALUE) then
   if not DuplicateHandle(GetCurrentProcess,Original,GetCurrentProcess,@ProtocolHandle,0,False,DUPLICATE_SAME_ACCESS) then
     RaiseLastOSError;
 // A GUI-subsystem launch may have no standard handles; the terminal will
 // allocate its dedicated console later, without ever borrowing diagnostic stdout.
 {$ENDIF}
 try RedirectCliDiagnostics(Diagnostics);
 except
   if ProtocolHandle<>THandle(-1) then FileClose(ProtocolHandle);
   ProtocolHandle:=THandle(-1);raise;
 end;
 Prepared:=True;
end;
function CliProtocolOutputHandle:THandle;
begin Result:=ProtocolHandle;end;
procedure Bootstrap;
var Args:TStringList;I:Integer;Request:TStartupCommand;
begin
 Args:=TStringList.Create;
 try
  for I:=1 to ParamCount do Args.Add(ParamStr(I));
  try
   // Flags are ASCII; full Unicode argument binding still happens in zgui.lpr.
   Request:=ParseStartupCommand(Args);
   if Request.Kind=sckInteractive then PrepareCliProtocolOutput;
  except
   // Startup reports argument/I/O errors through its normal GUI error path.
  end;
 finally Args.Free;end;
end;
initialization
 Bootstrap;
finalization
 if ProtocolHandle<>THandle(-1) then FileClose(ProtocolHandle);
end.
