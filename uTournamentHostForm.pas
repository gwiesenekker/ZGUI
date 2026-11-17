unit uTournamentHostForm;
{$mode objfpc}{$H+}
interface
uses Classes,Forms,Controls,ComCtrls,StdCtrls,ExtCtrls,uGamePosition,uTournamentDialog;
type
  TTournamentTab=class
  public
    Id:PtrInt;
    LastSelected:Int64;
    Page:TTabSheet;
    Dialog:TTournamentDialog;
    PendingVariant:TGameVariant;
  end;
  TTournamentClosePlan=record
    Tab:TTournamentTab;
    SaveName:string;
  end;
  TTournamentHostForm=class(TForm)
  private
    FTabs:TList;
    FPages:TPageControl;
    FSerial:PtrInt;
    FSelectionCounter:Int64;
    FSelectedId:PtrInt;
    FBusy,FDisposing,FLayoutQueued,FPreparingAll,FMeasuringLayout:Boolean;
    FDefaultVariant:TGameVariant;
    FTabUpdateDepth:Integer;
    FLayoutDirty:Boolean;
    FRedrawHandle:THandle;
    FRevealTab:TTournamentTab;
    procedure BeginTabUpdate;
    procedure EndTabUpdate;
    procedure RefreshActiveLayout;
    procedure MeasureTab(Tab:TTournamentTab);
    procedure ChildMinimumChanged(Sender:TObject);
  private
    FPlans:array of TTournamentClosePlan;
    FOnStartGame:TTournamentStartGameEvent;
    FOnSelectGame:TTournamentSelectGameEvent;
    FOnOpenRecord:TTournamentOpenRecordEvent;
    function GetCount:Integer;
    function GetDialog(Index:Integer):TTournamentDialog;
    function ActiveTab:TTournamentTab;
    function TabFor(Dialog:TObject):TTournamentTab;
    function CreateDialog(Variant:TGameVariant):TTournamentDialog;
    procedure Embed(Tab:TTournamentTab;Dialog:TTournamentDialog);
    procedure RemoveTab(Tab:TTournamentTab);
    procedure NewClick(Sender:TObject);
    procedure CloseClick(Sender:TObject);
    procedure ClosePage(Sender:TObject);
    procedure HostCloseQuery(Sender:TObject;var CanClose:Boolean);
    procedure ChildCloseQuery(Sender:TObject;var CanClose:Boolean);
    procedure AsyncClose(Id:PtrInt);
    procedure AsyncGameSwitch(Id:PtrInt);
    procedure SwitchGame(Tab:TTournamentTab;Variant:TGameVariant);
    procedure AsyncLayout(Data:PtrInt);
    procedure PageChanged(Sender:TObject);
    procedure TitleChanged(Sender:TObject);
    procedure ContextRequested(Sender:TObject;Variant:TGameVariant;const FileName:string);
    procedure CheckTargets(Sender:TObject;const JsonFile,Publication,Identity:string);
    function Prepare(Tab:TTournamentTab;out Plan:TTournamentClosePlan):Boolean;
    function FinishPlans:Boolean;
    function CloseOne(Tab:TTournamentTab):Boolean;
  protected
    procedure Notification(AComponent:TComponent;Operation:TOperation);override;
    procedure FontChanged(Sender:TObject);override;
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    function NewTournament(Variant:TGameVariant):TTournamentDialog;
    function ShowForVariant(Variant:TGameVariant):TTournamentDialog;
    function OpenFile(const FileName:string;Fallback:TGameVariant):TTournamentDialog;
    function CloseTournament(Dialog:TTournamentDialog):Boolean;
    function PrepareCloseAll:Boolean;
    function FinishCloseAll:Boolean;
    procedure BeginShutdown;
    function SessionTabId(Dialog:TTournamentDialog):PtrInt;
    function DialogById(Id:PtrInt):TTournamentDialog;
    function DiscardUnpublished(Dialog:TTournamentDialog):Boolean;
    function IsBusy:Boolean;
    property Count:Integer read GetCount;
    property Dialogs[Index:Integer]:TTournamentDialog read GetDialog;
    property Pages:TPageControl read FPages;
    property OnStartGame:TTournamentStartGameEvent read FOnStartGame write FOnStartGame;
    property OnOpenRecord:TTournamentOpenRecordEvent read FOnOpenRecord write FOnOpenRecord;
    property OnSelectGame:TTournamentSelectGameEvent read FOnSelectGame write FOnSelectGame;
  end;
