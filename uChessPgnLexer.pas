unit uChessPgnLexer;
{$mode objfpc}{$H+}

{ Chess file syntax only. This scanner creates no game tree, game history or
  annotation cache. Tokens will feed the existing actor through the reviewed
  PGN adapter. Source locations are one-based byte columns (UTF-8 is retained).
  Grammar reference: PGN Specification, sections 5-7 and 8.2.3.8.
  https://www.saremba.de/chessgml/standards/pgn/pgn-complete.htm }
interface
uses SysUtils;
type
  EPgnSyntaxError = class(EConvertError);
  TPgnTokenKind = (ptEnd, ptSymbol, ptInteger, ptString, ptComment, ptNag,
    ptPeriod, ptTagOpen, ptTagClose, ptVariationOpen, ptVariationClose,
    ptResult, ptReserved);
  TPgnToken = record
    Kind: TPgnTokenKind;
    Text: string; // decoded strings; comment body; otherwise original spelling
    Line, Column, Offset: Integer;
    Nag: Integer; // 0..255 for ptNag; -1 otherwise
  end;
  TChessPgnLexer = class
  private
    FText: string;
    FOffset, FLine, FColumn, FMaxTokenBytes: Integer;
    function Peek: Char;
    procedure Advance;
    procedure SkipWhitespaceAndEscapes;
    procedure Error(const MessageText: string);
    procedure CheckSize(AStart: Integer);
    function ReadString: string;
  public
    constructor Create(const AText: string; AMaxTokenBytes: Integer = 1024*1024);
    function NextToken: TPgnToken;
  end;
implementation

constructor TChessPgnLexer.Create(const AText: string; AMaxTokenBytes: Integer);
begin
  inherited Create;
  if AMaxTokenBytes < 1 then raise EArgumentException.Create('PGN token limit must be positive');
  FText:=AText; FOffset:=1; FLine:=1; FColumn:=1; FMaxTokenBytes:=AMaxTokenBytes;
  // Modern PGN files commonly use UTF-8, optionally with a leading BOM.
  if Copy(FText,1,3)=#$EF#$BB#$BF then FOffset:=4;
end;
function TChessPgnLexer.Peek: Char;
begin
  if FOffset>Length(FText) then Result:=#0 else Result:=FText[FOffset];
end;
procedure TChessPgnLexer.Advance;
begin
  if FOffset>Length(FText) then Exit;
  if FText[FOffset]=#13 then
  begin
    Inc(FOffset);
    if (FOffset<=Length(FText)) and (FText[FOffset]=#10) then Inc(FOffset);
    Inc(FLine); FColumn:=1;
  end
  else
  begin
    if FText[FOffset]=#10 then begin Inc(FLine); FColumn:=1; end
    else Inc(FColumn);
    Inc(FOffset);
  end;
end;
procedure TChessPgnLexer.Error(const MessageText: string);
begin
  raise EPgnSyntaxError.CreateFmt('PGN line %d, column %d: %s',[FLine,FColumn,MessageText]);
end;
procedure TChessPgnLexer.CheckSize(AStart: Integer);
begin
  if FOffset-AStart>FMaxTokenBytes then Error('token exceeds configured byte limit');
end;
procedure TChessPgnLexer.SkipWhitespaceAndEscapes;
begin
  while FOffset<=Length(FText) do
    if Peek in [' ',#9,#10,#11,#12,#13] then Advance
    else if (Peek='%') and (FColumn=1) then
    begin
      while (FOffset<=Length(FText)) and not (Peek in [#10,#13]) do Advance;
    end
    else Break;
end;
function TChessPgnLexer.ReadString: string;
var Start,I,N: Integer; Raw: string;
begin
  Advance; Start:=FOffset;
  while True do
  begin
    if FOffset>Length(FText) then Error('unterminated tag string');
    if Ord(Peek)<32 then Error('control character in tag string');
    if Peek='"' then Break;
    if Peek='\' then
    begin
      Advance;
      if not (Peek in ['"','\']) then Error('invalid tag-string escape');
    end;
    Advance; CheckSize(Start);
  end;
  Raw:=Copy(FText,Start,FOffset-Start); Advance;
  SetLength(Result,Length(Raw)); I:=1; N:=0;
  while I<=Length(Raw) do
  begin
    if Raw[I]='\' then Inc(I);
    Inc(N); Result[N]:=Raw[I]; Inc(I);
  end;
  SetLength(Result,N);
end;
function TChessPgnLexer.NextToken: TPgnToken;
var Start,N,I: Integer; DigitsOnly: Boolean;
begin
  SkipWhitespaceAndEscapes;
  Result:=Default(TPgnToken); Result.Nag:=-1;
  Result.Offset:=FOffset; Result.Line:=FLine; Result.Column:=FColumn;
  if FOffset>Length(FText) then begin Result.Kind:=ptEnd; Exit; end;
  Start:=FOffset;
  if Copy(FText,FOffset,2)='--' then Error('null moves are not supported');
  case Peek of
    '[': begin Result.Kind:=ptTagOpen; Advance; end;
    ']': begin Result.Kind:=ptTagClose; Advance; end;
    '(': begin Result.Kind:=ptVariationOpen; Advance; end;
    ')': begin Result.Kind:=ptVariationClose; Advance; end;
    '.': begin Result.Kind:=ptPeriod; Advance; end;
    '<','>': begin Result.Kind:=ptReserved; Advance; end;
    '*': begin Result.Kind:=ptResult; Advance; end;
    '"': begin Result.Kind:=ptString; Result.Text:=ReadString; Exit; end;
    '{': begin
      Result.Kind:=ptComment; Advance; Start:=FOffset;
      // Braces do not nest; punctuation inside a brace comment is ordinary text.
      while (FOffset<=Length(FText)) and (Peek<>'}') do begin Advance; CheckSize(Start); end;
      if FOffset>Length(FText) then Error('unterminated brace comment');
      Result.Text:=Copy(FText,Start,FOffset-Start); Advance; Exit;
    end;
    ';': begin
      Result.Kind:=ptComment; Advance; Start:=FOffset;
      while (FOffset<=Length(FText)) and not (Peek in [#10,#13]) do begin Advance; CheckSize(Start); end;
      Result.Text:=Copy(FText,Start,FOffset-Start); Exit;
    end;
    '$': begin
      Result.Kind:=ptNag; Advance;
      if not (Peek in ['0'..'9']) then Error('NAG requires digits');
      N:=0;
      while Peek in ['0'..'9'] do
      begin
        N:=N*10+Ord(Peek)-Ord('0');
        if N>255 then Error('NAG outside 0..255');
        Advance; CheckSize(Start);
      end;
      Result.Nag:=N;
    end;
    '!','?': begin
      Result.Kind:=ptNag;
      while Peek in ['!','?'] do begin Advance; CheckSize(Start); end;
      Result.Text:=Copy(FText,Start,FOffset-Start);
      if Result.Text='!' then Result.Nag:=1
      else if Result.Text='?' then Result.Nag:=2
      else if Result.Text='!!' then Result.Nag:=3
      else if Result.Text='??' then Result.Nag:=4
      else if Result.Text='!?' then Result.Nag:=5
      else if Result.Text='?!' then Result.Nag:=6
      else Error('invalid move suffix annotation');
      Exit;
    end;
    'a'..'z','A'..'Z','0'..'9': begin
      while Peek in ['a'..'z','A'..'Z','0'..'9','_','+','#','=',':','-','/'] do
      begin Advance; CheckSize(Start); end;
      Result.Text:=Copy(FText,Start,FOffset-Start);
      if (Result.Text='1-0') or (Result.Text='0-1') or (Result.Text='1/2-1/2') then
        Result.Kind:=ptResult
      else
      begin
        if Pos('/',Result.Text)>0 then Error('unexpected slash in symbol');
        DigitsOnly:=True;
        for I:=1 to Length(Result.Text) do
          if not (Result.Text[I] in ['0'..'9']) then begin DigitsOnly:=False; Break; end;
        if DigitsOnly then Result.Kind:=ptInteger else Result.Kind:=ptSymbol;
      end;
      Exit;
    end;
    else Error('unexpected character byte '+IntToStr(Ord(Peek)));
  end;
  Result.Text:=Copy(FText,Start,FOffset-Start);
end;
end.
