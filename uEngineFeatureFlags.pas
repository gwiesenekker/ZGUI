unit uEngineFeatureFlags;
{$mode objfpc}{$H+}
interface
uses Classes;
const
  FeatureNoPondering='no-pondering';
  FeatureNoPonderHit='no-ponder-hit';
  FeatureDxpPv='dxp-pv';
function ParseEngineFeatureFlags(const Text:string):TStringList;
function EngineFeatureFlagsJson(Flags:TStrings):string;
function HasEngineFeatureFlag(const Text,Flag:string):Boolean;
implementation
uses SysUtils,fpjson,jsonparser;
function ParseEngineFeatureFlags(const Text:string):TStringList;
var Data:TJSONData;I,J:Integer;Name:string;
begin
  Result:=TStringList.Create;Result.CaseSensitive:=False;Data:=nil;
  try
    try Data:=GetJSON(Text);except on E:Exception do raise EConvertError.Create('Feature flags must be a JSON array of flag names: '+E.Message);end;
    if Data.JSONType<>jtArray then raise EConvertError.Create('Feature flags must be a JSON array of flag names');
    for I:=0 to Data.Count-1 do begin
      if Data.Items[I].JSONType<>jtString then raise EConvertError.Create('Each feature flag must be a string');
      Name:=LowerCase(Trim(Data.Items[I].AsString));
      // Accept the earlier development spelling, and save only the common flag.
      if Name='gui-gwd-dxp-pv' then Name:=FeatureDxpPv;
      if Name='' then raise EConvertError.Create('Feature flag names cannot be empty');
      for J:=1 to Length(Name) do if not (Name[J] in ['a'..'z','0'..'9','-']) then
        raise EConvertError.Create('Feature flag names may contain letters, digits and hyphens');
      if Result.IndexOf(Name)<0 then Result.Add(Name);
    end;
  except Data.Free;Result.Free;raise;
  end;
  Data.Free;
end;
function EngineFeatureFlagsJson(Flags:TStrings):string;
var Data:TJSONArray;I:Integer;
begin
  Data:=TJSONArray.Create;
  try for I:=0 to Flags.Count-1 do Data.Add(Flags[I]);Result:=Data.AsJSON;finally Data.Free;end;
end;
function HasEngineFeatureFlag(const Text,Flag:string):Boolean;
var Flags:TStringList;
begin Flags:=ParseEngineFeatureFlags(Text);try Result:=Flags.IndexOf(Flag)>=0;finally Flags.Free;end;end;
end.
