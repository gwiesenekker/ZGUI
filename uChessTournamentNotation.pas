unit uChessTournamentNotation;
{$mode objfpc}{$H+}
{ Chess file decoration only: the existing lexer identifies tags and result
  tokens; the existing tree exporter supplies standings-only games. }
interface
function RenderChessTournamentGame(const Captured,PlayedResult,EffectiveResult,
  ManualResult,CaptureError,StartDate,TournamentId,EventName,RoundText,GameNo,
  Attempt,WhiteName,BlackName,Fen:string):string;
implementation
uses Classes,SysUtils,uChessPgnLexer,uChessPosition,uGameFileMetadata,
 uGameTree,uGameTreeBuilder,uGameTreePdn,uGameOrchestrator;
function RenderChessTournamentGame(const Captured,PlayedResult,EffectiveResult,
  ManualResult,CaptureError,StartDate,TournamentId,EventName,RoundText,GameNo,
  Attempt,WhiteName,BlackName,Fen:string):string;
const Roster:array[0..6]of string=('Event','Site','Date','Round','White','Black','Result');
var Source,Body,Name,Value,FinalResult:string;Tags:TGameFileTags;L:TChessPgnLexer;
 T:TPgnToken;I,J,BodyOffset,ResultOffset,ResultLength,Depth:Integer;
 V:TChessVariant;Tree:TGameTree;H:TGameTreeHeaderInput;Options:TGameTreePdnRenderOptions;
 procedure SetTag(const N,S:string);
 var K:Integer;
 begin
  for K:=0 to High(Tags) do if Tags[K].Name=N then begin Tags[K].Value:=S;Exit;end;
  SetLength(Tags,Length(Tags)+1);Tags[High(Tags)].Name:=N;Tags[High(Tags)].Value:=S;
 end;
 function TagLine(const N,S:string):string;
 var Q:string;
 begin
  Q:=StringReplace(S,#13,' ',[rfReplaceAll]);Q:=StringReplace(Q,#10,' ',[rfReplaceAll]);
  Q:=StringReplace(Q,'\','\\',[rfReplaceAll]);Q:=StringReplace(Q,'"','\"',[rfReplaceAll]);
  Result:='['+N+' "'+Q+'"]'+LineEnding;
 end;
begin
 Source:=Captured;
 if Source='' then begin
  V:=TChessVariant.Create;Tree:=TGameTree.Create(V);
  try
   H:=GameTreeHeaderInput('',EventName,WhiteName,BlackName,EffectiveResult,Fen,False,DefaultTimeControl);
   BeginGameTreeRebuild(Tree,H);Options:=DefaultGameTreePdnRenderOptions;
   Options.FileFormat:=gffPgn;Options.LosslessPgn:=True;
   Source:=GameTreeToPdnTextEx(Tree,Options);
  finally Tree.Free;V.Free;end;
 end;
 L:=TChessPgnLexer.Create(Source);Tags:=nil;
 try
  T:=L.NextToken;
  while T.Kind=ptComment do T:=L.NextToken;
  while T.Kind=ptTagOpen do begin
   T:=L.NextToken;if T.Kind<>ptSymbol then raise EConvertError.Create('Invalid tournament PGN tag');Name:=T.Text;
   for I:=0 to High(Tags) do if Tags[I].Name=Name then raise EConvertError.Create('Duplicate tournament PGN tag');
   T:=L.NextToken;if T.Kind<>ptString then raise EConvertError.Create('Invalid tournament PGN tag value');Value:=T.Text;
   T:=L.NextToken;if T.Kind<>ptTagClose then raise EConvertError.Create('Unclosed tournament PGN tag');
   SetTag(Name,Value);T:=L.NextToken;
  end;
  BodyOffset:=T.Offset;ResultOffset:=0;ResultLength:=0;Depth:=0;
  repeat
   if (ResultOffset<>0) and not (T.Kind in [ptComment,ptEnd]) then
    raise EConvertError.Create('Content after tournament PGN result');
   if T.Kind=ptVariationOpen then Inc(Depth)
   else if T.Kind=ptVariationClose then begin Dec(Depth);if Depth<0 then raise EConvertError.Create('Invalid tournament PGN variation');end
   else if (T.Kind=ptResult) and (Depth=0) then begin
    if ResultOffset<>0 then raise EConvertError.Create('Multiple tournament PGN results');
    ResultOffset:=T.Offset;ResultLength:=Length(T.Text);FinalResult:=T.Text;
   end else if (ResultOffset<>0) and not (T.Kind in [ptComment,ptEnd]) then
    raise EConvertError.Create('Content after tournament PGN result');
   if T.Kind=ptEnd then Break;T:=L.NextToken;
  until False;
  if (ResultOffset=0) or (Depth<>0) then raise EConvertError.Create('Incomplete tournament PGN');
  if GameFileTagValue(Tags,'Result','')<>FinalResult then
   raise EConvertError.Create('Captured tournament PGN tag and result disagree');
  if (Captured<>'') and (PlayedResult<>'') and (FinalResult<>PlayedResult) then
   raise EConvertError.Create('Captured tournament PGN result disagrees with played result');
  Body:=Copy(Source,BodyOffset,ResultOffset-BodyOffset)+EffectiveResult+
    Copy(Source,ResultOffset+ResultLength,MaxInt);
 finally L.Free;end;
 SetTag('Event',EventName);SetTag('Round',RoundText);SetTag('Result',EffectiveResult);
 if StartDate<>'' then SetTag('Date',StartDate);
 SetTag('TournamentId',TournamentId);SetTag('GameNo',GameNo);SetTag('Attempt',Attempt);
 if Captured='' then SetTag('RecordSource','standings');
 if CaptureError<>'' then begin SetTag('RecordSource','capture-failed');SetTag('CaptureError',CaptureError);end;
 if ManualResult<>'' then begin
  SetTag('ResultSource','manual');if PlayedResult<>'' then SetTag('PlayedResult',PlayedResult);
 end else if Captured='' then SetTag('ResultSource','standings') else SetTag('ResultSource','played');
 // Retain the roster order even after overriding Event/Round/Result.
 Result:='';
 for I:=0 to High(Roster) do begin
  Name:=Roster[I];Value:=GameFileTagValue(Tags,Name,'?');
  Result+=TagLine(Name,Value);
 end;
 for I:=0 to High(Tags) do begin
  J:=0;while (J<=High(Roster)) and (Roster[J]<>Tags[I].Name) do Inc(J);
  if J>High(Roster) then Result+=TagLine(Tags[I].Name,Tags[I].Value);
 end;
 Result+=LineEnding+Trim(Body)+LineEnding;
end;
end.
