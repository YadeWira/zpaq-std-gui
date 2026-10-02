{ fmain: the main window of manager mode: every command as an action, the toolbar, the path bar,
  the warning strip, the welcome panel, the status bar, the menu and the About box; it remembers
  its size, position and maximised state. M0: no archive can be opened yet (DESIGN.md §18). }
unit fmain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  StdCtrls, Buttons, Menus, ActnList, LCLIntf, LCLType, LazUTF8, LazFileUtils,
  zsconfig, zslang, zsui, zsicons;

type

  { TFormMain }

  TFormMain = class(TForm)
    actAbout: TAction;
    actAdd: TAction;
    actCloseArchive: TAction;
    actCreate: TAction;
    actExit: TAction;
    actExtract: TAction;
    actExtractTo: TAction;
    actFind: TAction;
    actMenu: TAction;
    actOpen: TAction;
    actProps: TAction;
    actReload: TAction;
    actSettings: TAction;
    actTest: TAction;
    actUp: TAction;
    alMain: TActionList;
    btnCloseWarning: TSpeedButton;
    btnUp: TSpeedButton;
    btnWelcomeCreate: TButton;
    btnWelcomeOpen: TButton;
    cbVersion: TComboBox;
    edPath: TEdit;
    edSearch: TEdit;
    imgWarning: TImage;
    imgWelcomeApp: TImage;
    lblNoRecent: TLabel;
    lblRecentTitle: TLabel;
    lblVersion: TLabel;
    lblWarning: TLabel;
    lblWelcomeHint: TLabel;
    lblWelcomeTitle: TLabel;
    miAbout: TMenuItem;
    miCloseArchive: TMenuItem;
    miExit: TMenuItem;
    miOpen: TMenuItem;
    miProps: TMenuItem;
    miRecent: TMenuItem;
    miReload: TMenuItem;
    miSep1: TMenuItem;
    miSep2: TMenuItem;
    miSep3: TMenuItem;
    miSettings: TMenuItem;
    pmMain: TPopupMenu;
    pnlPath: TPanel;
    pnlRecentList: TPanel;
    pnlToolbar: TPanel;
    pnlWarnings: TPanel;
    pnlWelcome: TPanel;
    pnlWelcomeButtons: TPanel;
    sbMain: TStatusBar;
    tbAdd: TToolButton;
    tbCloseArchive: TToolButton;
    tbCreate: TToolButton;
    tbExtract: TToolButton;
    tbExtractTo: TToolButton;
    tbMain: TToolBar;
    tbMenu: TToolButton;
    tbOpen: TToolButton;
    tbProps: TToolButton;
    tbRight: TToolBar;
    tbSep1: TToolButton;
    tbSep2: TToolButton;
    tbSep3: TToolButton;
    tbSettings: TToolButton;
    tbTest: TToolButton;
    procedure actAboutExecute(Sender: TObject);
    procedure actExitExecute(Sender: TObject);
    procedure actMenuExecute(Sender: TObject);
    procedure alMainUpdate(AAction: TBasicAction; var Handled: Boolean);
    procedure btnCloseWarningClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormShow(Sender: TObject);
    procedure FormWindowStateChange(Sender: TObject);
    procedure pnlWelcomeResize(Sender: TObject);
  private
    FStartupArchive: string;
    FStartupDone: Boolean;
    FRecentFiles: TStringArray;    // what the welcome links and the Recent menu show
    FWasMaximized: Boolean;        // the last state that was not minimised was maximised
    procedure ApplyIcons;
    procedure LoadPictures;
    procedure RestoreGeometry;
    procedure StoreGeometry;
    procedure UpdateTitle;
    procedure RebuildRecent;
    procedure RecentClick(Sender: TObject);
    procedure SetStatus(const Msg: string);
    procedure ShowStartupNotes;
    procedure OpenArchive(const FileName: string);
    procedure StartupOpen(Data: PtrInt);
  public
    procedure AfterConstruction; override;
    { archive named on the command line; opened once the window is shown }
    property StartupArchive: string read FStartupArchive write FStartupArchive;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.lfm}

const
  WelcomeRecentCount = 5;    // recent archives shown as links on the welcome panel
  StatusMessage = 0;         // status bar panels: message, folder totals, archive kind, selection

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  PrepareForm(Self);
  ApplyIcons;
  lblWelcomeTitle.Caption := AppName;
  lblWelcomeTitle.Font.Color := Pal.Accent;
  lblNoRecent.Font.Color := Pal.Dim;
  pnlWelcome.Color := Pal.BG3;
  RebuildRecent;
  UpdateTitle;
  SetStatus(Tr('status.ready'));
  ShowStartupNotes;
end;

{ OnCreate runs before the LCL scales the form to the screen PPI; what depends on the final pixel
  sizes is done here, after that scaling }
