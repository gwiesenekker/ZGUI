unit uGameBoardFactory;
{$mode objfpc}{$H+}
{ GUI composition only. Game rules/interfaces have no LCL dependency. }
interface
uses Classes, uGamePosition, uGameBoardControl;
function CreateGameBoardControl(AOwner: TComponent; AVariant: TGameVariant): TGameBoardControl;
implementation
uses uGameGuiProfile;
function CreateGameBoardControl(AOwner: TComponent; AVariant: TGameVariant): TGameBoardControl;
begin
  Result := GameGuiProfileFor(AVariant).BoardClass.Create(AOwner);
end;
end.
