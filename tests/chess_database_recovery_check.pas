program chess_database_recovery_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,SQLite3Conn,SQLDB,
 uGameDatabase,uGameTreePdn,uChessPosition;
procedure Check(B:Boolean;const Text:string);
begin if not B then raise Exception.Create(Text);end;
procedure Raw(const Name,Sql:string);
var C:TSQLite3Connection;T:TSQLTransaction;
begin
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);
 try C.Transaction:=T;C.DatabaseName:=Name;C.Open;C.ExecuteDirect(Sql);T.Commit;C.Close;
 finally T.Free;C.Free;end;
end;
function Scalar(const Name,Sql:string):Integer;
var C:TSQLite3Connection;T:TSQLTransaction;Q:TSQLQuery;
begin
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);Q:=TSQLQuery.Create(nil);
 try C.Transaction:=T;C.DatabaseName:=Name;C.Open;Q.Database:=C;Q.Transaction:=T;Q.SQL.Text:=Sql;Q.Open;
  Result:=Q.Fields[0].AsInteger;Q.Close;T.Rollback;C.Close;
 finally Q.Free;T.Free;C.Free;end;
end;
type TCancel=class
 procedure Progress(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
end;
procedure TCancel.Progress(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
begin Cancel:=Imported>=1;end;
var Name,Pgn:string;Db:TGameDatabase;Text:TStringList;Games:TList;P:TChessPosition;
 Cancel:TCancel;I,D,E,J:Integer;Raised:Boolean;
procedure Clear;
var J:Integer;
begin for J:=0 to Games.Count-1 do TObject(Games[J]).Free;Games.Clear;end;
begin
 Pgn:=GetTempFileName(GetTempDir,'zrecover');Name:=Pgn+'.db';Db:=TGameDatabase.Create(gffPgn);
 Text:=TStringList.Create;Games:=TList.Create;P:=TChessPosition.Create;Cancel:=TCancel.Create;
 try
  Db.CreateDatabase(Name);Text.Text:='[Event "one"] 1.e4 e5 *';Text.SaveToFile(Pgn);
  Db.Close;Raw(Name,'create trigger fail_positions before insert on positions when new.ply=1 begin select raise(abort,''injected position failure''); end');Db.OpenDatabase(Name);
  Raised:=False;try Db.ImportFile(Pgn,I,D,E);except on X:ESQLDatabaseError do Raised:=True;end;
  Check(Raised,'SQL insert failure propagates');Db.LoadGames(Games);Check(Games.Count=0,'Failed game row rolled back');Clear;
  Check(Scalar(Name,'select count(*) from positions')=0,'No orphan positions after failure');
  Check(Scalar(Name,'select count(*) from sqlite_master where type=''index'' and name in (''idx_positions_search'',''idx_positions_game'')')=2,'Indexes available after recovery');
  Db.Close;Raw(Name,'drop trigger fail_positions');Db.OpenDatabase(Name);Db.ImportFile(Pgn,I,D,E);Check(I=1,'Import succeeds after failure removed');
  Db.Close;Raw(Name,'create trigger fail_summary before insert on continuations begin select raise(abort,''injected summary failure''); end');Db.OpenDatabase(Name);
  Text.Text:='[Event "two"] 1.d4 d5 *';Text.SaveToFile(Pgn);
  Raised:=False;try Db.ImportFile(Pgn,I,D,E);except on X:ESQLDatabaseError do Raised:=True;end;
  Check(Raised,'Summary failure propagates');Check(Scalar(Name,'select summary_dirty from database_state where id=1')=1,'Failed rebuild stays dirty');
  Db.SearchPosition(P,Games);Check(Games.Count=2,'Direct query remains usable after failed summary');Clear;
  Db.Close;Raw(Name,'drop trigger fail_summary');Db.OpenDatabase(Name);Db.RebuildContinuationSummary;
  Check(Scalar(Name,'select summary_dirty from database_state where id=1')=0,'Repair publishes clean summary');
  Db.Close;Db.OpenDatabase(Name);Db.SearchPosition(P,Games);Check(Games.Count=2,'Reopen sees repaired summary');Clear;
  Text.Clear;for J:=1 to 5000 do Text.Add('[Event "cancel '+IntToStr(J)+'"] 1.Nf3 Nf6 *');Text.SaveToFile(Pgn);
  Db.ImportFile(Pgn,I,D,E,@Cancel.Progress);Check((I>0) and (I<5000) and (E=0),'Cancel stops at completed games');
  Check(Scalar(Name,'select count(*) from positions')=(I+2)*3,'Cancelled batch has complete position rows');
  Check(Scalar(Name,'select count(*) from positions p left join games g on g.id=p.game_id where g.id is null')=0,'No cancelled orphan positions');
  Check(Scalar(Name,'select summary_dirty from database_state where id=1')=0,'Cancelled import rebuilds summary');
  WriteLn('Chess database recovery checks passed');
 finally Clear;Cancel.Free;P.Free;Games.Free;Text.Free;Db.Free;DeleteFile(Pgn);DeleteFile(Name);end;
end.