procedure TFormMain.AfterConstruction;
begin
  inherited AfterConstruction;
  LoadPictures;
  RestoreGeometry;
end;

procedure TFormMain.FormShow(Sender: TObject);
begin
  if not FStartupDone then
  begin
    FStartupDone := True;
    if FStartupArchive <> '' then
      Application.QueueAsyncCall(@StartupOpen, 0);
  end;
end;

procedure TFormMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  WasWritable: Boolean;
begin
  StoreGeometry;
  WasWritable := Cfg.Writable;
  if not SaveConfig(Cfg) and WasWritable then
    ShowMessageBox(TrF('msg.settings_not_saved',
      ['file', Cfg.FileName, 'reason', Cfg.SaveError]), mtWarning);
end;

procedure TFormMain.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  // M1: one archive opens it; M4: other files go to the Create or Add dialog (DESIGN.md §5.13)
  if Length(FileNames) > 0 then
    OpenArchive(FileNames[0]);
end;

{ minimising keeps the state to come back to, so a window closed while minimised remembers it }
procedure TFormMain.FormWindowStateChange(Sender: TObject);
begin
  if WindowState <> wsMinimized then
    FWasMaximized := WindowState = wsMaximized;
end;

{ the welcome controls are centred horizontally by their anchors; this centres them vertically }
procedure TFormMain.pnlWelcomeResize(Sender: TObject);
var
  Used, Gap: Integer;
begin
  Used := pnlRecentList.Top + pnlRecentList.Height - imgWelcomeApp.Top;
  Gap := Max(Scale96ToForm(8), (pnlWelcome.ClientHeight - Used) div 2);
  if imgWelcomeApp.BorderSpacing.Top <> Gap then
    imgWelcomeApp.BorderSpacing.Top := Gap;
end;

{ ---- icons, title, status ------------------------------------------------------------------- }

procedure TFormMain.ApplyIcons;
begin
  // Settings and Menu sit at the right edge in their own toolbar, tbRight (DESIGN.md §5.2).
  // ImagesWidth stays 0: each list's own size (zsicons) is used, scaled to the screen.
  tbMain.Images := ToolbarImages;
  tbRight.Images := ToolbarImages;
  pmMain.Images := SmallImages;
  btnUp.Images := SmallImages;
  btnCloseWarning.Images := SmallImages;
  btnCloseWarning.ImageIndex := IconIndex(icoCloseArchive);

  actOpen.ImageIndex := IconIndex(icoOpen);
  actCreate.ImageIndex := IconIndex(icoCreate);
  actAdd.ImageIndex := IconIndex(icoAdd);
  actExtract.ImageIndex := IconIndex(icoExtract);
  actExtractTo.ImageIndex := IconIndex(icoExtractTo);
  actTest.ImageIndex := IconIndex(icoTest);
  actProps.ImageIndex := IconIndex(icoInfo);
  actCloseArchive.ImageIndex := IconIndex(icoCloseArchive);
  actSettings.ImageIndex := IconIndex(icoSettings);
  actMenu.ImageIndex := IconIndex(icoMenu);
  actUp.ImageIndex := IconIndex(icoUp);
  actReload.ImageIndex := IconIndex(icoReload);
  actFind.ImageIndex := IconIndex(icoSearch);
end;

procedure TFormMain.LoadPictures;
var
  Pic: TPortableNetworkGraphic;
begin
  Pic := LoadIconPicture(icoApp, imgWelcomeApp.Width);
  try
    imgWelcomeApp.Picture.Assign(Pic);
  finally
    Pic.Free;
  end;
  Pic := LoadIconPicture(icoWarn, imgWarning.Width);
  try
    imgWarning.Picture.Assign(Pic);
  finally
    Pic.Free;
  end;
end;

procedure TFormMain.UpdateTitle;
begin
  // M1: 'ZPAQ-std - <display name>' while an archive is open
  Caption := AppName;
end;

procedure TFormMain.SetStatus(const Msg: string);
begin
  sbMain.Panels[StatusMessage].Text := Msg;
  sbMain.Hint := Msg;   // the panel may cut a long message
end;

{ things the user should know once: a language file that failed, read-only portable settings }
procedure TFormMain.ShowStartupNotes;
begin
  if LangFailed <> '' then
    SetStatus(TrF('status.lang_failed', ['name', LangFailed]))
  else if Cfg.ReadOnlyPortable then
    SetStatus(TrF('status.readonly_portable', ['file', Cfg.FileName]));
end;

{ ---- window geometry ------------------------------------------------------------------------ }

{ R is usable when the top strip of the window (where the title bar is) lies on a monitor }
function OnVisibleMonitor(const R: TRect; MinVisible: Integer): Boolean;
var
  I: Integer;
  Strip, Inter: TRect;
