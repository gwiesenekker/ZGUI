unit uGameDatabase;

{$mode objfpc}{$H+}

interface

uses
  Classes, SQLite3Conn, SQLDB, SysUtils, uDraughtsBoard, uDraughtsPdn, uGamePosition, uGameTreePdn, uGameFileReader;

type
  TDatabaseGameSortColumn = (dgscId, dgscWhite, dgscBlack, dgscEvent);

  TDatabaseGameInfo = class
  public
    Id: Integer;
    WhiteName: string;
    BlackName: string;
    EventName: string;
    ResultText: string;
    StartingFEN: string;
    PlyCount: Integer;
  end;

  TDatabaseSearchResult = class
  public
    MoveText: string;
    GameCount: Integer;
    Wins: Integer;
    Draws: Integer;
    Losses: Integer;
  end;

  TDatabaseImportProgressEvent = procedure(ABytesRead, ATotalBytes: Int64;
    AImported, ADuplicates, AErrors: Integer; var ACancel: Boolean) of object;

  TGameDatabase = class
  private
    FFormat: TGameFileFormat;
    FVariant: TGameVariant;
    FWhiteWin, FDraw, FBlackWin: string;
    FConnection: TSQLite3Connection;
    FFileName: string;
    FTransaction: TSQLTransaction;
    procedure BindPositionKey(AQuery:TSQLQuery;const APositionKey:string);
    procedure CheckPosition(Position:TGamePosition);
    function GamesForPositionByKey(const APositionKey:string;ASideToMove:TGameSide;ALimit:Integer;out AProbeCount:Integer):Boolean;
    procedure LoadGamesForPositionByKey(const APositionKey:string;ASideToMove:TGameSide;AList:TList;ALimit:Integer;out ATotalMatches:Integer);
    procedure SearchPositionByKey(const APositionKey:string;ASideToMove:TGameSide;AList:TList);
    procedure InitializeDatabase(const AFileName: string);
    procedure PreflightDatabase(const AFileName:string);
    procedure ClearObjectList(AList: TList);
    procedure CommitActiveTransaction;
    function ContinuationSummaryAvailable: Boolean;
    procedure CreateImportIndexes;
    procedure EnsureContinuationTable;
    procedure EnsureContinuationState;
    procedure EnsureGameHashColumns;
    procedure ExecuteSql(const ASql: string);
    procedure SetBulkImportPragmas;
    procedure StartTransactionIfNeeded;
    function TableColumnExists(const ATableName, AColumnName: string): Boolean;
    function Query: TSQLQuery;
  public
    constructor Create(AFormat:TGameFileFormat = gffPdn);
    destructor Destroy; override;

    procedure Close;
    procedure CreateDatabase(const AFileName: string);
    procedure OpenDatabase(const AFileName: string);
    procedure ImportPdnFile(const AFileName: string; out AImported,
      ADuplicates, AErrors: Integer;
      AOnProgress: TDatabaseImportProgressEvent = nil;
      const AImportLogFileName: string = '');
    procedure ImportFile(const AFileName:string;out AImported,ADuplicates,AErrors:Integer;
      AOnProgress:TDatabaseImportProgressEvent=nil;const AImportLogFileName:string='');
    // Caller owns the entry; keep this database alive during validation/import.
    function LoadFileGameById(AGameId:Integer):TGameFileEntry;
    function GamesForPositionExceedLimit(Position:TGamePosition;Limit:Integer;out Count:Integer):Boolean; overload;
    procedure LoadGamesForPosition(Position:TGamePosition;List:TList;Limit:Integer;out Count:Integer); overload;
    procedure SearchPosition(Position:TGamePosition;List:TList); overload;
    procedure LoadGames(AList: TList; ALimit: Integer;
      const AWhiteFilter, ABlackFilter, AEventFilter, APlayerFilter: string;
      ASortColumn: TDatabaseGameSortColumn; ASortDescending: Boolean;
      out ATotalMatches: Integer);
    procedure LoadGames(AList: TList);
    function LoadGameById(AGameId: Integer): TPdnGame;
    function GamesForPositionExceedLimit(const APositionKey: string;
      ASideToMove: TDraughtsSide; ALimit: Integer; out AProbeCount: Integer): Boolean; overload;
    procedure LoadGamesForPosition(const APositionKey: string;
      ASideToMove: TDraughtsSide; AList: TList; ALimit: Integer;
      out ATotalMatches: Integer); overload;
    procedure RebuildContinuationSummary;
    procedure SearchPosition(const APositionKey: string; ASideToMove: TDraughtsSide;
      AList: TList); overload;

    property FileFormat:TGameFileFormat read FFormat;
    property FileName: string read FFileName;
  end;

implementation

uses SQLite3Dyn, ctypes, UnicodeData, ZStream, Base64, DB, uChessPosition,
  uChessPgn, uChessPgnLexer, uGameFileMetadata, uDraughtsPosition;

function PackStoredPdn(const Text: string): string;
var Buffer: TStringStream; Compressor: TCompressionStream;
begin
  Buffer := TStringStream.Create('');
  try
    Compressor := TCompressionStream.Create(clDefault, Buffer);
    try
      if Text <> '' then Compressor.WriteBuffer(Text[1], Length(Text));
    finally Compressor.Free; end;
    Result := 'gwd-zlib1:' + EncodeStringBase64(Buffer.DataString);
    if Length(Result) >= Length(Text) then Result := Text;
  finally Buffer.Free; end;
end;

function UnpackStoredPdn(const Text: string): string;
var Buffer, Output: TStringStream; Decompressor: TDecompressionStream;
begin
  Result := Text;
  if Copy(Text, 1, 10) <> 'gwd-zlib1:' then Exit;
  Buffer := TStringStream.Create(DecodeStringBase64(Copy(Text, 11, MaxInt)));
  Output := TStringStream.Create('');
  try
    Decompressor := TDecompressionStream.Create(Buffer);
    try Output.CopyFrom(Decompressor, 0); finally Decompressor.Free; end;
    Result := Output.DataString;
  finally Output.Free; Buffer.Free; end;
end;

function FoldUtf8(const Text: string): string;
var Lowered: UnicodeString;
begin
  UnicodeToLower(UTF8Decode(Text), True, Lowered);
  Result := UTF8Encode(Lowered);
end;

procedure SqlUnicodeLower(Context: psqlite3_context; Count: cint;
  Values: ppsqlite3_value); cdecl;
var Text: string;
begin
  try
    Text := FoldUtf8(StrPas(sqlite3_value_text(Values^)));
    sqlite3_result_text(Context, PChar(Text), Length(Text), sqlite3_destructor_type(SQLITE_TRANSIENT));
  except
    sqlite3_result_error(Context, 'Unicode name conversion failed', -1);
  end;
end;

type
  THash128 = record
    Lo: Int64;
    Hi: Int64;
  end;

  TDatabasePdnImporter = class
  private
    FBoard: TDraughtsBoard;
    FDatabase: TGameDatabase;
    FDuplicates: Integer;
    FErrors: Integer;
    FGame: TPdnGame;
    FGameId: Integer;
    FFullPdn: string;
    FRecordNumber: Integer;
    FRecordEnd, FSourceBytes: Int64;
    FWhite,FBlack,FEvent,FResult,FStartingFen,FAnnotations:string;
    FDate,FEco:string;FWhiteElo,FBlackElo:Integer;
    FKeys:TStringList;FStartingSide:TGameSide;
    FGameInsertQuery: TSQLQuery;
    FHashQuery: TSQLQuery;
    FIdQuery: TSQLQuery;
    FImported: Integer;
    FLastProgressTick: QWord;
    FLogFile: TextFile;
    FLogFileName: string;
    FLogOpen: Boolean;
    FMoves: TStringList;
    FOnProgress: TDatabaseImportProgressEvent;
    FPositionInsertQuery: TSQLQuery;
    procedure StoreGame(const Hash:THash128);
    procedure ImportPgnGame(const Text,ErrorText:string;BytesRead,TotalBytes:Int64;var Cancel:Boolean);
    procedure ScanProgress(BytesRead,TotalBytes:Int64;var Cancel:Boolean);
    procedure CanonicalizeMovesForImport;
    procedure CommitBatchIfNeeded;
    function GameHash: THash128;
    procedure ImportGame(AGame: TPdnGame; ABytesRead, ATotalBytes: Int64;
      var AStop: Boolean);
    function IsDuplicateGame(const AGameHash: THash128): Boolean;
    function IsLegacyDuplicate: Boolean;
    procedure InsertPosition(APly: Integer; const ANextMove: string);
    procedure LogDuplicate(const AGameHash: THash128);
    procedure LogError(const AMessage: string);
    procedure LogLine(const ALine: string);
    function PgnRecordContext: string;
    procedure ReportProgress(ABytesRead, ATotalBytes: Int64;
      var ACancel: Boolean);
  public
    constructor Create(ADatabase: TGameDatabase;
      AOnProgress: TDatabaseImportProgressEvent;
      const AImportLogFileName: string);
    destructor Destroy; override;
    procedure Run(const AFileName: string);
    property Duplicates: Integer read FDuplicates;
    property Errors: Integer read FErrors;
    property Imported: Integer read FImported;
  end;

