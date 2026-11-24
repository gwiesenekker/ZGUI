program engine_configuration_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,FPJSON,JSONParser,
 uEngineRegistry,uEngineParamsJson,uEngineConfiguration,uEngineInstallationFixture;
var Checks:Integer;L,R:TExternalEngineList;E:TExternalEngineDefinition;
 Params:TEngineParamArray;Patch:TJSONObject;Text:TStringList;Kind:TExternalEngineKind;
 Registry,Before,ParamFile,Directory,OriginalEnv:string;Rejected:Boolean;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
begin
 L:=TExternalEngineList.Create;R:=TExternalEngineList.Create;Text:=TStringList.Create;
 Directory:=GetTempFileName(GetTempDir,'config');DeleteFile(Directory);ForceDirectories(Directory);
 Registry:=Directory+'/registry.json';
 try
  for Kind:=Low(Kind) to High(Kind) do begin
   L.Clear;E:=TExternalEngineDefinition.Create;L.Add(E);E.Kind:=Kind;
   E.ExePath:=InstallEngineFixture(ParamStr(0),'config-'+IntToStr(Ord(Kind)));
   E.UciId:='UCI';E.HubId:='Hub';E.DxpId:='DXP';Params:=nil;
   AddOrUpdateParam(Params,'Threads','spin','1',False);Params[0].MinValue:='1';Params[0].MaxValue:='4';
   SaveEngineConfiguration(Registry,L,E,Params);OriginalEnv:=E.EnvironmentJson;
   if Kind<>eekUci then begin
    ParamFile:=EngineParamsFileName(E.ExePath);Text.LoadFromFile(ParamFile);Before:=Text.Text;
    AddOrUpdateParam(Params,'gui-environment','string','{"CONFIG_TEST":"rollback"}',False);
    ForceDirectories(Directory+'/invalid-registry');Rejected:=False;
    try SaveEngineConfiguration(Directory+'/invalid-registry',L,E,Params);except on X:Exception do Rejected:=True;end;
    Check(Rejected,'Storage failure reported');Text.LoadFromFile(ParamFile);
    Check(Text.Text=Before,'Parameter bytes restored after registry failure');
    Check(E.EnvironmentJson=OriginalEnv,'In-memory definition restored after failure');
   end;
   Patch:=TJSONObject(GetJSON('{"Threads":3}'));
   try ApplyEngineOptions(Params,Patch);finally Patch.Free;end;
   AddOrUpdateParam(Params,'gui-environment','string','{"CONFIG_TEST":"value","EMPTY":""}',False);
   AddOrUpdateParam(Params,'gui-feature-flags','string','["no-pondering"]',False);
   SaveEngineConfiguration(Registry,L,E,Params);LoadExternalEngines(Registry,R);
   Check(R.Count=1,'Configuration retains one registration');Check(R[0].EnvironmentJson=E.EnvironmentJson,'Environment stored in registry for every protocol');
   Params:=nil;LoadEngineDefinitionParams(R[0],LowerCase(E.KindText),Params);
   Check(EngineParamValue(Params,'Threads','')='3','Shared GUI loader reads changed option');
   Check(EngineHasFeatureFlag(Params,'no-pondering'),'Shared GUI loader reads feature flags');
  end;
 finally L.Free;R.Free;Text.Free;end;
 WriteLn('Engine configuration checks passed (',Checks,' checks)');
end.
