unit uChessPgn;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, uChessPgnLexer, uGameTreeActor, uGamePosition,
  uGameFileReader;
const MaxPgnGameBytes=16*1024*1024;
type
  TChessPgnReader = class(TGameFileReader)
  private
    FVariant: TGameVariant; // borrowed
  public
    constructor Create(AVariant: TGameVariant);
    procedure OpenFile(const FileName: string); override;
  end;
// Parse into a disposable existing tree first, then replay the immutable text
// into the target actor. No IO or grammar/rules validation is deferred to UI.
procedure ImportChessPgn(const Text: string; Actor: TGameTreeActor; Warnings: TStrings);
function PgnUtf8(const Bytes: string; out Converted: Boolean): string;
function PgnTournamentFileMatchesId(const FileName,Id:string):Boolean;
implementation
uses SHA1, StrUtils, uChessPosition, uGameTree, uGameTreeBuilder, uGameFileMetadata,
  uGameTreeNodeData, uChessPgnAnnotations, uGameOrchestrator;
var ImportSequence: QWord=0;
function PgnUtf8(const Bytes: string; out Converted: Boolean): string;
const CP: array[0..31] of Word=($20AC,$0081,$201A,$0192,$201E,$2026,$2020,$2021,
  $02C6,$2030,$0160,$2039,$0152,$008D,$017D,$008F,$0090,$2018,$2019,$201C,$201D,
  $2022,$2013,$2014,$02DC,$2122,$0161,$203A,$0153,$009D,$017E,$0178);
var I,J,N,B,C,Code,MinCode: Integer; Valid: Boolean; U: UnicodeString;
begin
  I:=1; Valid:=True;
  while I<=Length(Bytes) do begin
    B:=Ord(Bytes[I]); Inc(I); if B<128 then Continue;
    if (B>=$C2) and (B<=$DF) then begin N:=1; Code:=B and 31; MinCode:=128; end
    else if (B>=$E0) and (B<=$EF) then begin N:=2; Code:=B and 15; MinCode:=2048; end
    else if (B>=$F0) and (B<=$F4) then begin N:=3; Code:=B and 7; MinCode:=65536; end
    else begin Valid:=False; Break; end;
    for J:=1 to N do begin
      if I>Length(Bytes) then begin Valid:=False; Break; end;
      C:=Ord(Bytes[I]); Inc(I); if (C and $C0)<>$80 then begin Valid:=False; Break; end;
      Code:=Code*64+(C and 63);
    end;
    if not Valid or (Code<MinCode) or (Code>$10FFFF) or ((Code>=$D800) and (Code<=$DFFF)) then begin Valid:=False; Break; end;
  end;
  Converted:=not Valid;
  if Valid then Result:=Bytes
  else begin
    SetLength(U,Length(Bytes));
    for I:=1 to Length(Bytes) do begin
      B:=Ord(Bytes[I]); if (B>=128) and (B<=159) then U[I]:=WideChar(CP[B-128]) else U[I]:=WideChar(B);
    end;
    Result:=UTF8Encode(U);
  end;