function SideToText(ASide: TDraughtsSide): string;
begin
  if ASide = dsBlack then
    Result := 'B'
  else
    Result := 'W';
end;

function GameSideToText(Side:TGameSide):string;
begin if Side=gsBlack then Result:='B' else Result:='W';end;
function MoveCountText(const AMovesText: string): Integer;
var
  LMoves: TStringList;
begin
  LMoves := TStringList.Create;
  try
    ExtractStrings([' ', #9, #10, #13], [], PChar(Trim(AMovesText)), LMoves);
    Result := LMoves.Count;
  finally
    LMoves.Free;
  end;
end;

function LogField(const AText: string): string;
begin
  Result := StringReplace(AText, #9, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

function QWordAsInt64(AValue: QWord): Int64;
begin
  Result := 0;
  Move(AValue, Result, SizeOf(Result));
end;

function QWordLo32(AValue: QWord): QWord;
begin
  Result := AValue and QWord($FFFFFFFF);
end;

function QWordHi32(AValue: QWord): QWord;
begin
  Result := AValue shr 32;
end;

procedure Add128(var ALo, AHi: QWord; BLo, BHi: QWord);
var
  OldLo: QWord;
begin
  OldLo := ALo;
  ALo := ALo + BLo;
  AHi := AHi + BHi;
  if ALo < OldLo then
    Inc(AHi);
end;

procedure Mul128ByFNVPrime(var ALo, AHi: QWord);
var
  Carry: QWord;
  L0: QWord;
  L1: QWord;
  L2: QWord;
  L3: QWord;
  OldLo: QWord;
  Product: QWord;
  ShiftHi: QWord;
begin
  { FNV-1a-128 prime = 2^88 + 0x13B.  Modulo 2^128:
    hash * prime = (hash << 88) + (hash * 0x13B). }
  OldLo := ALo;

  Product := QWordLo32(ALo) * QWord($13B);
  L0 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordHi32(ALo) * QWord($13B) + Carry;
  L1 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordLo32(AHi) * QWord($13B) + Carry;
  L2 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordHi32(AHi) * QWord($13B) + Carry;
  L3 := QWordLo32(Product);

  ALo := L0 or (L1 shl 32);
  AHi := L2 or (L3 shl 32);
  ShiftHi := OldLo shl 24;
  Add128(ALo, AHi, 0, ShiftHi);
end;

function Fnv1a128Value(const AText: string): THash128;
var
  HashHi: QWord;
  HashLo: QWord;
  I: Integer;
begin
  HashHi := (QWord($6C62272E) shl 32) or QWord($07BB0142);
  HashLo := (QWord($62B82175) shl 32) or QWord($6295C58D);
  for I := 1 to Length(AText) do
  begin
    HashLo := HashLo xor Ord(AText[I]);
    Mul128ByFNVPrime(HashLo, HashHi);
  end;
  Result.Lo := QWordAsInt64(HashLo);
  Result.Hi := QWordAsInt64(HashHi);
end;

function PositionStateDigit(AState: Char): QWord;
begin
  case AState of
    'e':
      Result := 0;
    'w':
      Result := 1;
    'b':
      Result := 2;
    'W':
      Result := 3;
    'B':
      Result := 4;
  else
    raise EConvertError.CreateFmt('Invalid position key square state: %s',
      [AState]);
  end;
end;

procedure Mul128By5Add(var ALo, AHi: QWord; ADigit: QWord);
var
  Carry: QWord;
  L0: QWord;
  L1: QWord;
  L2: QWord;
  L3: QWord;
  Product: QWord;
begin
  Product := QWordLo32(ALo) * 5 + ADigit;
  L0 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordHi32(ALo) * 5 + Carry;
  L1 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordLo32(AHi) * 5 + Carry;
  L2 := QWordLo32(Product);
  Carry := QWordHi32(Product);

  Product := QWordHi32(AHi) * 5 + Carry;
  L3 := QWordLo32(Product);

  ALo := L0 or (L1 shl 32);
  AHi := L2 or (L3 shl 32);
end;

function PackedPositionKey128Value(const APositionKey: string): THash128;
var
  KeyHi: QWord;
  KeyLo: QWord;
  I: Integer;
  SquareOffset: Integer;
begin
  if (Length(APositionKey) = 52) and (APositionKey[2] = '|') then
    SquareOffset := 2
  else if Length(APositionKey) = 51 then
    SquareOffset := 1
  else
    raise EConvertError.CreateFmt('Invalid position key length: %d',
      [Length(APositionKey)]);

  if APositionKey[1] = 'B' then
    KeyLo := 1
  else if APositionKey[1] = 'W' then
    KeyLo := 0
  else
    raise EConvertError.CreateFmt('Invalid position key side to move: %s',
      [APositionKey[1]]);
  KeyHi := 0;

  for I := SquareOffset + 1 to Length(APositionKey) do
    Mul128By5Add(KeyLo, KeyHi, PositionStateDigit(APositionKey[I]));

  Result.Lo := QWordAsInt64(KeyLo);
  Result.Hi := QWordAsInt64(KeyHi);
end;

function Hash128ToHex(const AHash: THash128): string;
var
  HashHi: QWord;
  HashLo: QWord;
begin
  HashHi := 0;
  HashLo := 0;
  Move(AHash.Hi, HashHi, SizeOf(HashHi));
  Move(AHash.Lo, HashLo, SizeOf(HashLo));
  Result := IntToHex(HashHi, 16) + IntToHex(HashLo, 16);
end;

procedure TGameDatabase.BindPositionKey(AQuery: TSQLQuery; const APositionKey: string);
var
  PositionKey: THash128;
begin
  if FFormat=gffPgn then PositionKey:=Fnv1a128Value('chess-position-key-v1'#10+APositionKey)
  else PositionKey := PackedPositionKey128Value(APositionKey);
  AQuery.ParamByName('position_key_lo').AsLargeInt := PositionKey.Lo;
  AQuery.ParamByName('position_key_hi').AsLargeInt := PositionKey.Hi;
end;

constructor TDatabasePdnImporter.Create(ADatabase: TGameDatabase;
  AOnProgress: TDatabaseImportProgressEvent; const AImportLogFileName: string);
begin
  inherited Create;
  FDatabase := ADatabase;
  FOnProgress := AOnProgress;
  FLogFileName := AImportLogFileName;
  if Trim(FLogFileName) <> '' then
  begin
    AssignFile(FLogFile, FLogFileName);
    Rewrite(FLogFile);
    FLogOpen := True;
  end;
  FBoard := TDraughtsBoard.Create;
  FMoves := TStringList.Create; FKeys:=TStringList.Create;
  FGameInsertQuery := FDatabase.Query;
  FGameInsertQuery.SQL.Text :=
    'insert into games(game_hash_lo, game_hash_hi, white, black, event, result, starting_fen, moves_text, annotations_text, full_pdn, ply_count, hash_version) ' +
    'values(:game_hash_lo, :game_hash_hi, :white, :black, :event, :result, :starting_fen, :moves_text, :annotations_text,  :full_pdn, :ply_count, 6)';
  if FDatabase.FFormat=gffPgn then
    FGameInsertQuery.SQL.Text:=
      'insert into games(game_hash_lo,game_hash_hi,white,black,event,result,starting_fen,moves_text,annotations_text,full_pdn,ply_count,hash_version,date,eco,white_elo,black_elo) '+
      'values(:game_hash_lo,:game_hash_hi,:white,:black,:event,:result,:starting_fen,:moves_text,:annotations_text,:full_pdn,:ply_count,7,:date,:eco,:white_elo,:black_elo)';
  FHashQuery := FDatabase.Query;
  FHashQuery.SQL.Text :=
    'select id from games where game_hash_lo = :game_hash_lo and game_hash_hi = :game_hash_hi limit 1';
  if FDatabase.FFormat=gffPgn then FHashQuery.SQL.Text:=
    'select id, full_pdn from games where game_hash_lo = :game_hash_lo and game_hash_hi = :game_hash_hi limit 1';
  FPositionInsertQuery := FDatabase.Query;
  FPositionInsertQuery.SQL.Text :=
    'insert into positions(game_id, ply, position_key_lo, position_key_hi, side_to_move, next_move, result) ' +
    'values(:game_id, :ply, :position_key_lo, :position_key_hi, :side_to_move, :next_move, :result)';
  FIdQuery := FDatabase.Query;
  FIdQuery.SQL.Text := 'select last_insert_rowid() as id';
end;

destructor TDatabasePdnImporter.Destroy;
begin
  if FLogOpen then
  begin
    LogLine('finished' + #9 + 'imported=' + IntToStr(FImported) + #9 +
      'duplicates=' + IntToStr(FDuplicates) + #9 + 'errors=' +
      IntToStr(FErrors));
    CloseFile(FLogFile);
    FLogOpen := False;
  end;
  FIdQuery.Free;
  FPositionInsertQuery.Free;
  FHashQuery.Free;
  FGameInsertQuery.Free;
  FKeys.Free;FMoves.Free;
  FBoard.Free;
  inherited Destroy;
end;

procedure TDatabasePdnImporter.LogLine(const ALine: string);
begin
  if not FLogOpen then
    Exit;
  Writeln(FLogFile, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + #9 +
    ALine);
end;

procedure TDatabasePdnImporter.LogDuplicate(const AGameHash: THash128);
var
  LPlyCount: Integer;
begin
  if FDatabase.FFormat=gffPgn then begin
    LogLine('duplicate'+#9+'hash='+Hash128ToHex(AGameHash)+#9+'event='+LogField(FEvent)+#9+'white='+LogField(FWhite)+#9+'black='+LogField(FBlack)+PgnRecordContext);
    if FLogOpen then begin
      WriteLn(FLogFile,'----- DUPLICATE PGN -----');
      WriteLn(FLogFile,FFullPdn);
      WriteLn(FLogFile,'-------------------------');
    end;
    Exit;
  end;
  LPlyCount := MoveCountText(FGame.MovesText);
  if (LPlyCount = 0) and (FMoves <> nil) then
    LPlyCount := FMoves.Count;
  LogLine('duplicate' + #9 +
    'hash=' + LogField(Hash128ToHex(AGameHash)) + #9 +
    'event=' + LogField(FGame.EventName) + #9 +
    'white=' + LogField(FGame.WhiteName) + #9 +
    'black=' + LogField(FGame.BlackName) + #9 +
    'result=' + LogField(FGame.ResultText) + #9 +
    'fen=' + LogField(FGame.StartingFEN) + #9 +
    'plies=' + IntToStr(LPlyCount));
  if FLogOpen then
  begin
    Writeln(FLogFile, '----- DUPLICATE PDN -----');
    Writeln(FLogFile, PdnGameToText(FGame));
    Writeln(FLogFile, '-------------------------');
  end;
end;

function TDatabasePdnImporter.PgnRecordContext: string;
begin
  Result := '';
  if FDatabase.FFormat = gffPgn then
    Result := #9 + 'game=' + IntToStr(FRecordNumber) +
      #9 + 'byte_end=' + IntToStr(FRecordEnd) +
      #9 + 'source_bytes=' + IntToStr(FSourceBytes);
end;

procedure TDatabasePdnImporter.LogError(const AMessage: string);
begin
  LogLine('error' + #9 + LogField(AMessage) + PgnRecordContext);
  if FLogOpen then
  begin
    if FDatabase.FFormat=gffPgn then begin
      WriteLn(FLogFile, '----- PGN -----');
      WriteLn(FLogFile,FFullPdn);
    end else begin
      Writeln(FLogFile, '----- PDN -----');
      Writeln(FLogFile, PdnGameToText(FGame));
    end;
    Writeln(FLogFile, '---------------');
  end;
end;

procedure TDatabasePdnImporter.CanonicalizeMovesForImport;
var
  LLegalMove: string;
  LMove: string;
  Points: Integer;
begin
  FBoard.LoadFromFEN(FGame.StartingFEN);
  for Points := 0 to FMoves.Count - 1 do
  begin
    LMove := FMoves[Points];
    if not FBoard.TryGetLegalMove(LMove, LLegalMove) then
      raise EInvalidOperation.Create('Illegal move: ' + NormalizeMoveNotation(LMove) +
        LineEnding + 'Ply: ' + IntToStr(Points + 1) +
        LineEnding + 'Position: ' + FBoard.CurrentFEN +
        LineEnding + 'Legal moves:' + LineEnding + FBoard.LegalMovesText);
    FMoves[Points] := LLegalMove;
    FBoard.PlayMove(LLegalMove, False, False);
  end;

  // Keep the parsed tree intact; FMoves alone supplies canonical position rows.
end;

procedure TDatabasePdnImporter.CommitBatchIfNeeded;
begin
  if (FImported > 0) and ((FImported mod 10000) = 0) then
  begin
    FDatabase.CommitActiveTransaction;
    FDatabase.StartTransactionIfNeeded;
  end;
end;

function TDatabasePdnImporter.GameHash: THash128;
var
  LHashText: string;
begin
  if FDatabase.FFormat=gffPgn then
    LHashText:='zgui-db-v7-chess-complete-game-token-v1'#10+FFullPdn
  else LHashText := 'gwdgui-db-v6-complete-game' + #10 + FFullPdn;
  Result := Fnv1a128Value(LHashText);
end;

function TDatabasePdnImporter.IsDuplicateGame(const AGameHash: THash128): Boolean;
begin
  FHashQuery.Close;
  FHashQuery.ParamByName('game_hash_lo').AsLargeInt := AGameHash.Lo;
  FHashQuery.ParamByName('game_hash_hi').AsLargeInt := AGameHash.Hi;
  FHashQuery.Open;
  try
    Result := not FHashQuery.EOF;
    if Result and (FDatabase.FFormat=gffPgn) and
      (UnpackStoredPdn(FHashQuery.FieldByName('full_pdn').AsUTF8String)<>FFullPdn) then
      raise EConvertError.Create('Complete PGN game hash conflict');
  finally
    FHashQuery.Close;
  end;
end;

function TDatabasePdnImporter.IsLegacyDuplicate: Boolean;
var Q, Update: TSQLQuery; Games: TList; Candidate: TPdnGame;
  Canonical: string; I: Integer; Hash: THash128;
begin
  Result := False;
  Q := FDatabase.Query; Games := TList.Create; Canonical := '';
  try
    Q.SQL.Text := 'select * from games where hash_version < 6 and white=:white and black=:black and event=:event and result=:result and ply_count=:ply_count';
    Q.ParamByName('white').AsUTF8String := FGame.WhiteName;
    Q.ParamByName('black').AsUTF8String := FGame.BlackName;
    Q.ParamByName('event').AsUTF8String := FGame.EventName;
    Q.ParamByName('result').AsUTF8String := FGame.ResultText;
    Q.ParamByName('ply_count').AsInteger := FMoves.Count;
    Q.Open;
    while not Q.EOF do
    begin
      Candidate := nil;
      try
        if Q.FieldByName('full_pdn').AsUTF8String <> '' then
        begin
          LoadPdnGamesFromText(UnpackStoredPdn(Q.FieldByName('full_pdn').AsUTF8String), Games);
          if Games.Count <> 1 then raise EConvertError.Create('Invalid legacy stored game');
          Candidate := TPdnGame(Games[0]); Games.Clear;
        end
        else
        begin
          Candidate := TPdnGame.Create;
          Candidate.WhiteName := Q.FieldByName('white').AsUTF8String;
          Candidate.BlackName := Q.FieldByName('black').AsUTF8String;
          Candidate.EventName := Q.FieldByName('event').AsUTF8String;
          Candidate.ResultText := Q.FieldByName('result').AsUTF8String;
          Candidate.StartingFEN := Q.FieldByName('starting_fen').AsUTF8String;
          Candidate.MovesText := Q.FieldByName('moves_text').AsUTF8String;
          Candidate.MoveAnnotationsText := Q.FieldByName('annotations_text').AsUTF8String;
        end;
        // Only legacy candidates need a replay. Compare complete content, so an
        // old moves-only identity cannot discard newly supplied notes/branches.
        if Canonical = '' then Canonical := PdnGameToText(FGame);
        if PdnGameToText(Candidate) = Canonical then
        begin
          Hash := GameHash; Update := FDatabase.Query;
          try
            Update.SQL.Text := 'update games set game_hash_lo=:lo, game_hash_hi=:hi, hash_version=6, full_pdn=:pdn where id=:id';
            Update.ParamByName('lo').AsLargeInt := Hash.Lo;
            Update.ParamByName('hi').AsLargeInt := Hash.Hi;
            Update.ParamByName('pdn').AsUTF8String := PackStoredPdn(FFullPdn);
            Update.ParamByName('id').AsInteger := Q.FieldByName('id').AsInteger;
            Update.ExecSQL;
          finally Update.Free; end;
          Exit(True);
        end;
      finally Candidate.Free; end;
      Q.Next;
    end;
  finally
    for I := 0 to Games.Count - 1 do TObject(Games[I]).Free;
    Games.Free; Q.Free;
  end;
end;

procedure TDatabasePdnImporter.InsertPosition(APly: Integer;
  const ANextMove: string);
var
  PositionKey: THash128;
  SideText: string;
begin
  if FDatabase.FFormat=gffPgn then begin
    PositionKey:=Fnv1a128Value('chess-position-key-v1'#10+FKeys[APly]);
    if (FStartingSide=gsWhite)=(APly mod 2=0) then SideText:='W' else SideText:='B';
  end else begin
    PositionKey := PackedPositionKey128Value(FBoard.PositionKey);
    SideText := SideToText(FBoard.SideToMove);
  end;
  FPositionInsertQuery.ParamByName('game_id').AsInteger := FGameId;
  FPositionInsertQuery.ParamByName('ply').AsInteger := APly;
  FPositionInsertQuery.ParamByName('position_key_lo').AsLargeInt := PositionKey.Lo;
  FPositionInsertQuery.ParamByName('position_key_hi').AsLargeInt := PositionKey.Hi;
  FPositionInsertQuery.ParamByName('side_to_move').AsUTF8String := SideText;
  FPositionInsertQuery.ParamByName('next_move').AsUTF8String := ANextMove;
  FPositionInsertQuery.ParamByName('result').AsUTF8String := FResult;
  // SQLDB's implicit ExecSQL preparation is released after each execution.
  // Explicit preparation reuses this same statement until a batch commit.
  if FDatabase.FFormat=gffPgn then FPositionInsertQuery.Prepare;
  FPositionInsertQuery.ExecSQL;
end;

procedure TDatabasePdnImporter.ReportProgress(ABytesRead, ATotalBytes: Int64;
  var ACancel: Boolean);
begin
  if not Assigned(FOnProgress) then
    Exit;
  if (GetTickCount64 - FLastProgressTick < 250) and
    (ABytesRead < ATotalBytes) then
    Exit;
  FLastProgressTick := GetTickCount64;
  FOnProgress(ABytesRead, ATotalBytes, FImported, FDuplicates, FErrors,
    ACancel);
end;

procedure TDatabasePdnImporter.ImportGame(AGame: TPdnGame; ABytesRead,
  ATotalBytes: Int64; var AStop: Boolean);
var
  LGameHash: THash128;
  InitialWarnings, NewWarnings: string;
begin
  FGame := AGame;
  try
    InitialWarnings := FGame.ImportWarningsText;
    if Trim(FGame.ImportWarningsText) <> '' then
      LogLine('warning' + #9 + 'event=' + LogField(FGame.EventName) + #9 +
        LogField(Trim(FGame.ImportWarningsText)));
    FMoves.Clear;
    ExtractStrings([' ', #9, #10, #13], [], PChar(Trim(FGame.MovesText)),
      FMoves);
    // Validate the entire game before writing any game or position rows.
    // Only input errors are recoverable; database and I/O failures still abort.
    try
      CanonicalizeMovesForImport;
    except
      on E: EConvertError do
      begin
        Inc(FErrors);
        LogError(E.Message);
        ReportProgress(ABytesRead, ATotalBytes, AStop);
        Exit;
      end;
      on E: EInvalidOperation do
      begin
        Inc(FErrors);
        LogError(E.Message);
        ReportProgress(ABytesRead, ATotalBytes, AStop);
        Exit;
      end;
    end;
    FFullPdn := PdnGameToStorageText(FGame, FMoves);
    // Canonicalization may merge aliases and discover metadata conflicts.
    NewWarnings := Trim(Copy(FGame.ImportWarningsText, Length(InitialWarnings) + 1, MaxInt));
    if NewWarnings <> '' then
      LogLine('warning' + #9 + 'event=' + LogField(FGame.EventName) + #9 + LogField(NewWarnings));
    FWhite:=FGame.WhiteName;FBlack:=FGame.BlackName;FEvent:=FGame.EventName;
    FResult:=FGame.ResultText;FStartingFen:=FGame.StartingFEN;FAnnotations:=FGame.MoveAnnotationsText;
    LGameHash := GameHash;
    if IsDuplicateGame(LGameHash) or IsLegacyDuplicate then
    begin
      Inc(FDuplicates);
      LogDuplicate(LGameHash);
      ReportProgress(ABytesRead, ATotalBytes, AStop);
      Exit;
    end;

    FBoard.LoadFromFEN(FGame.StartingFEN);

    StoreGame(LGameHash);
    Inc(FImported);
    CommitBatchIfNeeded;
  except
    on E: Exception do
    begin
      Inc(FErrors);
      LogError(E.Message);
      raise;
    end;
  end;
  ReportProgress(ABytesRead, ATotalBytes, AStop);
end;

procedure TDatabasePdnImporter.StoreGame(const Hash:THash128);
var Points:Integer;
  procedure BindText(const Name,Value:string);
  begin
    FGameInsertQuery.ParamByName(Name).DataType:=ftString;
    if Value='' then FGameInsertQuery.ParamByName(Name).Clear
    else FGameInsertQuery.ParamByName(Name).AsUTF8String:=Value;
  end;
  procedure BindElo(const Name:string;Value:Integer);
  begin
    FGameInsertQuery.ParamByName(Name).DataType:=ftInteger;
    if Value<0 then FGameInsertQuery.ParamByName(Name).Clear
    else FGameInsertQuery.ParamByName(Name).AsInteger:=Value;
  end;
begin
    FGameInsertQuery.ParamByName('game_hash_lo').AsLargeInt := Hash.Lo;
    FGameInsertQuery.ParamByName('game_hash_hi').AsLargeInt := Hash.Hi;
    FGameInsertQuery.ParamByName('white').AsUTF8String := FWhite;
    FGameInsertQuery.ParamByName('black').AsUTF8String := FBlack;
    FGameInsertQuery.ParamByName('event').AsUTF8String := FEvent;
    FGameInsertQuery.ParamByName('result').AsUTF8String := FResult;
    FGameInsertQuery.ParamByName('starting_fen').AsUTF8String := FStartingFen;
    FGameInsertQuery.ParamByName('moves_text').AsUTF8String := Trim(StringReplace(FMoves.Text, LineEnding, ' ', [rfReplaceAll]));
    FGameInsertQuery.ParamByName('annotations_text').AsUTF8String := FAnnotations;
    FGameInsertQuery.ParamByName('full_pdn').AsUTF8String := PackStoredPdn(FFullPdn);
    FGameInsertQuery.ParamByName('ply_count').AsInteger := FMoves.Count;
    if FDatabase.FFormat=gffPgn then begin
      BindText('date',FDate);BindText('eco',FEco);
      BindElo('white_elo',FWhiteElo);BindElo('black_elo',FBlackElo);
    end;
    FGameInsertQuery.ExecSQL;

    FIdQuery.Open;
    FGameId := FIdQuery.FieldByName('id').AsInteger;
    FIdQuery.Close;

    for Points := 0 to FMoves.Count do
    begin
      if Points < FMoves.Count then
        InsertPosition(Points, FMoves[Points])
      else
        InsertPosition(Points, '');
      if (FDatabase.FFormat=gffPdn) and (Points < FMoves.Count) then
        FBoard.PlayMove(FMoves[Points], False, False, False);
    end;
end;

procedure TDatabasePdnImporter.ScanProgress(BytesRead,TotalBytes:Int64;var Cancel:Boolean);
begin ReportProgress(BytesRead,TotalBytes,Cancel);end;

function DatabaseDate(const Text:string):string;
var I,N:Integer;
begin
  Result:='';if (Length(Text)<>10) or (Text[5]<>'.') or (Text[8]<>'.') then Exit;
  for I:=1 to 10 do if not (I in [5,8]) and not (Text[I] in ['0'..'9','?']) then Exit;
  if TryStrToInt(Copy(Text,6,2),N) and ((N<1) or (N>12)) then Exit;
  if TryStrToInt(Copy(Text,9,2),N) and ((N<1) or (N>31)) then Exit;
  Result:=Text;
end;
function DatabaseElo(const Text:string):Integer;
var C:Char;
begin
 Result:=-1;if Text='' then Exit;
 for C in Text do if not (C in ['0'..'9']) then Exit;
 if not TryStrToInt(Text,Result) or (Result<0) then Result:=-1;
end;
procedure TDatabasePdnImporter.ImportPgnGame(const Text,ErrorText:string;
  BytesRead,TotalBytes:Int64;var Cancel:Boolean);
var G:TChessPgnDatabaseGame;W:TStringList;Hash:THash128;I:Integer;Duplicate:Boolean;
begin
 Inc(FRecordNumber);FRecordEnd:=BytesRead;FSourceBytes:=TotalBytes;
 FFullPdn:=Text;
 if ErrorText<>'' then begin Inc(FErrors);LogError(ErrorText);ReportProgress(BytesRead,TotalBytes,Cancel);Exit;end;
 G:=nil;W:=TStringList.Create;
 try
  try
  try G:=ReadChessPgnDatabaseGame(Text,FDatabase.FVariant,W);
  except on E:EPgnSyntaxError do begin Inc(FErrors);LogError(E.Message);ReportProgress(BytesRead,TotalBytes,Cancel);Exit;end;end;
  for I:=0 to W.Count-1 do LogLine('warning'+#9+LogField(W[I])+PgnRecordContext);
  FWhite:=GameFileTagValue(G.Tags,'White','?');FBlack:=GameFileTagValue(G.Tags,'Black','?');
  FEvent:=GameFileTagValue(G.Tags,'Event','?');FResult:=G.ResultText;FStartingFen:=G.StartingFEN;
  FAnnotations:='';FFullPdn:=G.CompletePgn;FMoves.Assign(G.Moves);FKeys.Assign(G.PositionKeys);
  FStartingSide:=FDatabase.FVariant.SideFromFEN(G.StartingFEN);
  FDate:=DatabaseDate(GameFileTagValue(G.Tags,'Date',GameFileTagValue(G.Tags,'UTCDate','')));
  FEco:=GameFileTagValue(G.Tags,'ECO','');
  if (Length(FEco)<>3) or not (FEco[1] in ['A'..'E']) or not (FEco[2] in ['0'..'9']) or not (FEco[3] in ['0'..'9']) then FEco:='';
  FWhiteElo:=DatabaseElo(GameFileTagValue(G.Tags,'WhiteElo',''));FBlackElo:=DatabaseElo(GameFileTagValue(G.Tags,'BlackElo',''));
  Hash:=GameHash;
  try Duplicate:=IsDuplicateGame(Hash);
  except on E:EConvertError do begin Inc(FErrors);LogError(E.Message);ReportProgress(BytesRead,TotalBytes,Cancel);Exit;end;end;
  if Duplicate then begin Inc(FDuplicates);LogDuplicate(Hash);end
  else begin StoreGame(Hash);Inc(FImported);CommitBatchIfNeeded;end;
  ReportProgress(BytesRead,TotalBytes,Cancel);
  except
    on E:Exception do begin
      Inc(FErrors);LogError(E.Message);
      raise;
    end;
  end;
 finally G.Free;W.Free;end;
end;

procedure TDatabasePdnImporter.Run(const AFileName: string);
var Reader:TChessPgnReader;
begin
  FLastProgressTick := 0;
  LogLine('started' + #9 + 'file=' + LogField(AFileName));
  try
    if FDatabase.FFormat=gffPgn then begin
      Reader:=TChessPgnReader.Create(FDatabase.FVariant);
      try Reader.ScanFile(AFileName,@ImportPgnGame,@ScanProgress);finally Reader.Free;end;
    end else ReadPdnGamesFromFile(AFileName, @ImportGame);
  finally
    // Release the retained insert before summary/index DDL or recovery.
    if FDatabase.FFormat=gffPgn then FPositionInsertQuery.UnPrepare;
  end;
end;

constructor TGameDatabase.Create(AFormat:TGameFileFormat);
begin
  inherited Create;
  FFormat:=AFormat;
  if FFormat=gffPgn then begin
    FVariant:=TChessVariant.Create;FWhiteWin:='1-0';FDraw:='1/2-1/2';FBlackWin:='0-1';
  end else begin FWhiteWin:='2-0';FDraw:='1-1';FBlackWin:='0-2';end;
  FConnection := TSQLite3Connection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);
  FConnection.Transaction := FTransaction;
end;

destructor TGameDatabase.Destroy;
begin
  Close;
  FTransaction.Free;
  FConnection.Free;FVariant.Free;
  inherited Destroy;
end;

procedure TGameDatabase.ClearObjectList(AList: TList);
var
  I: Integer;
begin
  if AList = nil then
    Exit;
  for I := 0 to AList.Count - 1 do
    TObject(AList[I]).Free;
  AList.Clear;
end;

procedure TGameDatabase.CommitActiveTransaction;
begin
  if FTransaction.Active then
    FTransaction.Commit;
end;

function TGameDatabase.ContinuationSummaryAvailable: Boolean;
var
  Q: TSQLQuery;
begin
  Result := False;
  if not FConnection.Connected then
    Exit;

  Q := Query;
  try
    Q.SQL.Text := 'select 1 from database_state where id=1 and summary_dirty=0';
    Q.Open;
    Result := not Q.EOF;
    Q.Close;
  finally
    Q.Free;
  end;
end;

procedure TGameDatabase.StartTransactionIfNeeded;
begin
  if not FTransaction.Active then
    FTransaction.StartTransaction;
end;

procedure TGameDatabase.ExecuteSql(const ASql: string);
var
  Q: TSQLQuery;
begin
  Q := Query;
  try
    Q.SQL.Text := ASql;
    Q.ExecSQL;
  finally
    Q.Free;
  end;
end;

procedure TGameDatabase.CreateImportIndexes;
begin
  ExecuteSql('create unique index if not exists idx_games_hash on games(game_hash_lo, game_hash_hi)');
  ExecuteSql('create index if not exists idx_games_white on games(white)');
  ExecuteSql('create index if not exists idx_games_black on games(black)');
  ExecuteSql('create index if not exists idx_games_event on games(event)');
  ExecuteSql('create index if not exists idx_positions_search on positions(position_key_lo, position_key_hi, side_to_move, next_move, result)');
  ExecuteSql('create index if not exists idx_positions_game on positions(game_id)');
end;

procedure TGameDatabase.EnsureContinuationTable;
begin
  ExecuteSql(
    'create table if not exists continuations (' +
    'position_key_lo integer not null,' +
    'position_key_hi integer not null,' +
    'side_to_move text not null,' +
    'next_move text not null,' +
    'game_count integer not null,' +
    'white_wins integer not null,' +
    'draws integer not null,' +
    'black_wins integer not null,' +
    'primary key(position_key_lo, position_key_hi, side_to_move, next_move))');
end;

procedure TGameDatabase.EnsureContinuationState;
const
  Changes: array[0..2] of string = ('insert', 'update', 'delete');
var
  Change: string;
begin
  ExecuteSql('create table if not exists database_state (' +
    'id integer primary key check(id=1),' +
    'summary_dirty integer not null check(summary_dirty in (0,1)))');
  // Existing databases have no trustworthy freshness information. Their first
  // open with this schema must rebuild even if the old summary is nonempty.
  ExecuteSql('insert or ignore into database_state(id, summary_dirty) values(1,1)');
  // Invalidate alongside every position change, including writes after a
  // reentrant rebuild or from another connection. Rollbacks undo this too.
  for Change in Changes do
    ExecuteSql('create trigger if not exists continuations_dirty_' + Change +
      ' after ' + Change + ' on positions ' +
      'when (select summary_dirty from database_state where id=1)=0 ' +
      'begin update database_state set summary_dirty=1 where id=1; end');
end;

procedure TGameDatabase.EnsureGameHashColumns;
begin
  if (not TableColumnExists('games', 'game_hash_lo')) or
    (not TableColumnExists('games', 'game_hash_hi')) then
    raise EInvalidOperation.Create(
      'This database uses the old game hash schema. Create a new database and reimport the PDN file.');
end;

function TGameDatabase.TableColumnExists(const ATableName,
  AColumnName: string): Boolean;
var
  Q: TSQLQuery;
begin
  Result := False;
  Q := Query;
  try
    Q.SQL.Text := 'pragma table_info(' + ATableName + ')';
    Q.Open;
    while not Q.EOF do
    begin
      if SameText(Q.FieldByName('name').AsUTF8String, AColumnName) then
      begin
        Result := True;
        Break;
      end;
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
  end;
end;

procedure TGameDatabase.SetBulkImportPragmas;
begin
  CommitActiveTransaction;
  if FFormat=gffPgn then FConnection.ExecuteDirect('pragma temp_store=file')
  else FConnection.ExecuteDirect('pragma temp_store=memory');
  FConnection.ExecuteDirect('pragma cache_size=-200000');
  CommitActiveTransaction;
end;

function TGameDatabase.Query: TSQLQuery;
begin
  Result := TSQLQuery.Create(nil);
  Result.DataBase := FConnection;
  Result.Transaction := FTransaction;
end;

procedure TGameDatabase.Close;
begin
  CommitActiveTransaction;
  FConnection.Connected := False;
  FFileName := '';
end;

procedure TGameDatabase.CreateDatabase(const AFileName: string);
begin
  if FileExists(AFileName) then
    raise EInvalidOperation.Create('Database already exists. Open it or choose a new filename.');
  InitializeDatabase(AFileName);
end;

procedure TGameDatabase.InitializeDatabase(const AFileName: string);
var
  Q: TSQLQuery;
  SchemaVersion: Integer;
begin
  Close;
  FConnection.DatabaseName := AFileName;
  FConnection.Connected := True;
  if sqlite3_create_function(FConnection.Handle, 'gwd_lower', 1, SQLITE_UTF8,
    nil, @SqlUnicodeLower, nil, nil) <> SQLITE_OK then
    raise EInvalidOperation.Create('Could not register Unicode name matching');
  StartTransactionIfNeeded;
  Q := Query;
  try
    Q.SQL.Text := 'pragma user_version';
    Q.Open;
    SchemaVersion := Q.Fields[0].AsInteger;
    if ((FFormat=gffPdn) and (SchemaVersion>6)) or (SchemaVersion>7) then
      raise EInvalidOperation.Create('This database was created by a newer GWDGUI version');
    Q.Close;
    Q.SQL.Text :=
      'create table if not exists games (' +
      'id integer primary key autoincrement,' +
      'game_hash_lo integer not null,' +
      'game_hash_hi integer not null,' +
      'white text, black text, event text, result text,' +
      'starting_fen text, moves_text text, annotations_text text,' +
      'ply_count integer)';
    Q.ExecSQL;
    EnsureGameHashColumns;
    if not TableColumnExists('games', 'full_pdn') then
      ExecuteSql('alter table games add column full_pdn text');
    if not TableColumnExists('games', 'hash_version') then
      ExecuteSql('alter table games add column hash_version integer not null default 0');
    if FFormat=gffPdn then begin
      if SchemaVersion < 6 then ExecuteSql('drop index if exists games_legacy_candidates');
      ExecuteSql('create index if not exists games_legacy_candidates on games(white, black, event, result, ply_count) where hash_version < 6');
      ExecuteSql('pragma user_version=6');
    end else begin
      if SchemaVersion=0 then begin
        ExecuteSql('alter table games add column date text');ExecuteSql('alter table games add column eco text');
        ExecuteSql('alter table games add column white_elo integer');ExecuteSql('alter table games add column black_elo integer');
        ExecuteSql('create table database_metadata (name text primary key,value text not null)');
        ExecuteSql('insert into database_metadata values(''game_variant'',''chess''),(''notation_format'',''pgn''),(''position_key_format'',''chess-position-key-v1-fnv128''),(''game_identity_format'',''complete-lossless-pgn-token-v1'')');
      end;
      ExecuteSql('pragma user_version=7');
    end;
    Q.SQL.Text :=
      'create table if not exists positions (' +
      'id integer primary key autoincrement,' +
      'game_id integer not null,' +
      'ply integer not null,' +
      'position_key_lo integer not null,' +
      'position_key_hi integer not null,' +
      'side_to_move text not null,' +
      'next_move text,' +
      'result text)';
    Q.ExecSQL;
    if (not TableColumnExists('positions', 'position_key_lo')) or
      (not TableColumnExists('positions', 'position_key_hi')) then
      raise EInvalidOperation.Create(
        'This database uses the old position schema. Create a new database and reimport the PDN file.');
    EnsureContinuationTable;
    EnsureContinuationState;
    CreateImportIndexes;
    FTransaction.Commit;
    if not ContinuationSummaryAvailable then RebuildContinuationSummary;
    CommitActiveTransaction;
    FFileName := AFileName;
  finally
    Q.Free;
  end;
end;

procedure TGameDatabase.PreflightDatabase(const AFileName:string);
var C:TSQLite3Connection;T:TSQLTransaction;Q:TSQLQuery;Stream:TFileStream;
 Version:Integer;
 procedure RequireColumns(const TableName:string;const Names:array of string);
 var Found:TStringList;I:Integer;
 begin
  Found:=TStringList.Create;
  try
   Q.Close;Q.SQL.Text:='pragma table_info('+TableName+')';Q.Open;
   while not Q.EOF do begin Found.Add(Q.FieldByName('name').AsString);Q.Next;end;
   Q.Close;
   for I:=0 to High(Names) do if Found.IndexOf(Names[I])<0 then
    raise EInvalidOperation.Create('Unsupported database: missing '+TableName+'.'+Names[I]);
  finally Found.Free;end;
 end;
 procedure RequireMetadata(const Name,Value:string);
 begin
   Q.Close;Q.SQL.Text:='select value from database_metadata where name=:name';
   Q.ParamByName('name').AsString:=Name;Q.Open;
   if Q.EOF or (Q.Fields[0].AsString<>Value) then raise EInvalidOperation.Create('Unsupported chess database metadata: '+Name);
   Q.Close;
 end;
begin
 // Inspect before closing the current database or running any schema upgrades.
 Stream:=TFileStream.Create(AFileName,fmOpenRead or fmShareDenyNone);
 try if Stream.Size=0 then begin
   if FFormat=gffPgn then raise EInvalidOperation.Create('Empty file is not a chess database; use Create database');
   Exit;
 end;finally Stream.Free;end;
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);Q:=TSQLQuery.Create(nil);
 try
  // Allow SQLite to recover a hot rollback journal before inspecting the schema.
  // This connection performs no DDL and rolls its inspection transaction back.
  C.DatabaseName:=AFileName;C.Transaction:=T;
  Q.DataBase:=C;Q.Transaction:=T;C.Connected:=True;T.StartTransaction;
  Q.SQL.Text:='pragma user_version';Q.Open;Version:=Q.Fields[0].AsInteger;Q.Close;
  if ((FFormat=gffPdn) and (Version>6)) or ((FFormat=gffPgn) and (Version<>7)) then
    raise EInvalidOperation.Create('Unsupported database variant or schema version');
  RequireColumns('games',['game_hash_lo','game_hash_hi','white','black','event','result',
   'starting_fen','moves_text','annotations_text','ply_count']);
  RequireColumns('positions',['game_id','ply','position_key_lo','position_key_hi',
   'side_to_move','next_move','result']);
  if FFormat=gffPgn then begin
    RequireColumns('games',['full_pdn','hash_version','date','eco','white_elo','black_elo']);
    RequireColumns('database_metadata',['name','value']);
    RequireMetadata('game_variant','chess');RequireMetadata('notation_format','pgn');
    RequireMetadata('position_key_format','chess-position-key-v1-fnv128');
    RequireMetadata('game_identity_format','complete-lossless-pgn-token-v1');
  end;
 finally
  Q.Free;if T.Active then T.Rollback;C.Close;T.Free;C.Free;
 end;
end;

procedure TGameDatabase.OpenDatabase(const AFileName: string);
begin
  if not FileExists(AFileName) then
    raise EInvalidOperation.Create('Database file does not exist');
  PreflightDatabase(AFileName);
  InitializeDatabase(AFileName);
end;

procedure TGameDatabase.ImportPdnFile(const AFileName:string;out AImported,ADuplicates,AErrors:Integer;
  AOnProgress:TDatabaseImportProgressEvent;const AImportLogFileName:string);
begin
  if FFormat<>gffPdn then raise EInvalidOperation.Create('Use ImportFile for chess PGN');
  ImportFile(AFileName,AImported,ADuplicates,AErrors,AOnProgress,AImportLogFileName);
end;
procedure TGameDatabase.ImportFile(const AFileName: string; out AImported,
  ADuplicates, AErrors: Integer; AOnProgress: TDatabaseImportProgressEvent;
  const AImportLogFileName: string);
var
  Importer: TDatabasePdnImporter;
begin
  AImported := 0;
  ADuplicates := 0;
  AErrors := 0;
  if not FConnection.Connected then
    raise EInvalidOperation.Create('No database is open');

  Importer := TDatabasePdnImporter.Create(Self, AOnProgress,
    AImportLogFileName);
  try
    try
      CommitActiveTransaction;
      SetBulkImportPragmas;
      StartTransactionIfNeeded;
      // Commit invalidation before any import rows can become durable (including
      // progress callbacks which may query and commit the active transaction).
      ExecuteSql('update database_state set summary_dirty=1 where id=1');
      // Draughts retains its search/game indexes throughout the import.
      // Chess uses the reviewed bulk policy below, retaining the unique hash.
      CommitActiveTransaction;
      StartTransactionIfNeeded;
      if FFormat=gffPgn then begin
        // Reviewed bulk-import policy: keep uniqueness and dirty-state recovery,
        // rebuild secondary indexes through the existing success/error shell.
        ExecuteSql('drop index if exists idx_positions_search');
        ExecuteSql('drop index if exists idx_positions_game');
        ExecuteSql('drop index if exists idx_games_white');
        ExecuteSql('drop index if exists idx_games_black');
        ExecuteSql('drop index if exists idx_games_event');
      end;
      Importer.Run(AFileName);
      CommitActiveTransaction;
      StartTransactionIfNeeded;
      RebuildContinuationSummary;
      StartTransactionIfNeeded;
      CreateImportIndexes;
      CommitActiveTransaction;
    except
      if FTransaction.Active then
        FTransaction.Rollback;
      try
        RebuildContinuationSummary;
        StartTransactionIfNeeded;
        CreateImportIndexes;
        CommitActiveTransaction;
      except
        if FTransaction.Active then
          FTransaction.Rollback;
      end;
      raise;
    end;
    AImported := Importer.Imported;
    ADuplicates := Importer.Duplicates;
    AErrors := Importer.Errors;
  finally
    Importer.Free;
  end;
end;

procedure TGameDatabase.RebuildContinuationSummary;
begin
  if not FConnection.Connected then
    raise EInvalidOperation.Create('No database is open');

  CommitActiveTransaction;
  StartTransactionIfNeeded;
  try
    EnsureContinuationTable;
    ExecuteSql('delete from continuations');
    ExecuteSql(
      'insert into continuations(position_key_lo, position_key_hi, side_to_move, next_move, game_count, white_wins, draws, black_wins) ' +
      'select position_key_lo, position_key_hi, side_to_move, next_move, count(*) as game_count, ' +
      'sum(case when result = '+QuotedStr(FWhiteWin)+' then 1 else 0 end) as white_wins, ' +
      'sum(case when result = '+QuotedStr(FDraw)+' then 1 else 0 end) as draws, ' +
      'sum(case when result = '+QuotedStr(FBlackWin)+' then 1 else 0 end) as black_wins ' +
      'from positions ' +
      'where coalesce(next_move, '''') <> '''' ' +
      'group by position_key_lo, position_key_hi, side_to_move, next_move');
    // Publish the replacement summary and its clean flag in one transaction.
    ExecuteSql('update database_state set summary_dirty=0 where id=1');
    CommitActiveTransaction;
  except
    if FTransaction.Active then
      FTransaction.Rollback;
    raise;
  end;
end;

procedure TGameDatabase.LoadGames(AList: TList; ALimit: Integer;
  const AWhiteFilter, ABlackFilter, AEventFilter, APlayerFilter: string;
  ASortColumn: TDatabaseGameSortColumn; ASortDescending: Boolean;
  out ATotalMatches: Integer);
var
  Info: TDatabaseGameInfo;
  OrderBy: string;
  Q: TSQLQuery;
  WhereSql: string;

  procedure AddFilter(const AColumn, AParamName, AValue: string);
  begin
    if Trim(AValue) = '' then
      Exit;
    if WhereSql = '' then
      WhereSql := ' where '
    else
      WhereSql := WhereSql + ' and ';
    WhereSql := WhereSql + 'instr(gwd_lower(' + AColumn + '), :' + AParamName + ') > 0';
  end;

  procedure AddPlayerFilter;
  begin
    if Trim(APlayerFilter) = '' then
      Exit;
    if WhereSql = '' then
      WhereSql := ' where '
    else
      WhereSql := WhereSql + ' and ';
    WhereSql := WhereSql +
      '(instr(gwd_lower(white), :player_filter) > 0 or instr(gwd_lower(black), :player_filter) > 0)';
  end;

  procedure BindFilters(AQuery: TSQLQuery);
  begin
    if Trim(AWhiteFilter) <> '' then
      AQuery.ParamByName('white_filter').AsUTF8String :=
        FoldUtf8(Trim(AWhiteFilter));
    if Trim(ABlackFilter) <> '' then
      AQuery.ParamByName('black_filter').AsUTF8String :=
        FoldUtf8(Trim(ABlackFilter));
    if Trim(AEventFilter) <> '' then
      AQuery.ParamByName('event_filter').AsUTF8String :=
        FoldUtf8(Trim(AEventFilter));
    if Trim(APlayerFilter) <> '' then
      AQuery.ParamByName('player_filter').AsUTF8String :=
        FoldUtf8(Trim(APlayerFilter));
  end;
begin
  ATotalMatches := 0;
  ClearObjectList(AList);
  if not FConnection.Connected then
    Exit;

  WhereSql := '';
  AddFilter('white', 'white_filter', AWhiteFilter);
  AddFilter('black', 'black_filter', ABlackFilter);
  AddFilter('event', 'event_filter', AEventFilter);
  AddPlayerFilter;

  case ASortColumn of
    dgscWhite:
      OrderBy := 'gwd_lower(white), gwd_lower(black), gwd_lower(event), id';
    dgscBlack:
      OrderBy := 'gwd_lower(black), gwd_lower(white), gwd_lower(event), id';
    dgscEvent:
      OrderBy := 'gwd_lower(event), gwd_lower(white), gwd_lower(black), id';
  else
    OrderBy := 'id';
  end;
  if ASortDescending then
    OrderBy := StringReplace(OrderBy, ',', ' desc,', [rfReplaceAll]) + ' desc';

  Q := Query;
  try
    Q.SQL.Text := 'select count(*) as game_count from games' + WhereSql;
    BindFilters(Q);
    Q.Open;
    ATotalMatches := Q.FieldByName('game_count').AsInteger;
    Q.Close;

    Q.SQL.Text :=
      'select id, white, black, event, result, starting_fen, ply_count ' +
      'from games' + WhereSql + ' order by ' + OrderBy;
    if ALimit > 0 then
      Q.SQL.Text := Q.SQL.Text + ' limit ' + IntToStr(ALimit);
    BindFilters(Q);
    Q.Open;
    while not Q.EOF do
    begin
      Info := TDatabaseGameInfo.Create;
      Info.Id := Q.FieldByName('id').AsInteger;
      Info.WhiteName := Q.FieldByName('white').AsUTF8String;
      Info.BlackName := Q.FieldByName('black').AsUTF8String;
      Info.EventName := Q.FieldByName('event').AsUTF8String;
      Info.ResultText := Q.FieldByName('result').AsUTF8String;
      Info.StartingFEN := Q.FieldByName('starting_fen').AsUTF8String;
      Info.PlyCount := Q.FieldByName('ply_count').AsInteger;
      AList.Add(Info);
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
    CommitActiveTransaction;
  end;
end;

procedure TGameDatabase.LoadGames(AList: TList);
var
  TotalMatches: Integer;
begin
  LoadGames(AList, 0, '', '', '', '', dgscId, False, TotalMatches);
end;

function TGameDatabase.LoadGameById(AGameId: Integer): TPdnGame;
var
  Q: TSQLQuery;
  Games: TList;
  I: Integer;
begin
  if FFormat<>gffPdn then raise EInvalidOperation.Create('Use LoadFileGameById for chess');
  if not FConnection.Connected then
    raise EInvalidOperation.Create('No database is open');

  Result := nil;
  Q := Query;
  try
    Q.SQL.Text :=
      'select white, black, event, result, starting_fen, moves_text, annotations_text, full_pdn ' +
      'from games where id = :id';
    Q.ParamByName('id').AsInteger := AGameId;
    Q.Open;
    if Q.EOF then
      raise EInvalidOperation.Create('Game not found');

    if Q.FieldByName('full_pdn').AsUTF8String <> '' then
    begin
      Games := TList.Create;
      try
        LoadPdnGamesFromText(UnpackStoredPdn(Q.FieldByName('full_pdn').AsUTF8String), Games);
        if Games.Count <> 1 then
          raise EConvertError.Create('Stored database game is not a single PDN game');
        Result := TPdnGame(Games[0]);
        Games.Clear;
      finally
        for I := 0 to Games.Count - 1 do TObject(Games[I]).Free;
        Games.Free;
      end;
      Exit;
    end;
    Result := TPdnGame.Create;
    Result.WhiteName := Q.FieldByName('white').AsUTF8String;
    Result.BlackName := Q.FieldByName('black').AsUTF8String;
    Result.EventName := Q.FieldByName('event').AsUTF8String;
    Result.ResultText := Q.FieldByName('result').AsUTF8String;
    Result.StartingFEN := Q.FieldByName('starting_fen').AsUTF8String;
    Result.MovesText := Q.FieldByName('moves_text').AsUTF8String;
    Result.MoveAnnotationsText := Q.FieldByName('annotations_text').AsUTF8String;
    Q.Close;
  finally
    Q.Free;
    CommitActiveTransaction;
  end;
end;

function TGameDatabase.GamesForPositionByKey(const APositionKey: string;
  ASideToMove: TGameSide; ALimit: Integer; out AProbeCount: Integer): Boolean;
var
  Q: TSQLQuery;
begin
  AProbeCount := 0;
  Result := False;
  if not FConnection.Connected then
    Exit;
  if ALimit < 1 then
    Exit;

  Q := Query;
  try
    Q.SQL.Text :=
      'select p.game_id from positions p ' +
      'where p.position_key_lo = :position_key_lo and p.position_key_hi = :position_key_hi ' +
      'and p.side_to_move = :side_to_move ' +
      'group by p.game_id limit ' + IntToStr(ALimit + 1);
    BindPositionKey(Q, APositionKey);
    Q.ParamByName('side_to_move').AsUTF8String := GameSideToText(ASideToMove);
    Q.Open;
    while not Q.EOF do
    begin
      Inc(AProbeCount);
      Q.Next;
    end;
    Q.Close;
    Result := AProbeCount > ALimit;
  finally
    Q.Free;
    CommitActiveTransaction;
  end;
end;

procedure TGameDatabase.LoadGamesForPositionByKey(const APositionKey: string;
  ASideToMove: TGameSide; AList: TList; ALimit: Integer;
  out ATotalMatches: Integer);
var
  Info: TDatabaseGameInfo;
  Q: TSQLQuery;
begin
  ATotalMatches := 0;
  ClearObjectList(AList);
  if not FConnection.Connected then
    Exit;

  Q := Query;
  try
    Q.SQL.Text :=
      'select count(*) as game_count from (' +
      'select p.game_id from positions p ' +
      'where p.position_key_lo = :position_key_lo and p.position_key_hi = :position_key_hi ' +
      'and p.side_to_move = :side_to_move ' +
      'group by p.game_id)';
    BindPositionKey(Q, APositionKey);
    Q.ParamByName('side_to_move').AsUTF8String := GameSideToText(ASideToMove);
    Q.Open;
    ATotalMatches := Q.FieldByName('game_count').AsInteger;
    Q.Close;

    Q.SQL.Text :=
      'select g.id, g.white, g.black, g.event, g.result, g.starting_fen, ' +
      'g.ply_count, min(p.ply) as first_ply ' +
      'from positions p join games g on g.id = p.game_id ' +
      'where p.position_key_lo = :position_key_lo and p.position_key_hi = :position_key_hi ' +
      'and p.side_to_move = :side_to_move ' +
      'group by g.id, g.white, g.black, g.event, g.result, g.starting_fen, g.ply_count ' +
      'order by first_ply, g.id';
    if ALimit > 0 then
      Q.SQL.Text := Q.SQL.Text + ' limit ' + IntToStr(ALimit);
    BindPositionKey(Q, APositionKey);
    Q.ParamByName('side_to_move').AsUTF8String := GameSideToText(ASideToMove);
    Q.Open;
    while not Q.EOF do
    begin
      Info := TDatabaseGameInfo.Create;
      Info.Id := Q.FieldByName('id').AsInteger;
      Info.WhiteName := Q.FieldByName('white').AsUTF8String;
      Info.BlackName := Q.FieldByName('black').AsUTF8String;
      Info.EventName := Q.FieldByName('event').AsUTF8String;
      Info.ResultText := Q.FieldByName('result').AsUTF8String;
      Info.StartingFEN := Q.FieldByName('starting_fen').AsUTF8String;
      Info.PlyCount := Q.FieldByName('ply_count').AsInteger;
      AList.Add(Info);
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
    CommitActiveTransaction;
  end;
end;

procedure TGameDatabase.SearchPositionByKey(const APositionKey: string;
  ASideToMove: TGameSide; AList: TList);
var
  ResultItem: TDatabaseSearchResult;
  Q: TSQLQuery;
  UseSummary: Boolean;
begin
  ClearObjectList(AList);
  if not FConnection.Connected then
    Exit;

  UseSummary := ContinuationSummaryAvailable;
  Q := Query;
  try
    if UseSummary then
    begin
      if ASideToMove = gsBlack then
        Q.SQL.Text :=
          'select c.next_move, c.game_count, c.black_wins as wins, c.draws, c.white_wins as losses ' +
          'from continuations c ' +
          'where c.position_key_lo = :position_key_lo and c.position_key_hi = :position_key_hi ' +
          'and c.side_to_move = :side_to_move ' +
          'order by c.game_count desc, wins desc, c.next_move'
      else
        Q.SQL.Text :=
          'select c.next_move, c.game_count, c.white_wins as wins, c.draws, c.black_wins as losses ' +
          'from continuations c ' +
          'where c.position_key_lo = :position_key_lo and c.position_key_hi = :position_key_hi ' +
          'and c.side_to_move = :side_to_move ' +
          'order by c.game_count desc, wins desc, c.next_move';
      Q.ParamByName('side_to_move').AsUTF8String := GameSideToText(ASideToMove);
    end
    else if ASideToMove = gsBlack then
      Q.SQL.Text :=
        'select p.next_move, count(*) as game_count, ' +
        'sum(case when p.result = '+QuotedStr(FBlackWin)+' then 1 else 0 end) as wins, ' +
        'sum(case when p.result = '+QuotedStr(FDraw)+' then 1 else 0 end) as draws, ' +
        'sum(case when p.result = '+QuotedStr(FWhiteWin)+' then 1 else 0 end) as losses ' +
        'from positions p ' +
        'where p.position_key_lo = :position_key_lo and p.position_key_hi = :position_key_hi ' +
        'and p.side_to_move = :side_to_move ' +
        'and coalesce(p.next_move, '''') <> '''' ' +
        'group by p.next_move ' +
        'order by game_count desc, wins desc, p.next_move'
    else
      Q.SQL.Text :=
        'select p.next_move, count(*) as game_count, ' +
        'sum(case when p.result = '+QuotedStr(FWhiteWin)+' then 1 else 0 end) as wins, ' +
        'sum(case when p.result = '+QuotedStr(FDraw)+' then 1 else 0 end) as draws, ' +
        'sum(case when p.result = '+QuotedStr(FBlackWin)+' then 1 else 0 end) as losses ' +
        'from positions p ' +
        'where p.position_key_lo = :position_key_lo and p.position_key_hi = :position_key_hi ' +
        'and p.side_to_move = :side_to_move ' +
        'and coalesce(p.next_move, '''') <> '''' ' +
        'group by p.next_move ' +
        'order by game_count desc, wins desc, p.next_move';
    BindPositionKey(Q, APositionKey);
    Q.ParamByName('side_to_move').AsUTF8String := GameSideToText(ASideToMove);
    Q.Open;
    while not Q.EOF do
    begin
      ResultItem := TDatabaseSearchResult.Create;
      ResultItem.MoveText := Q.FieldByName('next_move').AsUTF8String;
      ResultItem.GameCount := Q.FieldByName('game_count').AsInteger;
      ResultItem.Wins := Q.FieldByName('wins').AsInteger;
      ResultItem.Draws := Q.FieldByName('draws').AsInteger;
      ResultItem.Losses := Q.FieldByName('losses').AsInteger;
      AList.Add(ResultItem);
      Q.Next;
    end;
    Q.Close;
  finally
    Q.Free;
    CommitActiveTransaction;
  end;
end;


procedure TGameDatabase.CheckPosition(Position:TGamePosition);
begin
 if (Position=nil) or ((FFormat=gffPgn)<>(Position is TChessPosition)) or
   ((FFormat=gffPdn) and not (Position is TDraughtsPosition)) then
   raise EInvalidOperation.Create('Position does not match database variant');
end;
function TGameDatabase.GamesForPositionExceedLimit(Position:TGamePosition;Limit:Integer;out Count:Integer):Boolean;
begin CheckPosition(Position);Result:=GamesForPositionByKey(Position.PositionKey,Position.SideToMove,Limit,Count);end;
procedure TGameDatabase.LoadGamesForPosition(Position:TGamePosition;List:TList;Limit:Integer;out Count:Integer);
begin CheckPosition(Position);LoadGamesForPositionByKey(Position.PositionKey,Position.SideToMove,List,Limit,Count);end;
procedure TGameDatabase.SearchPosition(Position:TGamePosition;List:TList);
begin CheckPosition(Position);SearchPositionByKey(Position.PositionKey,Position.SideToMove,List);end;
function DraughtsGameSide(Side:TDraughtsSide):TGameSide;
begin if Side=dsBlack then Result:=gsBlack else Result:=gsWhite;end;
function TGameDatabase.GamesForPositionExceedLimit(const APositionKey:string;ASideToMove:TDraughtsSide;ALimit:Integer;out AProbeCount:Integer):Boolean;
begin Result:=GamesForPositionByKey(APositionKey,DraughtsGameSide(ASideToMove),ALimit,AProbeCount);end;
procedure TGameDatabase.LoadGamesForPosition(const APositionKey:string;ASideToMove:TDraughtsSide;AList:TList;ALimit:Integer;out ATotalMatches:Integer);
begin LoadGamesForPositionByKey(APositionKey,DraughtsGameSide(ASideToMove),AList,ALimit,ATotalMatches);end;
procedure TGameDatabase.SearchPosition(const APositionKey:string;ASideToMove:TDraughtsSide;AList:TList);
begin SearchPositionByKey(APositionKey,DraughtsGameSide(ASideToMove),AList);end;
function TGameDatabase.LoadFileGameById(AGameId:Integer):TGameFileEntry;
var Q:TSQLQuery;Text:string;
begin
 if FFormat<>gffPgn then raise EInvalidOperation.Create('Use LoadGameById for draughts');
 if not FConnection.Connected then raise EInvalidOperation.Create('No database is open');
 Q:=Query;
 try
  Q.SQL.Text:='select full_pdn,white,black,event,result from games where id=:id';
  Q.ParamByName('id').AsInteger:=AGameId;Q.Open;
  if Q.EOF then raise EInvalidOperation.Create('Game not found');
  Text:=UnpackStoredPdn(Q.FieldByName('full_pdn').AsUTF8String);
  if Text='' then raise EConvertError.Create('Stored chess game is missing full PGN');
  Result:=ChessPgnEntryFromText(Text,FVariant);
  Result.WhiteName:=Q.FieldByName('white').AsUTF8String;Result.BlackName:=Q.FieldByName('black').AsUTF8String;
  Result.EventName:=Q.FieldByName('event').AsUTF8String;Result.ResultText:=Q.FieldByName('result').AsUTF8String;
 finally Q.Free;CommitActiveTransaction;end;
end;

end.
