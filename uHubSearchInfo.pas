unit uHubSearchInfo;
{$mode objfpc}{$H+}
interface
uses uEngineParamsJson;
procedure MergeHubSearchInfo(const Line:string;const Params:TEngineParamArray;
  const StartingFEN:string;MoveCount:Integer;var Pv,Score,Depth,TimeText:string);
implementation
uses SysUtils,uDraughtsBoard;
function ScoreText(AValue: Double): string;
var
  FormatSettings: TFormatSettings;
begin
  if Abs(AValue) < 0.0000005 then
    AValue := 0.0;
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  Result := FormatFloat('0.###', AValue, FormatSettings);
end;

function TryHubFloat(const AText: string; out AValue: Double): Boolean;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := DefaultFormatSettings;
  FormatSettings.DecimalSeparator := '.';
  Result := TryStrToFloat(StringReplace(Trim(AText), ',', '.', []), AValue,
    FormatSettings);
end;

function SideToMoveFromPosition(const AStartingFEN: string;
  AMoveCount: Integer): TDraughtsSide;
begin
  if (Trim(AStartingFEN) <> '') and (UpCase(Trim(AStartingFEN)[1]) = 'B') then
    Result := dsBlack
  else
    Result := dsWhite;
  if Odd(AMoveCount) then
  begin
    if Result = dsWhite then
      Result := dsBlack
    else
      Result := dsWhite;
  end;
end;

function NormalizeHubScore(const AScore:string;const Params:TEngineParamArray;const StartingFEN:string;MoveCount:Integer):string;
var
  Perspective: string;
  ScoreValue: Double;
begin
  Result := Trim(AScore);
  if (Result = '') or (not TryHubFloat(Result, ScoreValue)) then
    Exit;

  Perspective := LowerCase(Trim(EngineParamValue(Params,
    'gui-score-perspective', 'side-to-move')));
  if Perspective = '' then
    Perspective := 'side-to-move';

  if (Perspective = 'black') or (Perspective = 'b') then
    ScoreValue := -ScoreValue
  else if (Perspective = 'side-to-move') or (Perspective = 'stm') or
    (Perspective = 'side') then
  begin
    if SideToMoveFromPosition(StartingFEN, MoveCount) = dsBlack then
      ScoreValue := -ScoreValue;
  end;

  Result := ScoreText(ScoreValue);
end;


procedure MergeHubSearchInfo(const Line:string;const Params:TEngineParamArray;
  const StartingFEN:string;MoveCount:Integer;var Pv,Score,Depth,TimeText:string);
var InfoLine,Value:string;
begin
  InfoLine:=Line;
  if Pos('info=',LowerCase(Line))=1 then InfoLine:='info '+Copy(Line,6,MaxInt)
  else if Pos('info ',LowerCase(Line))<>1 then Exit;
  Value:=ExtractHubArgument(InfoLine,'pv');if Value<>'' then Pv:=Value;
  Value:=ExtractHubArgument(InfoLine,'score');if Value<>'' then Score:=NormalizeHubScore(Value,Params,StartingFEN,MoveCount);
  Value:=ExtractHubArgument(InfoLine,'depth');if Value<>'' then Depth:=Value;
  Value:=ExtractHubArgument(InfoLine,'time');if Value<>'' then TimeText:=Value;
end;
end.
