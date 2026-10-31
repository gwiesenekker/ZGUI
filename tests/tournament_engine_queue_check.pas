program tournament_engine_queue_check;
{$mode objfpc}{$H+}
uses Classes, SysUtils, uTournamentEngineQueue;
var Q: TTournamentEngineQueue; A,B,C: TObject; Keys: TStringList; Checks: Integer;
procedure Check(Value: Boolean; const Msg: string);
begin Inc(Checks); if not Value then raise Exception.Create(Msg); end;
procedure Request(Owner: TObject; Row: Integer; const First,Second: string);
begin Keys.Clear; Keys.Add(First); Keys.Add(Second); Q.Request(Owner,Row,Keys); end;
begin
  Q:=TTournamentEngineQueue.Create; Keys:=TStringList.Create;
  A:=TObject.Create;B:=TObject.Create;C:=TObject.Create;
  try
    Request(A,1,'engine1','engine2');
    Request(B,1,'engine2','engine3');
    Request(C,1,'engine4','engine5');
    Check(Q.BlockingOwner(A,1)=nil,'Oldest contender can start');
    Check(Q.BlockingOwner(B,1)=A,'Older waiter wins shared-engine conflict');
    Check(Q.BlockingOwner(C,1)=nil,'Unrelated engines continue');
    Q.BeginUpdate(A);Request(A,1,'engine1','engine2');Q.EndUpdate(A);
    Check(Q.BlockingOwner(B,1)=A,'Timer refresh preserves waiting age');
    Q.RemoveOwner(A);
    Request(A,2,'engine1','engine2');
    Check(Q.BlockingOwner(A,2)=B,'Next game rejoins behind the existing waiter');
    Check(Q.BlockingOwner(B,1)=nil,'Reversed timer order cannot bypass the oldest waiter');
    Q.RemoveOwner(B);
    Check(Q.BlockingOwner(A,2)=nil,'Stopped/closed owner immediately releases precedence');
    Request(B,1,'engine2','engine3');
    Q.BeginUpdate(A);Q.EndUpdate(A);
    Check(Q.BlockingOwner(B,1)=nil,'No eligible pairing leaves no stale request');
    Q.RemoveOwner(B);Q.RemoveOwner(C);
    Request(A,1,'chess1','chess2');Request(A,2,'hub1','hub2');
    Request(B,1,'hub2','dxp-endpoint');
    Check(Q.BlockingOwner(B,1)=A,'All candidate pairs share the older tournament turn');
    Q.BeginUpdate(A);Request(A,1,'chess1','chess2');Q.EndUpdate(A);
    Check(Q.BlockingOwner(B,1)=nil,'Invalidated candidate releases its engine keys');
    Request(C,1,'dxp-endpoint','hub3');
    Check(Q.BlockingOwner(C,1)=B,'Endpoint aliases take part in precedence');
    Q.RemoveOwner(A);Q.RemoveOwner(B);Q.RemoveOwner(C);
    Request(C,1,'e1','e2');Request(B,1,'e2','e3');Request(A,1,'e3','e4');
    Check(Q.BlockingOwner(A,1)=B,'Oldest conflicting waiter protects its complete pair');
    Check(Q.BlockingOwner(B,1)=C,'Precedence chain has decreasing age, no deadlock cycle');
    Q.RemoveOwner(C);Q.RemoveOwner(B);
    Check(Q.BlockingOwner(A,1)=nil,'Precedence chain drains in order');
    WriteLn('Tournament engine queue checks passed (',Checks,' checks)');
  finally Q.Free;Keys.Free;A.Free;B.Free;C.Free;end;
end.
