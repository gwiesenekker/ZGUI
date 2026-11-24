program tournament_history_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} uEngineInstallationFixture,Interfaces,Forms,Controls,Classes,SysUtils,StdCtrls,Grids,FPJSON,JSONParser,
 uMainForm,uTournamentDialog,uTournamentGridModel,uGamePosition,uChessPosition,uDraughtsPosition,
 uGameGuiProfile,uEngineRegistry,uGameSetupTypes,uTimeForfeit,uGuiDialogs,Dialogs,uRunningGame;
var Checks:Integer=0;Chess,Draughts:TGameVariant;Main:TMainForm;Directory:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
begin Application.ProcessMessages;Main.TestDrainGuiEvents(True);Sleep(10);end;
procedure RegisterEngines;
var E:TExternalEngineDefinition;L:TExternalEngineList;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try for I:=0 to 3 do begin
  E:=TExternalEngineDefinition.Create;E.ExePath:=InstallEngineFixture(ExpandFileName(ParamStr(0)),'peer-'+IntToStr(I));E.Arguments:='unused '+IntToStr(I);
  if I<2 then begin E.Kind:=eekUci;E.UciId:='History UCI '+IntToStr(I);end
  else begin E.Kind:=eekHub;E.HubId:='History Hub '+IntToStr(I);end;L.Add(E);
 end;SaveExternalEngines(EnginesJsonFileName,L);finally L.Free;end;
end;
procedure Run(V:TGameVariant;Base:Integer);
var D:TTournamentDialog;Settings:TTournamentMatchSettings;Defs:TExternalEngineList;Grid:TStringGrid;
 History:TListBox;Game:TRunningGame;Doc,Item,RecordData:TJSONObject;Lines,Busy:TStringList;
 FileName,MissingFile,Text,MessageText,Before:string;Count:Integer;Policy:TTimeForfeitSettings;
