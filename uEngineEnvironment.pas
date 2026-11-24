unit uEngineEnvironment;
{$mode objfpc}{$H+}
interface
uses Classes,fpjson;
function ParseEngineEnvironment(const Text:string):TJSONObject;
function CanonicalEngineEnvironment(const Text:string):string;
function InheritedEngineEnvironment:TStringList;
function MergeEngineEnvironment(const Text:string;BaseEnvironment:TStrings):TStringList;
implementation
uses SysUtils,jsonparser{$IFDEF MSWINDOWS},Windows{$ENDIF};
function ParseEngineEnvironment(const Text:string):TJSONObject;
var Data:TJSONData;Names:TStringList;I,J:Integer;Name,Value,Input:string;
begin
 Result:=nil;Data:=nil;Names:=TStringList.Create;
 {$IFDEF MSWINDOWS}Names.CaseSensitive:=False;{$ELSE}Names.CaseSensitive:=True;{$ENDIF}
 try
  try
  Input:=Trim(Text);if Input='' then Input:='{}';
  // Some FPC JSON decoders drop an escaped NUL; reject it before decoding.
  if Pos(#0,Input)>0 then raise EConvertError.Create('Environment cannot contain NUL');
  I:=1;while I<=Length(Input) do begin
   if Input[I]='\' then begin
    if Copy(Input,I+1,5)='u0000' then raise EConvertError.Create('Environment cannot contain NUL');
    Inc(I,2);
   end else Inc(I);
  end;
  try Data:=GetJSON(Input);except on E:Exception do raise EConvertError.Create('Invalid environment JSON: '+E.Message);end;
  if Data.JSONType<>jtObject then raise EConvertError.Create('Environment must be a JSON object of string values');
  for I:=0 to Data.Count-1 do begin
   Name:=TJSONObject(Data).Names[I];
   if (Name='') or not (Name[1] in ['A'..'Z','a'..'z','_']) then
    raise EConvertError.Create('Environment names must start with a letter or underscore');
   for J:=1 to Length(Name) do if not (Name[J] in ['A'..'Z','a'..'z','0'..'9','_']) then
    raise EConvertError.Create('Environment names may contain only letters, digits and underscores');
   if Names.IndexOf(Name)>=0 then raise EConvertError.Create('Duplicate environment name: '+Name);
   Names.Add(Name);
   if Data.Items[I].JSONType<>jtString then raise EConvertError.Create('Environment values must be JSON strings');
   Value:=Data.Items[I].AsString;
   if Pos(#0,Value)>0 then raise EConvertError.Create('Environment values cannot contain NUL');
  end;
  Names.Sort;Result:=TJSONObject.Create;
  for I:=0 to Names.Count-1 do begin
   Name:=Names[I];Value:=TJSONObject(Data).Get(Name,'');
   {$IFDEF MSWINDOWS}Name:=UpperCase(Name);{$ENDIF}
   Result.Add(Name,Value);
  end;
 except Result.Free;Result:=nil;raise;end;
 finally Names.Free;Data.Free;end;
end;
function CanonicalEngineEnvironment(const Text:string):string;
var Obj:TJSONObject;
begin Obj:=ParseEngineEnvironment(Text);try Result:=Obj.AsJSON;finally Obj.Free;end;end;
function InheritedEngineEnvironment:TStringList;
{$IFDEF MSWINDOWS}var Block,P:PWideChar;{$ELSE}var I:Integer;{$ENDIF}
begin
 Result:=TStringList.Create;
 try
  {$IFDEF MSWINDOWS}
  Block:=GetEnvironmentStringsW;if Block=nil then RaiseLastOSError;
  try P:=Block;while P^<>#0 do begin Result.Add(UTF8Encode(UnicodeString(P)));Inc(P,Length(UnicodeString(P))+1);end;
  finally FreeEnvironmentStringsW(Block);end;
  {$ELSE}
  for I:=1 to GetEnvironmentVariableCount do Result.Add(GetEnvironmentString(I));
  {$ENDIF}
 except Result.Free;raise;end;
end;
function MergeEngineEnvironment(const Text:string;BaseEnvironment:TStrings):TStringList;
var Obj:TJSONObject;I,Index:Integer;Name:string;
begin
 Obj:=ParseEngineEnvironment(Text);Result:=TStringList.Create;
 {$IFDEF MSWINDOWS}Result.CaseSensitive:=False;{$ELSE}Result.CaseSensitive:=True;{$ENDIF}
 try
  try
  if BaseEnvironment<>nil then Result.Assign(BaseEnvironment);
  for I:=0 to Obj.Count-1 do begin
   Name:=Obj.Names[I];Index:=Result.IndexOfName(Name);
   // Remove every inherited spelling before adding exactly one override.
   while Index>=0 do begin Result.Delete(Index);Index:=Result.IndexOfName(Name);end;
   Result.Add(Name+'='+Obj.Items[I].AsString);
  end;
  Result.Sort;
 except Result.Free;raise;end;
 finally Obj.Free;end;
end;
end.