implementation
uses SysUtils,Math,Dialogs,FPJSON,uGuiDialogs,uGameGuiProfile,uGameDocumentContext,
  uTournamentStorage,LazFileUtils{$IFDEF MSWINDOWS},Windows{$ENDIF};
function SamePath(const A,B:string):Boolean;
begin
  Result:=(A<>'') and (B<>'');if not Result then Exit;
  {$IFDEF MSWINDOWS}Result:=SameText(GetPhysicalFilename(ExpandFileName(A),pfeOriginal),GetPhysicalFilename(ExpandFileName(B),pfeOriginal));
  {$ELSE}Result:=GetPhysicalFilename(ExpandFileName(A),pfeOriginal)=GetPhysicalFilename(ExpandFileName(B),pfeOriginal);{$ENDIF}
end;
constructor TTournamentHostForm.Create(AOwner:TComponent);
var Toolbar:TPanel;B:TButton;
begin
  inherited CreateNew(AOwner);FTabs:=TList.Create;
  Caption:='Tournaments';Width:=1250;Height:=740;Position:=poDesigned;
  OnCloseQuery:=@HostCloseQuery;OnResize:=@PageChanged;
  Toolbar:=TPanel.Create(Self);Toolbar.Parent:=Self;Toolbar.Align:=alTop;Toolbar.Height:=40;
  Toolbar.BevelOuter:=bvNone;
  B:=TButton.Create(Self);B.Parent:=Toolbar;B.Align:=alLeft;B.AutoSize:=True;
  B.Caption:='New tournament';B.OnClick:=@NewClick;
  B:=TButton.Create(Self);B.Parent:=Toolbar;B.Align:=alLeft;B.AutoSize:=True;
  B.Caption:='Close tournament';B.OnClick:=@CloseClick;
  FPages:=TPageControl.Create(Self);FPages.Parent:=Self;FPages.Align:=alClient;
  FPages.Options:=FPages.Options+[nboShowCloseButtons];FPages.OnCloseTabClicked:=@ClosePage;
  FPages.OnChange:=@PageChanged;
end;
destructor TTournamentHostForm.Destroy;
begin
  FDisposing:=True;Application.RemoveAsyncCalls(Self);
  while FTabs.Count>0 do RemoveTab(TTournamentTab(FTabs[FTabs.Count-1]));
  FTabs.Free;inherited Destroy;
end;
function TTournamentHostForm.SessionTabId(Dialog:TTournamentDialog):PtrInt;
var Tab:TTournamentTab;
begin Tab:=TabFor(Dialog);if Tab=nil then Exit(0);Result:=Tab.Id;end;
function TTournamentHostForm.DialogById(Id:PtrInt):TTournamentDialog;
var I:Integer;
begin
  Result:=nil;for I:=0 to FTabs.Count-1 do
    if TTournamentTab(FTabs[I]).Id=Id then Exit(TTournamentTab(FTabs[I]).Dialog);
end;
function TTournamentHostForm.IsBusy:Boolean;
begin Result:=FBusy or FDisposing or FPreparingAll;end;
function TTournamentHostForm.DiscardUnpublished(Dialog:TTournamentDialog):Boolean;
var Tab:TTournamentTab;
begin
  Tab:=TabFor(Dialog);Result:=(Tab<>nil) and not IsBusy and Dialog.AbandonUnpublished;
  if Result then RemoveTab(Tab);
