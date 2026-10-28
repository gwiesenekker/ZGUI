unit uGameFileReader;
{$mode objfpc}{$H+}
{ File-browser boundary. Entries own metadata, not a parallel move tree. }
interface
uses Classes, Contnrs, uGameTreeActor;
type
  TGameFileEntry = class
  public
    WhiteName, BlackName, EventName, ResultText, WarningsText, ErrorText: string;
    Deferred: Boolean;
    procedure Validate; virtual; abstract;
    procedure ImportInto(Actor: TGameTreeActor); virtual; abstract;
  end;
  TGameFileReader = class
  public
    Entries: TObjectList;
    constructor Create;
    destructor Destroy; override;
    procedure OpenFile(const FileName: string); virtual; abstract;
  end;
implementation
constructor TGameFileReader.Create;
begin inherited; Entries:=TObjectList.Create(True); end;
destructor TGameFileReader.Destroy;
begin Entries.Free; inherited; end;
end.
