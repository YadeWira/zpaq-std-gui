{ zsui: what every form shares: the program name and version, the palette and the theme choice
  (light only until M8), the [gui] font, the walker that translates a form's components from the
  language file, the LCL's key names, message boxes, and where the language files are. }
unit zsui;

{$mode objfpc}{$H+}

(* Public API

  AppName, AppVersion, AppExeName      from version.inc (included here only)
  AppArch: string                      'x64', 'x86' or the CPU name
  AppTitle: string                     'ZPAQ-std 0.0.1 (x64)'

  TPalette / Pal                       the colours of our own drawing (DESIGN.md §13): system colours
                                       in Light, coral for the accent tokens
  InitTheme(Choice)                    resolves auto/light/dark and fills Pal. M0-M7: always Light
                                       (Dark arrives in M8 on Windows 10 1809+)

  ApplyFormFont(Form)                  [gui] font, when set, as the font name of the form and of
                                       every control of it that does not take its parent's font
                                       (a bold title, a coloured label)
  ApplyControlFont(Control)            the same for one control created at run time; call it
                                       after its Font and Parent are set
  TranslateComponents(Form)            sets texts from the language file, by key
                                       '<form name>.<component name>[.suffix]' (lower case):
                                         <form>.caption                 Form.Caption
                                         <component>                    Caption of a control, menu
                                                                        item or action (not of edits
                                                                        and combos, whose caption is
                                                                        their text)
                                         <component>.hint               Hint
                                         <component>.texthint           TextHint of an edit
                                         <component>.col<N>             VirtualTreeView column N
                                         <component>.item<N>            radio/check group item N
                                       Actions first, so a control with its own key keeps it even
                                       when it is linked to an action. A missing key leaves the
                                       .lfm text.
  PrepareForm(Form)                    ApplyFormFont + TranslateComponents (call in FormCreate)

  TranslateKeyNames                    the LCL's key names in menu shortcuts ('Alt+Enter') from
                                       the [keys] section: keys.enter, keys.shift... (call after
                                       LangLoad, before the first form)
  ShowMessageBox(Text, Kind)           QuestionDlg titled AppName with one translated OK button
  GuiLangDir: string                   zslang.DefaultLangDir (<exe dir>/lang/). Only an exe of a
                                       checkout (bin/<cpu>-<os>/ under the folder of
                                       src/zpaqstdgui.lpi) without that folder uses <repo>/lang/
*)

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, StdCtrls, ExtCtrls, Menus, ActnList, Dialogs,
  LazUTF8, LazFileUtils, laz.VirtualTrees, zsconfig, zslang;

{$I version.inc}

type
  TPalette = record
    Dark: Boolean;
    BG, BG2, BG3: TColor;        // panels, strips, list background
    FG, Dim: TColor;             // text, secondary text
    Sel, SelFG: TColor;          // list selection
    Border: TColor;              // 1-px separators
    Accent, AccentTrack: TColor; // progress bar, progress header, sort glyph, welcome title
    Ok, Warn, Error: TColor;     // results and states (always with an icon and a word)
  end;

var
  Pal: TPalette;   // the palette of the program (one of the three globals)

function AppArch: string;
function AppTitle: string;
procedure InitTheme(Choice: TThemeChoice);
procedure ApplyFormFont(Form: TCustomForm);
procedure ApplyControlFont(C: TControl);
procedure TranslateComponents(Form: TCustomForm);
procedure PrepareForm(Form: TCustomForm);
procedure TranslateKeyNames;
procedure ShowMessageBox(const Text: string; Kind: TMsgDlgType);
function GuiLangDir: string;

implementation

const
  LightPalette: TPalette = (
    Dark: False;
    BG: clBtnFace; BG2: clBtnFace; BG3: clWindow;
    FG: clWindowText; Dim: clGrayText;
    Sel: clHighlight; SelFG: clHighlightText;
    Border: clBtnShadow;
    Accent: $002B3BCC;        // #CC3B2B (TColor is $00BBGGRR)
    AccentTrack: $00D2D6F3;   // #F3D6D2
    Ok: $00327D2E;            // #2E7D32
    Warn: $00005CA1;          // #A15C00
    Error: $002828C6);        // #C62828

function AppArch: string;
begin
  {$if defined(CPUX86_64)}
  Result := 'x64';
  {$elseif defined(CPU386)}
  Result := 'x86';
  {$else}
  Result := {$I %FPCTARGETCPU%};
  {$endif}
end;

function AppTitle: string;
begin
  Result := AppName + ' ' + AppVersion + ' (' + AppArch + ')';
end;

procedure InitTheme(Choice: TThemeChoice);
begin
  // M8: thDark, or thAuto on Windows 10 1809+ with AppsUseLightTheme = 0, gives the dark palette
  Pal := LightPalette;
end;

procedure ApplyControlFont(C: TControl);
begin
  if (Trim(Cfg.Font) <> '') and not C.IsParentFont then
    C.Font.Name := Trim(Cfg.Font);
end;

procedure ApplyFormFont(Form: TCustomForm);
var
  I: Integer;
begin
  if Trim(Cfg.Font) = '' then
    Exit;
  Form.Font.Name := Trim(Cfg.Font);
  // the controls with a font of their own (size, style or colour changed) do not follow the form
  for I := 0 to Form.ComponentCount - 1 do
    if Form.Components[I] is TControl then
      ApplyControlFont(TControl(Form.Components[I]));
end;

procedure TranslateAction(A: TCustomAction; const Key: string);
var
  V: string;
begin
  if LangTryGet(Key, V) then
    A.Caption := V;
  if LangTryGet(Key + '.hint', V) then
    A.Hint := V;
end;

procedure TranslateControl(C: TControl; const Key: string);
var
  V: string;
  I: Integer;
  Items: TStrings;
  Tree: TLazVirtualStringTree;
begin
  if not ((C is TCustomEdit) or (C is TCustomComboBox)) and LangTryGet(Key, V) then
    C.Caption := V;
  if LangTryGet(Key + '.hint', V) then
    C.Hint := V;
  if (C is TCustomEdit) and LangTryGet(Key + '.texthint', V) then
    TCustomEdit(C).TextHint := V;
  if C is TLazVirtualStringTree then
  begin
    Tree := TLazVirtualStringTree(C);
    for I := 0 to Tree.Header.Columns.Count - 1 do
      if LangTryGet(Key + '.col' + IntToStr(I), V) then
        Tree.Header.Columns[I].Text := V;
  end;
  Items := nil;
  if C is TCustomRadioGroup then
    Items := TCustomRadioGroup(C).Items
  else if C is TCustomCheckGroup then
    Items := TCustomCheckGroup(C).Items;
  if Items <> nil then
    for I := 0 to Items.Count - 1 do
      if LangTryGet(Key + '.item' + IntToStr(I), V) then
        Items[I] := V;
end;

procedure TranslateMenuItem(M: TMenuItem; const Key: string);
var
  V: string;
begin
  if LangTryGet(Key, V) then
    M.Caption := V;
  if LangTryGet(Key + '.hint', V) then
    M.Hint := V;
end;

procedure TranslateComponents(Form: TCustomForm);
var
  Prefix, V: string;
  I: Integer;
  C: TComponent;
begin
  Prefix := LowerCase(Form.Name) + '.';
  if LangTryGet(Prefix + 'caption', V) then
    Form.Caption := V;
  for I := 0 to Form.ComponentCount - 1 do
  begin
    C := Form.Components[I];
    if (C.Name <> '') and (C is TCustomAction) then
      TranslateAction(TCustomAction(C), Prefix + LowerCase(C.Name));
  end;
  for I := 0 to Form.ComponentCount - 1 do
  begin
    C := Form.Components[I];
    if C.Name = '' then
      Continue;
    if C is TControl then
      TranslateControl(TControl(C), Prefix + LowerCase(C.Name))
    else if C is TMenuItem then
      TranslateMenuItem(TMenuItem(C), Prefix + LowerCase(C.Name));
  end;
end;

procedure PrepareForm(Form: TCustomForm);
begin
  ApplyFormFont(Form);
  TranslateComponents(Form);
end;

{ LCL resourcestrings 'lclstrconsts.smkc<name>' ('Enter', 'Shift+') and the modifier names of
  the GTK accelerators ('lclstrconsts.ifsctrl') -> keys.<name> }
function KeyNameFor(Name, Value: AnsiString; Hash: LongInt; Arg: Pointer): AnsiString;
const
  Smkc = 'lclstrconsts.smkc';
var
  N, V: string;
  Plus: Boolean;
begin
  Result := '';
  N := LowerCase(Name);
  Plus := False;
  if Copy(N, 1, Length(Smkc)) = Smkc then
  begin
    N := Copy(N, Length(Smkc) + 1, MaxInt);
    Plus := (N = 'shift') or (N = 'ctrl') or (N = 'alt') or (N = 'meta');   // 'Shift+'
  end
  else if N = 'lclstrconsts.ifsvk_shift' then
    N := 'shift'
  else if N = 'lclstrconsts.ifsctrl' then
    N := 'ctrl'
  else if N = 'lclstrconsts.ifsalt' then
    N := 'alt'
  else
    Exit;
  if LangTryGet('keys.' + N, V) and (V <> '') then
  begin
    Result := V;
    if Plus then
      Result := Result + '+';
  end;
end;

procedure TranslateKeyNames;
begin
  SetUnitResourceStrings('lclstrconsts', @KeyNameFor, nil);
end;

procedure ShowMessageBox(const Text: string; Kind: TMsgDlgType);
begin
  QuestionDlg(AppName, Text, Kind, [mrOK, Tr('btn.ok'), 'IsDefault', 'IsCancel'], 0);
end;

function GuiLangDir: string;
var
  Repo: string;
begin
  Result := DefaultLangDir;
  if DirectoryExistsUTF8(Result) then
    Exit;
  // an IDE build in <repo>/bin/<cpu>-<os>/ (tools/build.sh copies lang/ next to the exe itself)
  Repo := ExpandFileNameUTF8(ExtractFilePath(ParamStrUTF8(0)) + '..' + PathDelim + '..')
    + PathDelim;
  if FileExistsUTF8(Repo + 'src' + PathDelim + 'zpaqstdgui.lpi')
    and FileExistsUTF8(Repo + 'lang' + PathDelim + 'en.zsl') then
    Result := Repo + 'lang' + PathDelim;
end;

end.