end;
function TTournamentHostForm.GetCount:Integer;
begin Result:=FTabs.Count;end;
function TTournamentHostForm.GetDialog(Index:Integer):TTournamentDialog;
begin Result:=TTournamentTab(FTabs[Index]).Dialog;end;
function TTournamentHostForm.ActiveTab:TTournamentTab;
var I:Integer;
begin
  Result:=nil;if FPages=nil then Exit;
  for I:=0 to FTabs.Count-1 do
    if TTournamentTab(FTabs[I]).Page=FPages.ActivePage then Exit(TTournamentTab(FTabs[I]));
end;
function TTournamentHostForm.TabFor(Dialog:TObject):TTournamentTab;
var I:Integer;
begin
  Result:=nil;for I:=0 to FTabs.Count-1 do
    if TTournamentTab(FTabs[I]).Dialog=Dialog then Exit(TTournamentTab(FTabs[I]));
end;
function TTournamentHostForm.CreateDialog(Variant:TGameVariant):TTournamentDialog;
begin
  Result:=TTournamentDialog.Create(Owner,Variant);
  Result.Font.Assign(Font);
  Result.OnStartGame:=FOnStartGame;Result.OnSelectGame:=FOnSelectGame;Result.OnOpenRecord:=FOnOpenRecord;
  Result.OnContextRequested:=@ContextRequested;Result.OnTargets:=@CheckTargets;
  Result.OnTitleChanged:=@TitleChanged;Result.OnCloseQuery:=@ChildCloseQuery;
  // Wrapping can settle after embedding/font propagation. Reuse the queued
  // host measurement when the child's measured minimum grows its bounds.
  Result.OnLayoutMinimumChanged:=@ChildMinimumChanged;
  Result.FreeNotification(Self);
end;
procedure TTournamentHostForm.Embed(Tab:TTournamentTab;Dialog:TTournamentDialog);
begin
  Tab.Dialog:=Dialog;Dialog.BorderStyle:=bsNone;Dialog.Align:=alClient;
  // Keep the current page on screen while every native child is constructed.
  // Selecting the new page here would expose it before final measurement.
  Tab.Page.Visible:=False;
  Dialog.Parent:=Tab.Page;Dialog.Show;Dialog.HandleNeeded;
  FRevealTab:=Tab;TitleChanged(Dialog);
end;
procedure TTournamentHostForm.BeginTabUpdate;
begin
  Inc(FTabUpdateDepth);if FTabUpdateDepth>1 then Exit;
  FRevealTab:=nil;
  DisableAlign;FPages.DisableAlign;
  {$IFDEF MSWINDOWS}
  // WM_SETREDRAW changes native visibility. Only suspend an already visible
  // page control, so resuming never makes a hidden host unexpectedly appear.
  if FPages.HandleAllocated and Windows.IsWindowVisible(FPages.Handle) then begin
    FRedrawHandle:=FPages.Handle;
    Windows.SendMessage(FRedrawHandle,WM_SETREDRAW,0,0);
  end;
  {$ENDIF}
end;

procedure TTournamentHostForm.EndTabUpdate;
begin
  if FTabUpdateDepth>1 then begin Dec(FTabUpdateDepth);Exit;end;
  try
    try FPages.EnableAlign;finally EnableAlign;end;
    if FRevealTab<>nil then begin
      // Layout and native handles must be ready before ActivePage makes the
      // page visible. No message pumping or timer delay is needed.
      MeasureTab(FRevealTab);
      FPages.ActivePage:=FRevealTab.Page;
      FRevealTab.Page.Visible:=True;
      FLayoutDirty:=False;
    end else RefreshActiveLayout;
  finally
    FRevealTab:=nil;
    Dec(FTabUpdateDepth);
    {$IFDEF MSWINDOWS}
    if FRedrawHandle<>0 then begin
      if Windows.IsWindow(FRedrawHandle) then begin
        Windows.SendMessage(FRedrawHandle,WM_SETREDRAW,1,0);
        Windows.RedrawWindow(FRedrawHandle,nil,0,
          RDW_INVALIDATE or RDW_ERASE or RDW_FRAME or RDW_ALLCHILDREN);
      end;
      FRedrawHandle:=0;
    end;
    {$ENDIF}
    FPages.Invalidate;
  end;