end;
// Normalize only nonbreaking spaces outside strings/comments, where PGN uses
// them as separators. Literal tag/comment text is retained.
function PgnWhitespace(const S: string): string;
var I: Integer; Brace,Quoted,Line,Escape: Boolean;
begin
  Result:=''; I:=1; Brace:=False; Quoted:=False; Line:=False; Escape:=False;
  while I<=Length(S) do begin
    if not Brace and not Quoted and not Line and (Copy(S,I,2)=#$C2#$A0) then begin Result+=' '; Inc(I,2); Continue; end;
    Result+=S[I];
    if Line then begin if S[I] in [#10,#13] then Line:=False; end
    else if Brace then begin if S[I]='}' then Brace:=False; end
    else if Quoted then begin
      if Escape then Escape:=False else if S[I]='\' then Escape:=True else if S[I]='"' then Quoted:=False;
    end
    else case S[I] of '{':Brace:=True; ';','%':Line:=True; '"':Quoted:=True; end;
    Inc(I);
  end;
end;
type
  TPgnParser = class
  private
    L: TChessPgnLexer; T: TPgnToken; A: TGameTreeActor; W: TStrings;
    Tags: TGameFileTags; Header: TGameTreeHeaderInput;
    procedure Next;
    procedure Fail(const Msg: string);
    procedure Execute(C: TGameTreeCommand);
    procedure Store(Node: TGameTreePlyNode; const Data: TGameTreeNodeData);
    procedure Line(Parent: TGameTreePlyNode; Position: TGamePosition; Depth: Integer);
  public
    constructor Create(const Text: string; Actor: TGameTreeActor; Warnings: TStrings);
    destructor Destroy; override;
    procedure Parse;
  end;
procedure TPgnParser.Next;
begin T:=L.NextToken; end;
procedure TPgnParser.Fail(const Msg: string);
begin raise EPgnSyntaxError.CreateFmt('PGN line %d, column %d: %s',[T.Line,T.Column,Msg]); end;
procedure TPgnParser.Execute(C: TGameTreeCommand);
begin
  try A.ExecuteCommand(C); if not C.Accepted then Fail(C.ErrorText); finally C.Free; end;
end;
procedure TPgnParser.Store(Node: TGameTreePlyNode; const Data: TGameTreeNodeData);
begin Execute(A.CreateRestoreNodeDataCommand(Node.NodeId,Data)); end;
constructor TPgnParser.Create(const Text: string; Actor: TGameTreeActor; Warnings: TStrings);
var Converted: Boolean;
begin
  inherited Create; A:=Actor; W:=Warnings;
  if Length(Text)>MaxPgnGameBytes then raise EPgnSyntaxError.Create('PGN game exceeds 16 MiB limit');
  L:=TChessPgnLexer.Create(PgnWhitespace(PgnUtf8(Text,Converted)));
  if Converted and (W<>nil) then W.Add('Legacy CP1252 text converted to UTF-8');
end;
destructor TPgnParser.Destroy;
begin L.Free; inherited; end;
procedure TPgnParser.Parse;
var Name,Value,Fen,Setup: string; Tag: TGameFileTag; I: Integer; Posn: TGamePosition;
begin
  Next;
  while T.Kind=ptTagOpen do begin
    Next; if T.Kind<>ptSymbol then Fail('expected tag name'); Name:=T.Text;
    for I:=1 to Length(Name) do if not (Name[I] in ['A'..'Z','a'..'z','0'..'9','_']) then Fail('invalid tag name');
    Next; if T.Kind<>ptString then Fail('expected quoted tag value'); Value:=T.Text;
    for Tag in Tags do if Tag.Name=Name then Fail('duplicate tag '+Name);
    SetLength(Tags,Length(Tags)+1); Tags[High(Tags)].Name:=Name; Tags[High(Tags)].Value:=Value;
    Next; if T.Kind<>ptTagClose then Fail('expected closing tag bracket'); Next;
  end;
  Fen:=GameFileTagValue(Tags,'FEN',''); Setup:=GameFileTagValue(Tags,'SetUp','0');
  if not ((Setup='0') or (Setup='1')) then Fail('SetUp must be 0 or 1');
  if ((Setup='1') and (Fen='')) or ((Fen<>'') and (Setup<>'1')) then Fail('FEN requires SetUp "1"');
  if Fen='' then Fen:=A.GameTree.Variant.DefaultStartingFEN;
  try Posn:=A.GameTree.Variant.CreatePositionFromFEN(Fen);
  except on E:Exception do begin Fail('invalid FEN: '+E.Message); Exit; end; end;
  try
    Inc(ImportSequence);
    Header:=GameTreeHeaderInput('pgn:'+IntToStr(ImportSequence),GameFileTagValue(Tags,'Event','?'),
      GameFileTagValue(Tags,'White','?'),GameFileTagValue(Tags,'Black','?'),
      GameFileTagValue(Tags,'Result','*'),Posn.ToFEN,False,DefaultTimeControl);
    if not ((Header.ResultText='*') or (Header.ResultText='1-0') or (Header.ResultText='0-1') or
      (Header.ResultText='1/2-1/2')) then Fail('invalid Result tag');
    for Tag in Tags do if (Tag.Name<>'Event') and (Tag.Name<>'White') and (Tag.Name<>'Black') and
      (Tag.Name<>'Result') and (Tag.Name<>'FEN') and (Tag.Name<>'SetUp') then begin
      SetLength(Header.ExtraTags,Length(Header.ExtraTags)+1); Header.ExtraTags[High(Header.ExtraTags)]:=Tag;
    end;
    Execute(A.CreateRebuildFromInputsCommand(Header,GameTreeMainlineInput(nil,nil,False,0,0,0,0),
      GameTreePvInput(False,0,'',''),GameTreePvInput(False,0,'','')));
    Line(A.GameTree.Root,Posn,0);
    if T.Kind<>ptResult then Fail('missing game termination marker');
    if GameFileTagValue(Tags,'Result',T.Text)<>T.Text then Fail('Result tag and termination marker disagree');
    Header.ResultText:=T.Text; Execute(A.CreateSetHeaderCommand(Header)); Next;
    // Post-result comments belong to the next game or are ignored by collections.
    while T.Kind=ptComment do Next;
    if T.Kind<>ptEnd then Fail('unexpected data after game result');
  finally Posn.Free; end;
end;
procedure TPgnParser.Line(Parent: TGameTreePlyNode; Position: TGamePosition; Depth: Integer);
var Node,Previous,Existing: TGameTreePlyNode; Before: TGamePosition;
  D: TGameTreeNodeData; Move,Caption,Leading: string; N: Byte;
  C: TGameTreeCommand; Id: Int64; Found,First,LastEp: Boolean; FromSq,ToSq: Integer;
begin
  Node:=Parent; Previous:=nil; Before:=nil; First:=True; LastEp:=False; Leading:='';
  try
    if Depth>128 then Fail('variation nesting exceeds 128');
    while not (T.Kind in [ptEnd,ptVariationClose,ptResult]) do begin
      case T.Kind of
        ptComment: begin
          D:=Node.NodeData;
          if First and (Depth>0) then begin
            D:=Default(TGameTreeNodeData); D.BeforeCommentText:=Leading;
            ReadPgnComment(T.Text,Position.SideToMove,D,True); Leading:=D.BeforeCommentText;
          end else begin ReadPgnComment(T.Text,Node.SideToMove,D); Store(Node,D); end;
          Next;
        end;
        ptInteger,ptPeriod: Next;
        ptNag: begin
          if First then Fail('NAG without a preceding move');
          D:=Node.NodeData; Found:=False;
          for N in D.Nags do if N=T.Nag then Found:=True;
          if not Found then begin SetLength(D.Nags,Length(D.Nags)+1); D.Nags[High(D.Nags)]:=T.Nag; Store(Node,D); end;
          Next;
        end;
        ptVariationOpen: begin
          if First or (Before=nil) then Fail('variation without a preceding move');
          Next; Line(Previous,Before.Clone,Depth+1);
          if T.Kind<>ptVariationClose then Fail('unterminated variation'); Next;
        end;
        ptSymbol: begin
          if T.Text='Z0' then Fail('null moves are not supported');
          if T.Text='e' then begin
            if not LastEp then Fail('e.p. suffix requires an en passant capture');
            Next; if T.Kind<>ptPeriod then Fail('expected e.p. suffix');
            Next; if (T.Kind<>ptSymbol) or (T.Text<>'p') then Fail('expected e.p. suffix');
            Next; if T.Kind<>ptPeriod then Fail('expected e.p. suffix'); Next; LastEp:=False; Continue;
          end;
          if not Position.TryParseMove(T.Text,Move) then Fail('illegal or unrecognized SAN move '+T.Text);
          Position.MoveSquares(Move,FromSq,ToSq);
          LastEp:=(Abs(TChessPosition(Position).PieceAt(FromSq))=1) and
            (FromSq mod 8<>ToSq mod 8) and (TChessPosition(Position).PieceAt(ToSq)=0);
          Caption:=Position.MoveNotation(Move); Existing:=A.GameTree.FindChildByMove(Node,Move);
          if Position.SideToMove=gsBlack then Caption:='... '+Caption else Caption:='. '+Caption;
          if (Existing<>nil) and (W<>nil) then W.Add('Repeated variation '+IntToStr(A.GameTree.Variant.StartingMoveNumberFromFEN(Position.ToFEN))+Caption+' merged');
          if Depth=0 then C:=A.CreateAppendMainlineMoveCommand(Move,gmsUnknown)
          else C:=A.CreateImportNodeCommand(Node.NodeId,Move,'');
          try
            A.ExecuteCommand(C); if not C.Accepted then Fail(C.ErrorText); Id:=C.CreatedNodeId;
          finally C.Free; end;
          Previous:=Node; Node:=A.GameTree.FindNodeById(Id);
          D:=Node.NodeData;
          if Leading<>'' then begin
            if D.BeforeCommentText<>'' then D.BeforeCommentText+=#10;
            D.BeforeCommentText+=Leading; Leading:='';
          end;
          // Inherit the other side's clock only; PGN clock commands describe
          // the side that just moved, never a game-running clock authority.
          if Existing=nil then begin
            D.WhiteRemainingSeconds:=Previous.NodeData.WhiteRemainingSeconds;
            D.BlackRemainingSeconds:=Previous.NodeData.BlackRemainingSeconds;
          end;
          Store(Node,D); FreeAndNil(Before); Before:=Position.Clone;
          Position.PlayMove(Move); First:=False; Next;
        end;
        else Fail('unexpected token '+T.Text);
      end;
    end;
    if (Depth>0) and First then Fail('empty variation');
  finally
    Before.Free;
    // Recursive calls own their position clone; the root position is caller-owned.
    if Depth>0 then Position.Free;
  end;
end;
procedure ParseText(const Text: string; Actor: TGameTreeActor; Warnings: TStrings);
var P: TPgnParser;
begin P:=TPgnParser.Create(Text,Actor,Warnings); try P.Parse; finally P.Free; end; end;
procedure ImportChessPgn(const Text: string; Actor: TGameTreeActor; Warnings: TStrings);
var Candidate: TGameTreeActor;
begin
  Candidate:=TGameTreeActor.Create(TGameTree.Create(Actor.GameTree.Variant),True);
  try ParseText(Text,Candidate,Warnings); finally Candidate.Free; end;
  ParseText(Text,Actor,nil);
end;
type
  TPgnEntry = class(TGameFileEntry)
    ValidatedDigest,TournamentId: string;
    IdentityHeaderValid: Boolean;
    FileName: string; Offset,Size: Int64; Variant: TGameVariant;
    function Text: string;
    procedure Validate; override;
    procedure ImportInto(Actor: TGameTreeActor); override;
  end;
function TPgnEntry.Text: string;
var F: TFileStream;
begin
  if (Size<0) or (Size>MaxPgnGameBytes) then raise EPgnSyntaxError.Create('PGN game exceeds 16 MiB limit');
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try F.Position:=Offset; SetLength(Result,Size); if Size>0 then F.ReadBuffer(Result[1],Size); finally F.Free; end;
end;
procedure TPgnEntry.Validate;
var Actor: TGameTreeActor; W: TStringList; S: string;
begin
  if not Deferred then Exit;
  W:=TStringList.Create; Actor:=TGameTreeActor.Create(TGameTree.Create(Variant),True);
  try
    try S:=Text; ParseText(S,Actor,W); ValidatedDigest:=SHA1Print(SHA1String(S));
    except on E:Exception do ErrorText:=E.Message; end;
    WarningsText:=W.Text; Deferred:=False;
  finally Actor.Free; W.Free; end;
end;
procedure TPgnEntry.ImportInto(Actor: TGameTreeActor);
var W: TStringList; S: string;
begin
  S:=Text; W:=TStringList.Create;
  try
    if (ValidatedDigest<>'') and (ValidatedDigest=SHA1Print(SHA1String(S))) and
      (Actor.GameTree.Variant=Variant) then
      // The same immutable bytes already passed a complete candidate parse.
      // Replay can only fail on an internal inconsistency/allocation failure.
      ParseText(S,Actor,nil)
    else begin ImportChessPgn(S,Actor,W); WarningsText:=W.Text; end;
  finally W.Free; end;
end;
constructor TChessPgnReader.Create(AVariant: TGameVariant);
begin inherited Create; FVariant:=AVariant; end;
procedure TChessPgnReader.OpenFile(const FileName: string);
var F: TFileStream; Buffer: array[0..65535] of Byte; Count,I,Depth: Integer;
  Posn,Start: Int64; C: Char; HeaderBytes,Symbol: string;
  Brace,Quote,Escape,LineComment,Tag,ColumnOne,Body,HadTag: Boolean;
  procedure Reset;
  begin
    HeaderBytes:=''; Symbol:=''; Depth:=0;
    Brace:=False; Quote:=False; Escape:=False; LineComment:=False;
    Tag:=False; ColumnOne:=True; Body:=False; HadTag:=False;
  end;
  procedure Finish;
  var Entry: TPgnEntry; L: TChessPgnLexer; T: TPgnToken; Name: string; Converted: Boolean; Seen:TStringList;
  begin
    if not (Body or HadTag) then begin Start:=Posn; Reset; Exit; end;
    Entry:=TPgnEntry.Create; Entry.FileName:=FileName; Entry.Offset:=Start; Entry.Size:=Posn-Start;
    Entry.Variant:=FVariant; Entry.Deferred:=True; Entry.WhiteName:='?'; Entry.BlackName:='?'; Entry.EventName:='?'; Entry.ResultText:='*';
    // Only the bounded header prefix is decoded/lexed for listing. Move bytes
    // remain in the file and are read for the selected entry alone.
    L:=TChessPgnLexer.Create(PgnWhitespace(PgnUtf8(HeaderBytes,Converted)));
    Seen:=TStringList.Create;
    try
      try
        T:=L.NextToken;
        while T.Kind=ptComment do T:=L.NextToken;
        while T.Kind=ptTagOpen do begin
          T:=L.NextToken; if T.Kind<>ptSymbol then raise EPgnSyntaxError.Create('Invalid PGN header name');
          Name:=T.Text;
          if Seen.IndexOf(Name)>=0 then raise EPgnSyntaxError.Create('Duplicate PGN header');Seen.Add(Name);
          T:=L.NextToken;
          if T.Kind<>ptString then raise EPgnSyntaxError.Create('Invalid PGN header value');
          if Name='White' then Entry.WhiteName:=T.Text else if Name='Black' then Entry.BlackName:=T.Text
          else if Name='Event' then Entry.EventName:=T.Text else if Name='Result' then Entry.ResultText:=T.Text
          else if Name='TournamentId' then Entry.TournamentId:=T.Text;
          T:=L.NextToken; if T.Kind<>ptTagClose then raise EPgnSyntaxError.Create('Unclosed PGN header'); T:=L.NextToken;
        end;
        Entry.IdentityHeaderValid:=Body and (Length(HeaderBytes)<1024*1024) and (Seen.Count>0);
      except on E:EPgnSyntaxError do Entry.WarningsText:=E.Message; end;
    finally Seen.Free;L.Free; end;
    Entries.Add(Entry); Start:=Posn; Reset;
  end;
  function StartsTagLine: Boolean;
  var Saved,At: Int64; Ch: Char; HaveName: Boolean;
  begin
    Result:=False; Saved:=F.Position; At:=Posn+1; HaveName:=False;
    try
      F.Position:=At;
      while F.Read(Ch,1)=1 do begin
        if Ch in ['a'..'z','A'..'Z','0'..'9','_'] then HaveName:=True
        else begin
          if not HaveName then Exit;
          while Ch in [' ',#9] do if F.Read(Ch,1)<>1 then Exit;
          Result:=Ch='"'; Exit;
        end;
      end;
    finally F.Position:=Saved; end;
  end;
  function IsResult: Boolean;
  begin Result:=(Symbol='*') or (Symbol='1-0') or (Symbol='0-1') or (Symbol='1/2-1/2'); end;
begin
  Entries.Clear; Start:=0; Posn:=0; Reset;
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    repeat
      Count:=F.Read(Buffer,SizeOf(Buffer));
      for I:=0 to Count-1 do begin
        C:=Chr(Buffer[I]);
        // A fresh tag line is the collection recovery boundary, even when
        // the preceding entry has an unclosed comment/string/variation.
        if (C='[') and ColumnOne and Body and StartsTagLine then Finish
        else if not Brace and not Quote and not LineComment and not Tag and (Depth=0) and
          not (C in ['0'..'9','a'..'z','A'..'Z','/','-','*']) and IsResult then Finish;
        Inc(Posn);
        if not Body and (Length(HeaderBytes)<1024*1024) then HeaderBytes+=C;
        if (Posn=3) and (HeaderBytes=#$EF#$BB#$BF) then begin ColumnOne:=True; Continue; end;
        if LineComment then begin if C in [#10,#13] then LineComment:=False; end
        else if Brace then begin if C='}' then Brace:=False; end
        else if Quote then begin
          if Escape then Escape:=False else if C='\' then Escape:=True else if C='"' then Quote:=False;
        end else case C of
          '{':Brace:=True; ';':LineComment:=True;
          '%':if ColumnOne then LineComment:=True;
          '"':Quote:=True; '[':begin Tag:=True; HadTag:=True; end; ']':Tag:=False;
          '(':begin Inc(Depth); Body:=True; end; ')':begin Dec(Depth); Body:=True; end;
          else if not Tag then begin
            if C in ['0'..'9','a'..'z','A'..'Z','/','-','*'] then begin
              if Length(Symbol)<16 then Symbol+=C;
              Body:=True;
            end else Symbol:='';
          end;
        end;
        ColumnOne:=C in [#10,#13];
      end;
    until Count=0;
    Finish;
  finally F.Free; end;
end;
function PgnTournamentFileMatchesId(const FileName,Id:string):Boolean;
var Reader:TChessPgnReader;I:Integer;Entry:TPgnEntry;
begin
 Result:=False;if Id='' then Exit;
 Reader:=TChessPgnReader.Create(nil);
 try
  try
   Reader.OpenFile(FileName);if Reader.Entries.Count=0 then Exit;
   for I:=0 to Reader.Entries.Count-1 do begin
    Entry:=TPgnEntry(Reader.Entries[I]);
    if not Entry.IdentityHeaderValid or (Entry.TournamentId<>Id) then Exit;
   end;
   Result:=True;
  except Result:=False;end;
 finally Reader.Free;end;
end;
end.
