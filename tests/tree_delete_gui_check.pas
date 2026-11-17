program tree_delete_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Interfaces,Forms,Classes,SysUtils,StdCtrls,ComCtrls,
 Menus,Dialogs,Controls,uMainForm,uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,
 uGameTree,uGameTreeView,uGuiDialogs,uRunningGame,uGameSetupTypes,uGameOrchestrator,
 uGameRunnerThread,uGameGuiMessages,uThreadMessageQueue;
var Main:TMainForm;Checks:Integer;
procedure Check(B:Boolean;const Text:string);
begin Inc(Checks);if not B then raise Exception.Create(Text);end;
procedure Pump;
begin Application.ProcessMessages;Main.TestDrainGuiEvents(True);Sleep(5);end;
procedure ShowTree;
var I:Integer;
begin
 for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TMenuItem then
  if TMenuItem(Main.Components[I]).Caption='Show game tree' then begin TMenuItem(Main.Components[I]).Click;Exit;end;
 raise Exception.Create('Show game tree menu missing');
end;
procedure SelectNode(NodeId:Int64;out View:TTreeView;out Item:TMenuItem);
var F:TForm;I:Integer;
begin
 ShowTree;F:=TForm(Main.FindComponent('GameTreeWindow'));F.Show;Pump;View:=TTreeView(F.FindComponent('GameTreeNodes'));
 Item:=TMenuItem(F.FindComponent('DeleteFromHere'));Check(Item<>nil,'Deletion uses existing tree popup');
 for I:=0 to View.Items.Count-1 do if Int64(PtrUInt(View.Items[I].Data))=NodeId then begin
  View.Selected:=View.Items[I];View.OnClick(View);View.PopupMenu.OnPopup(View.PopupMenu);Exit;
 end;
 raise Exception.Create('Tree node not displayed');
end;
procedure DeleteCase(Game:TRunningGame);
var Tree:TGameTree;View:TTreeView;Item:TMenuItem;ParentId:Int64;I:Integer;
 History:TListBox;Late:TGameRunnerSnapshot;Obj:TObject;Saved:TList;
begin
 Tree:=Main.ActiveGameTree;Check(Tree.MainlineCount=4,'Four real moves before deletion');
 ParentId:=Tree.MainlineNode[2].NodeId;
 SelectNode(Tree.Root.NodeId,View,Item);Check(not Item.Enabled,'Root deletion disabled');
 SelectNode(Tree.MainlineNode[3].NodeId,View,Item);
 if Game<>nil then begin
  Check(not Item.Enabled,'Running game deletion disabled');
  Main.MarkGameStopped(Game,'test stop');
  while not Game.Runner.Finished do Sleep(5);
  // Retain an actual final snapshot to deliver again after the edit.
  Late:=nil;Saved:=TList.Create;
  try
   while Main.TestGuiEventQueue.TryPop(Obj) do begin
    Saved.Add(Obj);
    if (Obj is TRunnerSnapshotGuiMessage) and (TRunnerSnapshotGuiMessage(Obj).GameId=Game.Id) then begin
     if Late=nil then Late:=TGameRunnerSnapshot.Create;
     Late.AssignFrom(TRunnerSnapshotGuiMessage(Obj).Snapshot);
    end;
   end;
   for I:=0 to Saved.Count-1 do Main.TestGuiEventQueue.Post(TObject(Saved[I]));
  finally Saved.Free;end;
  Pump;Check(Game.Lifecycle=rglFinished,'Final snapshot/completion drained before edit');
  SelectNode(Tree.MainlineNode[3].NodeId,View,Item);
 end else Late:=nil;
 try
  Check(Item.Enabled,'Stopped or standalone tree is editable');
  GuiTestConfirmationResult:=mrCancel;try Item.Click;finally GuiTestConfirmationResult:=0;end;
  Check(Tree.MainlineCount=4,'Cancellation leaves all moves');
  GuiTestConfirmationResult:=mrYes;try Item.Click;finally GuiTestConfirmationResult:=0;end;
  Check(Tree.MainlineCount=2,'Delete includes selected move and descendants');
  Check(SelectedGameTreeNodeId(View)=ParentId,'Selection returns to retained parent');
  if Game<>nil then begin
   Check(Game.TreeEdited,'Finished game records intentional tree edit');
   Check(Late<>nil,'Actual runner snapshot retained for late delivery test');
   Main.TestGuiEventQueue.Post(TRunnerSnapshotGuiMessage.Create(Game.Id,Late));Late:=nil;Pump;
   Check(Tree.MainlineCount=2,'Late original snapshot cannot resurrect deleted moves');
  end;
  History:=TListBox(Main.FindComponent('GameHistoryList'));
  if Game<>nil then begin
   History.ItemIndex:=0;History.OnClick(History);Pump;
   History.ItemIndex:=History.Items.IndexOfObject(Game);History.OnClick(History);Pump;
   Check((Main.ActiveGameTree=Tree) and (Tree.MainlineCount=2),'History navigation preserves deletion');
  end;
 finally Late.Free;end;
end;
procedure Run(V:TGameVariant);
var Setup:TGameSetup;G:TRunningGame;P:TGamePosition;Memo:TMemo;I:Integer;Tick:QWord;
begin
 Main.SelectGameVariant(V);Main.LoadStandaloneFen(V.DefaultStartingFEN);Pump;
 Memo:=TMemo(Main.FindComponent('LegalMovesMemo'));
 for I:=1 to 4 do begin Memo.CaretPos:=Point(0,0);Memo.OnClick(Memo);Pump;end;
 DeleteCase(nil);
 Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.StartingFEN:=V.DefaultStartingFEN;
 Setup.WhitePlayer:=pkHuman;Setup.BlackPlayer:=pkHuman;Setup.TimeControl.MinutesPerPeriod:=5;
 G:=Main.StartGameFromSetup(Setup,'Delete test',True);P:=V.CreatePosition;
 try
  for I:=1 to 4 do begin
   G.Runner.PostHumanMove(P.LegalMove(0));P.PlayMove(P.LegalMove(0));Tick:=GetTickCount64;
   repeat Pump;until (G.GameTree.MainlineCount=I) or (GetTickCount64-Tick>5000);
   Check(G.GameTree.MainlineCount=I,'Runner human move reached existing game tree');
  end;
  DeleteCase(G);
 finally P.Free;end;
end;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));Main:=TMainForm.Create(nil);
 try Main.Show;Pump;Run(RegisteredGame(0));Run(RegisteredGame(1));
 finally GuiTestConfirmationResult:=0;Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
 WriteLn('Tree deletion GUI checks passed: ',Checks);
end.
