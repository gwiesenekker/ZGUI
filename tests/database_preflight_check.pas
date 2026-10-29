program database_preflight_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,SQLite3Conn,SQLDB,uGameDatabase;
procedure Check(B:Boolean;const S:string);
begin if not B then raise Exception.Create(S);end;
function Bytes(const Name:string):string;
var F:TFileStream;
begin F:=TFileStream.Create(Name,fmOpenRead);try SetLength(Result,F.Size);if F.Size>0 then F.ReadBuffer(Result[1],F.Size);finally F.Free;end;end;
var Base,Good,Foreign,Before:string;Db:TGameDatabase;C:TSQLite3Connection;
 T:TSQLTransaction;Raised:Boolean;
begin
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
  WriteLn('Database preflight checks passed');
 finally Db.Free;T.Free;C.Free;DeleteFile(Good);DeleteFile(Foreign);end;
end.
