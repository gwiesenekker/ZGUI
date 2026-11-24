program engine_installation_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,BaseUnix,{$ENDIF} Classes,SysUtils,uEngineInstallationFixture,
 uEngineRegistry,uChessUciEngine,uDraughtsHubEngine,uDraughtsDxpEngine;
var Checks:Integer;
procedure Check(B:Boolean;const S:string);begin Inc(Checks);if not B then raise Exception.Create(S);end;
var A,B,Clone:TExternalEngineDefinition;L,R:TExternalEngineList;Text:TStringList;
 PathA,PathB,RegistryName,Marker,Before,Alias:string;U:TUciEngine;H:THubEngine;D:TDxpEngine;
begin
 if ParamStr(1)='--child' then begin Text:=TStringList.Create;Text.Add('LAUNCHED');Text.SaveToFile(ParamStr(2));Text.Free;Halt(0);end;
 A:=TExternalEngineDefinition.Create;B:=TExternalEngineDefinition.Create;Clone:=TExternalEngineDefinition.Create;
 L:=TExternalEngineList.Create;R:=TExternalEngineList.Create;Text:=TStringList.Create;
 RegistryName:=GetTempFileName(GetTempDir,'install');Marker:=RegistryName+'.launched';
 try
  PathA:=InstallEngineFixture(ParamStr(0),'one');PathB:=InstallEngineFixture(ParamStr(0),'two');
  A.Kind:=eekUci;A.ExePath:=PathA;A.UciId:='One';A.InitText:='';A.Arguments:='--child "'+Marker+'"';
  B.Assign(A);B.Kind:=eekHub;B.HubId:='Two';B.EnvironmentJson:='{"TEST":"different"}';
  L.Add(A);A:=nil;L.Add(B);B:=nil;
  RefreshEngineRegistrationProblems(L);
  Check((L[0].RegistrationProblem<>'') and (L[1].RegistrationProblem<>''),'Both shared-executable registrations invalid regardless of protocol/overrides');
  Check(EngineRegistrationConflict(L[0],L,0)<>'','Editing one cannot ignore the other');
  L[1].ExePath:=PathB;RefreshEngineRegistrationProblems(L);
  Check((L[0].RegistrationProblem='') and (L[1].RegistrationProblem=''),'Separate installed executables and directories allowed');
  Check(EngineRegistrationConflict(L[0],L,0)='','Editing itself allowed');
  Alias:=ExtractFilePath(PathA)+'another-engine';Text.Add('different file');Text.SaveToFile(Alias);
  L[1].ExePath:=Alias;RefreshEngineRegistrationProblems(L);
  Check(L[0].RegistrationProblem<>'','Different executables in one directory rejected');
  {$IFDEF UNIX}
  Alias:=ExtractFilePath(PathB)+'linked-engine';DeleteFile(Alias);
  Check(fpSymlink(PChar(PathA),PChar(Alias))=0,'Create executable symlink fixture');
  L[1].ExePath:=Alias;RefreshEngineRegistrationProblems(L);
  Check((L[0].RegistrationProblem<>'') and (L[1].RegistrationProblem<>''),'Executable symlink alias rejected across directories');DeleteFile(Alias);
  Check(fpLink(PChar(PathA),PChar(Alias))=0,'Create hardlink fixture');
  RefreshEngineRegistrationProblems(L);Check(L[0].RegistrationProblem<>'','Hardlink alias rejected');DeleteFile(Alias);
  Alias:=ExtractFilePath(ExcludeTrailingPathDelimiter(ExtractFilePath(PathB)))+'alias-dir';
  DeleteFile(Alias);Check(fpSymlink(PChar(ExcludeTrailingPathDelimiter(ExtractFilePath(PathA))),PChar(Alias))=0,'Create directory alias');
  L[1].ExePath:=Alias+DirectorySeparator+ExtractFileName(PathA);RefreshEngineRegistrationProblems(L);
  Check(L[0].RegistrationProblem<>'','Directory alias rejected');DeleteFile(Alias);
  ForceDirectories(ExtractFilePath(PathA)+'child');
  Check(fpSymlink(PChar(ExtractFilePath(PathA)+'child'),PChar(Alias))=0,'Create symlink parent fixture');
  L[1].ExePath:=Alias+'/../'+ExtractFileName(PathA);RefreshEngineRegistrationProblems(L);
  Check(FileExists(L[1].ExePath) and (L[1].RegistrationProblem<>''),'Resolve symlink/.. using actual filesystem semantics');DeleteFile(Alias);
  {$ENDIF}
  L[1].ExePath:=PathA;
  SaveExternalEngines(RegistryName,L);Text.LoadFromFile(RegistryName);Before:=Text.Text;
  LoadExternalEngines(RegistryName,R);Text.LoadFromFile(RegistryName);
  Check(Text.Text=Before,'Loading invalid legacy registry does not rewrite or delete it');
  Check((R.Count=2) and (EngineExecutableProblem(R[0])<>''),'Legacy conflict remains visible and unavailable');
  Clone.Assign(R[0]);Check(Clone.RegistrationProblem<>'','Launch definition clone retains conflict');
  U:=TUciEngine.Create(R[0]);try Check(not U.LaunchAndInit,'UCI refuses conflicted registration');finally U.Free;end;
  H:=THubEngine.Create(R[1]);try Check(not H.LaunchAndInit,'Hub refuses conflicted registration');finally H.Free;end;
  Clone.Kind:=eekDxp;D:=TDxpEngine.Create(Clone);try Check(not D.LaunchAndInit,'DXP refuses conflicted registration');finally D.Free;end;
  Check(not FileExists(Marker),'Blocked adapters never launched executable');
  R.Delete(1);RefreshEngineRegistrationProblems(R);
  Check(EngineExecutableProblem(R[0])='','Removing duplicate clears conflict');
 finally Text.Free;Clone.Free;A.Free;B.Free;L.Free;R.Free;DeleteFile(RegistryName);DeleteFile(Marker);end;
 WriteLn('Engine installation checks passed (',Checks,' checks)');
end.
