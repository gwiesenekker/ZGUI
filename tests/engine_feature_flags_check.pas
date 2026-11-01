program engine_feature_flags_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uEngineFeatureFlags,uEngineParamsJson,uProcessOutputLines,
  uHubSearchInfo;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
var Flags:TStringList;Lines:TStringList;Buffer,Pv,Score,Depth,TimeText:string;
    Dropping,Raised:Boolean;I:Integer;Params:TEngineParamArray;
begin
  Flags:=ParseEngineFeatureFlags('[" GUI-GWD-DXP-PV ","dxp-pv","future-feature"]');
  try
    Check((Flags.Count=2) and (Flags[0]=FeatureDxpPv),'Legacy DXP flag migrates and deduplicates');
    Check(HasEngineFeatureFlag(EngineFeatureFlagsJson(Flags),'future-feature'),'Unknown flag round-trips');
    Check(Pos('gui-gwd',EngineFeatureFlagsJson(Flags))=0,'Saved flags use common spelling');
  finally Flags.Free;end;
  Check(HasEngineFeatureFlag('["gui-gwd-dxp-pv"]',FeatureDxpPv),'Legacy configuration enables DXP PV');
  for I:=0 to 4 do begin
    case I of 0:Buffer:='null';1:Buffer:='{}';2:Buffer:='[true]';3:Buffer:='[""]';4:Buffer:='["bad flag"]';end;
    Raised:=False;
    try Flags:=ParseEngineFeatureFlags(Buffer);Flags.Free;except on E:EConvertError do Raised:=True;end;
    Check(Raised,'Malformed flags rejected');
  end;
  Lines:=TStringList.Create;
  try
    Buffer:='';Dropping:=False;
    FrameProcessOutput(Buffer,Dropping,' info dep',Lines);
    Check(Lines.Count=0,'Partial stdout line withheld');
    FrameProcessOutput(Buffer,Dropping,'th=8'#13,Lines);
    Check(Lines.Count=0,'Split CRLF withheld');
    FrameProcessOutput(Buffer,Dropping,#10'info score=0.3'#10'info pv="32-28"'#13#10#10,Lines);
    Check((Lines.Count=3) and (Lines[0]='info depth=8') and
      (Lines[1]='info score=0.3') and (Lines[2]='info pv="32-28"'),'Mixed LF and CRLF framed separately');
    Check((Buffer='') and not Dropping,'Framer consumes complete lines');
    Lines.Clear;
    FrameProcessOutput(Buffer,Dropping,StringOfChar('x',65536)+#10,Lines);
    Check((Lines.Count=1) and (Length(Lines[0])=65536),'Maximum stdout line accepted');
    Lines.Clear;
    FrameProcessOutput(Buffer,Dropping,StringOfChar('x',65537),Lines);
    Check((Buffer='') and Dropping and (Lines.Count=0),'Oversized partial line dropped with bounded buffer');
    FrameProcessOutput(Buffer,Dropping,'tail'#10'info depth=9'#10,Lines);
    Check((Lines.Count=1) and (Lines[0]='info depth=9') and not Dropping,'Oversized tail discarded through newline');
    Lines.Clear;
    FrameProcessOutput(Buffer,Dropping,StringOfChar('x',65537)+#10'ready'#13#10,Lines);
    Check((Lines.Count=1) and (Lines[0]='ready'),'Oversized complete line cannot hide next response');
  finally Lines.Free;end;
  Params:=nil;Pv:='';Score:='';Depth:='';TimeText:='';
  MergeHubSearchInfo('info depth=8 score=0.45 time=0.1 pv="32-28"',Params,'W:W31-50:B1-20',0,Pv,Score,Depth,TimeText);
  Check((Pv='32-28') and (Score='0.45') and (Depth='8') and (TimeText='0.1'),'Hub-format DXP information parsed');
  MergeHubSearchInfo('info=depth=9',Params,'W:W31-50:B1-20',0,Pv,Score,Depth,TimeText);
  Check((Depth='9') and (Pv='32-28') and (Score='0.45') and (TimeText='0.1'),'Partial info retains previous metadata');
  MergeHubSearchInfo('done move=99-99',Params,'W:W31-50:B1-20',0,Pv,Score,Depth,TimeText);
  Check((Pv='32-28') and (Score='0.45'),'Stdout done does not supply actual DXP move');
  MergeHubSearchInfo('info score=0,45',Params,'B:W31-50:B1-20',0,Pv,Score,Depth,TimeText);
  Check(Score='-0.45','Black side-to-move score converted to White perspective');
  MergeHubSearchInfo('info score=0.45',Params,'W:W31-50:B1-20',1,Pv,Score,Depth,TimeText);
  Check(Score='-0.45','Root and history determine side for score');
  AddOrUpdateParam(Params,'gui-score-perspective','string','white',False);
  MergeHubSearchInfo('info score=0.45',Params,'B:W31-50:B1-20',0,Pv,Score,Depth,TimeText);
  Check(Score='0.45','Explicit White score perspective preserved');
  WriteLn('Engine compatibility checks passed (',Checks,' checks)');
end.
