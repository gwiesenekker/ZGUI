unit uDraughtsDxpTestConnection;

{$mode objfpc}{$H+}

interface

uses
  Classes, SyncObjs, ssockets, uEngineRegistry;

type
  TDxpTestLogEvent = procedure(Sender: TObject; const AText: string) of object;

  TDxpTestConnectionThread = class(TThread)
  private
    FLock: TCriticalSection;
    FListenerReady:TEvent;
    FListening:Boolean;
    FStartupError:string;
    procedure PublishListenerState(Listening:Boolean;const ErrorText:string);
  private
    FDxpHost: string;
    FAllowedPeer: string;
    FDxpPort: Word;
    FLogText: string;
    FOnLog: TDxpTestLogEvent;
    FRole: TDxpEngineRole;
    FServer: TInetServer;
    FSocket: TSocketStream;
    procedure AcceptConnection(Sender: TObject; Data: TSocketStream);
    procedure DeliverLog;
    procedure Log(const AText: string);
    procedure WakeListener;
  protected
    procedure Execute; override;
  public
    constructor Create(const AHost: string; APort: Word; ARole: TDxpEngineRole;
      AOnLog: TDxpTestLogEvent; const AAllowedPeer: string = '');
    destructor Destroy; override;
    function WaitForListener(ATimeoutMs:Integer;out ErrorText:string):Boolean;
    procedure StopConnection;
  end;

implementation

uses
  SysUtils, sockets, uSocketSafety;

