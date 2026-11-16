program interactive_command_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uCliTokenizer,uCliErrors,uInteractiveProtocol;
var Checks:Integer;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Tokens(const Line:string;const Expected:array of string;Bad:Boolean=False);
var L:TStringList;I:Integer;Raised:Boolean;
begin
 L:=TStringList.Create;try
  Raised:=False;try TokenizeCommand(Line,L);except on E:ECliError do Raised:=True;end;
  Check(Raised=Bad,'Quote validation '+Line);
  if not Bad then begin Check(L.Count=Length(Expected),'Token count '+Line);for I:=0 to High(Expected) do Check(L[I]=Expected[I],'Token preserved '+Line);end;
 finally L.Free;end;
end;
begin
 Tokens('list_engines',['list_engines']);
 Tokens('run_tournament engine1="GWD multi-cut" ballot=C:\Matches\b.fen', ['run_tournament','engine1=GWD multi-cut','ballot=C:\Matches\b.fen']);
 Tokens('run_tournament ballot="C:\Matches\b.fen"',['run_tournament','ballot=C:\Matches\b.fen']);
 Tokens('run_tournament ballot=\\server\share\b.fen',['run_tournament','ballot=\\server\share\b.fen']);
 Tokens('run_tournament ballot=''\\server\share\b.fen''',['run_tournament','ballot=\\server\share\b.fen']);
 Tokens('run_tournament ballot="\\\\server\\share\\b.fen"',['run_tournament','ballot=\\server\share\b.fen']);
 Tokens('run_tournament name="a\"b"',['run_tournament','name=a"b']);
 Tokens('run_tournament name="Ö ♞"',['run_tournament','name=Ö ♞']);
 Tokens('run_tournament name=""',['run_tournament','name=']);
 Tokens('run_tournament name="unfinished',[],True);Tokens('run_tournament '+#0,[],True);
 Check(ValidCliUtf8('Ö ♞'),'Valid Unicode');Check(not ValidCliUtf8(#$C0#$80),'Reject overlong UTF-8');
 Check(not ValidCliUtf8(#$ED#$A0#$80),'Reject surrogate');Check(not ValidCliUtf8(#$F4#$90#$80#$80),'Reject out of Unicode range');
 WriteLn('Interactive command text checks passed: ',Checks);
end.
