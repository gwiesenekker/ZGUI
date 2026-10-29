program chess_database_worker_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uGameDatabase,uGameTreePdn,uDatabaseImportWorker;
var Db:TGameDatabase;Worker:TDatabaseImportWorker;State:TDatabaseImportState;
 FileName,Name:string;Text:TStringList;Games:TList;I:Integer;Tick:QWord;
procedure Check(B:Boolean;const S:string);
begin if not B then raise Exception.Create(S);end;
procedure Run(Cancel:Boolean;const Source:string);
begin
 Worker:=TDatabaseImportWorker.Create(Name,Source,gffPgn);
 try
  if Cancel then Worker.RequestCancel;Worker.Start;Tick:=GetTickCount64;
  repeat State:=Worker.Snapshot;
   Check(GetTickCount64-Tick<15000,'Chess worker finishes without GUI synchronization');
   if not State.Done then Sleep(5);
  until State.Done;
  Worker.WaitFor;Check(State.WorkerThreadId<>GetCurrentThreadID,'Worker owns database on its own thread');
 finally Worker.Free;end;
end;
begin
 FileName:=GetTempFileName(GetTempDir,'zworker');Name:=FileName+'.db';
 Db:=TGameDatabase.Create(gffPgn);Text:=TStringList.Create;Games:=TList.Create;
 try
  Db.CreateDatabase(Name);Db.Close;
  for I:=1 to 200 do Text.Add('[Event "Chess '+IntToStr(I)+'"] 1.e4 e5 *');Text.SaveToFile(FileName);
  Run(True,FileName);Check((State.Failure='') and (State.Imported=0),'Cancel at initial scanner progress writes nothing');
  Run(False,FileName);Check((State.Failure='') and (State.Imported=200),'Chess worker imports complete games');
  Db.OpenDatabase(Name);Db.LoadGames(Games);Check(Games.Count=200,'Worker completed rows visible on main connection');
  for I:=0 to Games.Count-1 do TObject(Games[I]).Free;Games.Clear;Db.Close;
  Run(False,FileName);Check((State.Failure='') and (State.Duplicates=200),'Worker duplicate import');
  Run(False,FileName+'.missing');Check(State.Failure<>'','Worker IO failure delivered as data');
  Db.OpenDatabase(Name);Db.LoadGames(Games);Check(Games.Count=200,'Failed import repairs indexes and preserves committed games');
 finally for I:=0 to Games.Count-1 do TObject(Games[I]).Free;Games.Free;Text.Free;Db.Free;
  DeleteFile(Name);DeleteFile(FileName);DeleteFile(ChangeFileExt(FileName,'.import.log'));
  DeleteFile(ChangeFileExt(FileName+'.missing','.import.log'));end;
 WriteLn('Chess database worker checks passed');
end.
