program startup_command_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uStartupCommand,uCliErrors;
var Checks:Integer;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure CaseOf(const Args:array of string;Kind:TStartupCommandKind;const FileName:string='';Bad:Boolean=False);
var L:TStringList;R:TStartupCommand;I:Integer;Raised:Boolean;
begin
 L:=TStringList.Create;
 try
  for I:=0 to High(Args) do L.Add(Args[I]);Raised:=False;
  try R:=ParseStartupCommand(L);except on E:ECliError do Raised:=True;end;
  Check(Raised=Bad,'Parse '+L.CommaText);
  if not Bad then begin
   Check(R.Kind=Kind,'Kind '+L.CommaText);
   if Kind=sckRunTournament then Check(R.FileName=ExpandFileName(FileName),'File preserved '+FileName);
  end;
 finally L.Free;end;
end;
procedure MissingValue;
var L:TStringList;I:Integer;R:TStartupCommand;
begin
 L:=TStringList.Create;
 try
  for I:=0 to 1 do begin
   L.Clear;L.Add('run_tournament');L.Add('--file');if I=1 then L.Add('--debug-log');
   try R:=ParseStartupCommand(L);Check(False,'Missing value refused');
   except on E:ECliError do Check(E.Message='Expected a value for --file.','Missing option value names its option');end;
  end;
 finally L.Free;end;
end;
begin
 CaseOf(['--cli'],sckInteractive);
 CaseOf(['--debug-log=x','--cli','--disableaccurateframe'],sckInteractive);
 CaseOf(['--cli','run_tournament','a.json'],sckNone,'',True);
 CaseOf(['run_tournament','a.json','--cli'],sckNone,'',True);
 CaseOf(['--cli','--help'],sckNone,'',True);
 CaseOf(['--unknown','--cli'],sckNone,'',True);
 CaseOf([],sckNone);CaseOf(['--debug-log=x'],sckNone);
 CaseOf(['--disableaccurateframe'],sckNone);CaseOf(['--some-widget-option'],sckNone);
 CaseOf(['--help'],sckHelp);CaseOf(['help','run_tournament'],sckHelp);
 CaseOf(['run_tournament','a.json'],sckRunTournament,'a.json');
 CaseOf(['run_tournament','file=a b.json'],sckRunTournament,'a b.json');
 CaseOf(['run_tournament','--file=a.json'],sckRunTournament,'a.json');
 CaseOf(['run_tournament','--file','a.json'],sckRunTournament,'a.json');
 CaseOf(['run_tournament','--','file=literal.json'],sckRunTournament,'file=literal.json');
 CaseOf(['run_tournament','--file','C:\Tournaments\Kampioen Ö.json'],sckRunTournament,'C:\Tournaments\Kampioen Ö.json');
 CaseOf(['run_tournament','file=\\server\share\a.json'],sckRunTournament,'\\server\share\a.json');
 CaseOf(['--debug-log=x','run_tournament','x.json','--disableaccurateframe'],sckRunTournament,'x.json');
 CaseOf(['run_tournament','x.json','--debug-log','y'],sckRunTournament,'x.json');
 CaseOf(['run_tournament','--file','--debug-log=x'],sckRunTournament,'',True);
 CaseOf(['run_tournament','--','--debug-log=x'],sckRunTournament,'--debug-log=x');
 CaseOf(['run_tournament'],sckNone,'',True);
 CaseOf(['run_tournament','file='],sckNone,'',True);
 CaseOf(['run_tournament','--file'],sckNone,'',True);
 CaseOf(['run_tournament','--file='],sckNone,'',True);
 CaseOf(['run_tournament','a','b'],sckNone,'',True);
 CaseOf(['run_tournament','file=a','--file=b'],sckNone,'',True);
 CaseOf(['run_tournament','fil=a'],sckNone,'',True);
 CaseOf(['run_tournament','--nonsense'],sckNone,'',True);
 CaseOf(['run_tournment','a'],sckNone,'',True);
 CaseOf(['help','bogus'],sckNone,'',True);
 CaseOf(['--help','a'],sckNone,'',True);
 MissingValue;
 WriteLn('Startup parser checks passed: ',Checks);
end.