end;

function TTournamentHostForm.NewTournament(Variant:TGameVariant):TTournamentDialog;
var Tab:TTournamentTab;
begin
  if FBusy then Exit(nil);
  FDefaultVariant:=Variant;
  BeginTabUpdate;
  try
   Tab:=TTournamentTab.Create;
   try
    Inc(FSerial);Tab.Id:=FSerial;Tab.Dialog:=CreateDialog(Variant);
    Tab.Dialog.TournamentName:='Tournament'+IntToStr(FSerial);
    Tab.Dialog.AcceptInitialSettings;
    Tab.Page:=TTabSheet.Create(FPages);Tab.Page.PageControl:=FPages;
    FTabs.Add(Tab);Embed(Tab,Tab.Dialog);Result:=Tab.Dialog;
  except
    if FTabs.IndexOf(Tab)>=0 then FTabs.Remove(Tab);
    Tab.Dialog.Free;Tab.Page.Free;Tab.Free;raise;
   end;
  finally EndTabUpdate;end;
end;
function TTournamentHostForm.ShowForVariant(Variant:TGameVariant):TTournamentDialog;
var I:Integer;Tab,Best:TTournamentTab;
begin
  FDefaultVariant:=Variant;Best:=nil;
  for I:=0 to FTabs.Count-1 do begin
    Tab:=TTournamentTab(FTabs[I]);
    if (Tab.Dialog<>nil) and (Tab.Dialog.Variant=Variant) and
      ((Best=nil) or (Tab.LastSelected>=Best.LastSelected)) then Best:=Tab;
  end;
  if Best<>nil then begin
    FPages.ActivePage:=Best.Page;PageChanged(Self);Exit(Best.Dialog);
  end;
  Result:=NewTournament(Variant);
end;
procedure TTournamentHostForm.NewClick(Sender:TObject);
var Tab:TTournamentTab;V:TGameVariant;
begin
  if FBusy then Exit;Tab:=ActiveTab;V:=FDefaultVariant;
  if (Tab<>nil) and (Tab.Dialog<>nil) then V:=Tab.Dialog.Variant;
  if V<>nil then NewTournament(V);
end;
procedure TTournamentHostForm.TitleChanged(Sender:TObject);
var I,J:Integer;Tab,Other:TTournamentTab;LabelText:string;Duplicate:Boolean;
begin
  if FDisposing then Exit;
  for I:=0 to FTabs.Count-1 do begin
    Tab:=TTournamentTab(FTabs[I]);if Tab.Dialog=nil then Continue;
    LabelText:=Trim(Tab.Dialog.TournamentName);if LabelText='' then LabelText:='Tournament'+IntToStr(Tab.Id);
    Duplicate:=False;
    for J:=0 to FTabs.Count-1 do begin
      Other:=TTournamentTab(FTabs[J]);
      if (Other<>Tab) and (Other.Dialog<>nil) and SameText(Other.Dialog.TournamentName,Tab.Dialog.TournamentName) then Duplicate:=True;
    end;
    if Duplicate then LabelText+=' ['+IntToStr(Tab.Id)+']';
    Tab.Page.Caption:=LabelText+' ('+Tab.Dialog.Variant.Name+')';
    if Tab.Dialog.ReadOnly then Tab.Page.Caption:=Tab.Page.Caption+' (read-only)';
  end;
  PageChanged(Self);
end;
procedure TTournamentHostForm.PageChanged(Sender:TObject);
var Tab:TTournamentTab;
begin
  if FDisposing then Exit;
  Tab:=ActiveTab;
  if (Tab<>nil) and (Tab.Id<>FSelectedId) then begin
    Inc(FSelectionCounter);Tab.LastSelected:=FSelectionCounter;FSelectedId:=Tab.Id;
  end;
  FLayoutDirty:=True;
  if FLayoutQueued or (FPages=nil) or (FTabUpdateDepth>0) then Exit;
  FLayoutQueued:=True;Application.QueueAsyncCall(@AsyncLayout,0);
