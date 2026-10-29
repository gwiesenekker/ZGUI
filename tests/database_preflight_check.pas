program database_preflight_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,Process,SQLite3Conn,SQLDB,uGameDatabase;
procedure Check(B:Boolean;const S:string);
begin if not B then raise Exception.Create(S);end;
function Bytes(const Name:string):string;
var F:TFileStream;
begin F:=TFileStream.Create(Name,fmOpenRead);try SetLength(Result,F.Size);if F.Size>0 then F.ReadBuffer(Result[1],F.Size);finally F.Free;end;end;
procedure CrashWrite(const Name:string);
var C:TSQLite3Connection;T:TSQLTransaction;I:Integer;
begin
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);
 C.DatabaseName:=Name;C.Transaction:=T;C.Open;
 C.ExecuteDirect('pragma cache_size=5');
 for I:=1 to 3000 do
  C.ExecuteDirect('insert into games(game_hash_lo,game_hash_hi,white,black,event,result,moves_text) values ('+
   IntToStr(I)+','+IntToStr(I)+','''+StringOfChar('w',200)+''','''+
   StringOfChar('b',200)+''',''crash test'',''2-0'','''+StringOfChar('x',500)+''')');
 // Exit without freeing the connection or committing/rolling back its transaction.
 Halt(0);
end;
var Base,Good,Foreign,Before,Journal:string;Db:TGameDatabase;C:TSQLite3Connection;
 T:TSQLTransaction;Q:TSQLQuery;Child:TProcess;Raised:Boolean;
begin
 if ParamStr(1)='--crash-write' then begin CrashWrite(ParamStr(2));Halt(0);end;
 Base:=GetTempFileName(GetTempDir,'dbpreflight');DeleteFile(Base);Good:=Base+'.good';Foreign:=Base+'.foreign';
 Db:=TGameDatabase.Create;C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);
 try
  Db.CreateDatabase(Good);
  C.DatabaseName:=Foreign;C.Transaction:=T;C.Open;
  C.ExecuteDirect('create table notes(message text)');C.ExecuteDirect('insert into notes values(''keep me'')');
  T.Commit;C.Close;Before:=Bytes(Foreign);Raised:=False;
  try Db.OpenDatabase(Foreign);except on E:EInvalidOperation do Raised:=True;end;
  Check(Raised,'Foreign SQLite must be rejected');
  Check(Bytes(Foreign)=Before,'Rejected foreign file bytes unchanged');
  Check(Db.FileName=Good,'Rejected open keeps current database');
  Db.RebuildContinuationSummary;Db.Close;Db.OpenDatabase(Good);
  Check(Db.FileName=Good,'Known database remains usable');
  Db.Close;
  Child:=TProcess.Create(nil);
  try
   Child.Executable:=ExpandFileName(ParamStr(0));
   Child.Parameters.Add('--crash-write');Child.Parameters.Add(Good);
   Child.Options:=[poWaitOnExit];Child.Execute;
   Check(Child.ExitStatus=0,'Interrupted writer child succeeds');
  finally Child.Free;end;
  Check(FileExists(Good+'-journal'),'Interrupted write leaves rollback journal');
  Journal:=Bytes(Good+'-journal');
  Check((Length(Journal)>512) and (Copy(Journal,1,8)=#$D9#$D5#$05#$F9#$20#$A1#$63#$D7),
   'Journal has hot header and saved pages');
  Db.OpenDatabase(Good);
  Check(Db.FileName=Good,'Hot-journal database opens and recovers');
  Db.RebuildContinuationSummary;Db.Close;
  C.DatabaseName:=Good;C.Open;Q:=TSQLQuery.Create(nil);
  try
   Q.Database:=C;Q.Transaction:=T;Q.SQL.Text:='select count(*) from games';Q.Open;
   Check(Q.Fields[0].AsInteger=0,'Recovery removes all uncommitted games');
   Q.Close;T.Rollback;
  finally Q.Free;C.Close;end;
  Db.OpenDatabase(Good);Db.RebuildContinuationSummary;
  WriteLn('Database preflight checks passed');
 finally Db.Free;T.Free;C.Free;DeleteFile(Good);DeleteFile(Good+'-journal');DeleteFile(Foreign);end;
end.
