unit uGameBoardFactory;
{$mode objfpc}{$H+}
{ GUI composition only. Game rules/interfaces have no LCL dependency. }
interface
uses Classes, uGamePosition, uGameBoardControl;
function CreateGameBoardControl(AOwner: TComponent; AVariant: TGameVariant): TGameBoardControl;
implementation
uses uChessPosition, uChessBoardControl, uDraughtsPosition, uDraughtsBoardControl;
function CreateGameBoardControl(AOwner: TComponent; AVariant: TGameVariant): TGameBoardControl;
begin
  if AVariant is TChessVariant then Result := TChessBoardControl.Create(AOwner)
  else if AVariant is TDraughtsVariant then Result := TDraughtsBoardControl.Create(AOwner)
  else raise EGamePositionError.Create('No board view for '+AVariant.Name);
end;
end.
