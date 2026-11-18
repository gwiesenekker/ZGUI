unit uTournamentEngineQueue;

{$mode objfpc}{$H+}

interface

uses Classes, Contnrs;

type
  { Queue precedence supplements the existing live-engine reservations. It never
    takes a partial reservation or launches a game. One successful game ends a
    tournament's turn, so its remaining pairings rejoin behind existing waiters. }
  TTournamentEngineQueue = class
  private
    FRequests: TObjectList;
    FSequence: QWord;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginUpdate(AOwner: TObject);
    procedure Request(AOwner: TObject; ARow: Integer; AKeys: TStrings);
    procedure EndUpdate(AOwner: TObject);
    procedure RemoveOwner(AOwner: TObject);
    function BlockingOwner(AOwner: TObject; ARow: Integer; ABusyKeys:TStrings=nil): TObject;
    procedure GameStarted(AOwner:TObject;ARow:Integer;ABusyKeys:TStrings);
  end;

implementation

type
  TEngineRequest = class
    Owner: TObject;
    Row: Integer;
    Sequence: QWord;
    Seen,BackfillUsed: Boolean;
    Keys: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TEngineRequest.Create;
begin
  inherited Create;
  Keys := TStringList.Create;
end;

destructor TEngineRequest.Destroy;
begin
  Keys.Free;
  inherited Destroy;
end;

constructor TTournamentEngineQueue.Create;
begin
  inherited Create;
  FRequests := TObjectList.Create(True);
end;

destructor TTournamentEngineQueue.Destroy;
begin
  FRequests.Free;
  inherited Destroy;
end;

procedure TTournamentEngineQueue.BeginUpdate(AOwner: TObject);
var I: Integer;
begin
  for I := 0 to FRequests.Count - 1 do
    if TEngineRequest(FRequests[I]).Owner = AOwner then
      TEngineRequest(FRequests[I]).Seen := False;
end;

procedure TTournamentEngineQueue.Request(AOwner: TObject; ARow: Integer;
  AKeys: TStrings);
var I: Integer; R, Existing: TEngineRequest; Ticket: QWord;Used:Boolean;
begin
  Existing := nil;
  Ticket := 0;Used:=False;
  for I := 0 to FRequests.Count - 1 do begin
    R := TEngineRequest(FRequests[I]);
    if R.Owner <> AOwner then Continue;
    Ticket := R.Sequence;Used:=Used or R.BackfillUsed;
    if R.Row = ARow then Existing := R;
  end;
  if Existing = nil then begin
    if Ticket = 0 then begin Inc(FSequence); Ticket := FSequence; end;
    Existing := TEngineRequest.Create;
    Existing.Owner := AOwner;
    Existing.Row := ARow;
    Existing.Sequence := Ticket;Existing.BackfillUsed:=Used;
    FRequests.Add(Existing);
  end;
  Existing.Seen := True;
  Existing.Keys.Assign(AKeys);
end;

procedure TTournamentEngineQueue.EndUpdate(AOwner: TObject);
var I: Integer; R: TEngineRequest;
begin
  for I := FRequests.Count - 1 downto 0 do begin
    R := TEngineRequest(FRequests[I]);
    if (R.Owner = AOwner) and not R.Seen then FRequests.Delete(I);
  end;
end;

procedure TTournamentEngineQueue.RemoveOwner(AOwner: TObject);
var I: Integer;
begin
  for I := FRequests.Count - 1 downto 0 do
    if TEngineRequest(FRequests[I]).Owner = AOwner then FRequests.Delete(I);
end;

function HasBusyKey(Request:TEngineRequest;Busy:TStrings):Boolean;
var I:Integer;
begin
 Result:=False;if Busy=nil then Exit;
 for I:=0 to Request.Keys.Count-1 do if Busy.IndexOf(Request.Keys[I])>=0 then Exit(True);
end;

function SharesKeys(A,B:TEngineRequest):Boolean;
var I:Integer;
begin
 Result:=False;
 for I:=0 to A.Keys.Count-1 do if B.Keys.IndexOf(A.Keys[I])>=0 then Exit(True);
end;

function TTournamentEngineQueue.BlockingOwner(AOwner: TObject;
  ARow: Integer; ABusyKeys:TStrings): TObject;
var I: Integer; Candidate,R,Oldest: TEngineRequest;
begin
  Result := nil;
  Candidate := nil;
  for I := 0 to FRequests.Count - 1 do begin
    R := TEngineRequest(FRequests[I]);
    if (R.Owner = AOwner) and (R.Row = ARow) then Candidate := R;
  end;
  if Candidate = nil then Exit;
  Oldest := nil;
  for I := 0 to FRequests.Count - 1 do begin
    R := TEngineRequest(FRequests[I]);
    if (R.Owner = AOwner) or (R.Sequence >= Candidate.Sequence) then Continue;
    if not SharesKeys(Candidate,R) then Continue;
    // A blocked turn can lend its otherwise idle keys to one successful game.
    // Once spent, preserve precedence until this older turn actually starts.
    if HasBusyKey(R,ABusyKeys) and not R.BackfillUsed then Continue;
    if (Oldest=nil) or (R.Sequence<Oldest.Sequence) then Oldest:=R;
  end;
  if Oldest <> nil then Result := Oldest.Owner;
end;

procedure TTournamentEngineQueue.GameStarted(AOwner:TObject;ARow:Integer;ABusyKeys:TStrings);
var I,J:Integer;Candidate,R:TEngineRequest;
begin
 Candidate:=nil;
 for I:=0 to FRequests.Count-1 do begin
  R:=TEngineRequest(FRequests[I]);if (R.Owner=AOwner) and (R.Row=ARow) then Candidate:=R;
 end;
 if Candidate=nil then Exit;
 for I:=0 to FRequests.Count-1 do begin
  R:=TEngineRequest(FRequests[I]);
  if R.BackfillUsed or (R.Owner=AOwner) or (R.Sequence>=Candidate.Sequence) or
    not SharesKeys(Candidate,R) or not HasBusyKey(R,ABusyKeys) then Continue;
  for J:=0 to FRequests.Count-1 do
   if TEngineRequest(FRequests[J]).Sequence=R.Sequence then TEngineRequest(FRequests[J]).BackfillUsed:=True;
 end;
end;

end.