end;
procedure TTournamentHostForm.AsyncLayout(Data:PtrInt);
begin
  FLayoutQueued:=False;
  if FDisposing or (FTabUpdateDepth>0) or not FLayoutDirty then Exit;
  RefreshActiveLayout;
end;
procedure TTournamentHostForm.RefreshActiveLayout;
var Tab:TTournamentTab;I:Integer;
begin
  if FDisposing then Exit;
  FLayoutDirty:=False;
  // External frees (legacy callers/tests) leave no stale owner/session pointers.
  for I:=FTabs.Count-1 downto 0 do
    if TTournamentTab(FTabs[I]).Dialog=nil then RemoveTab(TTournamentTab(FTabs[I]));
  Tab:=ActiveTab;if (Tab=nil) or (Tab.Dialog=nil) then Exit;
  MeasureTab(Tab);
end;
procedure TTournamentHostForm.ChildMinimumChanged(Sender:TObject);
var Tab:TTournamentTab;
begin
  if FDisposing then Exit;
  Tab:=ActiveTab;
  if Visible and not FMeasuringLayout and (FTabUpdateDepth=0) and
    (Tab<>nil) and (Tab.Dialog=Sender) then RefreshActiveLayout
  else PageChanged(Sender);
end;
procedure TTournamentHostForm.MeasureTab(Tab:TTournamentTab);
var ChromeWidth,ChromeHeight,PageWidth,PageHeight,PageInsetWidth,PageInsetHeight:Integer;
begin
  if FMeasuringLayout then Exit;
  FMeasuringLayout:=True;
  try
  // Native page client bounds are not final until the host is shown.
  // Never grow a hidden top-level window from those provisional bounds.
  if not Visible then begin Tab.Dialog.RefreshLayout;Exit;end;
  FPages.HandleNeeded;Tab.Page.HandleNeeded;
  if (FPages.ClientWidth<=0) or (FPages.ClientHeight<=0) then Exit;
  // An inactive/hidden page can still have zero bounds. The notebook's client
  // area describes real page space; zero page bounds are not window chrome.
  PageWidth:=FPages.ClientWidth;PageHeight:=FPages.ClientHeight;
  // A realized active page measures the native tab strip/border as well as
  // notebook chrome. A new hidden page can still have provisional zero bounds.
  if FPages.ActivePage<>nil then begin
    if FPages.ActivePage.ClientWidth>1 then PageWidth:=FPages.ActivePage.ClientWidth;
    if FPages.ActivePage.ClientHeight>1 then PageHeight:=FPages.ActivePage.ClientHeight;
  end;
  PageInsetWidth:=Max(0,FPages.ClientWidth-PageWidth);
  PageInsetHeight:=Max(0,FPages.ClientHeight-PageHeight);
  Tab.Page.BoundsRect:=FPages.ClientRect;
  Tab.Dialog.SetBounds(0,0,PageWidth,PageHeight);
  Tab.Dialog.HandleNeeded;
  Tab.Dialog.RefreshLayout;
  DefaultControl:=nil;ActiveDefaultControl:=nil;CancelControl:=nil;
  ChromeWidth:=Max(0,Width-PageWidth);
  ChromeHeight:=Max(0,Height-PageHeight);
  Constraints.MinWidth:=Tab.Dialog.Constraints.MinWidth+ChromeWidth;
  Constraints.MinHeight:=Tab.Dialog.Constraints.MinHeight+ChromeHeight;
  Width:=Max(Width,Constraints.MinWidth);Height:=Max(Height,Constraints.MinHeight);
  Tab.Page.BoundsRect:=FPages.ClientRect;
  Tab.Dialog.SetBounds(0,0,Max(1,FPages.ClientWidth-PageInsetWidth),Max(1,FPages.ClientHeight-PageInsetHeight));
  FLayoutDirty:=False;
  finally FMeasuringLayout:=False;end;
