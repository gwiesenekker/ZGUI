program game_tree_delete_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Classes,SysUtils,uGamePosition,uChessPosition,uDraughtsPosition,uGameTree,
 uGameTreeActor,uGameTreeSearchRef,uGameTreePdn,uGameFileReader,uChessPgn,uPdnFileReader,uDraughtsPdn;
var Checks:Integer;
procedure Check(B:Boolean;const Text:string);
begin Inc(Checks);if not B then raise Exception.Create(Text);end;
procedure Run(V:TGameVariant);
var Actor:TGameTreeActor;P:TGamePosition;C,Stale:TGameTreeCommand;Ids:array[1..4] of Int64;
 Sibling,Branch,Leaf,Revision:Int64;Search:TGameTreeSearchRef;State:TGameTreeSearchState;I:Integer;
 Parsed:TPdnMoveNode;Options:TGameTreePdnRenderOptions;Reader:TGameFileReader;Imported:TGameTreeActor;Lines:TStringList;Name:string;
 procedure Apply;
 begin Actor.ExecuteCommand(C);Check(C.Accepted,'Command accepted: '+C.ErrorText);end;
begin
 Actor:=TGameTreeActor.Create(TGameTree.Create(V),True);P:=V.CreatePosition;
 try
  Actor.GameTree.SetHeader('Event','White','Black','*',V.DefaultStartingFEN);
  for I:=1 to 4 do begin
   C:=Actor.CreateAppendMainlineMoveCommand(P.LegalMove(0),gmsHuman);
   try Apply;Ids[I]:=C.CreatedNodeId;P.PlayMove(C.MoveText);finally C.Free;end;
  end;
  Actor.GameTree.RecordMainlineAnnotation(1,'prefix comment');Actor.GameTree.RecordClockState(1,10,20,1,2);
  P.LoadFromFEN(V.DefaultStartingFEN);
  C:=Actor.CreateImportNodeCommand(Actor.GameTree.Root.NodeId,P.LegalMove(1),'root sibling');
  try Apply;Sibling:=C.CreatedNodeId;finally C.Free;end;
  P.PlayMove(Actor.GameTree.MainlineNode[1].MoveText);
  C:=Actor.CreateImportNodeCommand(Ids[1],P.LegalMove(1),'nested branch');
  try Apply;Branch:=C.CreatedNodeId;P.PlayMove(Actor.GameTree.FindNodeById(Branch).MoveText);finally C.Free;end;
  C:=Actor.CreateImportNodeCommand(Branch,P.LegalMove(0),'branch leaf');
  try Apply;Leaf:=C.CreatedNodeId;finally C.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Branch);
  try Apply;Check(C.CreatedNodeId=Ids[1],'Nested branch selects retained parent');finally C.Free;end;
  Check((Actor.GameTree.FindNodeById(Branch)=nil) and (Actor.GameTree.FindNodeById(Leaf)=nil),'Variation subtree removed');
  Check((Actor.GameTree.MainlineCount=4) and (Actor.GameTree.FindNodeById(Sibling)<>nil),'Other mainline/sibling nodes preserved');
  Stale:=Actor.CreateDeleteFromHereCommand(Ids[2]);
  C:=Actor.CreateRecordEnginePVCommand(Ids[1],'0.3',Actor.GameTree.MainlineNode[2].MoveText,'8','0.1');
  try Apply;finally C.Free;end;
  Revision:=Actor.Revision;try Actor.ExecuteCommand(Stale);Check(not Stale.Accepted,'Stale revision rejected');Check(Actor.Revision=Revision,'Rejected deletion does not mark changed');finally Stale.Free;end;
  C:=Actor.CreateStartSearchCommand(Ids[4],Search);try Apply;finally C.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Ids[3]);
  try Apply;Check(C.CreatedNodeId=Ids[2],'Mainline deletion selects parent');finally C.Free;end;
  Check(Actor.GameTree.MainlineCount=2,'Mainline suffix removed inclusively');
  Check((Actor.GameTree.FindNodeById(Ids[3])=nil) and (Actor.GameTree.FindNodeById(Ids[4])=nil),'Removed IDs invalidated');
  Check((Actor.GameTree.MainlineNode[1].NodeId=Ids[1]) and (Actor.GameTree.FindNodeById(Sibling)<>nil),'Survivor IDs and root sibling retained');
  Check((Actor.GameTree.MainlineNode[1].CommentText='prefix comment') and (Actor.GameTree.MainlineNode[1].WhiteRemainingSeconds=10),'Prefix comments/clocks retained');
  Check(Actor.GameTree.MainlineNode[1].EngineScore='0.3','Prefix evaluation retained');
  Check(Actor.SearchState(Search,State) and (State=gssFailed),'Searches targeting removed nodes invalidated');
  C:=Actor.CreateSearchDoneCommand(Search,'');try Actor.ExecuteCommand(C);Check(not C.Accepted,'Late removed-target search rejected');finally C.Free;end;
  Options:=DefaultGameTreePdnRenderOptions;
  if V is TChessVariant then begin Options.FileFormat:=gffPgn;Options.LosslessPgn:=True;Reader:=TChessPgnReader.Create(V);end
  else Reader:=TPdnFileReader.Create;
  Imported:=TGameTreeActor.Create(TGameTree.Create(V),True);Lines:=TStringList.Create;Name:=GetTempFileName(GetTempDir,'deleted');
  try
   Lines.Text:=GameTreeToPdnTextEx(Actor.GameTree,Options);Lines.SaveToFile(Name);Reader.OpenFile(Name);
   Check(Reader.Entries.Count=1,'Edited tree exports as one PGN/PDN game');
   TGameFileEntry(Reader.Entries[0]).Validate;
   if V is TChessVariant then begin
    TGameFileEntry(Reader.Entries[0]).ImportInto(Imported);
    Check(Imported.GameTree.MainlineCount=2,'PGN save/reload preserves truncated mainline');
    Check(Imported.GameTree.BranchCount=Actor.GameTree.BranchCount,'PGN save/reload preserves retained sibling');
    Check(Imported.GameTree.MainlineNode[1].CommentText='prefix comment','PGN save/reload preserves prefix comment');
   end else begin
    // PDN retains its legacy selection/import boundary; inspect its validated parse.
    Parsed:=TPdnFileEntry(Reader.Entries[0]).Game.BuildMoveTree;
    try
     Check((Parsed.Children[0].ChildCount=1) and (Parsed.Children[0].Children[0].ChildCount=0),'PDN save/reload preserves truncated mainline');
     Check(Parsed.ChildCount=2,'PDN save/reload preserves retained sibling');
     Check(Pos('prefix comment',Parsed.Children[0].AnnotationText)>0,'PDN save/reload preserves prefix comment');
    finally Parsed.Free;end;
   end;
  finally DeleteFile(Name);Lines.Free;Imported.Free;Reader.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Actor.GameTree.Root.NodeId);
  try Actor.ExecuteCommand(C);Check(not C.Accepted,'Root cannot be deleted');finally C.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Ids[3]);try Actor.ExecuteCommand(C);Check(not C.Accepted,'Missing target rejected');finally C.Free;end;
  P.LoadFromFEN(V.DefaultStartingFEN);for I:=1 to 2 do P.PlayMove(Actor.GameTree.MainlineNode[I].MoveText);
  C:=Actor.CreateAppendMainlineMoveCommand(P.LegalMove(1),gmsHuman);try Apply;Check(Actor.GameTree.MainlineCount=3,'Append after deletion uses surviving position');finally C.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Actor.GameTree.MainlineNode[3].NodeId);
  try Apply;Check(Actor.GameTree.MainlineCount=2,'Tip deletion removes only the final move');finally C.Free;end;
  C:=Actor.CreateDeleteFromHereCommand(Ids[1]);
  try Apply;Check(C.CreatedNodeId=Actor.GameTree.Root.NodeId,'First-move deletion selects root');finally C.Free;end;
  Check((Actor.GameTree.MainlineCount=0) and (Actor.GameTree.FindNodeById(Sibling)<>nil),'First-move deletion preserves root siblings without promotion');

 finally P.Free;Actor.Free;end;
end;
var Chess,Draughts:TGameVariant;
begin Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 try Run(Chess);Run(Draughts);finally Chess.Free;Draughts.Free;end;
 WriteLn('Tree deletion checks passed: ',Checks);
end.
