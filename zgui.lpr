program ZGUI;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, Classes, SysUtils, LazUTF8, uStartupCommand,
  uMainForm,
  // The game and its engine protocols register themselves when linked.
  uPreferences, uGamePosition, uChessPosition, uGameGuiProfile, uChessUciEngine,
  uDraughtsPosition, uDraughtsHubEngine, uDraughtsDxpEngine;

var
  Chess: TChessVariant;
  Arguments:TStringList;Request:TStartupCommand;ErrorText:string;I:Integer;

begin
  Arguments:=TStringList.Create;
  Request:=Default(TStartupCommand);ErrorText:='';
  try
    for I:=1 to ParamCount do Arguments.Add(ParamStrUTF8(I));
    try Request:=ParseStartupCommand(Arguments);
    except on E:Exception do ErrorText:=E.Message;end;
  finally Arguments.Free;end;
  RequireDerivedFormResource := False;
  // Select the game explicitly before any GUI object asks for the default.
  // Linked draughts adapters stay available to their existing legacy consumers.
  Chess := TChessVariant.Create;
  RegisterGame(Chess,ChessGuiProfile);
  RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
  if LastGamePreference='draughts' then RegisterDefaultGameVariant(GameVariantById('draughts'))
  else RegisterDefaultGameVariant(Chess);
  try
    Application.Scaled := True;
    Application.Initialize;
    Application.CreateForm(TMainForm, MainForm);
    MainForm.QueueStartupCommand(Request,ErrorText);
    Application.Run;
  finally
    // The selected variant outlives all its trees, browsers and board views.
    if Application.MainForm <> nil then Application.MainForm.Free;
    MainForm := nil;
    RegisterDefaultGameVariant(nil);
    ClearRegisteredGames;
  end;
end.
