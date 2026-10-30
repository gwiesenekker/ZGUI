program multi_game_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,StdCtrls,
  uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,uEngineRegistry,
  uGameSetupTypes,uGameSetupForm,uGameOrchestrator,uRunningGame,uEngineEditForm;
var Chess,Draughts:TGameVariant;Checks:Integer=0;
procedure Check(Value:Boolean;const Msg:string);
begin Inc(Checks);if not Value then raise Exception.Create(Msg);end;
procedure RegistryAndContexts;
var Candidate:TGameVariant;Rejected:Boolean;Setup:TGameSetup;Game:TRunningGame;
    Dialog:TGameSetupForm;Editor:TEngineEditForm;I:Integer;Kind:TComboBox;
begin
  Check(RegisteredGameCount=2,'Two application-owned games');
  Check((GameForEngineKind(eekUci)=Chess) and (GameForEngineKind(eekHub)=Draughts)
    and (GameForEngineKind(eekDxp)=Draughts),'Protocols map to registered variants');
  Check((GameVariantById('chess')=Chess) and (GameVariantById('draughts')=Draughts),'Stable game IDs');
  Candidate:=TChessVariant.Create;Rejected:=False;
  try try RegisterGame(Candidate,ChessGuiProfile);except on E:EGamePositionError do Rejected:=True;end;
    Check(Rejected,'Duplicate registration rejected');finally Candidate.Free;end;
  Setup:=Default(TGameSetup);Setup.Variant:=Draughts;Setup.StartingFEN:=Draughts.DefaultStartingFEN;
  Setup.TimeControl:=DraughtsGuiProfile.DefaultClock;
  ValidateGameSetup(Setup,Draughts,DraughtsGuiProfile.EngineKinds);
  Game:=TRunningGame.Create(1,'Draughts',nil,pkHuman,pkHuman,'','','White','Black',nil,Setup);
  try Check(Game.GameTree.Variant=Draughts,'Running tree gets explicit variant despite chess process default');
    Game.AssignSetupTo(Setup);Check(Setup.Variant=Draughts,'Replay setup retains variant');
  finally Game.Free;end;
  Dialog:=TGameSetupForm.Create(nil,Draughts);Editor:=TEngineEditForm.Create(nil,Draughts);
  try
    Check(Dialog.Variant=Draughts,'Dialog has explicit target game');Editor.LoadEngine(nil);Kind:=nil;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TComboBox then
      if TComboBox(Editor.Components[I]).Items.IndexOf('UCI')>=0 then Kind:=TComboBox(Editor.Components[I]);
    Check((Kind<>nil) and SameText(Kind.Text,'hub'),'Draughts editor defaults to Hub while process starts as chess');
  finally Editor.Free;Dialog.Free;end;
end;
begin
  RequireDerivedFormResource:=False;Application.Initialize;Application.ShowMainForm:=False;
  Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
  RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
  try RegistryAndContexts;WriteLn('Multi-game checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
