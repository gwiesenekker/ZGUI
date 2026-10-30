program dxp_editor_launch_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,StdCtrls,
 ssockets,sockets,uEngineEditForm,uEngineRegistry,uDraughtsPosition,uGameGuiProfile,
 uGamePosition,uDraughtsDxpTestConnection;
type TErrors=class
 procedure Report(Sender:TObject;E:Exception);
end;
type TServerPeer=class
 procedure Connected(Sender:TObject;Data:TSocketStream);
end;
procedure TServerPeer.Connected(Sender:TObject;Data:TSocketStream);
begin
 WriteLn('FAST SERVER CONNECTED');Flush(Output);Data.Free;
 TInetServer(Sender).StopAccepting(False);
end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
procedure Check(B:Boolean;const S:string);
begin if not B then raise Exception.Create(S);end;
procedure FakeClient;
var S:TInetSocket;L:TStringList;
begin
 L:=TStringList.Create;
 try
  L.Text:='started';L.SaveToFile(ParamStr(4));
  // One immediate attempt: a retry would hide the editor's launch-order bug.
  S:=TInetSocket.Create(ParamStr(2),StrToInt(ParamStr(3)),1000);
  try WriteLn('FAST CLIENT CONNECTED');Flush(Output);Sleep(300);
  finally S.Free;end;
 finally L.Free;end;
end;
procedure FakeServer;
var S:TInetServer;P:TServerPeer;
begin
 S:=TInetServer.Create(ParamStr(2),StrToInt(ParamStr(3)));P:=TServerPeer.Create;
 try S.OnConnect:=@P.Connected;S.Listen;S.StartAccepting;
 finally S.Free;P.Free;end;
end;
function FreePort:Word;
var S:TInetServer;A:TInetSockAddr;N:TSockLen;
begin
 S:=TInetServer.Create('127.0.0.1',0);
 try S.Listen;N:=SizeOf(A);Check(fpGetSockName(S.Socket,@A,@N)=0,'getsockname');Result:=ntohs(A.sin_port);
 finally S.Free;end;
end;
function LaunchButton(F:TForm):TButton;
var I:Integer;
begin
 Result:=nil;
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption='Launch engine') then Result:=TButton(F.Components[I]);
 Check(Result<>nil,'launch button missing');
end;
function Logs(F:TForm):string;
var I:Integer;
begin
 Result:='';for I:=0 to F.ComponentCount-1 do
  if F.Components[I] is TMemo then Result+=TMemo(F.Components[I]).Text;
end;
var V:TGameVariant;F:TEngineEditForm;E:TExternalEngineDefinition;Port:Word;
 Marker,ErrorText:string;Blocked:TInetServer;T:TDxpTestConnectionThread;
 I,J:Integer;Errors:TErrors;
begin
 if ParamStr(1)='--fast-client' then begin FakeClient;Halt(0);end;
 if ParamStr(1)='--fast-server' then begin FakeServer;Halt(0);end;
 if ParamStr(1)='--no-connect' then Halt(0);
 RequireDerivedFormResource:=False;Application.Initialize;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 V:=TDraughtsVariant.Create;RegisterGame(V,DraughtsGuiProfile);
 Marker:=GetTempDir(False)+'zgui-dxp-launch-'+IntToStr(GetProcessID)+'.txt';
 E:=TExternalEngineDefinition.Create;
 try
  E.Kind:=eekDxp;E.ExePath:=ExpandFileName(ParamStr(0));E.ExecutableName:=ExtractFileName(E.ExePath);
  E.DxpHost:='127.0.0.1';E.DxpRole:=derListen;
  for I:=0 to 1 do begin
   Port:=FreePort;E.DxpPort:=Port;
   E.Arguments:='--fast-client {ip} {port} "'+Marker+'"';
   F:=TEngineEditForm.Create(nil,V);
   try
    F.LoadEngine(E);F.Show;Application.ProcessMessages;
    LaunchButton(F).Click;
    for J:=1 to 30 do begin Application.ProcessMessages;Sleep(10);end;
    Check(FileExists(Marker),'client was not launched');
    Check(Pos('FAST CLIENT CONNECTED',Logs(F))>0,'client did not connect on its first attempt: '+Logs(F));
   finally F.Free;DeleteFile(Marker);end;
  end;
  E.Arguments:='--no-connect';E.DxpPort:=FreePort;
  F:=TEngineEditForm.Create(nil,V);
  try F.LoadEngine(E);LaunchButton(F).Click;
  finally F.Free;end;
  Blocked:=TInetServer.Create('127.0.0.1',E.DxpPort);
  try Blocked.ReuseAddress:=True;Blocked.Listen;
  finally Blocked.Free;end;
  E.DxpRole:=derConnect;E.DxpPort:=FreePort;
  E.Arguments:='--fast-server {ip} {port}';
  F:=TEngineEditForm.Create(nil,V);
  try
   F.LoadEngine(E);LaunchButton(F).Click;
   for J:=1 to 30 do begin Application.ProcessMessages;Sleep(10);end;
   Check(Pos('FAST SERVER CONNECTED',Logs(F))>0,'connect role no longer reaches engine server');
  finally F.Free;end;
  E.DxpRole:=derListen;E.Arguments:='--fast-client {ip} {port} "'+Marker+'"';
  Port:=FreePort;Blocked:=TInetServer.Create('127.0.0.1',Port);
  try
   Blocked.Listen;E.DxpPort:=Port;
   F:=TEngineEditForm.Create(nil,V);
   try
    F.LoadEngine(E);LaunchButton(F).Click;
    Check(not FileExists(Marker),'process launched despite failed bind');
    Check(Pos('DXP listener not ready',Logs(F))>0,'bind failure not reported');
   finally F.Free;end;
  finally Blocked.Free;end;
  Port:=FreePort;T:=TDxpTestConnectionThread.Create('127.0.0.1',Port,derListen,nil);
  try
   Check(T.WaitForListener(2000,ErrorText),'listener not ready: '+ErrorText);
   T.StopConnection;
   Check(not T.WaitForListener(2000,ErrorText),'cancelled listener reported ready');
  finally T.Free;end;
  WriteLn('PASS: first-attempt DXP client, repeated launch, early exit, connect role, bind failure and cancellation');
 finally E.Free;DeleteFile(Marker);ClearRegisteredGames;Application.OnException:=nil;Errors.Free;end;
end.
