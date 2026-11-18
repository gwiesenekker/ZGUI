unit uGuiLayoutTestWatch;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Controls,Forms,SyncObjs;
type
 TGuiLayoutTestWatch=class(TComponent)
 private
  FLock:TCriticalSection;
  FWorker:TThread;
  FControls:TList;
  FPhase,FLastControl:string;
  FProgress:QWord;
  FChanges:Integer;
  FTimeout:QWord;
  procedure Watch(C:TControl);
  procedure Changed(Sender:TObject);
  procedure Fail(const Reason:string);
 protected
  procedure Notification(AComponent:TComponent;Operation:TOperation);override;
 public
  constructor Create(TimeoutMs:QWord=20000);reintroduce;
  destructor Destroy;override;
  procedure Step(const Phase:string);
 end;
implementation
{$IFDEF WINDOWS}uses Windows;{$ENDIF}
{$IFDEF UNIX}
// libc _exit terminates the entire process without running GUI finalizers on
// the watchdog thread (Halt can deadlock when GTK is already stuck).
procedure ExitWithoutFinalization(Status:LongInt);cdecl;external 'c' name '_exit';
{$ENDIF}
type
 TWatchThread=class(TThread)
  Owner:TGuiLayoutTestWatch;
  procedure Execute;override;
 end;
procedure TWatchThread.Execute;
var Expired:Boolean;
begin
 while not Terminated do begin
  Sleep(20);Owner.FLock.Acquire;
  try Expired:=GetTickCount64-Owner.FProgress>Owner.FTimeout;
  finally Owner.FLock.Release;end;
  if Expired then Owner.Fail('no progress before deadline (native allocation loop possible)');
 end;
end;
constructor TGuiLayoutTestWatch.Create(TimeoutMs:QWord);
begin
 inherited Create(nil);FLock:=TCriticalSection.Create;FControls:=TList.Create;
 FTimeout:=TimeoutMs;FProgress:=GetTickCount64;FPhase:='initialization';
 FWorker:=TWatchThread.Create(True);TWatchThread(FWorker).Owner:=Self;FWorker.Start;
end;
destructor TGuiLayoutTestWatch.Destroy;
var I:Integer;
begin
 FWorker.Terminate;FWorker.WaitFor;FWorker.Free;
 for I:=FControls.Count-1 downto 0 do begin
  TControl(FControls[I]).RemoveHandlerOnChangeBounds(@Changed);
  TControl(FControls[I]).RemoveFreeNotification(Self);
 end;
 FControls.Free;FLock.Free;inherited Destroy;
end;
procedure TGuiLayoutTestWatch.Notification(AComponent:TComponent;Operation:TOperation);
begin
 if (Operation=opRemove) and (FControls<>nil) then FControls.Remove(AComponent);
 inherited Notification(AComponent,Operation);
end;
procedure TGuiLayoutTestWatch.Watch(C:TControl);
var I:Integer;
begin
 if FControls.IndexOf(C)<0 then begin
  FControls.Add(C);C.FreeNotification(Self);C.AddHandlerOnChangeBounds(@Changed,True);
 end;
 if C is TWinControl then
  for I:=0 to TWinControl(C).ControlCount-1 do Watch(TWinControl(C).Controls[I]);
end;
procedure TGuiLayoutTestWatch.Step(const Phase:string);
var I:Integer;
begin
 FLock.Acquire;
 try if Phase<>'' then FPhase:=Phase;FProgress:=GetTickCount64;FChanges:=0;
 finally FLock.Release;end;
 for I:=0 to Screen.CustomFormCount-1 do Watch(Screen.CustomForms[I]);
end;
procedure TGuiLayoutTestWatch.Changed(Sender:TObject);
var C,ParentControl:TControl;Path:string;TooMany:Boolean;
begin
 C:=TControl(Sender);Path:=C.ClassName+':'+C.Name;ParentControl:=C.Parent;
 while ParentControl<>nil do begin
  Path:=ParentControl.ClassName+':'+ParentControl.Name+'/'+Path;ParentControl:=ParentControl.Parent;
 end;
 FLock.Acquire;
 try
  Inc(FChanges);FLastControl:=Path+Format(' bounds=%d,%d,%d,%d',[C.Left,C.Top,C.Width,C.Height]);
  TooMany:=FChanges>5000;
 finally FLock.Release;end;
 if TooMany then Fail('more than 5000 bounds changes in one test step');
end;
procedure TGuiLayoutTestWatch.Fail(const Reason:string);
begin
 FLock.Acquire;
 try
  WriteLn(StdErr,'LAYOUT WATCHDOG: ',Reason);
  WriteLn(StdErr,'phase=',FPhase,' bounds_changes=',FChanges,' last_control=',FLastControl);Flush(StdErr);
  // Do not unwind GTK or join the blocked GUI thread; terminate this test process.
  {$IFDEF UNIX}ExitWithoutFinalization(3);{$ELSE}
  {$IFDEF WINDOWS}Windows.ExitProcess(3);{$ELSE}Halt(3);{$ENDIF}{$ENDIF}
 finally FLock.Release;end;
end;
end.
