program tournament_embedding_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
  StdCtrls,ExtCtrls,ComCtrls,Graphics,LCLType,LMessages,Math,uMainForm,
  uTournamentDialog,uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile;
type
  TEmbeddingHost=class(TForm)
  public
    Main:TMainForm;
    Pages:TPageControl;
    Dialogs:array[0..1]of TTournamentDialog;
    Accepts,Cancels:array[0..1]of Integer;
    Defaults,CancelButtons:array[0..1]of TButton;
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure AcceptClick(Sender:TObject);
    procedure CancelClick(Sender:TObject);
    procedure TabChanged(Sender:TObject);
    procedure SyncMinimum;
    function ShortcutKey:Boolean;
  end;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Pump;
var I:Integer;
begin for I:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;end;
constructor TEmbeddingHost.Create(AOwner:TComponent);
var I:Integer;Tab:TTabSheet;Footer:TPanel;B:TButton;
begin
  inherited CreateNew(AOwner);
  Caption:='Tournament embedding spike (no engines launched)';
  Width:=1250;Height:=740;Position:=poScreenCenter;
  Main:=TMainForm.Create(nil);
  Pages:=TPageControl.Create(Self);Pages.Parent:=Self;Pages.Align:=alClient;
  for I:=0 to 1 do begin
    Tab:=TTabSheet.Create(Pages);Tab.PageControl:=Pages;
    Tab.Caption:='Tournament'+IntToStr(I+1)+' ('+RegisteredGame(I).Name+')';
    Dialogs[I]:=TTournamentDialog.Create(Main,RegisteredGame(I));
    Dialogs[I].BorderStyle:=bsNone;Dialogs[I].Align:=alClient;
    Dialogs[I].Parent:=Tab;Dialogs[I].Show;
    Footer:=TPanel.Create(Dialogs[I]);Footer.Parent:=Dialogs[I];Footer.Align:=alBottom;
    Footer.Height:=40;Footer.Caption:='Test-only keys: Enter = Accept, Esc = Cancel, Alt+K = shortcut';
    B:=TButton.Create(Dialogs[I]);B.Parent:=Footer;B.Align:=alRight;
    B.Caption:='&Key test';B.Tag:=I;B.OnClick:=@AcceptClick;
    B:=TButton.Create(Dialogs[I]);B.Parent:=Footer;B.Align:=alRight;
    B.Caption:='Test Cancel';B.Cancel:=True;B.Tag:=I;B.OnClick:=@CancelClick;CancelButtons[I]:=B;
    B:=TButton.Create(Dialogs[I]);B.Parent:=Footer;B.Align:=alRight;
    B.Caption:='Test Accept';B.Default:=True;B.Tag:=I;B.OnClick:=@AcceptClick;Defaults[I]:=B;
  end;
  Pages.ActivePageIndex:=0;
  Pages.OnChange:=@TabChanged;TabChanged(Pages);
end;
procedure TEmbeddingHost.TabChanged(Sender:TObject);
begin
  // LCL permits only one default/cancel role per top-level form.
  Defaults[Pages.ActivePageIndex].Default:=True;
  CancelButtons[Pages.ActivePageIndex].Cancel:=True;
  DefaultControl:=Defaults[Pages.ActivePageIndex];
  ActiveDefaultControl:=Defaults[Pages.ActivePageIndex];
  CancelControl:=CancelButtons[Pages.ActivePageIndex];
end;
procedure TEmbeddingHost.SyncMinimum;
var D:TTournamentDialog;
begin
  D:=Dialogs[Pages.ActivePageIndex];
  Constraints.MinWidth:=D.Constraints.MinWidth+Width-D.Parent.ClientWidth;
  Constraints.MinHeight:=D.Constraints.MinHeight+Height-D.Parent.ClientHeight;
  Width:=Max(Width,Constraints.MinWidth);Height:=Max(Height,Constraints.MinHeight);
end;
function TEmbeddingHost.ShortcutKey:Boolean;
var Message:TLMKey;
begin
  FillChar(Message,SizeOf(Message),0);Message.CharCode:=Ord('K');Message.KeyData:=1 shl 29;
  Result:=DialogChar(Message);
end;
destructor TEmbeddingHost.Destroy;
begin
  Dialogs[0].Free;Dialogs[1].Free;Main.Free;
  inherited Destroy;
