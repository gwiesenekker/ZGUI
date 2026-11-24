program engine_installation_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,Grids,
 Menus,StdCtrls,CheckLst,LCLIntf,Dialogs,uEngineRegistry,uEnginesDialog,uEngineEditForm,
 uTournamentDialog,uChessPosition,uDraughtsPosition,uGamePosition,uGameGuiProfile,
 uGuiDialogs,uEngineInstallationFixture;
type TGridAccess=class(TStringGrid);
var Checks:Integer;
procedure Check(B:Boolean;const S:string);begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;var I:Integer;begin for I:=1 to 8 do begin Application.ProcessMessages;Sleep(5);end;end;
function Grid(Form:TForm):TStringGrid;
var I:Integer;
begin for I:=0 to Form.ComponentCount-1 do if Form.Components[I] is TStringGrid then Exit(TStringGrid(Form.Components[I]));raise Exception.Create('No grid');end;
procedure Button(Form:TForm;const Caption:string);
var I:Integer;
begin for I:=0 to Form.ComponentCount-1 do if (Form.Components[I] is TButton) and
 (TButton(Form.Components[I]).Caption=Caption) then begin TButton(Form.Components[I]).Click;Exit;end;raise Exception.Create('Missing button '+Caption);end;
var L:TExternalEngineList;A,Clone:TExternalEngineDefinition;V:TGameVariant;Kind:TExternalEngineKind;
 Engines:TEnginesDialog;Editor:TEngineEditForm;D:TTournamentDialog;G,Cross:TStringGrid;
 I,OldWidth,X,Y:Integer;P:TPoint;Marker,Before:string;Lines:TStringList;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
 RegisterDefaultGameVariant(RegisteredGame(0));L:=TExternalEngineList.Create;Lines:=TStringList.Create;
 Engines:=nil;D:=nil;Marker:=GetTempFileName(GetTempDir,'install-gui');DeleteFile(Marker);
 try
  for Kind:=Low(Kind) to High(Kind) do begin
   L.Clear;
   A:=TExternalEngineDefinition.Create;A.ExePath:=InstallEngineFixture(ParamStr(0),'registered');
   A.Kind:=Kind;A.UciId:='One';A.HubId:='One';A.DxpId:='One';L.Add(A);SaveExternalEngines(EnginesJsonFileName,L);
   if Kind=eekUci then V:=RegisteredGame(0) else V:=RegisteredGame(1);
   Engines:=TEnginesDialog.Create(nil,V);
   try
    Engines.Show;Pump;G:=Grid(Engines);G.PopupMenu.Items[0].Click;Pump;Editor:=nil;
    for I:=0 to Engines.ComponentCount-1 do if Engines.Components[I] is TEngineEditForm then Editor:=TEngineEditForm(Engines.Components[I]);
    Check((Editor<>nil) and Assigned(Editor.OnRegistrationCheck),'Editor has shared registration preflight');
    Clone:=TExternalEngineDefinition.Create;
    try Clone.Assign(A);Clone.EnvironmentJson:='{"TEST":"different"}';Clone.Arguments:='--not-allowed';
     Check(Editor.OnRegistrationCheck(Clone)<>'','Different overrides cannot permit a second registration');
     Clone.IniFileName:=Marker;Clone.IniContent:='must not be written';Editor.LoadEngine(Clone);
     GuiTestConfirmationResult:=mrOk;Button(Editor,'Launch engine');Pump;
     Check(not FileExists(Marker),'Directory preflight runs before probe launch/INI writes');
     Button(Editor,'Launched correctly');Check(Engines.Engines.Count=1,'Duplicate acceptance rejected');
     Check(Pos('already registered',GuiTestLastConfirmationText)>0,'Conflict explains installed-directory policy');
    finally Clone.Free;end;
    Editor.Hide;G.Row:=1;G.OnDblClick(G);Pump;
    Check(Editor.OnRegistrationCheck(A)='','Editing the existing registration is allowed');
   finally GuiTestConfirmationResult:=0;Engines.Free;Engines:=nil;end;
  end;
  for I:=0 to 1 do begin
   V:=RegisteredGame(I);L.Clear;
   A:=TExternalEngineDefinition.Create;A.ExePath:=InstallEngineFixture(ParamStr(0),'cross-one');
   if I=0 then begin A.Kind:=eekUci;A.UciId:='One';end else begin A.Kind:=eekHub;A.HubId:='One';end;L.Add(A);
   A:=TExternalEngineDefinition.Create;A.Assign(L[0]);A.ExePath:=InstallEngineFixture(ParamStr(0),'cross-two');
   A.UciId:='Two';A.HubId:='Two';L.Add(A);SaveExternalEngines(EnginesJsonFileName,L);
   D:=TTournamentDialog.Create(nil,V);
   try
    D.Show;Pump;Button(D,'Create pairing');Pump;
    Cross:=TStringGrid(D.FindComponent('TournamentCrossTable'));
    Check((Cross<>nil) and (goFixedColSizing in Cross.Options),'Fixed Engine column permits resize');
    OldWidth:=Cross.ColWidths[0];X:=Cross.CellRect(0,0).Right;Y:=Cross.DefaultRowHeight div 2;
    Cross.SetFocus;P:=Cross.ClientToScreen(Point(X,Y));SetCursorPos(P.X,P.Y);
    TGridAccess(Cross).MouseMove([],X,Y);
    TGridAccess(Cross).MouseDown(mbLeft,[],X,Y);
    P:=Cross.ClientToScreen(Point(X+65,Y));SetCursorPos(P.X,P.Y);
    TGridAccess(Cross).MouseMove([ssLeft],X+65,Y);TGridAccess(Cross).MouseUp(mbLeft,[],X+65,Y);Pump;
    Check(Cross.ColWidths[0]>OldWidth,'Dragging divider after Engine changes width');
    OldWidth:=Cross.ColWidths[0];Cross.ColWidths[Cross.ColCount-1]:=119;
    G:=TStringGrid(D.FindComponent('TournamentPairings'));G.Row:=1;D.SetSelectedResult(V.ResultText(goDraw));Pump;
    Check((Cross.ColWidths[0]=OldWidth) and (Cross.ColWidths[Cross.ColCount-1]=119),'Result refresh preserves user widths');
    TCheckListBox(D.FindComponent('TournamentEngines')).Checked[0]:=False;
    D.SetSelectedResult(V.ResultText(goWhiteWins));Pump;
    Check((Cross.ColWidths[0]=OldWidth) and (Cross.ColWidths[Cross.ColCount-1]=119),'Participant changes retain Engine and statistics widths');
   finally D.Free;D:=nil;end;
  end;
  WriteLn('Installation policy and cross-table GUI checks passed (',Checks,' checks)');
 finally D.Free;Engines.Free;L.Free;Lines.Free;DeleteFile(Marker);DeleteFile(EnginesJsonFileName);ClearRegisteredGames;end;
end.
