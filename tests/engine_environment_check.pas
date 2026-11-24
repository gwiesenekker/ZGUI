program engine_environment_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,cwstring,{$ENDIF} Classes,SysUtils,fpjson,jsonparser,sockets,ssockets,uDraughtsDxpEngine,
 uChessUciEngine,uDraughtsHubEngine,uEngineEnvironment,uPlatformProcess,uEngineRegistry,uEngineParamsJson;
type TProbe=class
 Text:string;
 procedure Data(Sender:TObject;const Chunk:string);
end;
procedure TProbe.Data(Sender:TObject;const Chunk:string);begin Text+=Chunk;end;
var Checks:Integer;
procedure Check(B:Boolean;const S:string);begin Inc(Checks);if not B then raise Exception.Create(S);end;
var A,B,CopyDef:TExternalEngineDefinition;List,Reloaded:TExternalEngineList;
 Env,Base:TStringList;Obj:TJSONObject;Data:TJSONData;I:Integer;Kind:TExternalEngineKind;
 Params,Loaded:TEngineParamArray;FileName,ParamFile,Key,Before,Invalid:string;Raised:Boolean;
 First,Second:TPlatformProcess;Args:TStringList;One,Two:TProbe;Tick:QWord;Line:string;Uci:TUciEngine;Hub:THubEngine;Dxp:TDxpEngine;Socket:TInetSocket;Server:TInetServer;Address:TInetSockAddr;AddressSize:TSockLen;Port:Word;
