program cli_terminal_check;
{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE GUI}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils,Classes,FPJSON,uCliTerminal,uInteractiveProtocol,uPlatformProcess{$IFDEF UNIX},BaseUnix{$ENDIF};
type TPeerOutput=class
  Text1,Text2:string;
  procedure Data1(Sender:TObject;const Text:string);
  procedure Data2(Sender:TObject;const Text:string);
end;
procedure TPeerOutput.Data1(Sender:TObject;const Text:string);
begin Text1+=Text;end;
procedure TPeerOutput.Data2(Sender:TObject;const Text:string);
begin Text2+=Text;end;
var Terminal:TCliTerminal;Request:TCliLineRequest;J:TJSONObject;Deadline,Tick:QWord;
 CloseAfter,I:Integer;Engines:array[0..1] of TPlatformProcess;Args:TStringList;
 Sink:TPeerOutput;Line:string;
begin
 for I:=0 to 1 do Engines[I]:=nil;
 if ParamStr(1)='--signal-peer' then begin
  while not EOF(Input) do begin ReadLn(Line);if Line='quit' then Break;WriteLn('pong');Flush(Output);end;Halt(0);
 end;
 CloseAfter:=0;if ParamStr(1)='--close-after-ms' then CloseAfter:=StrToInt(ParamStr(2));
 Terminal:=TCliTerminal.Create;Args:=TStringList.Create;Sink:=TPeerOutput.Create;
 try
   Terminal.Start;Deadline:=GetTickCount64;
   while not Terminal.Finished do begin
     for I:=0 to 1 do if Engines[I]<>nil then Engines[I].ReadAvailable;
     if Terminal.TryPop(Request) then try
       J:=TJSONObject.Create;
       try
         if Request.Line='engine' then begin
           Args.Clear;Args.Add('--signal-peer');
           for I:=0 to 1 do if Engines[I]=nil then begin
             Engines[I]:=TPlatformProcess.Create;Engines[I].SynchronizeData:=False;
             if I=0 then Engines[I].OnData:=@Sink.Data1 else Engines[I].OnData:=@Sink.Data2;
             Engines[I].Start(ExpandFileName(ParamStr(0)),Args,GetTempDir);
           end;
           J.Add('engine_started',2);
         end else if Request.Line='ping_engine' then begin
           Sink.Text1:='';Sink.Text2:='';
           for I:=0 to 1 do if Engines[I]<>nil then Engines[I].WriteLine('ping');
           Tick:=GetTickCount64;
           repeat
             for I:=0 to 1 do if Engines[I]<>nil then Engines[I].ReadAvailable;
             Sleep(5);
           until ((Pos('pong',Sink.Text1)>0) and (Pos('pong',Sink.Text2)>0)) or (GetTickCount64-Tick>500);
           J.Add('engines_alive',(Pos('pong',Sink.Text1)>0) and (Pos('pong',Sink.Text2)>0));
         end else if Request.Line='large' then J.Add('echo',StringOfChar('x',1024*1024)) else J.Add('echo',Request.Line);
         Request.Reply('OK '+J.AsJSON);
       finally J.Free;end;
     finally Request.Release;end;
     if (CloseAfter>0) and (GetTickCount64-Deadline>=QWord(CloseAfter)) then Break;
     Sleep(5);
   end;
   Terminal.Stop;
   Terminal.Stop; // Main-form shutdown followed by terminal destructor must be safe.
 finally
   for I:=0 to 1 do Engines[I].Free;
   Sink.Free;Args.Free;Terminal.Free;
 end;
end.
