unit uInteractiveCommands;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,FPJSON,uTournamentHostForm,uTournamentDialog;
type
  TCliTournamentEvent=procedure(Dialog:TTournamentDialog) of object;
  { GUI-thread-only adapter. Tournament state stays in the real host/dialog. }
  TInteractiveCommands=class
  private type
    TBinding=record TabId:PtrInt;Uuid,Engine1,Engine2:string;end;
  private
    FHost:TTournamentHostForm;
    FBaseDirectory:string;
    FEngineKeys:TStringList;
    FBindings:array of TBinding;
    FExecuting:Boolean;
    FOnTournament:TCliTournamentEvent;
    function EngineId(const Key:string):Integer;
  public
    constructor Create(Host:TTournamentHostForm;const BaseDirectory:string='');
    destructor Destroy;override;
    function Execute(const Line:string):string;
    property OnTournament:TCliTournamentEvent read FOnTournament write FOnTournament;
  end;
function CliError(const Code,MessageText:string;const Command:string=''):string;
implementation
uses uTimeForfeit,Forms,Math,uCliCommand,uCliDefinitions,uCliBinder,uCliTokenizer,uEngineRegistry,
 uGamePosition,uGameGuiProfile,LazFileUtils;
type ECliRequest=class(Exception)
  Code:string;
  constructor Create(const ACode,AMessage:string);
end;
constructor ECliRequest.Create(const ACode,AMessage:string);
begin inherited Create(AMessage);Code:=ACode;end;
procedure Fail(const Code,Text:string);
begin raise ECliRequest.Create(Code,Text);end;
function CliError(const Code,MessageText:string;const Command:string):string;
var J:TJSONObject;
begin
 J:=TJSONObject.Create;
 try J.Add('code',Code);J.Add('message',MessageText);J.Add('command',Command);Result:='ERROR '+J.AsJSON;
 finally J.Free;end;
end;
constructor TInteractiveCommands.Create(Host:TTournamentHostForm;const BaseDirectory:string);
begin
 inherited Create;FHost:=Host;FEngineKeys:=TStringList.Create;
 if BaseDirectory='' then FBaseDirectory:=GetCurrentDir else FBaseDirectory:=ExpandFileName(BaseDirectory);
end;
destructor TInteractiveCommands.Destroy;
begin FEngineKeys.Free;inherited Destroy;end;
function TInteractiveCommands.EngineId(const Key:string):Integer;
begin
 Result:=FEngineKeys.IndexOf(Key);if Result<0 then Result:=FEngineKeys.Add(Key);Inc(Result);
end;
function TInteractiveCommands.Execute(const Line:string):string;
var Tokens:TStringList;Spec:TCommandDefinition;Binder:TCommandBinder;Cmd:TCliCommand;
 Engines:TExternalEngineList;J,Item:TJSONObject;Items:TJSONArray;Name,Msg,Key,Phase:string;
 D:TTournamentDialog;Settings:TTournamentMatchSettings;A,B:TExternalEngineDefinition;
 I,N,Id,BindIndex:Integer;Started:TTournamentStartResult;AllowShared,IncludePairs,IncludeSprt:Boolean;V:TGameVariant;
 function Number(const Param:string):Double;
 var FS:TFormatSettings;
 begin
   FS:=DefaultFormatSettings;FS.DecimalSeparator:='.';FS.ThousandSeparator:=#0;
   if not TryStrToFloat(Cmd[Param],Result,FS) or IsNan(Result) or IsInfinite(Result) then Fail('BAD_ARGUMENT',Param+' requires a finite decimal number');
 end;
 function IntegerValue(const Param:string):Integer;
 var Value:Int64;X:Integer;
 begin
   if Cmd[Param]='' then Fail('BAD_ARGUMENT',Param+' requires a nonnegative integer');
   for X:=1 to Length(Cmd[Param]) do if not (Cmd[Param][X] in ['0'..'9']) then Fail('BAD_ARGUMENT',Param+' requires decimal digits');
   if not TryStrToInt64(Cmd[Param],Value) or (Value<0) or (Value>High(Integer)) then Fail('BAD_ARGUMENT',Param+' requires a nonnegative integer');
   Result:=Value;
 end;
 function Resolve(const Prefix:string):TExternalEngineDefinition;
 var K,C,Idx:Integer;Selector,Identity:string;
 begin
   C:=Ord(Cmd.HasArgument(Prefix))+Ord(Cmd.HasArgument(Prefix+'_id'))+Ord(Cmd.HasArgument(Prefix+'_key'));
   if C<>1 then Fail('BAD_ARGUMENT','Supply exactly one '+Prefix+', '+Prefix+'_id or '+Prefix+'_key');
   Result:=nil;
   if Cmd.HasArgument(Prefix+'_id') then begin
     Idx:=IntegerValue(Prefix+'_id');
     if (Idx<1) or (Idx>FEngineKeys.Count) then Fail('UNKNOWN_ENGINE','Unknown engine ID');
     Identity:=FEngineKeys[Idx-1];
   end else Identity:=Cmd.Argument(Prefix+'_key');
   if Identity<>'' then begin
     for K:=0 to Engines.Count-1 do if EngineIdentityKey(Engines[K])=Identity then Exit(Engines[K]);
   end else begin
     Selector:=Cmd.Argument(Prefix);if Selector='' then Fail('BAD_ARGUMENT','Empty engine selector');
     for K:=0 to Engines.Count-1 do if SameText(Engines[K].IdText,Selector) then begin
       if Result<>nil then Fail('AMBIGUOUS_ENGINE','Engine name is ambiguous; use an ID or key');Result:=Engines[K];
     end;
     if Result=nil then Fail('UNKNOWN_ENGINE','No engine named "'+Selector+'" (see list_engines)');
   end;
   if Result=nil then Fail('UNKNOWN_ENGINE','Engine registration no longer exists');
 end;
 procedure AddParams(const Names:array of string);
 var X:Integer;
 begin for X:=0 to High(Names) do Spec.Arguments.Add(TParameterDefinition.Create(Names[X],False));end;
 function BindDialog(Dialog:TTournamentDialog):Integer;
 var X:Integer;
 begin
   for X:=0 to High(FBindings) do if (FBindings[X].TabId=FHost.SessionTabId(Dialog)) and
     (FBindings[X].Uuid=Dialog.TournamentIdentity) then Exit(X+1);
   X:=Length(FBindings);SetLength(FBindings,X+1);FBindings[X].TabId:=FHost.SessionTabId(Dialog);
   FBindings[X].Uuid:=Dialog.TournamentIdentity;FBindings[X].Engine1:=Settings.Engine1Key;
   FBindings[X].Engine2:=Settings.Engine2Key;Result:=X+1;
 end;
