unit uCliBinder;

{ Adapted from SCU 44eba85 by G. Wiesenekker; GPL-3.0, as ZGUI.
  Execution binding only; no SCU executor, library or terminal dependencies. }
{$mode objfpc}{$H+}

interface

uses
  uCliCommand, uCliDefinitions;

type
  TBindingMode = (bmExecution, bmCompletion);

  TCommandBinder = class
  private type
    TBinding = record
      Value: string;
      Supplied, Provided: Boolean;
    end;
  private
    FSpec: TCommandDefinition;
    FArguments: TParameterDefinitions;
    FName, FPendingSpelling: string;
    FBindings: array of TBinding;
    FPendingSlot: Integer;
    FMode: TBindingMode;
    FPositionalOnly: Boolean;
    function GetCount: Integer;
    function GetSupplied(Slot: Integer): Boolean;
    function GetValue(Slot: Integer): string;
    function ArgumentSuggestion(const Name: string): string;
    procedure CheckDuplicate(Slot: Integer);
  public
    constructor Create(Spec: TCommandDefinition; Mode: TBindingMode);
    procedure Feed(const Token: string);
    procedure FinishTokens;
    procedure Bind(Slot: Integer; const Value: string; Provided: Boolean);
    function NextPositional: Integer;
    function NamedSlot(const Token: string; out EqualsAt: Integer): Integer;
    function PendingAccepts(const Token: string): Boolean;
    function ParameterAt(Slot: Integer): TParameterDefinition;
    function WithReservedSlot(Slot: Integer): TCommandBinder;
    function CreateCommand: TCliCommand;
    property Count: Integer read GetCount;
    property Name: string read FName;
    property Arguments: TParameterDefinitions read FArguments;
    property PendingSlot: Integer read FPendingSlot;
    property PositionalOnly: Boolean read FPositionalOnly;
    property Supplied[Slot: Integer]: Boolean read GetSupplied;
    property Values[Slot: Integer]: string read GetValue;
  end;

implementation

uses
  SysUtils, uCliErrors;

function NameDistance(const Left, Right: string): Integer;
var Previous, Current: array of Integer;
  I, J, Cost: Integer;
begin
  if Abs(Length(Left) - Length(Right)) > 2 then Exit(3);
  SetLength(Previous, Length(Right) + 1);
  SetLength(Current, Length(Right) + 1);
  for J := 0 to Length(Right) do Previous[J] := J;
  for I := 1 to Length(Left) do
  begin
    Current[0] := I;
    for J := 1 to Length(Right) do
    begin
      Cost := Ord(LowerCase(Left[I]) <> LowerCase(Right[J]));
      Current[J] := Previous[J] + 1;
      if Current[J - 1] + 1 < Current[J] then Current[J] := Current[J - 1] + 1;
      if Previous[J - 1] + Cost < Current[J] then Current[J] := Previous[J - 1] + Cost;
    end;
    Previous := Copy(Current);
  end;
  Result := Previous[Length(Right)];
end;

function TCommandBinder.ArgumentSuggestion(const Name: string): string;
var Index, Distance, Best: Integer;
begin
  Result := '';
  Best := 3;
  for Index := 0 to FArguments.Count - 1 do
  begin
    Distance := NameDistance(Name, FArguments[Index].Name);
    if Distance < Best then
    begin
      Result := FArguments[Index].Name;
      Best := Distance;
    end;
  end;
end;

constructor TCommandBinder.Create(Spec: TCommandDefinition; Mode: TBindingMode);
begin
  inherited Create;
  FSpec := Spec;
  FMode := Mode;
  FName := Spec.Name;
  FArguments := Spec.Arguments;
  FPendingSlot := -1;
  SetLength(FBindings, FArguments.Count);
end;

function TCommandBinder.GetCount: Integer;
begin
  Result := Length(FBindings);
end;

function TCommandBinder.GetSupplied(Slot: Integer): Boolean;
begin
  Result := FBindings[Slot].Supplied;
end;

function TCommandBinder.GetValue(Slot: Integer): string;
begin
  Result := FBindings[Slot].Value;
end;

function TCommandBinder.ParameterAt(Slot: Integer): TParameterDefinition;
begin
  Result := FArguments[Slot];
end;

function TCommandBinder.NextPositional: Integer;
var
  Slot: Integer;
begin
  for Slot := 0 to FArguments.Count - 1 do
    if not Supplied[Slot] then
      Exit(Slot);
  Result := -1;
end;

function TCommandBinder.NamedSlot(const Token: string; out EqualsAt: Integer): Integer;
var
  Key: string;
begin
  Result := -1;
  EqualsAt := 0;
  if FPositionalOnly then
    Exit;
  EqualsAt := Pos('=', Token);
  if Copy(Token, 1, 2) = '--' then
  begin
    if Token = '--' then
      Exit;
    if EqualsAt > 0 then
      Key := Copy(Token, 3, EqualsAt - 3)
    else
      Key := Copy(Token, 3, MaxInt);
    Result := FArguments.FindIndex(Key);
  end
  else
  begin
    if EqualsAt <= 1 then
      Exit;
    Key := Copy(Token, 1, EqualsAt - 1);
    Result := FArguments.FindIndex(Key);
  end;