begin
  Inter := Default(TRect);
  Strip := Rect(R.Left, R.Top, R.Right, R.Top + MinVisible);
  for I := 0 to Screen.MonitorCount - 1 do
    if IntersectRect(Inter, Strip, Screen.Monitors[I].WorkareaRect)
      and (Inter.Right - Inter.Left >= 2 * MinVisible) then
      Exit(True);
  Result := False;
end;

{ what the window frame adds to the client size that the LCL calls Width and Height: the borders
  and the caption (the window is not shown yet, so the system metrics are used) }
procedure FrameSize(out FrameW, FrameH: Integer);
{$IFDEF WINDOWS}
const
  ZS_SM_CXPADDEDBORDER = 92;   // Vista and later; 0 on XP
{$ENDIF}
var
  Border: Integer;
begin
  Border := GetSystemMetrics(SM_CXSIZEFRAME);
  {$IFDEF WINDOWS}
  Inc(Border, GetSystemMetrics(ZS_SM_CXPADDEDBORDER));
  {$ENDIF}
  FrameW := 2 * Max(Border, 0);
  FrameH := FrameW + Max(GetSystemMetrics(SM_CYCAPTION), 0);
end;

{ the saved bounds, made to fit: the size within the work area of the monitor that holds the
  window (with the frame), the position moved inside it; a window on no monitor (one that was
  unplugged) is centred on the nearest one. Done by hand rather than with poScreenCenter, which
  the LCL ignores for a maximised form, whose restored bounds would then stay off-screen. }
procedure TFormMain.RestoreGeometry;
var
  L, T, W, H, FrameW, FrameH: Integer;
  Saved, Work: TRect;
  OnScreen: Boolean;
begin
  // [gui] window is at 96 PPI
  L := Scale96ToForm(Cfg.Window.Left);
  T := Scale96ToForm(Cfg.Window.Top);
  W := Max(Constraints.MinWidth, Scale96ToForm(Cfg.Window.Width));
  H := Max(Constraints.MinHeight, Scale96ToForm(Cfg.Window.Height));
  FrameSize(FrameW, FrameH);
  Saved := Rect(L, T, L + W + FrameW, T + H + FrameH);
  OnScreen := OnVisibleMonitor(Saved, Scale96ToForm(32));
  Work := Screen.MonitorFromRect(Saved, mdNearest).WorkareaRect;
  W := Min(W, Max(Constraints.MinWidth, Work.Right - Work.Left - FrameW));
  H := Min(H, Max(Constraints.MinHeight, Work.Bottom - Work.Top - FrameH));
  if OnScreen then
  begin
    L := Max(Work.Left, Min(L, Work.Right - W - FrameW));
    T := Max(Work.Top, Min(T, Work.Bottom - H - FrameH));
  end
  else
  begin
    L := Work.Left + Max(0, (Work.Right - Work.Left - W - FrameW) div 2);
    T := Work.Top + Max(0, (Work.Bottom - Work.Top - H - FrameH) div 2);
  end;
  Position := poDesigned;
  SetRestoredBounds(L, T, W, H, False);
  FWasMaximized := Cfg.Maximized;
  if Cfg.Maximized then
    WindowState := wsMaximized;
end;

procedure TFormMain.StoreGeometry;
var
  G: TWindowGeometry;
begin
  if WindowState = wsNormal then
  begin
    G.Left := Left;
    G.Top := Top;
    G.Width := Width;
    G.Height := Height;
  end
  else
  begin
    G.Left := RestoredLeft;
    G.Top := RestoredTop;
    G.Width := RestoredWidth;
    G.Height := RestoredHeight;
  end;
  if (G.Width <= 0) or (G.Height <= 0) then
    Exit;
  Cfg.Window.Left := ScaleFormTo96(G.Left);
  Cfg.Window.Top := ScaleFormTo96(G.Top);
  Cfg.Window.Width := Max(100, ScaleFormTo96(G.Width));
  Cfg.Window.Height := Max(100, ScaleFormTo96(G.Height));
  Cfg.Maximized := (WindowState = wsMaximized)
    or ((WindowState = wsMinimized) and FWasMaximized);
end;

{ ---- recent archives ------------------------------------------------------------------------ }

procedure TFormMain.RebuildRecent;
var
  I, N: Integer;
  Link: TLabel;
  Item: TMenuItem;