begin
 if (Application.ModalLevel>0) or FExecuting or FHost.IsBusy then Exit(CliError('BUSY','GUI is busy with another operation'));
 FExecuting:=True;Name:='';Tokens:=TStringList.Create;Spec:=nil;Binder:=nil;Cmd:=nil;Engines:=nil;J:=nil;D:=nil;
 try
  try
   TokenizeCommand(Line,Tokens);if Tokens.Count=0 then Fail('BAD_ARGUMENT','Empty command');
   Name:=LowerCase(Tokens[0]);Spec:=TCommandDefinition.Create(Name);
   if Name='run_tournament' then AddParams(['engine1','engine2','engine1_id','engine2_id','engine1_key','engine2_key',
      'name','ballot','shuffle_opening_pairs','time','moves','increment','concurrent','allow_shared_executable',
      'time_forfeit','time_forfeit_id','time_forfeit_key','adjudication_time','adjudication_threshold'])
   else if (Name='query_tournament') or (Name='stop_tournament') then begin
     Spec.Arguments.Add(TParameterDefinition.Create('id',True));
     if Name='query_tournament' then AddParams(['pairs','sprt']);
   end
   else if Name<>'list_engines' then Fail('BAD_ARGUMENT','Unknown interactive command: '+Name);
   Binder:=TCommandBinder.Create(Spec,bmExecution);
   for I:=1 to Tokens.Count-1 do Binder.Feed(Tokens[I]);Binder.FinishTokens;
   for I:=0 to Binder.Count-1 do if not Binder.Supplied[I] and Binder.ParameterAt(I).Required then
     Fail('BAD_ARGUMENT','Missing required argument '+Binder.ParameterAt(I).Name);
   Cmd:=Binder.CreateCommand;J:=TJSONObject.Create;J.Add('command',Name);
   IncludePairs:=False;IncludeSprt:=False;
   if (Name='query_tournament') and Cmd.HasArgument('pairs') then begin
     Msg:=LowerCase(Cmd['pairs']);
     if (Msg<>'true') and (Msg<>'false') then Fail('BAD_ARGUMENT','pairs requires true or false');
     IncludePairs:=Msg='true';
   end;
   if (Name='query_tournament') and Cmd.HasArgument('sprt') then begin
     Msg:=LowerCase(Cmd['sprt']);
     if (Msg<>'true') and (Msg<>'false') then Fail('BAD_ARGUMENT','sprt requires true or false');
     IncludeSprt:=Msg='true';
   end;
   if Name='list_engines' then begin
     Engines:=TExternalEngineList.Create;LoadExternalEngines(EnginesJsonFileName,Engines);
     Items:=TJSONArray.Create;J.Add('engines',Items);
     for I:=0 to Engines.Count-1 do begin
       A:=Engines[I];Key:=EngineIdentityKey(A);Id:=EngineId(Key);Item:=TJSONObject.Create;Items.Add(Item);
       Item.Add('id',Id);Item.Add('key',Key);Item.Add('name',A.IdText);Item.Add('protocol',A.KindText);
       if A.Kind=eekUci then Item.Add('game','chess') else Item.Add('game','draughts');
       Msg:=EngineExecutableProblem(A);Item.Add('available',Msg='');Item.Add('error',Msg);
     end;
   end else if (Name='query_tournament') or (Name='stop_tournament') then begin
     Id:=IntegerValue('id');if (Id<1) or (Id>Length(FBindings)) then Fail('UNKNOWN_TOURNAMENT','Unknown tournament ID');
     BindIndex:=Id-1;D:=FHost.DialogById(FBindings[BindIndex].TabId);
     if D=nil then Fail('UNKNOWN_TOURNAMENT','Tournament tab is closed');
     if D.TournamentIdentity<>FBindings[BindIndex].Uuid then Fail('TOURNAMENT_REPLACED','Tournament tab contains a different event');
     if Name='stop_tournament' then begin
       // Stopping needs the same live tab/event, not an unchanged match shape.
       // The GUI button and CLI share the entire existing asynchronous stop path.
       D.StopTournament;J.Add('tournament',Id);
     end else begin
       try Item:=D.MatchSnapshot(FBindings[BindIndex].Engine1,FBindings[BindIndex].Engine2,IncludePairs);
       except on E:Exception do Fail('MATCH_CHANGED',E.Message);end;
       if IncludeSprt then Item.Add('sprt',D.SprtSnapshot);
       J.Free;J:=Item;J.Add('command',Name);J.Add('tournament',Id);
     end;
   end else begin
     Engines:=TExternalEngineList.Create;LoadExternalEngines(EnginesJsonFileName,Engines);
     A:=Resolve('engine1');B:=Resolve('engine2');
     if EngineIdentityKey(A)=EngineIdentityKey(B) then Fail('BAD_ARGUMENT','Choose distinct engine registrations');
     if (A.Kind=eekUci)<>(B.Kind=eekUci) then Fail('GAME_MISMATCH','Engines belong to different games');
     if A.Kind=eekUci then V:=GameVariantById('chess') else V:=GameVariantById('draughts');
     Settings:=Default(TTournamentMatchSettings);Settings.Engine1Key:=EngineIdentityKey(A);Settings.Engine2Key:=EngineIdentityKey(B);
     Settings.Name:=Cmd.Argument('name');Settings.Ballot:=Cmd.Argument('ballot');
     if Cmd.HasArgument('ballot') and (Trim(Settings.Ballot)='') then
       Fail('BAD_ARGUMENT','ballot requires a nonempty filename');
     if (Settings.Ballot<>'') and not FilenameIsAbsolute(Settings.Ballot) then
       Settings.Ballot:=ExpandFileName(IncludeTrailingPathDelimiter(FBaseDirectory)+Settings.Ballot);
     if Cmd.HasArgument('shuffle_opening_pairs') then begin
       Msg:=LowerCase(Cmd['shuffle_opening_pairs']);
       if (Msg<>'true') and (Msg<>'false') then Fail('BAD_ARGUMENT','shuffle_opening_pairs requires true or false');
       Settings.ShuffleOpeningPairs:=Msg='true';
       if Settings.ShuffleOpeningPairs and (Settings.Ballot='') then Fail('BAD_ARGUMENT','shuffle_opening_pairs=true requires a ballot');
     end;
     Settings.HasTime:=Cmd.HasArgument('time');if Settings.HasTime then Settings.Seconds:=Number('time');
     Settings.HasMoves:=Cmd.HasArgument('moves');if Settings.HasMoves then Settings.Moves:=IntegerValue('moves');
     Settings.HasIncrement:=Cmd.HasArgument('increment');if Settings.HasIncrement then Settings.Increment:=Number('increment');
     Settings.HasConcurrency:=Cmd.HasArgument('concurrent');if Settings.HasConcurrency then Settings.Concurrency:=IntegerValue('concurrent');
     Settings.TimeForfeit:=DefaultTimeForfeit;
     Settings.HasTimeForfeit:=Cmd.HasArgument('time_forfeit') or Cmd.HasArgument('time_forfeit_id') or Cmd.HasArgument('time_forfeit_key') or Cmd.HasArgument('adjudication_time') or Cmd.HasArgument('adjudication_threshold');
     if Cmd.HasArgument('time_forfeit') or Cmd.HasArgument('time_forfeit_id') or Cmd.HasArgument('time_forfeit_key') then begin
       if SameText(Cmd.Argument('time_forfeit'),'loss') and (Cmd.HasArgument('time_forfeit_id') or Cmd.HasArgument('time_forfeit_key')) then
         Fail('BAD_ARGUMENT','Supply one time-forfeit selector');
       if not SameText(Cmd.Argument('time_forfeit'),'loss') then begin
         A:=Resolve('time_forfeit');
         if (A.Kind=eekDxp) or ((A.Kind=eekUci)<>(V=GameVariantById('chess'))) then
           Fail('GAME_MISMATCH','Time-forfeit adjudicator must support Hub for draughts or UCI for chess');
         Settings.TimeForfeit.EngineKey:=EngineIdentityKey(A);Settings.TimeForfeit.EngineName:=A.IdText;
       end;
     end;
     if Cmd.HasArgument('adjudication_time') then Settings.TimeForfeit.Seconds:=Number('adjudication_time');
     if Cmd.HasArgument('adjudication_threshold') then Settings.TimeForfeit.ThresholdCp:=Number('adjudication_threshold');
     if ((Cmd.HasArgument('adjudication_time') or Cmd.HasArgument('adjudication_threshold')) and
       (Settings.TimeForfeit.EngineKey='')) then Fail('BAD_ARGUMENT','Adjudication settings require time_forfeit=engine-name');
     try ValidateTimeForfeit(Settings.TimeForfeit);except on E:Exception do Fail('BAD_ARGUMENT',E.Message);end;
     AllowShared:=False;if Cmd.HasArgument('allow_shared_executable') then begin
       Msg:=LowerCase(Cmd['allow_shared_executable']);if (Msg<>'true') and (Msg<>'false') then Fail('BAD_ARGUMENT','allow_shared_executable requires true or false');
       AllowShared:=Msg='true';
     end;
     Phase:='CONFIGURE';
     try
       D:=FHost.NewTournament(V);if D=nil then Fail('BUSY','Tournament host is busy');
       D.ConfigureNewTournament(Settings);
       if not D.ConfirmSharedExecutables(True,AllowShared) then
         Fail('CONFIRMATION_REQUIRED','Shared executable requires allow_shared_executable=true');
       Phase:='PAIRING';
       if not D.CreatePairing(Msg,True) then begin
         if D.StorageError<>'' then Phase:='STORAGE';Fail(Phase,Msg);
       end;
       Id:=BindDialog(D);Phase:='START';
       if Assigned(FOnTournament) then FOnTournament(D) else FHost.Show;
       Started:=D.StartTournament(Msg,True,AllowShared);
       if not (Started in [tsrStarted,tsrAlreadyRunning]) then begin
         if D.StorageError<>'' then Phase:='STORAGE';
         if Pos('allow_shared_executable',Msg)>0 then Phase:='CONFIRMATION_REQUIRED';Fail(Phase,Msg);
       end;
       J.Add('tournament',Id);J.Add('uuid',D.TournamentIdentity);J.Add('file',D.SaveFileName);
       J.Add('engine1',EngineId(Settings.Engine1Key));J.Add('engine2',EngineId(Settings.Engine2Key));
       Item:=D.MatchSnapshot(Settings.Engine1Key,Settings.Engine2Key);
       try J.Add('state',Item.Get('state',''));J.Add('games_total',Item.Get('games_total',0));J.Add('pairs_total',Item.Get('pairs_total',0));finally Item.Free;end;
     except on E:Exception do begin
       Msg:=E.Message;
       if E is ECliRequest then Phase:=ECliRequest(E).Code;
       if D<>nil then begin
         if FHost.DiscardUnpublished(D) then D:=nil
         else begin Id:=BindDialog(D);Msg:=Msg+'; retained tournament='+IntToStr(Id)+' file='+D.SaveFileName;FHost.Show;end;
       end;
       J.Free;J:=TJSONObject.Create;J.Add('command',Name);J.Add('code',Phase);J.Add('message',Msg);
       if D<>nil then begin J.Add('tournament',Id);J.Add('file',D.SaveFileName);end;
       Exit('ERROR '+J.AsJSON);
     end;end;
   end;
   Result:='OK '+J.AsJSON;
  except
   on E:ECliRequest do Result:=CliError(E.Code,E.Message,Name);
   on E:Exception do Result:=CliError('BAD_ARGUMENT',E.Message,Name);
  end;
 finally J.Free;Engines.Free;Cmd.Free;Binder.Free;Spec.Free;Tokens.Free;FExecuting:=False;end;
end;
end.