begin
 {$IFDEF MSWINDOWS}
 SetMultiByteConversionCodePage(CP_UTF8);SetMultiByteFileSystemCodePage(CP_UTF8);
 {$ENDIF}
 if ParamStr(1)='--dxp-env' then begin
  if GetEnvironmentVariable('ZGUI_ENV_TEST')<>'protocol' then Halt(1);
  Socket:=TInetSocket.Create('127.0.0.1',StrToInt(GetEnvironmentVariable('ZGUI_DXP_PORT')),3000);
  try Sleep(1000);finally Socket.Free;end;Halt(0);
 end;
 if ParamStr(1)='--protocol-env' then begin
  if GetEnvironmentVariable('ZGUI_ENV_TEST')<>'protocol' then Halt(1);
  while not EOF(Input) do begin ReadLn(Line);
   if Line='uci' then WriteLn('uciok') else if Line='isready' then WriteLn('readyok')
   else if Line='hub' then begin WriteLn('id name=Environment version=1');WriteLn('wait');end
   else if Line='init' then WriteLn('ready') else if Line='quit' then Break;
   Flush(Output);
  end;Halt(0);
 end;
 if ParamStr(1)='--envdump' then begin
  Env:=InheritedEngineEnvironment;Obj:=TJSONObject.Create;
  try Obj.Add('marker',Env.Values['ZGUI_ENV_TEST']);Obj.Add('empty',Env.IndexOfName('ZGUI_EMPTY')>=0);
   Obj.Add('empty_value',Env.Values['ZGUI_EMPTY']);Obj.Add('path',Env.Values['PATH']);WriteLn(Obj.AsJSON);
  finally Obj.Free;Env.Free;end;Halt(0);
 end;
 for I:=0 to 7 do begin
  case I of 0:Invalid:='[]';1:Invalid:='{"X":1}';2:Invalid:='{"X":null}';3:Invalid:='{"X":"a","X":"b"}';
   4:Invalid:='{"A=B":"x"}';5:Invalid:='{"1BAD":"x"}';6:Invalid:='{"X":"\u0000"}';7:Invalid:='{';end;
  Raised:=False;try CanonicalEngineEnvironment(Invalid);except on E:EConvertError do Raised:=True;end;
  Check(Raised,'Reject invalid environment '+IntToStr(I));
 end;
 Check(Pos('u0000',CanonicalEngineEnvironment('{"X":"\\u0000"}'))>0,'Literal escaped backslash is not a NUL');
 {$IFDEF MSWINDOWS}
 Raised:=False;try CanonicalEngineEnvironment('{"Path":"one","PATH":"two"}');except on E:EConvertError do Raised:=True;end;
 Check(Raised,'Windows rejects duplicate names with different case');
 {$ELSE}
 Obj:=ParseEngineEnvironment('{"Path":"one","PATH":"two"}');
 try Check((Obj.Get('Path','')='one') and (Obj.Get('PATH','')='two'),'Linux keeps case-sensitive names distinct');finally Obj.Free;end;
 {$ENDIF}
 Check(CanonicalEngineEnvironment('')=CanonicalEngineEnvironment('{}'),'Empty default');
 Check(CanonicalEngineEnvironment('{"B":"b","A":"a"}')=CanonicalEngineEnvironment('{"A":"a","B":"b"}'),'Stable order');
 Base:=TStringList.Create;Env:=nil;
 try Base.Add('PATH=inherited path');Base.Add('ZGUI_EMPTY=old');Base.Add('ZGUI_EMPTY=duplicate');
  Env:=MergeEngineEnvironment('{"ZGUI_EMPTY":"","ZGUI_ENV_TEST":"a=b\n棋"}',Base);
  Check(Env.Count=3,'Override removes duplicate inherited entries');
  Check(Env.Values['PATH']='inherited path','Inherit unrelated variables');
  Check((Env.IndexOfName('ZGUI_EMPTY')>=0) and (Env.Values['ZGUI_EMPTY']=''),'Empty string retained');
  Check(Env.Values['ZGUI_ENV_TEST']='a=b'+#10+'棋','Unicode, equals and newline values');
  Check(Base.Values['ZGUI_EMPTY']='old','Input snapshot unchanged');
 finally Env.Free;Base.Free;end;
 List:=TExternalEngineList.Create;Reloaded:=TExternalEngineList.Create;
 A:=TExternalEngineDefinition.Create;B:=TExternalEngineDefinition.Create;CopyDef:=TExternalEngineDefinition.Create;
 FileName:=GetTempFileName(GetTempDir,'env');ParamFile:=EngineParamsFileName(FileName);
 try
  A.ExePath:=FileName;Key:=EngineIdentityKey(A);A.EnvironmentJson:='{}';
  Check(EngineIdentityKey(A)=Key,'Empty environment preserves prior identity');
  A.EnvironmentJson:='{"ZGUI_ENV_TEST":"one"}';B.Assign(A);
  B.EnvironmentJson:='{"ZGUI_ENV_TEST":"two"}';
  Check(EngineIdentityKey(A)<>EngineIdentityKey(B),'Environment distinguishes registrations');
  CopyDef.Assign(A);Check(CopyDef.EnvironmentJson=A.EnvironmentJson,'Assign copies overrides');
  for Kind:=Low(Kind) to High(Kind) do begin
   A.Kind:=Kind;Params:=nil;SeedDefaultGuiParams(Params,A);SaveEngineDefinitionParams(A,Params);
   LoadEngineDefinitionParams(A,LowerCase(A.KindText),Loaded);
   Check(EngineParamValue(Loaded,'gui-environment','')=A.EnvironmentJson,'Private params loaded for '+A.KindText);
   if Kind<>eekUci then begin LoadEngineParamsFromJson(ParamFile,LowerCase(A.KindText),Loaded);
    Check(EngineParamValue(Loaded,'gui-environment','ABSENT')='ABSENT','Not written into shared '+A.KindText+' params');end;
  end;
  List.Add(A);A:=nil;List.Add(B);B:=nil;SaveExternalEngines(FileName,List);LoadExternalEngines(FileName,Reloaded);
  Check((Reloaded[0].RegistrationProblem<>'') and (Reloaded[1].RegistrationProblem<>''),'Legacy overrides do not exempt a shared executable');
  Check((Reloaded.Count=2) and (Reloaded[0].EnvironmentJson=List[0].EnvironmentJson) and
   (Reloaded[1].EnvironmentJson=List[1].EnvironmentJson),'Legacy registry settings remain readable for inspection');
 finally A.Free;B.Free;CopyDef.Free;List.Free;Reloaded.Free;DeleteFile(FileName);DeleteFile(ParamFile);end;
 First:=TPlatformProcess.Create;Second:=TPlatformProcess.Create;Args:=TStringList.Create;
 One:=TProbe.Create;Two:=TProbe.Create;
 Before:=GetEnvironmentVariable('ZGUI_ENV_TEST');
 try
  Args.Add('--envdump');First.SynchronizeData:=False;Second.SynchronizeData:=False;
  First.OnData:=@One.Data;Second.OnData:=@Two.Data;
  First.Start(ExpandFileName(ParamStr(0)),Args,GetTempDir,'{"ZGUI_ENV_TEST":"one 棋","ZGUI_EMPTY":""}');
  Second.Start(ExpandFileName(ParamStr(0)),Args,GetTempDir,'{"ZGUI_ENV_TEST":"two","ZGUI_EMPTY":""}');
  Tick:=GetTickCount64;
  repeat First.ReadAvailable;Second.ReadAvailable;Sleep(5);
  until ((Pos(#10,One.Text)>0) and (Pos(#10,Two.Text)>0)) or (GetTickCount64-Tick>4000);
  Data:=GetJSON(One.Text);try Obj:=TJSONObject(Data);
   Check(Obj.Get('marker','')='one 棋','First child Unicode override');Check(Obj.Get('empty',False) and (Obj.Get('empty_value','bad')=''),'Child empty variable');
   Check(Obj.Get('path','')<>'','Child inherits PATH');finally Data.Free;end;
  Data:=GetJSON(Two.Text);try Check(TJSONObject(Data).Get('marker','')='two','Concurrent second child isolated');finally Data.Free;end;
  Check(GetEnvironmentVariable('ZGUI_ENV_TEST')=Before,'Parent environment unchanged');
 finally First.Free;Second.Free;One.Free;Two.Free;Args.Free;end;
 A:=TExternalEngineDefinition.Create;
 try
  A.ExePath:=ExpandFileName(ParamStr(0));A.Arguments:='--protocol-env';
  A.EnvironmentJson:='{"ZGUI_ENV_TEST":"protocol"}';A.Kind:=eekUci;A.InitText:='';
  Uci:=TUciEngine.Create(A);try Check(Uci.LaunchAndInit,'UCI runtime receives private environment');finally Uci.Free;end;
  A.Kind:=eekHub;A.InitText:='init';
  Hub:=THubEngine.Create(A);try Check(Hub.LaunchAndInit,'Hub runtime receives private environment');finally Hub.Free;end;
  Server:=TInetServer.Create('127.0.0.1',0);
  try Server.Listen;AddressSize:=SizeOf(Address);
   Check(fpGetSockName(Server.Socket,@Address,@AddressSize)=0,'Obtain isolated DXP port');Port:=ntohs(Address.sin_port);
  finally Server.Free;end;
  A.Kind:=eekDxp;A.Arguments:='--dxp-env';A.DxpHost:='127.0.0.1';A.DxpPort:=Port;A.DxpRole:=derListen;
  A.EnvironmentJson:='{"ZGUI_ENV_TEST":"protocol","ZGUI_DXP_PORT":"'+IntToStr(Port)+'"}';
  Dxp:=TDxpEngine.Create(A);try Check(Dxp.LaunchAndInit,'Local DXP receives private environment');finally Dxp.Free;end;
 finally A.Free;end;
 WriteLn('Engine environment checks passed (',Checks,' checks)');
end.
