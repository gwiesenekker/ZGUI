program ZGUI;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  uMainForm,
  // The game and its engine protocols register themselves when linked.
  uGamePosition, uChessPosition, uGameGuiProfile, uChessUciEngine,
  uDraughtsPosition, uDraughtsHubEngine, uDraughtsDxpEngine;

var
  Chess: TChessVariant;
  PreviousVariant: TGameVariant;

begin
  RequireDerivedFormResource := False;
  // Select the game explicitly before any GUI object asks for the default.
  // Linked draughts adapters stay available to their existing legacy consumers.
  PreviousVariant := DefaultGameVariant;
  Chess := TChessVariant.Create;
  RegisterDefaultGameVariant(Chess);
  RegisterGameGuiProfile(Chess,ChessGuiProfile);
  try
    Application.Scaled := True;
    Application.Initialize;
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;
  finally
    // The selected variant outlives all its trees, browsers and board views.
    if Application.MainForm <> nil then Application.MainForm.Free;
    MainForm := nil;
    RegisterDefaultGameVariant(PreviousVariant);
    RegisterGameGuiProfile(nil,DraughtsGuiProfile);
    Chess.Free;
  end;
end.