begin
  for I := pnlRecentList.ControlCount - 1 downto 0 do
    if pnlRecentList.Controls[I] <> lblNoRecent then
      pnlRecentList.Controls[I].Free;
  miRecent.Clear;
  // missing files are dropped when shown (DESIGN.md §11.2)
  FRecentFiles := nil;
  for I := 0 to High(Cfg.Recent) do
    if FileExistsUTF8(Cfg.Recent[I]) then
    begin
      N := Length(FRecentFiles);
      SetLength(FRecentFiles, N + 1);
      FRecentFiles[N] := Cfg.Recent[I];
    end;
  for I := 0 to High(FRecentFiles) do
  begin
    Item := TMenuItem.Create(Self);
    Item.Caption := StringReplace(FRecentFiles[I], '&', '&&', [rfReplaceAll]);
    Item.Tag := I;
    Item.OnClick := @RecentClick;
    miRecent.Add(Item);
    if I < WelcomeRecentCount then
    begin
      Link := TLabel.Create(Self);
      Link.ShowAccelChar := False;   // '&' is part of the file name
      Link.Caption := ExtractFileName(FRecentFiles[I]);
      Link.Hint := FRecentFiles[I];
      Link.ShowHint := True;
      Link.Font.Color := Pal.Accent;
      Link.Font.Style := [fsUnderline];
      Link.Cursor := crHandPoint;
      Link.Tag := I;
      Link.OnClick := @RecentClick;
      Link.Parent := pnlRecentList;
      ApplyControlFont(Link);   // its own colour and style: it does not follow the form's font
    end;
  end;
  lblNoRecent.Visible := Length(FRecentFiles) = 0;
  if Length(FRecentFiles) = 0 then
  begin
    Item := TMenuItem.Create(Self);
    Item.Caption := Tr('main.recent_empty');
    Item.Enabled := False;
    miRecent.Add(Item);
  end;
end;

procedure TFormMain.RecentClick(Sender: TObject);
var
  I: Integer;
begin
  I := TComponent(Sender).Tag;
  if (I >= 0) and (I <= High(FRecentFiles)) then
    OpenArchive(FRecentFiles[I]);
end;

{ ---- commands ------------------------------------------------------------------------------- }

procedure TFormMain.OpenArchive(const FileName: string);
begin
  // M1: zsops.DetectArchive, the password, the list job and the model (DESIGN.md §5.12)
  SetStatus(TrF('main.open_not_available', ['name', ExtractFileName(FileName)]));
end;

procedure TFormMain.StartupOpen(Data: PtrInt);
begin
  OpenArchive(FStartupArchive);
end;

procedure TFormMain.alMainUpdate(AAction: TBasicAction; var Handled: Boolean);
var
  HasArchive: Boolean;
begin
  HasArchive := False;                  // M1: True while an archive is open
  // commands of later milestones stay disabled until their code exists (DESIGN.md §18)
  actOpen.Enabled := False;             // M1
  actCreate.Enabled := False;           // M4
  actSettings.Enabled := False;         // M6
  actAdd.Enabled := HasArchive;         // M4: zpaq or zip at the latest version
  actExtract.Enabled := HasArchive;     // M2
  actExtractTo.Enabled := HasArchive;   // M2
  actTest.Enabled := HasArchive;        // M2
  actProps.Enabled := HasArchive;       // M1
  actCloseArchive.Enabled := HasArchive;
  actReload.Enabled := HasArchive;
  actUp.Enabled := HasArchive;          // M1: and not at the root
  actFind.Enabled := HasArchive;        // M5
  edSearch.Enabled := HasArchive;
  Handled := True;
end;

procedure TFormMain.actMenuExecute(Sender: TObject);
var
  P: TPoint;
begin
  P := tbMenu.ClientToScreen(Point(tbMenu.Width, tbMenu.Height));
  pmMain.PopUp(P.X, P.Y);
end;

procedure TFormMain.actExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TFormMain.btnCloseWarningClick(Sender: TObject);
begin
  pnlWarnings.Visible := False;
end;

procedure TFormMain.actAboutExecute(Sender: TObject);
var
  Msg, LicDir: string;
begin
  Msg := AppTitle + LineEnding + Tr('about.description') + LineEnding + LineEnding
    + Tr('about.license') + LineEnding + LineEnding
    + Tr('about.credits') + LineEnding
    + Tr('about.credit_zpaq') + LineEnding
    + Tr('about.credit_7z') + LineEnding
    + Tr('about.credit_icons') + LineEnding
    + Tr('about.credit_tools');
  LicDir := ExtractFilePath(ParamStrUTF8(0)) + 'licenses';
  // the licence texts ship with the package (M6); a development build has none
  if DirectoryExistsUTF8(LicDir) then
  begin
    if QuestionDlg(TrF('about.title', ['name', AppName]), Msg, mtInformation,
      [mrYes, Tr('btn.licenses'), mrClose, Tr('btn.close'), 'IsDefault', 'IsCancel'], 0) = mrYes then
      OpenDocument(LicDir);
  end
  else
    QuestionDlg(TrF('about.title', ['name', AppName]), Msg, mtInformation,
      [mrClose, Tr('btn.close'), 'IsDefault', 'IsCancel'], 0);
end;

end.
