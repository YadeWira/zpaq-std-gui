{ zsconfig: the settings (TConfig and the global Cfg) with every key of zpaq-std-gui.ini, the
  location rule (portable, read-only portable, %APPDATA%\ZPAQ-std, XDG on Unix), loading with
  validation, and the atomic merge-save that keeps other writers' keys and hand-written lines. }
unit zsconfig;

{$mode objfpc}{$H+}
{$PACKENUM 4}   // the enum fields of TConfig are read and written as LongInt (see FieldOf)

(* Public API

  File: zpaq-std-gui.ini, UTF-8 without BOM (a BOM is accepted), CRLF on Windows, LF on Unix.

  Location (LocateConfig)
    <ExeDir>/zpaq-std-gui.ini exists, and both ExeDir and the file are writable
                                      -> FileName = it, Portable = True
    it exists but ExeDir or the file is read-only (Program Files, a CD, a read-only copy)
                                      -> DefaultsFile = it (read first), FileName = the user file,
                                         ReadOnlyPortable = True (the GUI says so once)
    otherwise                         -> FileName = UserConfigDir + 'zpaq-std-gui.ini'
    UserConfigDir: Windows SHGetFolderPathW(CSIDL_APPDATA) + '\ZPAQ-std\' (not GetAppConfigDir,
    which is LOCAL_APPDATA in FPC 3.2.2); Unix $XDG_CONFIG_HOME (default ~/.config) +
    '/zpaq-std-gui/'.

  Reading (LoadConfig)
    Defaults, then DefaultsFile, then FileName (later files win; a list section present in
    FileName replaces the whole list). Keys and sections are case-insensitive, the last duplicate
    wins. An invalid value keeps the default and is listed in Warnings ('[gui] theme=purple').
    Booleans read 0/1, true/false, yes/no, on/off and are written 0/1. theme=white means light.
    Comments: a line that starts with ';' or '#', and a value that starts with one ('font=   ;
    empty = system font' is an empty font). Every key also drops a trailing ' ; comment' except
    the paths (last_open_dir, last_dir, [paths], the [recent] and [extract.history] items),
    which keep the rest of the line as written because a path may contain ' ;' or ' #': a
    comment about a path goes on its own line.

  Saving (SaveConfig) - merge-save
    Only the keys whose value differs from the Baseline (the values as last loaded or saved) are
    written: the file is re-read now, those keys are replaced in place (the line keeps its
    spelling and comment; when a text key with a comment-only value gets a value, the comment
    moves to its own line above it) or added at the end of their section (the section is added
    at the end of the file), list sections get their numbered keys rewritten, every other line
    stays as it is. Then <file>.tmp is written, flushed and moved over the file (MoveFileExW
    REPLACE_EXISTING|WRITE_THROUGH; Unix fsync + rename). Nothing changed -> no write.
    On failure: Writable := False, SaveError := the system's reason, Result False; later calls
    do nothing until Writable is set again. The values in memory stay as they are.

  Adding a key: its TConfig field, its row in KeyDefs (section, name, kind, default text, range
  or choices) and its line in FieldOf. Loading, defaults and saving follow from the table.

  procedure ConfigDefaults(out C)          every key at its default; Writable = True
  function  UserConfigDir: string          with the trailing delimiter; not created
  function  FolderIsWritable(Dir): Boolean creates and deletes a probe file
  procedure LocateConfig(var C, ExeDir, UserDir = '')   UserDir '' = UserConfigDir
  procedure LoadConfig(var C)              resets the keys, reads, sets Baseline and the flags
  procedure InitConfig(var C, ExeDir = '', UserDir = '')  defaults + locate + load
                                           (ExeDir '' = the folder of ParamStrUTF8(0))
  function  SaveConfig(var C): Boolean
  procedure AddRecent(var C, FileName)     to the front, without duplicates, at most MaxRecent
  procedure AddExtractHistory(var C, Dir)  the same for [extract.history]
  function  ParseTheme(S, out T): Boolean  'auto', 'light', 'dark' or 'white' (= light), any case
  function  ParseColumns(S, out Cols): Boolean   'name:320,-size:100' ('-' = hidden); known ids
                                                 only, no duplicates, widths 0..5000
  function  FormatColumns(Cols): string
  function  ParseWindowGeometry(S, out G): Boolean   'left,top,width,height' (96 PPI);
                                                 width/height 100..32767, left/top -32768..32767
  function  FormatWindowGeometry(G): string
  function  IsColumnId(Id): Boolean        name size packed ratio modified method ver folder
*)

interface

uses
  Classes, SysUtils, LazUTF8;

type
  TThemeChoice = (thAuto, thLight, thDark);
  TCreateFormat = (cfZpaq, cfZip);
  TOverwriteMode = (owAsk, owOverwrite, owSkip, owRename);
  TSubfolderMode = (sfSmart, sfAlways, sfNever);

  TWindowGeometry = record
    Left, Top, Width, Height: Integer;   // at 96 PPI
  end;

  TSortSpec = record
    Column: string;      // a column id
    Descending: Boolean;
  end;

  TColumnSpec = record
    Id: string;          // one of ColumnIds
    Width: Integer;      // at 96 PPI
    Visible: Boolean;    // written with a leading '-' when hidden
  end;
  TColumnSpecArray = array of TColumnSpec;

  TConfig = record
    // ---- where the settings live (LocateConfig) and what happened (LoadConfig/SaveConfig)
    FileName: string;           // the file SaveConfig writes
    DefaultsFile: string;       // read-only portable ini read before FileName; '' = none
    Portable: Boolean;          // FileName is next to the exe
    ReadOnlyPortable: Boolean;  // a portable ini exists but it or its folder is read-only
    Writable: Boolean;          // False after a failed save
    SaveError: string;          // the reason of the last failed save
    Warnings: TStringArray;     // invalid values met while loading
    LanguageKeyFound: Boolean;  // [gui] language exists in a file (installer hint: first run only)
    // ---- [gui]
    Language: string;           // 'auto' or a language code ('es', 'es-pe')
    Theme: TThemeChoice;
    Font: string;               // '' = system UI font
    Window: TWindowGeometry;
    Maximized: Boolean;
    ColumnsZpaq: string;        // ParseColumns format, normalised
    Columns7z: string;
    Sort: TSortSpec;
    LastOpenDir: string;
    // ---- [recent]  1..MaxRecent, most recent first
    Recent: TStringArray;
    // ---- [create]
    CreateFormat: TCreateFormat;
    ZpaqMethod: string;         // '0'..'5' or a codec name (lower case)
    ZpaqLevel: Integer;         // 0 = codec default
    ZpaqThreads: Integer;       // 0 = automatic
    ZpaqMultipart: Boolean;
    ZipLevel: Integer;          // 0, 1, 3, 5, 7 or 9
    CreateLastDir: string;
    // ---- [extract]
    Overwrite: TOverwriteMode;
    Subfolder: TSubfolderMode;
    OpenFolder: Boolean;
    // ---- [extract.history]  1..MaxExtractHistory
    ExtractHistory: TStringArray;
    // ---- [progress]
    CloseWhenDone: Boolean;
    ConfirmCancel: Boolean;
    DetailsOpen: Boolean;
    // ---- [paths]  '' = <exe dir>/bin/...
    ZpaqPath: string;
    SevenZipPath: string;
    // ---- [advanced]
    Log: Boolean;
    CollectQuietMs: Integer;    // 200..5000
    // ---- internal: the serialised values as last loaded or saved (merge-save)
    Baseline: TStringArray;
  end;

const
  ConfigFileName = 'zpaq-std-gui.ini';
  MaxRecent = 10;
  MaxExtractHistory = 10;
  DefaultColumnsZpaq = 'name:320,size:100,modified:140,ver:50';
  DefaultColumns7z = 'name:300,size:100,packed:100,ratio:60,modified:140,method:120';
  ColumnIds: array[0..7] of string =
    ('name', 'size', 'packed', 'ratio', 'modified', 'method', 'ver', 'folder');

var
  Cfg: TConfig;   // the settings of the program (one of the three globals)

procedure ConfigDefaults(out C: TConfig);
function UserConfigDir: string;
function FolderIsWritable(const Dir: string): Boolean;
procedure LocateConfig(var C: TConfig; const ExeDir: string; const UserDir: string = '');
procedure LoadConfig(var C: TConfig);
procedure InitConfig(var C: TConfig; const ExeDir: string = ''; const UserDir: string = '');
function SaveConfig(var C: TConfig): Boolean;
procedure AddRecent(var C: TConfig; const FileName: string);
procedure AddExtractHistory(var C: TConfig; const Dir: string);
function ParseTheme(const S: string; out T: TThemeChoice): Boolean;
function ParseColumns(const S: string; out Cols: TColumnSpecArray): Boolean;
function FormatColumns(const Cols: TColumnSpecArray): string;
function ParseWindowGeometry(const S: string; out G: TWindowGeometry): Boolean;
function FormatWindowGeometry(const G: TWindowGeometry): string;
function IsColumnId(const Id: string): Boolean;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  zsutil, zslang;

{$IFDEF MSWINDOWS}
function SHGetFolderPathW(Wnd: HWND; Csidl: LongInt; Token: THandle; Flags: DWORD;
  Path: PWideChar): HRESULT; stdcall; external 'shell32.dll' name 'SHGetFolderPathW';

const
  ZS_CSIDL_APPDATA = $001A;
  ZS_MOVEFILE_REPLACE_EXISTING = $1;
  ZS_MOVEFILE_WRITE_THROUGH = $8;
{$ENDIF}

{ ============================================================================================== }
{ The keys                                                                                       }
{ ============================================================================================== }

type
  { how a key's text is parsed and written, and the type of its TConfig field }
  TValueKind = (
    vkText,       // string, as written ('' allowed): a path, so ' ;' and ' #' are part of it
    vkName,       // string ('' allowed) that never holds ' ;': a trailing comment is dropped
    vkBool,       // Boolean
    vkInt,        // Integer in Lo..Hi (and one of Choices when given)
    vkEnum,       // an enum, by its name in Choices
    vkLanguage,   // string: 'auto' or a language code, normalised ('es_PE' -> 'es-pe')
    vkMethod,     // string: '0'..'5' or a codec name, lower case
    vkColumns,    // string in the ParseColumns format, normalised
    vkWindow,     // TWindowGeometry
    vkSort,       // TSortSpec: 'column,asc|desc'
    vkList);      // TStringArray: a whole section of numbered keys, at most Hi items

  TCfgKey = (ckLanguage, ckTheme, ckFont, ckWindow, ckMaximized, ckColumnsZpaq, ckColumns7z,
    ckSort, ckLastOpenDir, ckRecent, ckCreateFormat, ckZpaqMethod, ckZpaqLevel, ckZpaqThreads,
    ckZpaqMultipart, ckZipLevel, ckCreateLastDir, ckOverwrite, ckSubfolder, ckOpenFolder,
    ckExtractHistory, ckCloseWhenDone, ckConfirmCancel, ckDetailsOpen, ckZpaqPath,
    ckSevenZipPath, ckLog, ckCollectQuietMs);

  TKeyDef = record
    Section: string;
    Name: string;      // '' for a list section
    Kind: TValueKind;
    Default: string;   // as written in the file
    Lo, Hi: Integer;   // vkInt: the range; vkList: Hi = the most items
    Choices: string;   // vkEnum: the names in ordinal order, then aliases 'alias=name';
                       // vkInt: the only values allowed, when not every one of Lo..Hi
  end;

  PWindowGeometry = ^TWindowGeometry;
  PSortSpec = ^TSortSpec;
  PListField = ^TStringArray;

{$push}{$warn 3177 off}   // fields left out of a row are 0 or ''
const
  KeyDefs: array[TCfgKey] of TKeyDef = (
    (Section: 'gui'; Name: 'language'; Kind: vkLanguage; Default: 'auto'),
    (Section: 'gui'; Name: 'theme'; Kind: vkEnum; Default: 'auto';
      Lo: 0; Hi: 0; Choices: 'auto|light|dark|white=light'),
    (Section: 'gui'; Name: 'font'; Kind: vkName),
    (Section: 'gui'; Name: 'window'; Kind: vkWindow; Default: '100,80,900,560'),
    (Section: 'gui'; Name: 'maximized'; Kind: vkBool; Default: '0'),
    (Section: 'gui'; Name: 'columns_zpaq'; Kind: vkColumns; Default: DefaultColumnsZpaq),
    (Section: 'gui'; Name: 'columns_7z'; Kind: vkColumns; Default: DefaultColumns7z),
    (Section: 'gui'; Name: 'sort'; Kind: vkSort; Default: 'name,asc'),
    (Section: 'gui'; Name: 'last_open_dir'; Kind: vkText),
    (Section: 'recent'; Name: ''; Kind: vkList; Default: ''; Lo: 0; Hi: MaxRecent),
    (Section: 'create'; Name: 'format'; Kind: vkEnum; Default: 'zpaq';
      Lo: 0; Hi: 0; Choices: 'zpaq|zip'),
    (Section: 'create'; Name: 'zpaq_method'; Kind: vkMethod; Default: '1'),
    (Section: 'create'; Name: 'zpaq_level'; Kind: vkInt; Default: '0'; Lo: 0; Hi: 99),
    (Section: 'create'; Name: 'zpaq_threads'; Kind: vkInt; Default: '0'; Lo: 0; Hi: 1024),
    (Section: 'create'; Name: 'zpaq_multipart'; Kind: vkBool; Default: '0'),
    (Section: 'create'; Name: 'zip_level'; Kind: vkInt; Default: '5';
      Lo: 0; Hi: 9; Choices: '0|1|3|5|7|9'),
    (Section: 'create'; Name: 'last_dir'; Kind: vkText),
    (Section: 'extract'; Name: 'overwrite'; Kind: vkEnum; Default: 'ask';
      Lo: 0; Hi: 0; Choices: 'ask|overwrite|skip|rename'),
    (Section: 'extract'; Name: 'subfolder'; Kind: vkEnum; Default: 'smart';
      Lo: 0; Hi: 0; Choices: 'smart|always|never'),
    (Section: 'extract'; Name: 'open_folder'; Kind: vkBool; Default: '0'),
    (Section: 'extract.history'; Name: ''; Kind: vkList; Default: ''; Lo: 0;
      Hi: MaxExtractHistory),
    (Section: 'progress'; Name: 'close_when_done'; Kind: vkBool; Default: '1'),
    (Section: 'progress'; Name: 'confirm_cancel'; Kind: vkBool; Default: '1'),
    (Section: 'progress'; Name: 'details_open'; Kind: vkBool; Default: '0'),
    (Section: 'paths'; Name: 'zpaq'; Kind: vkText),
    (Section: 'paths'; Name: 'sevenzip'; Kind: vkText),
    (Section: 'advanced'; Name: 'log'; Kind: vkBool; Default: '0'),
    (Section: 'advanced'; Name: 'collect_quiet_ms'; Kind: vkInt; Default: '700';
      Lo: 200; Hi: 5000));
{$pop}

const
  BoolNames: array[Boolean] of string = ('0', '1');
  SortDirNames: array[Boolean] of string = ('asc', 'desc');
  ListSep = #10;

{ the TConfig field of a key; its type follows KeyDefs[K].Kind (see TValueKind) }
function FieldOf(var C: TConfig; K: TCfgKey): Pointer;
begin
  case K of
    ckLanguage: Result := @C.Language;
    ckTheme: Result := @C.Theme;
    ckFont: Result := @C.Font;
    ckWindow: Result := @C.Window;
    ckMaximized: Result := @C.Maximized;
    ckColumnsZpaq: Result := @C.ColumnsZpaq;
    ckColumns7z: Result := @C.Columns7z;
    ckSort: Result := @C.Sort;
    ckLastOpenDir: Result := @C.LastOpenDir;
    ckRecent: Result := @C.Recent;
    ckCreateFormat: Result := @C.CreateFormat;
    ckZpaqMethod: Result := @C.ZpaqMethod;
    ckZpaqLevel: Result := @C.ZpaqLevel;
    ckZpaqThreads: Result := @C.ZpaqThreads;
    ckZpaqMultipart: Result := @C.ZpaqMultipart;
    ckZipLevel: Result := @C.ZipLevel;
    ckCreateLastDir: Result := @C.CreateLastDir;
    ckOverwrite: Result := @C.Overwrite;
    ckSubfolder: Result := @C.Subfolder;
    ckOpenFolder: Result := @C.OpenFolder;
    ckExtractHistory: Result := @C.ExtractHistory;
    ckCloseWhenDone: Result := @C.CloseWhenDone;
    ckConfirmCancel: Result := @C.ConfirmCancel;
    ckDetailsOpen: Result := @C.DetailsOpen;
    ckZpaqPath: Result := @C.ZpaqPath;
    ckSevenZipPath: Result := @C.SevenZipPath;
    ckLog: Result := @C.Log;
    ckCollectQuietMs: Result := @C.CollectQuietMs;
  else
    Result := nil;
  end;
end;

{ ---- small parsers --------------------------------------------------------------------------- }

function IsColumnId(const Id: string): Boolean;
var
  I: Integer;
begin
  for I := Low(ColumnIds) to High(ColumnIds) do
    if ColumnIds[I] = Id then
      Exit(True);
  Result := False;
end;

function ParseColumns(const S: string; out Cols: TColumnSpecArray): Boolean;
var
  Items, Pair: TStringArray;
  I, J, W: Integer;
  Id: string;
  Visible: Boolean;
begin
  Cols := nil;
  Result := False;
  if Trim(S) = '' then
    Exit;
  Items := SplitAt(S, ',');
  SetLength(Cols, Length(Items));
  for I := 0 to High(Items) do
  begin
    Pair := SplitAt(Trim(Items[I]), ':');
    if Length(Pair) <> 2 then
      Exit;
    Id := LowerCase(Trim(Pair[0]));
    Visible := True;
    if (Id <> '') and (Id[1] = '-') then
    begin
      Visible := False;
      Id := Trim(Copy(Id, 2, MaxInt));
    end;
    if not IsColumnId(Id) then
      Exit;
    for J := 0 to I - 1 do
      if Cols[J].Id = Id then
        Exit;
    if not TryStrToInt(Trim(Pair[1]), W) or (W < 0) or (W > 5000) then
      Exit;
    Cols[I].Id := Id;
    Cols[I].Width := W;
    Cols[I].Visible := Visible;
  end;
  Result := True;
end;

function FormatColumns(const Cols: TColumnSpecArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Cols) do
  begin
    if I > 0 then
      Result := Result + ',';
    if not Cols[I].Visible then
      Result := Result + '-';
    Result := Result + Cols[I].Id + ':' + IntToStr(Cols[I].Width);
  end;
end;

function ParseWindowGeometry(const S: string; out G: TWindowGeometry): Boolean;
var
  Items: TStringArray;
  V: array[0..3] of Integer;
  I: Integer;
begin
  G := Default(TWindowGeometry);
  Result := False;
  Items := SplitAt(S, ',');
  if Length(Items) <> 4 then
    Exit;
  for I := 0 to 3 do
    if not TryStrToInt(Trim(Items[I]), V[I]) then
      Exit;
  if (V[0] < -32768) or (V[0] > 32767) or (V[1] < -32768) or (V[1] > 32767) then
    Exit;
  if (V[2] < 100) or (V[2] > 32767) or (V[3] < 100) or (V[3] > 32767) then
    Exit;
  G.Left := V[0];
  G.Top := V[1];
  G.Width := V[2];
  G.Height := V[3];
  Result := True;
end;

function FormatWindowGeometry(const G: TWindowGeometry): string;
begin
  Result := Format('%d,%d,%d,%d', [G.Left, G.Top, G.Width, G.Height]);
end;

{ 'column,asc' or 'column,desc' (lower case) }
function ParseSort(const S: string; out Sort: TSortSpec): Boolean;
var
  Parts: TStringArray;
begin
  Sort := Default(TSortSpec);
  Parts := SplitAt(S, ',');
  Result := (Length(Parts) = 2) and IsColumnId(Trim(Parts[0]))
    and ((Trim(Parts[1]) = 'asc') or (Trim(Parts[1]) = 'desc'));
  if Result then
  begin
    Sort.Column := Trim(Parts[0]);
    Sort.Descending := Trim(Parts[1]) = 'desc';
  end;
end;

function ParseBool(const S: string; out B: Boolean): Boolean;
begin
  B := False;
  Result := True;
  if (S = '1') or (S = 'true') or (S = 'yes') or (S = 'on') then
    B := True
  else if not ((S = '0') or (S = 'false') or (S = 'no') or (S = 'off')) then
    Result := False;
end;

{ a lower-case name: letters, digits and Extra, at most 32 characters }
function ValidIdent(const S: string; Extra: Char): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and (Length(S) <= 32);
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', '0'..'9', Extra]) then
      Exit(False);
end;

{ Choices 'a|b|c|x=b': the ordinal of Name (an alias gives the ordinal of its target), or -1 }
function ChoiceIndex(const Choices, Name: string): Integer;
var
  Items: TStringArray;
  I, N, P: Integer;
begin
  Items := SplitAt(Choices, '|');
  N := 0;
  for I := 0 to High(Items) do
  begin
    P := Pos('=', Items[I]);
    if P = 0 then
    begin
      if Items[I] = Name then
        Exit(N);
      Inc(N);
    end
    else if Copy(Items[I], 1, P - 1) = Name then
      Exit(ChoiceIndex(Choices, Copy(Items[I], P + 1, MaxInt)));
  end;
  Result := -1;
end;

function ChoiceName(const Choices: string; Index: Integer): string;
var
  Items: TStringArray;
begin
  Items := SplitAt(Choices, '|');
  Result := '';
  if (Index >= 0) and (Index <= High(Items)) and (Pos('=', Items[Index]) = 0) then
    Result := Items[Index];
end;

function ParseTheme(const S: string; out T: TThemeChoice): Boolean;
var
  I: Integer;
begin
  I := ChoiceIndex(KeyDefs[ckTheme].Choices, LowerCase(Trim(S)));
  Result := I >= 0;
  if Result then
    T := TThemeChoice(I)
  else
    T := thAuto;
end;

function JoinList(const L: TStringArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(L) do
  begin
    if I > 0 then
      Result := Result + ListSep;
    Result := Result + L[I];
  end;
end;

{ ---- one value: text <-> field --------------------------------------------------------------- }

{ parses Raw (comment already removed) into the field P; False, field unchanged, when invalid }
function ParseValue(const Def: TKeyDef; const Raw: string; P: Pointer): Boolean;
var
  L: string;
  I: Integer;
  B: Boolean;
  G: TWindowGeometry;
  Sort: TSortSpec;
  Cols: TColumnSpecArray;
begin
  L := LowerCase(Trim(Raw));
  Result := True;
  case Def.Kind of
    vkText, vkName: PString(P)^ := Raw;
    vkBool:
      begin
        Result := ParseBool(L, B);
        if Result then
          PBoolean(P)^ := B;
      end;
    vkInt:
      begin
        Result := TryStrToInt(L, I) and (I >= Def.Lo) and (I <= Def.Hi)
          and ((Def.Choices = '') or (ChoiceIndex(Def.Choices, IntToStr(I)) >= 0));
        if Result then
          PInteger(P)^ := I;
      end;
    vkEnum:
      begin
        I := ChoiceIndex(Def.Choices, L);
        Result := I >= 0;
        if Result then
          PLongInt(P)^ := I;
      end;
    vkLanguage:
      begin
        L := NormalizeLangCode(Raw);
        Result := (L = 'auto') or ValidLangCode(L);
        if Result then
          PString(P)^ := L;
      end;
    vkMethod:
      begin
        Result := ValidIdent(L, '_');
        if Result then
          PString(P)^ := L;
      end;
    vkColumns:
      begin
        Result := ParseColumns(Raw, Cols);
        if Result then
          PString(P)^ := FormatColumns(Cols);
      end;
    vkWindow:
      begin
        Result := ParseWindowGeometry(Raw, G);
        if Result then
          PWindowGeometry(P)^ := G;
      end;
    vkSort:
      begin
        Result := ParseSort(L, Sort);
        if Result then
          PSortSpec(P)^ := Sort;
      end;
  else
    Result := False;   // vkList: a whole section, read by ApplyFile
  end;
end;

function FormatValue(const Def: TKeyDef; P: Pointer): string;
begin
  case Def.Kind of
    vkText, vkName, vkLanguage, vkMethod, vkColumns: Result := PString(P)^;
    vkBool: Result := BoolNames[PBoolean(P)^];
    vkInt: Result := IntToStr(PInteger(P)^);
    vkEnum: Result := ChoiceName(Def.Choices, PLongInt(P)^);
    vkWindow: Result := FormatWindowGeometry(PWindowGeometry(P)^);
    vkSort: Result := PSortSpec(P)^.Column + ',' + SortDirNames[PSortSpec(P)^.Descending];
    vkList: Result := JoinList(PListField(P)^);
  else
    Result := '';
  end;
end;

function Serialize(var C: TConfig): TStringArray;
var
  K: TCfgKey;
begin
  Result := nil;
  SetLength(Result, Ord(High(TCfgKey)) + 1);
  for K := Low(TCfgKey) to High(TCfgKey) do
    Result[Ord(K)] := FormatValue(KeyDefs[K], FieldOf(C, K));
end;

procedure ConfigDefaults(out C: TConfig);
var
  K: TCfgKey;
  Ok: Boolean;
begin
  C := Default(TConfig);
  C.Writable := True;
  for K := Low(TCfgKey) to High(TCfgKey) do
    if KeyDefs[K].Kind <> vkList then
    begin
      Ok := ParseValue(KeyDefs[K], KeyDefs[K].Default, FieldOf(C, K));
      Assert(Ok, 'invalid default of [' + KeyDefs[K].Section + '] ' + KeyDefs[K].Name);
    end;
  C.Baseline := Serialize(C);
end;

{ ============================================================================================== }
{ Ini file plumbing: lines, sections, comments (knows nothing about the settings)                }
{ ============================================================================================== }

type
  TLineKind = (lkOther, lkSection, lkKey);

  { the values of one file: 'section.key' -> raw value, last one wins; list items as
    'section.#<n>'; Sections holds every section name seen }
  TIniValues = record
    Values: TStringList;
    Sections: TStringList;
  end;

{ classifies one line; for a key, Key is lower case and Value is the trimmed text after '=' }
function ParseLine(const Line: string; out Section, Key, Value: string): TLineKind;
var
  T: string;
  P: Integer;
begin
  Section := '';
  Key := '';
  Value := '';
  T := Trim(Line);
  if (T = '') or (T[1] in [';', '#']) then
    Exit(lkOther);
  if (T[1] = '[') and (T[Length(T)] = ']') then
  begin
    Section := LowerCase(Trim(Copy(T, 2, Length(T) - 2)));
    Exit(lkSection);
  end;
  P := Pos('=', T);
  if P <= 1 then
    Exit(lkOther);
  Key := LowerCase(Trim(Copy(T, 1, P - 1)));
  Value := Trim(Copy(T, P + 1, MaxInt));
  if Key = '' then
    Exit(lkOther);
  Result := lkKey;
end;

{ splits a trimmed value: one that starts with ';' or '#' is empty and all of it is the comment;
  with TrailingToo, '... ; comment' (a blank before the ';' or '#') ends the value as well, and
  Comment keeps its leading blanks }
function SplitComment(const Value: string; TrailingToo: Boolean; out Comment: string): string;
var
  I: Integer;
begin
  Comment := '';
  Result := Value;
  if (Value <> '') and (Value[1] in [';', '#']) then
  begin
    Comment := Value;
    Exit('');
  end;
  if TrailingToo then
    for I := 2 to Length(Value) do
      if (Value[I] in [';', '#']) and (Value[I - 1] in [' ', #9]) then
      begin
        Result := TrimRight(Copy(Value, 1, I - 1));
        Comment := Copy(Value, Length(Result) + 1, MaxInt);
        Exit;
      end;
end;

{ reads FileName into lines; a missing file gives no lines; False only when it exists but cannot
  be read }
function ReadIniLines(const FileName: string; out Lines: TStringList; out Err: string): Boolean;
var
  Text: string;
begin
  Err := '';
  Text := '';
  Result := not FileExists(FileName) or ReadFileText(FileName, Text, Err);
  Lines := TextToLines(Text);
end;

function NumericKey(const Key: string; out N: Integer): Boolean;
begin
  N := 0;
  Result := (Length(Key) <= 6) and AllDigits(Key);
  if Result then
    N := StrToInt(Key);
end;

procedure CollectValues(Lines: TStrings; const Lists: array of string; out V: TIniValues);
var
  I, N, Idx: Integer;
  Section, S, Key, Value, Name: string;
  IsList: Boolean;
begin
  V.Values := TStringList.Create;
  V.Sections := TStringList.Create;
  V.Sections.Sorted := True;
  V.Sections.Duplicates := dupIgnore;
  Section := '';
  IsList := False;
  for I := 0 to Lines.Count - 1 do
    case ParseLine(Lines[I], S, Key, Value) of
      lkSection:
        begin
          Section := S;
          V.Sections.Add(S);
          IsList := False;
          for N := 0 to High(Lists) do
            if Lists[N] = S then
              IsList := True;
        end;
      lkKey:
        begin
          if IsList then
          begin
            if not NumericKey(Key, N) then
              Continue;
            Name := Section + '.#' + IntToStr(N);
          end
          else
            Name := Section + '.' + Key;
          Idx := V.Values.IndexOfName(Name);
          if Idx >= 0 then
            V.Values.ValueFromIndex[Idx] := Value
          else
            V.Values.Add(Name + '=' + Value);
        end;
    end;
end;

procedure FreeValues(var V: TIniValues);
begin
  FreeAndNil(V.Values);
  FreeAndNil(V.Sections);
end;

{ the numbered items of a list section in number order; empty and comment-only items skipped }
function ReadList(const V: TIniValues; const Section: string; MaxItems: Integer): TStringArray;
var
  Nums: TStringList;
  I: Integer;
  Prefix, Item, Comment: string;
begin
  Result := nil;
  Prefix := Section + '.#';
  Nums := TStringList.Create;
  try
    for I := 0 to V.Values.Count - 1 do
      if Copy(V.Values.Names[I], 1, Length(Prefix)) = Prefix then
        Nums.AddObject(Format('%.8d', [StrToInt(Copy(V.Values.Names[I], Length(Prefix) + 1,
          MaxInt))]), TObject(PtrInt(I)));
    Nums.Sort;
    for I := 0 to Nums.Count - 1 do
    begin
      Item := SplitComment(V.Values.ValueFromIndex[PtrInt(Nums.Objects[I])], False, Comment);
      if (Item = '') or (Length(Result) >= MaxItems) then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Item;
    end;
  finally
    Nums.Free;
  end;
end;

{ index of the last 'key=' line of Section, or -1 }
function FindKeyLine(Lines: TStrings; const Section, Key: string): Integer;
var
  I: Integer;
  Cur, S, K, V: string;
begin
  Result := -1;
  Cur := '';
  for I := 0 to Lines.Count - 1 do
    case ParseLine(Lines[I], S, K, V) of
      lkSection: Cur := S;
      lkKey:
        if (Cur = Section) and (K = Key) then
          Result := I;
    end;
end;

{ where a new line of Section goes: after the last non-blank line of its last occurrence;
  -1 when the section does not exist }
function SectionInsertPos(Lines: TStrings; const Section: string): Integer;
var
  I, Header: Integer;
  S, K, V: string;
begin
  Header := -1;
  for I := 0 to Lines.Count - 1 do
    if (ParseLine(Lines[I], S, K, V) = lkSection) and (S = Section) then
      Header := I;
  if Header < 0 then
    Exit(-1);
  Result := Header + 1;
  I := Header + 1;
  while (I < Lines.Count) and (ParseLine(Lines[I], S, K, V) <> lkSection) do
  begin
    if Trim(Lines[I]) <> '' then
      Result := I + 1;
    Inc(I);
  end;
end;

{ where a new line of Section goes; the section is appended to the file when it is missing }
function InsertPosOrAppend(Lines: TStrings; const Section: string): Integer;
begin
  Result := SectionInsertPos(Lines, Section);
  if Result >= 0 then
    Exit;
  if (Lines.Count > 0) and (Trim(Lines[Lines.Count - 1]) <> '') then
    Lines.Add('');
  Lines.Add('[' + Section + ']');
  Result := Lines.Count;
end;

{ sets Section/Key to Value, in place when the key exists (indentation, spelling and the blanks
  after '=' kept). TrailingComment: the line's ' ; comment' after a value is kept; otherwise
  (text keys) only a comment-only value is a comment, and it moves to its own line when the key
  gets a value }
procedure SetLineValue(Lines: TStrings; const Section, Key, Value: string;
  TrailingComment: Boolean);
var
  Idx, Eq, P: Integer;
  Line, Lead, Pad, Old, Comment: string;
begin
  Idx := FindKeyLine(Lines, Section, Key);
  if Idx < 0 then
  begin
    Lines.Insert(InsertPosOrAppend(Lines, Section), Key + '=' + Value);
    Exit;
  end;
  Line := Lines[Idx];
  Eq := Pos('=', Line);
  P := Eq;
  while (P < Length(Line)) and (Line[P + 1] in [' ', #9]) do
    Inc(P);
  Lead := Copy(Line, 1, Eq);
  Pad := Copy(Line, Eq + 1, P - Eq);
  Old := SplitComment(Trim(Copy(Line, P + 1, MaxInt)), TrailingComment, Comment);
  if Comment = '' then
    Lines[Idx] := Lead + Pad + Value
  else if Old <> '' then
    Lines[Idx] := Lead + Pad + Value + Comment     // 'key = value   ; comment'
  else if Value = '' then
    Exit                                           // 'key=   ; comment' stays as it is
  else if TrailingComment then
  begin
    if Pad = '' then
      Pad := ' ';
    Lines[Idx] := Lead + Value + Pad + Comment;    // 'key=value   ; comment'
  end
  else
  begin
    // a text value would swallow the comment: the comment gets its own line above the key
    if (Eq > 1) and (Line[Eq - 1] in [' ', #9]) then
      Lead := Lead + ' ';
    Lines[Idx] := Lead + Value;
    Lines.Insert(Idx, Comment);
  end;
end;

{ replaces every numbered key of Section (all occurrences) with Items as 1=, 2=, ...; a
  comment-only item ('1=   ; most recent first') is kept as a comment line }
procedure SetLineList(Lines: TStrings; const Section: string; const Items: TStringArray);
var
  I, N, Pos0: Integer;
  Cur, S, K, V, Comment: string;
begin
  Pos0 := -1;
  Cur := '';
  I := 0;
  while I < Lines.Count do
  begin
    case ParseLine(Lines[I], S, K, V) of
      lkSection: Cur := S;
      lkKey:
        if (Cur = Section) and NumericKey(K, N) then
        begin
          if (SplitComment(V, False, Comment) = '') and (Comment <> '') then
            Lines[I] := Comment
          else
          begin
            if Pos0 < 0 then
              Pos0 := I;
            Lines.Delete(I);
            Continue;
          end;
        end;
    end;
    Inc(I);
  end;
  if Pos0 < 0 then
    Pos0 := InsertPosOrAppend(Lines, Section);
  for I := 0 to High(Items) do
    Lines.Insert(Pos0 + I, IntToStr(I + 1) + '=' + Items[I]);
end;

function WriteFileAtomic(const FileName, Text: string; out Err: string): Boolean;
var
  Tmp: string;
  H: THandle;
  Attempt, Done, N: Integer;
begin
  Err := '';
  Tmp := FileName + '.tmp';
  // exclusive: a second writer waits for the first one instead of mixing its bytes in
  H := feInvalidHandle;
  for Attempt := 1 to 20 do
  begin
    H := FileCreate(Tmp, fmShareExclusive, 438);
    if H <> feInvalidHandle then
      Break;
    Err := SysErrorMessageUTF8(GetLastOSError);
    Sleep(50);
  end;
  if H = feInvalidHandle then
    Exit(False);
  Done := 0;
  N := 0;
  while Done < Length(Text) do
  begin
    N := FileWrite(H, Text[Done + 1], Length(Text) - Done);
    if N <= 0 then
      Break;
    Inc(Done, N);
  end;
  if (Done < Length(Text)) or not FileFlush(H) then
  begin
    Err := SysErrorMessageUTF8(GetLastOSError);
    FileClose(H);
    SysUtils.DeleteFile(Tmp);
    Exit(False);
  end;
  FileClose(H);
  {$IFDEF MSWINDOWS}
  Result := MoveFileExW(PWideChar(UTF8ToUTF16(Tmp)), PWideChar(UTF8ToUTF16(FileName)),
    ZS_MOVEFILE_REPLACE_EXISTING or ZS_MOVEFILE_WRITE_THROUGH);
  {$ELSE}
  Result := fpRename(Tmp, FileName) = 0;
  {$ENDIF}
  if not Result then
  begin
    Err := SysErrorMessageUTF8(GetLastOSError);
    SysUtils.DeleteFile(Tmp);
  end;
end;

{ ============================================================================================== }
{ Location                                                                                       }
{ ============================================================================================== }

function UserConfigDir: string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..MAX_PATH] of WideChar;
begin
  Buf[0] := #0;
  if SHGetFolderPathW(0, ZS_CSIDL_APPDATA, 0, 0, @Buf[0]) = S_OK then
    Result := UTF16ToUTF8(UnicodeString(PWideChar(@Buf[0])))
  else
    Result := GetEnvironmentVariableUTF8('APPDATA');
  Result := IncludeTrailingPathDelimiter(Result) + 'ZPAQ-std' + PathDelim;
end;
{$ELSE}
begin
  Result := GetEnvironmentVariableUTF8('XDG_CONFIG_HOME');
  if (Result = '') or (Result[1] <> '/') then
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariableUTF8('HOME')) + '.config';
  Result := IncludeTrailingPathDelimiter(Result) + 'zpaq-std-gui' + PathDelim;
end;
{$ENDIF}

function FolderIsWritable(const Dir: string): Boolean;
var
  Probe: string;
  H: THandle;
begin
  Probe := IncludeTrailingPathDelimiter(Dir) + '.zpaq-std-gui-probe-' + IntToStr(GetProcessID)
    + '.tmp';
  H := FileCreate(Probe);
  if H = feInvalidHandle then
    Exit(False);
  FileClose(H);
  SysUtils.DeleteFile(Probe);
  Result := True;
end;

{ the file can be opened for writing (not read-only, not locked); nothing is written }
function FileIsWritable(const FileName: string): Boolean;
var
  H: THandle;
begin
  H := FileOpen(FileName, fmOpenReadWrite or fmShareDenyNone);
  Result := H <> feInvalidHandle;
  if Result then
    FileClose(H);
end;

procedure LocateConfig(var C: TConfig; const ExeDir: string; const UserDir: string);
var
  E, U: string;
begin
  E := IncludeTrailingPathDelimiter(ExeDir);
  if UserDir = '' then
    U := UserConfigDir
  else
    U := IncludeTrailingPathDelimiter(UserDir);
  C.Portable := False;
  C.ReadOnlyPortable := False;
  C.DefaultsFile := '';
  C.Writable := True;
  C.SaveError := '';
  if FileExists(E + ConfigFileName) then
  begin
    if FolderIsWritable(E) and FileIsWritable(E + ConfigFileName) then
    begin
      C.FileName := E + ConfigFileName;
      C.Portable := True;
      Exit;
    end;
    C.DefaultsFile := E + ConfigFileName;
    C.ReadOnlyPortable := True;
  end;
  C.FileName := U + ConfigFileName;
end;

{ ============================================================================================== }
{ Load and save                                                                                  }
{ ============================================================================================== }

procedure AddWarning(var C: TConfig; const S: string);
begin
  SetLength(C.Warnings, Length(C.Warnings) + 1);
  C.Warnings[High(C.Warnings)] := S;
end;

function ListSections: TStringArray;
var
  K: TCfgKey;
begin
  Result := nil;
  for K := Low(TCfgKey) to High(TCfgKey) do
    if KeyDefs[K].Kind = vkList then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := KeyDefs[K].Section;
    end;
end;

procedure ApplyFile(var C: TConfig; const FileName: string);
var
  Lines: TStringList;
  V: TIniValues;
  Err, Raw, Comment: string;
  K: TCfgKey;
  Idx: Integer;
begin
  if (FileName = '') or not FileExists(FileName) then
    Exit;
  if not ReadIniLines(FileName, Lines, Err) then
    AddWarning(C, FileName + ': ' + Err);
  try
    CollectValues(Lines, ListSections, V);
    try
      for K := Low(TCfgKey) to High(TCfgKey) do
      begin
        if KeyDefs[K].Kind = vkList then
        begin
          if V.Sections.IndexOf(KeyDefs[K].Section) >= 0 then
            PListField(FieldOf(C, K))^ := ReadList(V, KeyDefs[K].Section, KeyDefs[K].Hi);
          Continue;
        end;
        Idx := V.Values.IndexOfName(KeyDefs[K].Section + '.' + KeyDefs[K].Name);
        if Idx < 0 then
          Continue;
        Raw := SplitComment(V.Values.ValueFromIndex[Idx], KeyDefs[K].Kind <> vkText, Comment);
        if K = ckLanguage then
          C.LanguageKeyFound := True;
        if not ParseValue(KeyDefs[K], Raw, FieldOf(C, K)) then
          AddWarning(C, '[' + KeyDefs[K].Section + '] ' + KeyDefs[K].Name + '=' + Raw);
      end;
    finally
      FreeValues(V);
    end;
  finally
    Lines.Free;
  end;
end;

procedure LoadConfig(var C: TConfig);
var
  Loc: TConfig;
begin
  Loc := C;
  ConfigDefaults(C);
  C.FileName := Loc.FileName;
  C.DefaultsFile := Loc.DefaultsFile;
  C.Portable := Loc.Portable;
  C.ReadOnlyPortable := Loc.ReadOnlyPortable;
  C.Writable := Loc.Writable;
  C.SaveError := Loc.SaveError;
  ApplyFile(C, C.DefaultsFile);
  ApplyFile(C, C.FileName);
  C.Baseline := Serialize(C);
end;

procedure InitConfig(var C: TConfig; const ExeDir: string; const UserDir: string);
var
  E: string;
begin
  E := ExeDir;
  if E = '' then
    E := ExtractFilePath(ParamStrUTF8(0));
  ConfigDefaults(C);
  LocateConfig(C, E, UserDir);
  LoadConfig(C);
end;

function SaveConfig(var C: TConfig): Boolean;
var
  Cur: TStringArray;
  K: TCfgKey;
  Changed: Boolean;
  Lines: TStringList;
  Err, Text: string;
  I: Integer;

  function KeyChanged(K: TCfgKey): Boolean;
  begin
    Result := (Ord(K) > High(C.Baseline)) or (Cur[Ord(K)] <> C.Baseline[Ord(K)]);
  end;

begin
  if not C.Writable then
    Exit(False);
  Cur := Serialize(C);
  Changed := False;
  for K := Low(TCfgKey) to High(TCfgKey) do
    if KeyChanged(K) then
      Changed := True;
  if not Changed then
    Exit(True);
  Result := False;
  Lines := nil;
  try
    if not ForceDirectories(ExtractFileDir(C.FileName)) then
      Err := SysErrorMessageUTF8(GetLastOSError)
    else if ReadIniLines(C.FileName, Lines, Err) then
    begin
      for K := Low(TCfgKey) to High(TCfgKey) do
        if KeyChanged(K) then
          if KeyDefs[K].Kind = vkList then
            SetLineList(Lines, KeyDefs[K].Section, PListField(FieldOf(C, K))^)
          else
            SetLineValue(Lines, KeyDefs[K].Section, KeyDefs[K].Name, Cur[Ord(K)],
              KeyDefs[K].Kind <> vkText);
      Text := '';
      for I := 0 to Lines.Count - 1 do
        Text := Text + Lines[I] + LineEnding;
      Result := WriteFileAtomic(C.FileName, Text, Err);
    end;
  finally
    Lines.Free;
  end;
  if Result then
    C.Baseline := Cur
  else
  begin
    C.Writable := False;
    if Err = '' then
      Err := SysErrorMessageUTF8(GetLastOSError);
    C.SaveError := Err;
  end;
end;

{ ---- lists ----------------------------------------------------------------------------------- }

procedure PushFront(var L: TStringArray; const Item: string; MaxItems: Integer);
var
  R: TStringArray;
  I: Integer;
begin
  if Item = '' then
    Exit;
  R := nil;
  SetLength(R, 1);
  R[0] := Item;
  for I := 0 to High(L) do
    if (Length(R) < MaxItems) and not SameFileName(L[I], Item) then
    begin
      SetLength(R, Length(R) + 1);
      R[High(R)] := L[I];
    end;
  L := R;
end;

procedure AddRecent(var C: TConfig; const FileName: string);
begin
  PushFront(C.Recent, FileName, MaxRecent);
end;

procedure AddExtractHistory(var C: TConfig; const Dir: string);
begin
  PushFront(C.ExtractHistory, Dir, MaxExtractHistory);
end;

end.
