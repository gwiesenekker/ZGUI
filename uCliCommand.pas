unit uCliCommand;

{ Adapted from SCU 44eba85 by G. Wiesenekker; GPL-3.0, as ZGUI.
  Execution binding only; no SCU executor, library or terminal dependencies. }
{$mode objfpc}{$H+}

interface

type
  TCliArgument = record
    Name, Value: string;
    Provided: Boolean;
  end;
  TCliArguments = array of TCliArgument;

  TCliCommand = class
  private
    FName: string;
    FArguments: TCliArguments;
    function FindArgument(const Key: string): Integer;
    function GetArgument(Index: Integer): TCliArgument;
    function GetNamedArgument(const Key: string): TCliArgument;
    function GetArgumentValue(const Key: string): string;
    function GetArgumentProvided(const Key: string): Boolean;
    function GetArgumentCount: Integer;
  public
    constructor Create(const AName: string; const Arguments: TCliArguments);
    function HasArgument(const Key: string): Boolean;
    function Argument(const Key: string; const Default: string = ''): string;
    property Name: string read FName;
    property ArgumentCount: Integer read GetArgumentCount;
    property Arguments[Index: Integer]: TCliArgument read GetArgument;
    property Values[const Key: string]: string read GetArgumentValue; default;
    property Provided[const Key: string]: Boolean read GetArgumentProvided;
  end;

implementation

uses
  SysUtils, uCliErrors;

constructor TCliCommand.Create(const AName: string; const Arguments: TCliArguments);
begin
  inherited Create;
  FName := AName;
  FArguments := Copy(Arguments);
end;

function TCliCommand.FindArgument(const Key: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FArguments) do
    if FArguments[Index].Name = Key then
      Exit(Index);
  Result := -1;
end;

function TCliCommand.HasArgument(const Key: string): Boolean;
begin
  Result := FindArgument(Key) >= 0;
end;

function TCliCommand.GetNamedArgument(const Key: string): TCliArgument;
var
  Index: Integer;
begin
  Index := FindArgument(Key);
  if Index < 0 then
    raise ECliError.CreateFmt('Missing argument %s for %s.', [Key, FName]);
  Result := FArguments[Index];
end;

function TCliCommand.GetArgumentValue(const Key: string): string;
begin
  Result := GetNamedArgument(Key).Value;
end;

function TCliCommand.GetArgumentProvided(const Key: string): Boolean;
var
  Index: Integer;
begin
  Index := FindArgument(Key);
  Result := (Index >= 0) and FArguments[Index].Provided;
end;

function TCliCommand.GetArgument(Index: Integer): TCliArgument;
begin
  if (Index < 0) or (Index >= Length(FArguments)) then
    raise ECliError.CreateFmt('Missing argument %d for %s.', [Index + 1, FName]);
  Result := FArguments[Index];
end;

function TCliCommand.GetArgumentCount: Integer;
begin
  Result := Length(FArguments);
end;

function TCliCommand.Argument(const Key: string; const Default: string): string;
var
  Index: Integer;
begin
  Index := FindArgument(Key);
  if Index < 0 then
    Exit(Default);
  Result := FArguments[Index].Value;
end;

end.