end;
procedure TTournamentHostForm.FontChanged(Sender:TObject);
var I:Integer;
begin
  inherited FontChanged(Sender);if FTabs=nil then Exit;
  for I:=0 to Count-1 do if Dialogs[I]<>nil then Dialogs[I].Font.Assign(Font);
  PageChanged(Self);
end;
procedure TTournamentHostForm.CheckTargets(Sender:TObject;const JsonFile,Publication,Identity:string);
var I:Integer;D:TTournamentDialog;
begin
  for I:=0 to Count-1 do begin
    D:=Dialogs[I];if (D=nil) or (D=Sender) then Continue;
    if ((Identity<>'') and (Identity=D.TournamentIdentity)) or
      SamePath(JsonFile,D.SaveFileName) or SamePath(JsonFile,D.PublicationFileName) or
      SamePath(Publication,D.SaveFileName) or SamePath(Publication,D.PublicationFileName) then
      raise EInvalidOperation.Create('Tournament file or identity is already in use by '+D.TournamentName);
  end;
end;
function TTournamentHostForm.OpenFile(const FileName:string;Fallback:TGameVariant):TTournamentDialog;
var I:Integer;V:TGameVariant;Data:TJSONObject;Identity,Publication:string;Tab:TTournamentTab;D:TTournamentDialog;
begin
  if FBusy then Exit(nil);
  V:=TournamentFileVariant(FileName,Fallback);
  Data:=ReadTournamentDocument(FileName,GameGuiProfileFor(V).FileFormat);
  try
    Identity:=Data.Get('tournament_id','');Publication:=Data.Get('pdn_file_name','');
    if (Publication<>'') and not FilenameIsAbsolute(Publication) then
      Publication:=ExpandFileName(ExtractFilePath(ExpandFileName(FileName))+Publication);
    for I:=0 to Count-1 do begin
      D:=Dialogs[I];if D=nil then Continue;
      if SamePath(FileName,D.SaveFileName) or ((Identity<>'') and (Identity=D.TournamentIdentity)) then begin
        FPages.ActivePage:=TTournamentTab(FTabs[I]).Page;PageChanged(Self);Exit(D);
      end;
    end;
    CheckTargets(nil,FileName,Publication,Identity);
  finally Data.Free;end;
  // Validate and load before adding a page. Load reuses the existing storage path.
  D:=CreateDialog(V);
  try
    D.LoadTournamentFromFile(FileName);
    if D.StorageError<>'' then raise EInOutError.Create(D.StorageError);
    BeginTabUpdate;
    try
      Tab:=TTournamentTab.Create;Inc(FSerial);Tab.Id:=FSerial;Tab.Dialog:=D;
      Tab.Page:=TTabSheet.Create(FPages);Tab.Page.PageControl:=FPages;
      FTabs.Add(Tab);Embed(Tab,D);Result:=D;D:=nil;
    finally EndTabUpdate;end;
  finally D.Free;end;
end;
function TTournamentHostForm.Prepare(Tab:TTournamentTab;out Plan:TTournamentClosePlan):Boolean;
var Response,I:Integer;LabelText,Names:string;
begin
  Plan.Tab:=Tab;Plan.SaveName:='';Result:=True;
  if (Tab=nil) or (Tab.Dialog=nil) then Exit;
  if Tab.Dialog.ReadOnly then Exit;
  if not Tab.Dialog.HasTournamentData and not Tab.Dialog.IsRunning then Exit;
  LabelText:='Close "'+Tab.Dialog.TournamentName+'"?';
  if FPreparingAll then begin
    Names:='';
    for I:=0 to Count-1 do if (Dialogs[I]<>nil) and Dialogs[I].IsRunning then begin
      if Names<>'' then Names+=', ';Names+=Dialogs[I].TournamentName;
    end;
    if Names<>'' then LabelText+=LineEnding+'Closing this window will stop ALL running tournaments: '+Names+'.';
  end else if Tab.Dialog.IsRunning then LabelText+=LineEnding+'This will stop this tournament and its running games.'+
    LineEnding+'Remaining pairings will be left unplayed. Other tournaments will continue.';
  LabelText+=LineEnding+'Save the tournament before closing?'+LineEnding+
    'Discard closes without an explicit save; existing recovery files and published results remain.';
  Response:=ShowGuiConfirmationDialog(Self,'Close tournament',LabelText,'Save','Discard',mrNo,True);
  if Response=mrCancel then Exit(False);
  if Response=mrYes then Result:=Tab.Dialog.ChooseSaveFileName(Plan.SaveName);
