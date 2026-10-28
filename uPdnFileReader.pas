unit uPdnFileReader;
{$mode objfpc}{$H+}
interface
uses uGameFileReader, uDraughtsPdn, uGameTreeActor;
type
  TPdnFileEntry = class(TGameFileEntry)
  public
    Game: TPdnGame;
    constructor Create(AGame: TPdnGame);
    destructor Destroy; override;
    procedure Validate; override;
    procedure ImportInto(Actor: TGameTreeActor); override;
  end;
  TPdnFileReader = class(TGameFileReader)
    procedure OpenFile(const FileName: string); override;
  end;
implementation
uses Classes, SysUtils;
constructor TPdnFileEntry.Create(AGame: TPdnGame);
begin
  inherited Create; Game:=AGame;
  WhiteName:=Game.WhiteName; BlackName:=Game.BlackName; EventName:=Game.EventName;
  ResultText:=Game.ResultText; WarningsText:=Game.ImportWarningsText; Deferred:=Game.Deferred;
end;
destructor TPdnFileEntry.Destroy;
begin Game.Free; inherited; end;
procedure TPdnFileEntry.Validate;
begin
  Game.ParseDeferredMoves; Game.ValidateMoveTree;
  WarningsText:=Game.ImportWarningsText; Deferred:=Game.Deferred;
end;
procedure TPdnFileEntry.ImportInto(Actor: TGameTreeActor);
begin
  // The legacy PDN selection callback retains its existing main-form import
  // path (including header/mainline rebuilding). No second importer here.
  raise EInvalidOperation.Create('PDN import uses the existing game selection callback');
end;
procedure TPdnFileReader.OpenFile(const FileName: string);
var Games: TList; I: Integer; Entry: TPdnFileEntry;
begin
  Entries.Clear; Games:=TList.Create;
  try
    LoadPdnGamesFromFile(FileName,Games,True);
    for I:=0 to Games.Count-1 do begin
      Entry:=TPdnFileEntry.Create(TPdnGame(Games[I])); Games[I]:=nil; Entries.Add(Entry);
    end;
  finally
    for I:=0 to Games.Count-1 do TObject(Games[I]).Free;
    Games.Free;
  end;
end;
end.