begin
 D:=Main.TournamentHost.NewTournament(V);Defs:=TExternalEngineList.Create;Lines:=TStringList.Create;Busy:=TStringList.Create;
 try
  LoadExternalEngines(EnginesJsonFileName,Defs);Settings:=Default(TTournamentMatchSettings);
  Settings.Engine1Key:=EngineIdentityKey(Defs[Base]);Settings.Engine2Key:=EngineIdentityKey(Defs[Base+1]);D.ConfigureNewTournament(Settings);
  Check(D.CreatePairing(MessageText,True),'Existing pairing');FileName:=Directory+'/'+GameVariantId(V)+'.json';D.SaveTournamentToFile(FileName);
  Lines.LoadFromFile(FileName);Doc:=TJSONObject(GetJSON(Lines.Text));
  try
   Item:=TJSONArray(Doc.Find('games')).Objects[0];RecordData:=TJSONObject(Item.Find('record'));
   Text:='[Event "History test"]'+LineEnding+'[White "Saved white"]'+LineEnding+'[Black "Saved black"]'+LineEnding+
    '[Result "'+V.ResultText(goWhiteWins)+'"]'+LineEnding+LineEnding;
   if V=Chess then Text+='1. e4 {saved comment} (1. d4) e5 1-0'
   else Text+='1. 31-26 {saved comment} (1. 32-27) 16-21 2-0';
   RecordData.Strings['pdn']:=Text;RecordData.Strings['played_result']:=V.ResultText(goWhiteWins);Item.Strings['result']:=V.ResultText(goWhiteWins);
   Lines.Text:=Doc.AsJSON;Lines.SaveToFile(FileName);
  finally Doc.Free;end;
  D.LoadTournamentFromFile(FileName);Lines.LoadFromFile(FileName);Before:=Lines.Text;
  Grid:=TStringGrid(D.FindComponent('TournamentPairings'));Grid.Row:=1;History:=TListBox(Main.FindComponent('GameHistoryList'));Count:=Main.TestGameCount;
  Check(Assigned(Grid.OnDblClick),'Saved tournament supports double-click');Grid.OnDblClick(Grid);Pump;
  Check(Main.TestGameCount=Count+1,'Archived game added to existing history');
  Check(History.Items.Objects[History.ItemIndex] is TRunningGame,'History uses existing game container');Game:=TRunningGame(History.Items.Objects[History.ItemIndex]);
  Check((Game.Runner=nil) and (Game.Lifecycle=rglFinished),'Historical selection launches no worker');
  Check((Main.ActiveGameTree=Game.GameTree) and (Game.GameTree.Variant=V),'Correct game and variant selected');
  Check((Game.ResultText=V.ResultText(goWhiteWins)) and (Pos(V.ResultText(goWhiteWins),History.Items[History.ItemIndex])>0),'Saved result shown in history');
  Check((Game.MainlineCount=2) and (Game.GameTree.Root.ChildCount=2),'Existing import preserves moves and variation');
  Check(Pos('saved comment',Main.CurrentGameTreePdnText(''))>0,'Saved comment retained');
  Grid.Row:=2;Grid.OnDblClick(Grid);Pump;Check(Main.TestGameCount=Count+1,'Unplayed rows do not create placeholder duplicates');Grid.Row:=1;
  Grid.OnDblClick(Grid);Pump;Check((Main.TestGameCount=Count+1) and (Main.ActiveGameTree=Game.GameTree),'Repeated double-click reuses entry');
  D.ResetForVariant(V);D.LoadTournamentFromFile(FileName);Grid.Row:=1;Grid.OnDblClick(Grid);Pump;
  Check((Main.TestGameCount=Count+1) and (Main.ActiveGameTree=Game.GameTree),'Reloaded same event reuses history identity');
  Lines.LoadFromFile(FileName);Check(Lines.Text=Before,'Viewing does not rewrite tournament');
  Doc:=TJSONObject(GetJSON(Before));
  try
   Doc.Integers['storage_version']:=5;
   if Doc.Find('game_variant')=nil then begin
    Doc.Add('game_variant',GameVariantId(V));Doc.Add('notation_format',GameGuiProfileFor(V).FileExtension);
    Doc.Add('force_ponder_off',GameGuiProfileFor(V).TournamentForcePonderOff);
   end;
   Policy:=DefaultTimeForfeit;Policy.EngineKey:='missing-judge';Policy.EngineName:='Unavailable judge';Doc.Add('time_forfeit',TimeForfeitJson(Policy));
   MissingFile:=Directory+'/'+GameVariantId(V)+'-missing.json';Lines.Text:=Doc.AsJSON;Lines.SaveToFile(MissingFile);
  finally Doc.Free;end;
  D.ResetForVariant(V);D.LoadTournamentFromFile(MissingFile);Grid.Row:=1;Grid.OnDblClick(Grid);Pump;
  Check((Main.TestGameCount=Count+1) and (Main.ActiveGameTree=Game.GameTree),'Missing adjudicator does not block historical viewing');
  D.ResetForVariant(V);D.LoadTournamentFromFile(FileName);Grid.Row:=1;
  D.SetSelectedResult(V.ResultText(goDraw));Grid.OnDblClick(Grid);Pump;
  Check((Main.TestGameCount=Count+1) and (Game.ResultText=V.ResultText(goDraw)),'Referee result updates existing history header');
  Main.CollectBusyEngineKeys(Busy);Check(Busy.Count=0,'History entries never reserve engines');
 finally Defs.Free;Lines.Free;Busy.Free;end;
end;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 Directory:=GetTempDir+'zgui-tournament-history-'+IntToStr(GetProcessID);ForceDirectories(Directory);RegisterEngines;Main:=TMainForm.Create(nil);
 try
  Main.InteractiveCommand('list_engines');Run(Chess,0);Run(Draughts,2);
  GuiTestConfirmationResult:=mrNo;Check(Main.TournamentHost.PrepareCloseAll and Main.TournamentHost.FinishCloseAll,'Normal tab close');
  WriteLn('Tournament history GUI checks passed: ',Checks);
 finally Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