end;
function TTournamentHostForm.PrepareCloseAll:Boolean;
var I,J:Integer;
begin
  Result:=False;if FBusy then Exit;
  FBusy:=True;FPreparingAll:=True;
  try
    SetLength(FPlans,Count);
    for I:=0 to Count-1 do begin
      if not Prepare(TTournamentTab(FTabs[I]),FPlans[I]) then begin FPlans:=nil;Exit;end;
      for J:=0 to I-1 do if SamePath(FPlans[I].SaveName,FPlans[J].SaveName) then begin
        FPlans:=nil;raise EInvalidOperation.Create('Two tournaments cannot save to the same file');
      end;
    end;
    Result:=True;
  finally
    if not Result then FPlans:=nil;FBusy:=False;FPreparingAll:=False;
  end;
end;
function TTournamentHostForm.FinishPlans:Boolean;
var I:Integer;AllDrained:Boolean;
begin
  Result:=False;if FBusy then Exit;FBusy:=True;
  try
   try
    for I:=0 to High(FPlans) do if FPlans[I].Tab.Dialog<>nil then FPlans[I].Tab.Dialog.StopForClose;
    AllDrained:=True;
    for I:=0 to High(FPlans) do if FPlans[I].Tab.Dialog<>nil then
      AllDrained:=FPlans[I].Tab.Dialog.DrainClose and AllDrained;
    for I:=0 to High(FPlans) do if (FPlans[I].SaveName<>'') and (FPlans[I].Tab.Dialog<>nil) then begin
      if not AllDrained then raise EInOutError.Create('Final tournament capture failed; the stopped tabs remain open');
      FPlans[I].Tab.Dialog.SaveTournamentToFile(FPlans[I].SaveName);
    end;
    for I:=High(FPlans) downto 0 do RemoveTab(FPlans[I].Tab);
    Result:=True;
  except on E:Exception do ShowGuiOkDialog(Self,'Close tournament',E.Message);end;
  finally FPlans:=nil;FBusy:=False;end;
end;
function TTournamentHostForm.FinishCloseAll:Boolean;
begin Result:=FinishPlans;end;
function TTournamentHostForm.CloseOne(Tab:TTournamentTab):Boolean;
begin
  Result:=False;if FBusy or (Tab=nil) then Exit;
  FBusy:=True;
  try
    SetLength(FPlans,1);
    if not Prepare(Tab,FPlans[0]) then begin FPlans:=nil;Exit;end;
  finally FBusy:=False;end;
  Result:=FinishPlans;
end;
function TTournamentHostForm.CloseTournament(Dialog:TTournamentDialog):Boolean;
begin Result:=CloseOne(TabFor(Dialog));end;
procedure TTournamentHostForm.CloseClick(Sender:TObject);
begin CloseOne(ActiveTab);end;
procedure TTournamentHostForm.ClosePage(Sender:TObject);
var I:Integer;
begin
  if FBusy then Exit;
  for I:=0 to Count-1 do if TTournamentTab(FTabs[I]).Page=Sender then begin
    Application.QueueAsyncCall(@AsyncClose,TTournamentTab(FTabs[I]).Id);Exit;
  end;
end;
procedure TTournamentHostForm.ChildCloseQuery(Sender:TObject;var CanClose:Boolean);
var Tab:TTournamentTab;
begin
  CanClose:=False;Tab:=TabFor(Sender);
  if (Tab<>nil) and not FBusy then Application.QueueAsyncCall(@AsyncClose,Tab.Id);