end;

function TCommandBinder.PendingAccepts(const Token: string): Boolean;
var
  EqualsAt: Integer;
begin
  Result := (FPendingSlot >= 0) and
    (not ParameterAt(FPendingSlot).Required or
      ((Copy(Token, 1, 2) <> '--') and (NamedSlot(Token, EqualsAt) < 0)));
end;

procedure TCommandBinder.CheckDuplicate(Slot: Integer);
var
  Key: string;
begin
  if (FMode <> bmExecution) or not Supplied[Slot] then
    Exit;
  Key := ParameterAt(Slot).Name;
  raise ECliError.CreateFmt('Duplicate argument %s.', [Key]);
end;

procedure TCommandBinder.Bind(Slot: Integer; const Value: string; Provided: Boolean);
begin
  CheckDuplicate(Slot);
  // The catalog validates defaults, and the CLI validates answers at the prompt.
  if (FMode = bmExecution) and Provided then
    ParameterAt(Slot).Validate(Value);
  FBindings[Slot].Value := ParameterAt(Slot).CanonicalValue(Value);
  FBindings[Slot].Supplied := True;
  FBindings[Slot].Provided := Provided;
end;

procedure TCommandBinder.Feed(const Token: string);
var
  Slot, EqualsAt, Index: Integer;
  Key, Suggestion, Message: string;
  LooksNamed: Boolean;
begin
  if FPendingSlot >= 0 then
  begin
    Slot := FPendingSlot;
    if PendingAccepts(Token) then
    begin
      FPendingSlot := -1;
      Bind(Slot, Token, True);
      Exit;
    end;
    FinishTokens;
  end;
  if not FPositionalOnly and (Token = '--') then
  begin
    FPositionalOnly := True;
    Exit;
  end;
  Slot := NamedSlot(Token, EqualsAt);
  if Slot >= 0 then
  begin
    if EqualsAt > 0 then
      Bind(Slot, Copy(Token, EqualsAt + 1, MaxInt), True)
    else
    begin
      FPendingSlot := Slot;
      FPendingSpelling := Token;
    end;
  end
  else if not FPositionalOnly and (Copy(Token, 1, 2) = '--') then
  begin
    if FMode = bmExecution then
      raise ECliError.CreateFmt('Unknown argument %s for %s.', [Token, FName]);
  end
  else
  begin
    EqualsAt := Pos('=', Token);
    LooksNamed := not FPositionalOnly and (EqualsAt > 1);
    if LooksNamed then
      for Index := 1 to EqualsAt - 1 do
        if not (Token[Index] in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-']) then LooksNamed := False;
    if LooksNamed and (FMode = bmExecution) then
    begin
      Key := Copy(Token, 1, EqualsAt - 1);
      Message := 'Unknown argument ' + Key + ' for ' + FName + '.';
      Suggestion := ArgumentSuggestion(Key);
      if Suggestion <> '' then Message := Message + ' Did you mean ' + Suggestion + '?';
      raise ECliError.Create(Message);
    end;
    Slot := NextPositional;
    if Slot >= 0 then
      Bind(Slot, Token, True)
    else if FMode = bmExecution then
      raise ECliError.CreateFmt('Too many arguments for %s. Run zgui --help.', [FName]);
  end;
end;

procedure TCommandBinder.FinishTokens;
begin
  if FPendingSlot < 0 then
    Exit;
  if FMode = bmExecution then
  begin
    if not ParameterAt(FPendingSlot).Required then
      raise ECliError.CreateFmt('Expected a value for %s.', [FPendingSpelling]);
    CheckDuplicate(FPendingSlot);
  end;
  FPendingSlot := -1;
end;

function TCommandBinder.WithReservedSlot(Slot: Integer): TCommandBinder;
begin
  // The token being completed separates the earlier bindings from the tail.
  Result := TCommandBinder.Create(FSpec, FMode);
  try
    Result.FBindings := Copy(FBindings);
    Result.FPositionalOnly := FPositionalOnly;
    if Slot >= 0 then
      Result.FBindings[Slot].Supplied := True;
  except
    Result.Free;
    raise;
  end;
end;

function TCommandBinder.CreateCommand: TCliCommand;
var
  BoundArguments: TCliArguments;
  Slot, BoundCount: Integer;
begin
  BoundArguments := nil;
  SetLength(BoundArguments, FArguments.Count);
  BoundCount := 0;
  for Slot := 0 to FArguments.Count - 1 do
    if Supplied[Slot] then
    begin
      BoundArguments[BoundCount].Name := ParameterAt(Slot).Name;
      BoundArguments[BoundCount].Value := Values[Slot];
      BoundArguments[BoundCount].Provided := FBindings[Slot].Provided;
      Inc(BoundCount);
    end;
  SetLength(BoundArguments, BoundCount);
  Result := TCliCommand.Create(FName, BoundArguments);
end;

end.
