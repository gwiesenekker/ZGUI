unit uCliDefinitions;
{$mode objfpc}{$H+}
{ Minimal parameter-definition adapter for the SCU 44eba85 binder.
  G. Wiesenekker; GPL-3.0, as ZGUI. No JSON catalog or library types. }
interface
uses Contnrs;
type
  TParameterDefinition=class
  public
    Name:string;
    Required,HasDefault:Boolean;
    DefaultValue:string;
    constructor Create(const AName:string;ARequired:Boolean);
    procedure Validate(const Value:string);
    function CanonicalValue(const Value:string):string;
  end;
  TParameterDefinitions=class(TObjectList)
  private
    function GetParameter(Index:Integer):TParameterDefinition;
  public
    function FindIndex(const Spelling:string):Integer;
    property Items[Index:Integer]:TParameterDefinition read GetParameter;default;
  end;
  TCommandDefinition=class
  public
    Name:string;
    Arguments:TParameterDefinitions;
    constructor Create(const AName:string);
    destructor Destroy;override;
  end;
implementation
uses SysUtils;
constructor TParameterDefinition.Create(const AName:string;ARequired:Boolean);
begin inherited Create;Name:=AName;Required:=ARequired;end;
procedure TParameterDefinition.Validate(const Value:string);
begin { String parameter, as SCU pkString. Request validates non-empty file. } end;
function TParameterDefinition.CanonicalValue(const Value:string):string;
begin Result:=Value;end;
function TParameterDefinitions.GetParameter(Index:Integer):TParameterDefinition;
begin Result:=TParameterDefinition(inherited Items[Index]);end;
function TParameterDefinitions.FindIndex(const Spelling:string):Integer;
var I:Integer;
begin for I:=0 to Count-1 do if SameText(Items[I].Name,Spelling) then Exit(I);Result:=-1;end;
constructor TCommandDefinition.Create(const AName:string);
begin inherited Create;Name:=AName;Arguments:=TParameterDefinitions.Create(True);end;
destructor TCommandDefinition.Destroy;
begin Arguments.Free;inherited Destroy;end;
end.