end;
procedure TTournamentHostForm.AsyncClose(Id:PtrInt);
var I:Integer;
begin
  if FDisposing or FBusy then Exit;
  for I:=0 to Count-1 do if TTournamentTab(FTabs[I]).Id=Id then begin CloseOne(TTournamentTab(FTabs[I]));Exit;end;
end;
procedure TTournamentHostForm.HostCloseQuery(Sender:TObject;var CanClose:Boolean);
begin
  CanClose:=False;if FDisposing then begin CanClose:=True;Exit;end;
  try if PrepareCloseAll then CanClose:=FinishCloseAll;
  except on E:Exception do ShowGuiOkDialog(Self,'Close tournaments',E.Message);end;
end;
procedure TTournamentHostForm.RemoveTab(Tab:TTournamentTab);
var D:TTournamentDialog;
begin
  FTabs.Remove(Tab);D:=Tab.Dialog;Tab.Dialog:=nil;
  if D<>nil then begin D.RemoveFreeNotification(Self);D.Free;end;
  Tab.Page.Free;Tab.Free;
end;
procedure TTournamentHostForm.Notification(AComponent:TComponent;Operation:TOperation);
var Tab:TTournamentTab;
begin
  inherited Notification(AComponent,Operation);
  if FDisposing or (FTabs=nil) or (Operation<>opRemove) then Exit;
  Tab:=TabFor(AComponent);if Tab<>nil then begin Tab.Dialog:=nil;PageChanged(Self);end;
end;
procedure TTournamentHostForm.BeginShutdown;
var I:Integer;
begin
  for I:=0 to Count-1 do if Dialogs[I]<>nil then Dialogs[I].BeginShutdown;
end;
procedure TTournamentHostForm.ContextRequested(Sender:TObject;Variant:TGameVariant;const FileName:string);
var Tab:TTournamentTab;
begin
  if FDisposing or FBusy then Exit;
  try
    if FileName<>'' then begin OpenFile(FileName,Variant);Exit;end;
    Tab:=TabFor(Sender);
    if (Tab=nil) or (Tab.Dialog=nil) or (Tab.Dialog.Variant=Variant) then Exit;
    // Never destroy a combo or its form inside the native selection callback.
    // Identify the tab by its stable ID: it may close before this call runs.
    if Tab.PendingVariant=nil then Application.QueueAsyncCall(@AsyncGameSwitch,Tab.Id);
    Tab.PendingVariant:=Variant;
  except on E:Exception do ShowGuiOkDialog(Self,'Tournament game',E.Message);end;
end;

procedure TTournamentHostForm.AsyncGameSwitch(Id:PtrInt);
var I:Integer;Tab:TTournamentTab;Variant:TGameVariant;
begin
  if FDisposing then Exit;
  for I:=0 to Count-1 do begin
    Tab:=TTournamentTab(FTabs[I]);
    if Tab.Id<>Id then Continue;
    Variant:=Tab.PendingVariant;Tab.PendingVariant:=nil;
    if (Variant<>nil) and not FBusy and (Tab.Dialog<>nil) and
      (Tab.Dialog.Variant<>Variant) then SwitchGame(Tab,Variant);
    Exit;
  end;
end;

procedure TTournamentHostForm.SwitchGame(Tab:TTournamentTab;Variant:TGameVariant);
var Plan:TTournamentClosePlan;
begin
  try
    FBusy:=True;
    try if not Prepare(Tab,Plan) then Exit;finally FBusy:=False;end;
    FBusy:=True;
    try
      Tab.Dialog.StopForClose;
      if not Tab.Dialog.DrainClose and (Plan.SaveName<>'') then
        raise EInOutError.Create('Final tournament capture failed');
      if Plan.SaveName<>'' then Tab.Dialog.SaveTournamentToFile(Plan.SaveName);
      BeginTabUpdate;
      try Tab.Dialog.ResetForVariant(Variant);
      finally EndTabUpdate;end;
    finally FBusy:=False;end;
  except on E:Exception do ShowGuiOkDialog(Self,'Tournament game',E.Message);end;
end;
end.
