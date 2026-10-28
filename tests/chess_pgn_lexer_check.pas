program chess_pgn_lexer_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, uChessPgnLexer;
var Checks: Integer=0;
procedure Check(Value: Boolean; const MessageText: string);
begin Inc(Checks); if not Value then raise Exception.Create(MessageText); end;
procedure CheckTokens;
var L: TChessPgnLexer; T: TPgnToken;
  procedure Expect(Kind: TPgnTokenKind; const Text: string; Nag: Integer=-1);
  begin
    T:=L.NextToken;
    Check(T.Kind=Kind,'Token kind for '+Text);
    Check(T.Text=Text,'Token spelling '+Text+' got '+T.Text);
    Check(T.Nag=Nag,'NAG value '+Text);
  end;
begin
  L:=TChessPgnLexer.Create(#$EF#$BB#$BF+'% private escape'+#13#10+'[Event "BOM"]');
  try
    Expect(ptTagOpen,'['); Check((T.Line=2) and (T.Column=1) and (T.Offset>3),'BOM/CRLF source location');
    Expect(ptSymbol,'Event'); Expect(ptString,'BOM'); Expect(ptTagClose,']'); Expect(ptEnd,'');
  finally L.Free; end;
  L:=TChessPgnLexer.Create('[Event "A \"B\" \\ club"]');
  try
    Expect(ptTagOpen,'['); Expect(ptSymbol,'Event'); Expect(ptString,'A "B" \ club');
    Expect(ptTagClose,']'); Expect(ptEnd,''); Expect(ptEnd,'');
  finally L.Free; end;
  L:=TChessPgnLexer.Create('{initial'#13#10+'{literal; % }37...Ke7!? (37... Kf7 $146 {branch}) 38.Ra7+ ;line {text}'+#10+
    'Ke6 $0 $255 1/2-1/2 [Result "*"] *');
  try
    Expect(ptComment,'initial'#13#10+'{literal; % ');
    Expect(ptInteger,'37'); Check((T.Line=2) and (T.Column=14),'Comment CRLF tracking');
    Expect(ptPeriod,'.'); Expect(ptPeriod,'.'); Expect(ptPeriod,'.'); Expect(ptSymbol,'Ke7'); Expect(ptNag,'!?',5);
    Expect(ptVariationOpen,'('); Expect(ptInteger,'37'); Expect(ptPeriod,'.'); Expect(ptPeriod,'.'); Expect(ptPeriod,'.');
    Expect(ptSymbol,'Kf7'); Expect(ptNag,'$146',146); Expect(ptComment,'branch'); Expect(ptVariationClose,')');
    Expect(ptInteger,'38'); Expect(ptPeriod,'.'); Expect(ptSymbol,'Ra7+'); Expect(ptComment,'line {text}');
    Expect(ptSymbol,'Ke6'); Check(T.Line=3,'Semicolon newline tracking');
    Expect(ptNag,'$0',0); Expect(ptNag,'$255',255); Expect(ptResult,'1/2-1/2');
    Expect(ptTagOpen,'['); Expect(ptSymbol,'Result'); Expect(ptString,'*'); Expect(ptTagClose,']');
    Expect(ptResult,'*'); Expect(ptEnd,'');
  finally L.Free; end;
  L:=TChessPgnLexer.Create('e4! e5? Nf3!! Nc6?? Bb5!? a6?! 1-0 0-1 * O-O O-O-O e8=Q# e7e8q');
  try
    Expect(ptSymbol,'e4'); Expect(ptNag,'!',1); Expect(ptSymbol,'e5'); Expect(ptNag,'?',2);
    Expect(ptSymbol,'Nf3'); Expect(ptNag,'!!',3); Expect(ptSymbol,'Nc6'); Expect(ptNag,'??',4);
    Expect(ptSymbol,'Bb5'); Expect(ptNag,'!?',5); Expect(ptSymbol,'a6'); Expect(ptNag,'?!',6);
    Expect(ptResult,'1-0'); Expect(ptResult,'0-1'); Expect(ptResult,'*');
    Expect(ptSymbol,'O-O'); Expect(ptSymbol,'O-O-O'); Expect(ptSymbol,'e8=Q#'); Expect(ptSymbol,'e7e8q'); Expect(ptEnd,'');
  finally L.Free; end;
  L:=TChessPgnLexer.Create('[White "José"] {文字}'+#13+'%ignore'+#13+'1.e4');
  try
    Expect(ptTagOpen,'['); Expect(ptSymbol,'White'); Expect(ptString,'José'); Expect(ptTagClose,']'); Expect(ptComment,'文字');
    Expect(ptInteger,'1'); Check((T.Line=3) and (T.Column=1),'CR-only lines'); Expect(ptPeriod,'.'); Expect(ptSymbol,'e4');
  finally L.Free; end;
  L:=TChessPgnLexer.Create('$000 < >');
  try
    Expect(ptNag,'$000',0); Expect(ptReserved,'<'); Expect(ptReserved,'>'); Expect(ptEnd,'');
  finally L.Free; end;
end;
procedure CheckErrors;
  procedure Bad(const Text: string; Limit: Integer=1024*1024);
  var L: TChessPgnLexer; T: TPgnToken; Raised: Boolean;
  begin
    L:=TChessPgnLexer.Create(Text,Limit); Raised:=False;
    try
      try
        repeat T:=L.NextToken until T.Kind=ptEnd;
      except on E:EPgnSyntaxError do
        begin Raised:=True; Check(Pos('line ',E.Message)>0,'Error has source location'); end;
      end;
      Check(Raised,'Malformed input rejected: '+Text);
    finally L.Free; end;
  end;
begin
  Bad('{unterminated'); Bad('"unterminated'); Bad('"bad\q"'); Bad('"line'+#10+'break"');
  Bad('$'); Bad('$-1'); Bad('$256'); Bad('$999999999999999999999999');
  Bad('e4!!!'); Bad(' %not-an-escape'); Bad('1/2-1/20'); Bad(#0); Bad('@');
  Bad('{12345}',4); Bad('"12345"',4); Bad('abcdef',4);
end;
procedure CheckProgress;
var L: TChessPgnLexer; T: TPgnToken; Text: string; I,J,N,LastOffset: Integer;
begin
  RandSeed:=20261028;
  for I:=1 to 500 do
  begin
    Text:='';
    for J:=1 to 200 do Text+=Chr(1+Random(126));
    L:=TChessPgnLexer.Create(Text);
    try
      N:=0; LastOffset:=0;
      try
        repeat
          T:=L.NextToken; Inc(N);
          Check(T.Offset>LastOffset,'Every token advances'); LastOffset:=T.Offset;
          Check(N<=Length(Text)+1,'Scanning is bounded');
        until T.Kind=ptEnd;
      except on E:EPgnSyntaxError do ; end;
    finally L.Free; end;
  end;
end;
begin
  CheckTokens; CheckErrors; CheckProgress;
  WriteLn('Chess PGN lexer checks passed (',Checks,' checks)');
end.