constructor TDxpTestConnectionThread.Create(const AHost: string; APort: Word;
  ARole: TDxpEngineRole; AOnLog: TDxpTestLogEvent; const AAllowedPeer: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FListenerReady:=TEvent.Create(nil,True,False,'');
  FDxpHost := Trim(AHost);
  FAllowedPeer := Trim(AAllowedPeer);
  if Trim(FDxpHost) = '' then FDxpHost := '127.0.0.1';
  FDxpPort := APort;
  FRole := ARole;
  FOnLog := AOnLog;
  FServer := nil;
  FSocket := nil;
  Start;
end;

destructor TDxpTestConnectionThread.Destroy;
begin
  StopConnection;
  WaitFor;
  FSocket.Free;
  FListenerReady.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TDxpTestConnectionThread.PublishListenerState(Listening:Boolean;const ErrorText:string);
begin
  FLock.Acquire;
  try FListening:=Listening and not Terminated;FStartupError:=ErrorText;
  finally FLock.Release;end;
  FListenerReady.SetEvent;
end;

function TDxpTestConnectionThread.WaitForListener(ATimeoutMs:Integer;out ErrorText:string):Boolean;
var Started:QWord;
begin
  Result:=False;ErrorText:='';
  if FRole<>derListen then begin ErrorText:='DXP is not configured as a listener';Exit;end;
  Started:=GetTickCount64;
  repeat
    // Startup logs use Synchronize; service them without re-entering UI actions.
    CheckSynchronize;
    if FListenerReady.WaitFor(10)=wrSignaled then begin
      FLock.Acquire;
      try Result:=FListening and not Terminated;ErrorText:=FStartupError;
      finally FLock.Release;end;
      if not Result and (ErrorText='') then ErrorText:='DXP listener cancelled';
      Exit;
    end;
  until (ATimeoutMs<=0) or (GetTickCount64-Started>=QWord(ATimeoutMs));
  ErrorText:='DXP listener startup timed out';
end;

procedure TDxpTestConnectionThread.AcceptConnection(Sender: TObject;
  Data: TSocketStream);
var Peer: string;
begin
  Peer := NetAddrToStr(TInetSockAddr(Data.RemoteAddress).sin_addr);
  if not DxpPeerAllowed(DxpListenAddress(FDxpHost), FAllowedPeer, Peer) then
  begin
    Data.Free;
    Log('[DXP rejected peer ' + Peer + ']');
    Exit;
  end;
  FSocket := Data;
  if FServer <> nil then
    FServer.StopAccepting(False);
end;

procedure TDxpTestConnectionThread.DeliverLog;
begin
  if Assigned(FOnLog) then
    FOnLog(Self, FLogText);
end;

procedure TDxpTestConnectionThread.Log(const AText: string);
begin
  FLogText := AText;
  Synchronize(@DeliverLog);
end;

procedure TDxpTestConnectionThread.WakeListener;
var
  Socket: TInetSocket;
begin
  if FRole <> derListen then
    Exit;
  Socket := nil;
  try
    if FDxpHost = '0.0.0.0' then Socket := TInetSocket.Create('127.0.0.1', FDxpPort, 100)
    else Socket := TInetSocket.Create(FDxpHost, FDxpPort, 100);
  except
    on E: Exception do
      ;
  end;
  Socket.Free;
end;

procedure TDxpTestConnectionThread.Execute;
var
  Attempt: Integer;
  InetSocket: TInetSocket;
  ListenHost: string;
begin
  try
    if FRole = derListen then
    begin
      // Host/peer configuration remains immutable while StopConnection can read it.
      ListenHost := DxpListenAddress(FDxpHost);
      if FAllowedPeer <> '' then DxpListenAddress(FAllowedPeer);
      Log('[DXP preparing listener on ' + ListenHost + ':' + IntToStr(FDxpPort) + ']');
      FLock.Acquire;
      try FServer := TInetServer.Create(ListenHost, FDxpPort);
      finally FLock.Release; end;
      try
        FServer.ReuseAddress := True;
        FServer.MaxConnections := -1;
        FServer.OnConnect := @AcceptConnection;
        FServer.Listen;
        PublishListenerState(True,'');
        Log('[DXP listening on '+ListenHost+':'+IntToStr(FDxpPort)+']');
        if not Terminated then FServer.StartAccepting;
      finally
        FLock.Acquire;
        try FreeAndNil(FServer);
        finally FLock.Release; end;
      end;
      if Terminated then
        Exit;
      if FSocket <> nil then
        Log('[DXP socket connected]')
      else
        Log('[DXP listener stopped without connection]');
    end
    else
    begin
      Log('[DXP connecting to ' + FDxpHost + ':' + IntToStr(FDxpPort) + ']');
      for Attempt := 1 to 120 do
      begin
        if Terminated then
          Exit;
        try
          InetSocket := TInetSocket.Create(FDxpHost, FDxpPort, 1000);
          try
            FSocket := InetSocket;
            InetSocket := nil;
            Log('[DXP socket connected after attempt ' + IntToStr(Attempt) + ']');
            Break;
          finally
            InetSocket.Free;
          end;
        except
          on E: Exception do
          begin
            if (Attempt = 1) or (Attempt mod 10 = 0) then
              Log('[DXP connect attempt ' + IntToStr(Attempt) + ' failed: ' +
                E.Message + ']');
            Sleep(250);
          end;
        end;
      end;
      if (not Terminated) and (FSocket = nil) then
        Log('[DXP connect failed]');
    end;

    while (not Terminated) and (FSocket <> nil) do
      Sleep(100);
  except
    on E: Exception do
      begin
        PublishListenerState(False,E.Message);
        if not Terminated then Log('[DXP socket error: ' + E.Message + ']');
      end;
  end;
end;

procedure TDxpTestConnectionThread.StopConnection;
var Wake:Boolean;
begin
  Terminate;
  FLock.Acquire;
  try
    Wake:=FListening and (FServer<>nil);
    FListening:=False;FStartupError:='DXP listener cancelled';
    if FServer <> nil then FServer.StopAccepting(False);
  finally FLock.Release; end;
  FListenerReady.SetEvent;
  // A failed bind must not probe/consume another program's listener.
  if Wake then WakeListener;
end;

end.
