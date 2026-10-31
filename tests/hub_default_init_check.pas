program hub_default_init_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uDraughtsHubEngine,uEngineRegistry,
 uEngineParamsJson,uGamePosition,uDraughtsPosition;
procedure Fake;
var Line:string;
begin
 while not EOF(Input) do begin
  ReadLn(Line);
  if Line='hub' then WriteLn('wait')
  else if Line='init' then WriteLn('ready')
  else if Line='quit' then Break;
  Flush(Output);
 end;
end;
var D:TExternalEngineDefinition;E:THubEngine;I:Integer;P:TEngineParamArray;
begin
 if ParamStr(1)='--fake-init' then begin Fake;Halt(0);end;
 RegisterDefaultGameVariant(DraughtsVariant);
 D:=TExternalEngineDefinition.Create;
 try
  D.ExePath:=ExpandFileName(ParamStr(0));D.Arguments:='--fake-init';
  P:=nil;AddOrUpdateParam(P,'gui-startup-timeout-ms','string','250',False);
  AddOrUpdateParam(P,'gui-hub-init','string','quit',False);
  SaveEngineParamsToJson(EngineParamsFileName(D.ExePath),'hub',P);
  // Existing registrations can contain an empty/whitespace script. The Hub
  // adapter must complete the fixed handshake and ignore old startup scripts.
  for I:=0 to 3 do begin
   case I of 0:D.InitText:='';1:D.InitText:='  '+LineEnding;2:D.InitText:='set-param name=threads value=1'+LineEnding+'init';3:D.InitText:='quit';end;
   E:=THubEngine.Create(D);
   try
    if not E.LaunchAndInit then raise Exception.Create('Hub initialization failed for script '+IntToStr(I));
   finally E.Free;end;
  end;
  WriteLn('PASS: mandatory Hub init ignores blank, custom and quit legacy scripts');
 finally DeleteFile(EngineParamsFileName(D.ExePath));D.Free;RegisterDefaultGameVariant(nil);end;
end.
