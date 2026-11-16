unit uStartupCommand;
{$mode objfpc}{$H+}
interface
uses Classes;
type
  TStartupCommandKind=(sckNone,sckHelp,sckRunTournament);
  TStartupCommand=record
    Kind:TStartupCommandKind;
    FileName:string;
  end;
function ParseStartupCommand(Arguments:TStrings):TStartupCommand;
function StartupCommandHelp:string;
implementation
uses SysUtils,uCliErrors,uCliBinder,uCliCommand,uCliDefinitions;
function StartupCommandHelp:string;
begin
  Result:='ZGUI command-line help'+LineEnding+LineEnding+
    'zgui run_tournament file="tournament.json"'+LineEnding+
    'zgui run_tournament --file "tournament.json"'+LineEnding+
    'zgui run_tournament "tournament.json"'+LineEnding+
    'zgui --help'+LineEnding+'zgui help run_tournament'+LineEnding+LineEnding+
    'Open a saved chess or draughts tournament in a visible tab and press Play.'+LineEnding+
    'Existing results are preserved. Use Reschedule in the GUI to replay a game.'+LineEnding+
    'Relative paths use the launch directory. The GUI stays open after completion.'+LineEnding+
    'Only one startup command is accepted; there is no headless mode.';
end;
function ToolkitOption(const Token:string;out NeedsValue:Boolean):Boolean;
var Key:string;P:Integer;
begin
  P:=Pos('=',Token);Key:=Token;if P>0 then Key:=Copy(Token,1,P-1);
  { Only documented LCL/GTK options. Leave original argv untouched for LCL.
    A -- separator disables filtering so filenames stay literal. }
  NeedsValue:=(P=0) and ((Key='--debug-log') or (Key='--debug-enabled') or
    (Key='--display') or (Key='--gtk-module') or (Key='--name') or (Key='--class'));
  Result:=NeedsValue or (Key='--disableaccurateframe') or (Key='--sync') or
    (Key='--g-fatal-warnings') or (Key='--debug-log') or (Key='--debug-enabled') or
    (Key='--display') or (Key='--gtk-module') or (Key='--name') or (Key='--class');
  {$IFDEF DARWIN}Result:=Result or (Copy(Token,1,5)='-psn_');{$ENDIF}
end;
function ParseStartupCommand(Arguments:TStrings):TStartupCommand;
var Tokens:TStringList;I,Slot:Integer;NeedsValue,Literal,FilePending:Boolean;
  Spec:TCommandDefinition;Binder:TCommandBinder;Command:TCliCommand;Token:string;
begin
  Result:=Default(TStartupCommand);Tokens:=TStringList.Create;
  try
    I:=0;Literal:=False;FilePending:=False;
    while I<Arguments.Count do begin
      Token:=Arguments[I];
      if not Literal and not FilePending and ToolkitOption(Token,NeedsValue) then begin
        if NeedsValue then begin
          Inc(I);if I>=Arguments.Count then raise ECliError.Create('Missing value for '+Token);
        end;
      end else begin
        Tokens.Add(Token);
        if Token='--' then Literal:=True;
        if FilePending then FilePending:=False
        else FilePending:=not Literal and SameText(Token,'--file');
      end;
      Inc(I);
    end;
    if Tokens.Count=0 then Exit;
    Token:=LowerCase(Tokens[0]);
    if (Copy(Token,1,1)='-') and (Token<>'--help') and
      (Tokens.IndexOf('run_tournament')<0) and (Tokens.IndexOf('help')<0) then Exit;
    if (Token='--help') or (Token='help') then begin
      if (Tokens.Count>2) or ((Token='--help') and (Tokens.Count<>1)) or
        ((Tokens.Count=2) and not SameText(Tokens[1],'run_tournament')) then
        raise ECliError.Create('Use zgui help run_tournament or zgui --help');
      Result.Kind:=sckHelp;Exit;
    end;
    if Token<>'run_tournament' then raise ECliError.Create('Unknown command '+Tokens[0]+'. Use zgui --help');
    Spec:=TCommandDefinition.Create('run_tournament');
    try
      Spec.Arguments.Add(TParameterDefinition.Create('file',True));
      Binder:=TCommandBinder.Create(Spec,bmExecution);
      try
        for I:=1 to Tokens.Count-1 do Binder.Feed(Tokens[I]);
        Binder.FinishTokens;
        { SCU ParseCommand's non-interactive finalization, not just the binder. }
        for Slot:=0 to Binder.Count-1 do if not Binder.Supplied[Slot] then
          if Binder.ParameterAt(Slot).HasDefault then
            Binder.Bind(Slot,Binder.ParameterAt(Slot).DefaultValue,False)
          else if Binder.ParameterAt(Slot).Required then
            raise ECliError.Create('Missing required argument '+Binder.ParameterAt(Slot).Name);
        Command:=Binder.CreateCommand;
        try
          if Trim(Command['file'])='' then raise ECliError.Create('Tournament file must not be empty');
          Result.Kind:=sckRunTournament;Result.FileName:=ExpandFileName(Command['file']);
        finally Command.Free;end;
      finally Binder.Free;end;
    finally Spec.Free;end;
  finally Tokens.Free;end;
end;
end.