end;
procedure TEmbeddingHost.AcceptClick(Sender:TObject);
begin
  Inc(Accepts[TControl(Sender).Tag]);
  Caption:=Format('Embedding: tab %d Accept %d / Cancel %d',[TControl(Sender).Tag+1,
    Accepts[TControl(Sender).Tag],Cancels[TControl(Sender).Tag]]);
end;
procedure TEmbeddingHost.CancelClick(Sender:TObject);
begin
  Inc(Cancels[TControl(Sender).Tag]);
  Caption:=Format('Embedding: tab %d Accept %d / Cancel %d',[TControl(Sender).Tag+1,
    Accepts[TControl(Sender).Tag],Cancels[TControl(Sender).Tag]]);
end;
procedure KeyPress(Control:TWinControl;Key:Word);
begin
  if Control.Perform(CN_KEYDOWN,Key,0)=0 then Control.Perform(LM_KEYDOWN,Key,0);
  if Control.Perform(CN_KEYUP,Key,0)=0 then Control.Perform(LM_KEYUP,Key,0);
end;
procedure Inspect(Host:TEmbeddingHost);
var I,J,Size,Mode:Integer;D:TTournamentDialog;Edit:TEdit;Field:TControl;W,H:Integer;
begin
  for Size:=0 to 1 do begin
    Host.Font.Size:=10+6*Size;
    for Mode:=0 to 1 do begin
      if Mode=0 then Host.SetBounds(0,0,1250,740) else Host.SetBounds(0,0,1600,1000);
      for I:=0 to 1 do begin
        Host.Pages.ActivePageIndex:=I;Host.TabChanged(Host.Pages);D:=Host.Dialogs[I];D.Font.Assign(Host.Font);Pump;
        Host.SyncMinimum;Pump;
        Check(D.Owner=Host.Main,'Embedding preserves main-form component ownership');
        Check(D.Parent=Host.Pages.Pages[I],'Each existing dialog is parented to its own tab');
        Check((D.Left=0) and (D.Top=0),'Embedded form starts at page origin');
        Check((D.Width<=D.Parent.ClientWidth) and (D.Height<=D.Parent.ClientHeight),
          'Embedded dialog fits the host page');
        for J:=0 to D.ComponentCount-1 do if D.Components[J] is TButton then begin
          Field:=TControl(D.Components[J]);
          if Field.IsVisible then begin
            Field.GetPreferredSize(W,H,True);
            Check(Field.Width>=W,'Embedded button caption fits');
          end;
        end;
        Edit:=TEdit(D.FindComponent('TournamentName'));Edit.SetFocus;Pump;
        Check(Edit.Focused,'Tab receives keyboard focus');
        Edit.Text:='Tournament '+IntToStr(I+1);
        Check(TEdit(Host.Dialogs[1-I].FindComponent('TournamentName')).Text<>Edit.Text,
          'Edits stay in their own tab');
        J:=Host.Accepts[I];KeyPress(Edit,VK_RETURN);Pump;
        Check(Host.Accepts[I]=J+1,'Enter uses this embedded form default button');
        J:=Host.Cancels[I];KeyPress(Edit,VK_ESCAPE);Pump;
        Check(Host.Cancels[I]=J+1,'Escape uses this embedded form cancel button');
        J:=Host.Accepts[I];Check(Host.ShortcutKey,'Alt+K mnemonic is handled');Pump;
        Check(Host.Accepts[I]=J+1,'Mnemonic targets only the active page');
        Edit.SetFocus;KeyPress(Edit,VK_TAB);Pump;
        Check(not Edit.Focused,'Tab moves keyboard focus within the embedded dialog');
        Check(Host.Visible and D.Visible,'Default/cancel do not close the host or child');
      end;
    end;
  end;
  WriteLn('Tournament embedding checks passed (',Checks,' checks)');
end;
var Host:TEmbeddingHost;
begin
  RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
  RegisterGame(TChessVariant.Create,ChessGuiProfile);RegisterGame(TDraughtsVariant.Create,DraughtsGuiProfile);
  RegisterDefaultGameVariant(RegisteredGame(0));
  try
    Application.CreateForm(TEmbeddingHost,Host);Host.Show;Pump;
    try
      if ParamStr(1)='--interactive' then Application.Run else Inspect(Host);
    finally Host.Free;end;
  finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
