unit uEngineConfiguration;
{$mode objfpc}{$H+}
interface
uses Classes,FPJSON,uEngineRegistry,uEngineParamsJson;
procedure ValidateEngineConfiguration(Engine:TExternalEngineDefinition;const Params:TEngineParamArray);
procedure ApplyEngineOptions(var Params:TEngineParamArray;Options:TJSONObject);
procedure SaveEngineConfiguration(const RegistryFile:string;Engines:TExternalEngineList;
  Engine:TExternalEngineDefinition;const Params:TEngineParamArray);
implementation
uses SysUtils,uChessUciProtocol,uEngineFeatureFlags,uEngineEnvironment,uAtomicFile;
procedure ValidateEngineConfiguration(Engine:TExternalEngineDefinition;const Params:TEngineParamArray);
var I:Integer;
begin
 CanonicalEngineEnvironment(EngineParamValue(Params,'gui-environment',Engine.EnvironmentJson));
 ParseEngineFeatureFlags(EngineParamValue(Params,'gui-feature-flags','[]')).Free;
 if Engine.Kind=eekUci then begin
  for I:=0 to High(Params) do if Copy(LowerCase(Params[I].Name),1,4)<>'gui-' then
   ValidateUciValue(Params[I],Params[I].Value);
 end else if Engine.Kind=eekHub then ValidateHubParams(Params);
end;
procedure ApplyEngineOptions(var Params:TEngineParamArray;Options:TJSONObject);
var I,J,K:Integer;Name,Value:string;Seen:TStringList;
begin
 Seen:=TStringList.Create;Seen.CaseSensitive:=False;
 try for I:=0 to Options.Count-1 do begin
  Name:=Options.Names[I];
  if Seen.IndexOf(Name)>=0 then raise EConvertError.Create('Duplicate option: '+Name);
  Seen.Add(Name);
  if Copy(LowerCase(Name),1,4)='gui-' then
   raise EConvertError.Create('Use environment or feature_flags for GUI settings; options contains engine options only');
  K:=-1;for J:=0 to High(Params) do if SameText(Params[J].Name,Name) then begin K:=J;Break;end;
  if K<0 then raise EConvertError.Create('Unknown engine option: '+Name+'; launch and accept the engine in Engines first to capture its options');
  if SameText(Params[K].ParamType,'button') then raise EConvertError.Create('Button options cannot be saved: '+Name);
  case Options.Items[I].JSONType of
   jtString:Value:=Options.Items[I].AsString;
   jtBoolean,jtNumber:Value:=Options.Items[I].AsJSON;
   else raise EConvertError.Create('Option values must be strings, numbers or booleans: '+Name);
  end;
  Params[K].Value:=Value;
 end;finally Seen.Free;end;
end;
function ReadText(const FileName:string):string;
var Stream:TFileStream;
begin
 Stream:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyNone);
 try SetLength(Result,Stream.Size);if Length(Result)>0 then Stream.ReadBuffer(Result[1],Length(Result));
 finally Stream.Free;end;
end;
procedure SaveEngineConfiguration(const RegistryFile:string;Engines:TExternalEngineList;
 Engine:TExternalEngineDefinition;const Params:TEngineParamArray);
var ParamFile,OldParams,OldRegistry:string;HadParams,HadRegistry:Boolean;Original:TExternalEngineDefinition;
 procedure Restore(const Name,Text:string;Existed:Boolean);
 begin if Existed then WriteTextFileAtomically(Name,Text)
  else if FileExists(Name) and not DeleteFile(Name) then raise EInOutError.Create('Cannot restore '+Name);end;
begin
 ValidateEngineConfiguration(Engine,Params);
 ParamFile:='';if Engine.Kind<>eekUci then ParamFile:=EngineParamsFileName(Engine.ExePath);
 HadParams:=(ParamFile<>'') and FileExists(ParamFile);HadRegistry:=FileExists(RegistryFile);
 if HadParams then OldParams:=ReadText(ParamFile);if HadRegistry then OldRegistry:=ReadText(RegistryFile);
 Original:=TExternalEngineDefinition.Create;Original.Assign(Engine);
 try
 try
  // Use the same storage paths/serializers as accepting the GUI engine editor.
  SaveEngineDefinitionParams(Engine,Params);SaveExternalEngines(RegistryFile,Engines);
 except
  on E:Exception do begin
   Engine.Assign(Original);
   try
    if ParamFile<>'' then Restore(ParamFile,OldParams,HadParams);
    Restore(RegistryFile,OldRegistry,HadRegistry);
   except on R:Exception do raise EInOutError.Create(E.Message+'; restoring configuration failed: '+R.Message);end;
   raise;
  end;
 end;
 finally Original.Free;end;
end;
end.
