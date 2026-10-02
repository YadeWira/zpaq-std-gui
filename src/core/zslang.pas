{ zslang: language files (lang/<code>.zsl, syc .syl rules), the English text embedded as the
  RCDATA resource LANG_EN, the per-key fallback chain, Tr/TrF/TrN, the system UI language and the
  list of installed languages. Holds the only language table of the program. RTL/FCL/LazUtils. }
unit zslang;

{$mode objfpc}{$H+}

(* Public API

  File format (.zsl, UTF-8, a BOM is stripped, LF or CRLF)
    ';' or '#' first = comment; '[section]' lower-cased; 'key = value' split at the FIRST '=', both
    sides trimmed, key lower-cased; internal key = 'section.key' (just 'key' before any section);
    escapes in values: \n line break (LineEnding), \t tab, \\ backslash, \s space (keeps leading or
    trailing spaces); any other '\x' stays as it is; a duplicate key: the last one wins; lines
    without '=' are ignored.

  Lookup (per key)
    selected file (es-pe.zsl) -> its base language (es.zsl) -> embedded English -> '⟨key⟩'
    (U+27E8 key U+27E9; the key is also recorded once in LangMissingKeys).

    Tr(Key): string                    keys are case-insensitive ('formmain.tbopen')
    TrF(Key, ['name', Value, ...])     named placeholders '{name}' replaced in one pass (a value
                                       that contains '{x}' is never substituted again); an unknown
                                       placeholder stays visible
    TrN(Key, N)                        plurals: Key.one when N = 1 and the SAME file has it, else
                                       Key.other, else Key itself; '{n}' = N
    TrNF(Key, N, [...])                TrN plus named placeholders
    LangTryGet(Key, out Value)         no fallback text and nothing recorded (for the form walker)
    FormatPlaceholders(S, [...])       the TrF replacement on any string
    LangMissingKeys: TStringArray      keys asked for and found nowhere, sorted, once each

  Choosing and loading
    LangLoad(Choice, LangDir): Boolean
        Choice: '' or 'auto' = system UI language (LangAutoCode); a code ('es', 'es_PE', 'es-pe');
        or a path (it ends in '.zsl' or has a '/' or '\'; a relative one is relative to the current
        folder). Builds the chain; English is always the last link. Returns False when the code or
        file asked for was not found or could not be read: English is then used and LangFailed
        names what failed ('' after a success). Auto fails only when the file it picked cannot
        be read (no file for the system language is not a failure).
    LangCode: string                   code of the active language ('es-pe', 'es', 'en')
    LangName: string                   its [info] name ('Español'); 'English' for English
    LangFailed: string                 see LangLoad
    LangAutoCode(LangDir): string      what 'auto' loads: 'es-pe' if lang/es-pe.zsl exists, else
                                       'es' if lang/es.zsl exists, else 'en'
    DefaultLangDir: string             <exe dir>/lang/ (with the trailing delimiter)
    ListLanguages(LangDir): TLangInfoArray
                                       English (embedded, FileName = '') plus every *.zsl of
                                       LangDir, one per code, sorted by Name
    SystemLanguageCode: string         Windows: GetUserDefaultUILanguage -> 'es-pe';
                                       Unix: first non-empty LC_ALL, LC_MESSAGES, LANG -> 'es-pe';
                                       '' when unknown
    LocaleToLangCode(Locale): string   'es_PE.UTF-8@euro' -> 'es-pe', 'C'/'POSIX' -> 'en'
    NormalizeLangCode(S): string       trimmed, lower case, '_' -> '-'
    ValidLangCode(Code): Boolean       a normalised code: a letter, then letters, digits or '-';
                                       at most 32 characters
    BaseLangCode(Code): string         'es-pe' -> 'es'

  Embedded English
    The project embeds lang/en.zsl as RCDATA 'LANG_EN' (see the .lpi resources).
    LangResourceEnglish: string        that resource's text, '' when the exe has none
    LangSetEmbeddedEnglish(Text)       replace it (tests, or a build without the resource)
    LangUseResourceEnglish             go back to the resource

  TLangTable                           one parsed file (public for the tests and the tools)
    LoadFromText(Text), LoadFromFile(FileName): Boolean, TryGet(Key, out Value): Boolean,
    Has(Key), Count, Clear
*)

interface

uses
  Classes, SysUtils, contnrs, LazUTF8;

type
  TLangTable = class
  private
    FHash: TFPStringHashTable;
    FCount: Integer;
    procedure Put(const Key, Value: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromText(const Text: string);
    function LoadFromFile(const FileName: string): Boolean;
    function TryGet(const Key: string; out Value: string): Boolean;
    function Has(const Key: string): Boolean;
    property Count: Integer read FCount;
  end;

  TLangInfo = record
    Code: string;          // file name without '.zsl', lower case; 'en' for the embedded English
    Name: string;          // [info] name, or the code
    EnglishName: string;   // [info] english_name
    Author: string;        // [info] author
    FileName: string;      // full path; '' for the embedded English
  end;
  TLangInfoArray = array of TLangInfo;

const
  LangFileExt = '.zsl';
  LangResourceName = 'LANG_EN';
  MissingOpen = #$E2#$9F#$A8;    // U+27E8
  MissingClose = #$E2#$9F#$A9;   // U+27E9

function Tr(const Key: string): string;
function TrF(const Key: string; const Args: array of string): string;
function TrN(const Key: string; N: Int64): string;
function TrNF(const Key: string; N: Int64; const Args: array of string): string;
function LangTryGet(const Key: string; out Value: string): Boolean;
function FormatPlaceholders(const S: string; const Args: array of string): string;
function LangMissingKeys: TStringArray;

function LangLoad(const Choice, LangDir: string): Boolean;
function LangCode: string;
function LangName: string;
function LangFailed: string;
function LangAutoCode(const LangDir: string): string;
function DefaultLangDir: string;
function ListLanguages(const LangDir: string): TLangInfoArray;
function SystemLanguageCode: string;
function LocaleToLangCode(const Locale: string): string;
function NormalizeLangCode(const S: string): string;
function ValidLangCode(const Code: string): Boolean;
function BaseLangCode(const Code: string): string;

function LangResourceEnglish: string;
procedure LangSetEmbeddedEnglish(const Text: string);
procedure LangUseResourceEnglish;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  LazFileUtils, zsutil;

{$IFDEF MSWINDOWS}
function GetUserDefaultUILanguage: Word; stdcall; external 'kernel32' name 'GetUserDefaultUILanguage';

const
  ZS_LOCALE_SISO639LANGNAME = $59;
  ZS_LOCALE_SISO3166CTRYNAME = $5A;
{$ENDIF}

type
  TLangState = record
    English: TLangTable;           // the embedded English; always the last link of Chain
    EnglishReady: Boolean;
    UseOverride: Boolean;
    OverrideText: string;
    Chain: array of TLangTable;    // selected file, its base language, English
    Owned: array of TLangTable;    // the tables of Chain loaded from files (freed on reload)
    Code: string;
    Failed: string;
    Missing: TStringList;
  end;

var
  State: TLangState;   // the language table of the program (one of the three globals)

{ ---------------------------------------------------------------------------------------------- }
{ TLangTable                                                                                     }
{ ---------------------------------------------------------------------------------------------- }

constructor TLangTable.Create;
begin
  inherited Create;
  FHash := TFPStringHashTable.Create;
end;

destructor TLangTable.Destroy;
begin
  FHash.Free;
  inherited Destroy;
end;

procedure TLangTable.Clear;
begin
  FHash.Clear;
  FCount := 0;
end;

procedure TLangTable.Put(const Key, Value: string);
begin
  if FHash.Find(Key) = nil then
    Inc(FCount);
  FHash[Key] := Value;
end;

function Unescape(const S: string): string;
var
  I: Integer;
begin
  if Pos('\', S) = 0 then
    Exit(S);
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '\') and (I < Length(S)) then
    begin
      case S[I + 1] of
        'n': Result := Result + LineEnding;
        't': Result := Result + #9;
        's': Result := Result + ' ';
        '\': Result := Result + '\';
      else
        Result := Result + '\' + S[I + 1];
      end;
      Inc(I, 2);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

procedure TLangTable.LoadFromText(const Text: string);
var
  Lines: TStringList;
  Line, Section, Key: string;
  I, EqPos: Integer;
begin
  Clear;
  Section := '';
  Lines := TextToLines(Text);
  try
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] in [';', '#']) then
        Continue;
      if (Line[1] = '[') and (Line[Length(Line)] = ']') then
      begin
        Section := LowerCase(Trim(Copy(Line, 2, Length(Line) - 2)));
        Continue;
      end;
      EqPos := Pos('=', Line);
      if EqPos = 0 then
        Continue;
      Key := LowerCase(Trim(Copy(Line, 1, EqPos - 1)));
      if Key = '' then
        Continue;
      if Section <> '' then
        Key := Section + '.' + Key;
      Put(Key, Unescape(Trim(Copy(Line, EqPos + 1, MaxInt))));
    end;
  finally
    Lines.Free;
  end;
end;

function TLangTable.LoadFromFile(const FileName: string): Boolean;
var
  Text, Err: string;
begin
  Clear;
  Result := ReadFileText(FileName, Text, Err);
  if Result then
    LoadFromText(Text);
end;

function TLangTable.TryGet(const Key: string; out Value: string): Boolean;
var
  Node: THTCustomNode;
begin
  Node := FHash.Find(Key);
  Result := Node <> nil;
  if Result then
    Value := THTStringNode(Node).Data
  else
    Value := '';
end;

function TLangTable.Has(const Key: string): Boolean;
begin
  Result := FHash.Find(Key) <> nil;
end;

{ ---------------------------------------------------------------------------------------------- }
{ Embedded English and the chain                                                                 }
{ ---------------------------------------------------------------------------------------------- }

function LangResourceEnglish: string;
var
  RS: TResourceStream;
begin
  Result := '';
  if System.FindResource(HInstance, PChar(LangResourceName), PChar(RT_RCDATA)) = 0 then
    Exit;
  RS := TResourceStream.Create(HInstance, LangResourceName, PChar(RT_RCDATA));
  try
    SetLength(Result, RS.Size);
    if RS.Size > 0 then
      RS.ReadBuffer(Result[1], RS.Size);
  finally
    RS.Free;
  end;
end;

procedure EnsureEnglish;
begin
  if State.English = nil then
    State.English := TLangTable.Create;
  if State.Missing = nil then
  begin
    State.Missing := TStringList.Create;
    State.Missing.Sorted := True;
    State.Missing.Duplicates := dupIgnore;
  end;
  if not State.EnglishReady then
  begin
    if State.UseOverride then
      State.English.LoadFromText(State.OverrideText)
    else
      State.English.LoadFromText(LangResourceEnglish);
    State.EnglishReady := True;
  end;
  if Length(State.Chain) = 0 then
  begin
    SetLength(State.Chain, 1);
    State.Chain[0] := State.English;
    State.Code := 'en';
  end;
end;

procedure LangSetEmbeddedEnglish(const Text: string);
begin
  State.UseOverride := True;
  State.OverrideText := Text;
  State.EnglishReady := False;
  EnsureEnglish;
end;

procedure LangUseResourceEnglish;
begin
  State.UseOverride := False;
  State.OverrideText := '';
  State.EnglishReady := False;
  EnsureEnglish;
end;

procedure FreeOwned;
var
  I: Integer;
begin
  for I := 0 to High(State.Owned) do
    State.Owned[I].Free;
  State.Owned := nil;
end;

{ appends a table loaded from FileName to the chain; False when it cannot be read }
function AddFileToChain(const FileName: string): Boolean;
var
  T: TLangTable;
  N: Integer;
begin
  T := TLangTable.Create;
  Result := T.LoadFromFile(FileName);
  if not Result then
  begin
    T.Free;
    Exit;
  end;
  N := Length(State.Owned);
  SetLength(State.Owned, N + 1);
  State.Owned[N] := T;
  N := Length(State.Chain);
  SetLength(State.Chain, N + 1);
  State.Chain[N] := T;
end;

function FindValue(const Key: string; out Value: string): Boolean;
var
  I: Integer;
begin
  EnsureEnglish;
  for I := 0 to High(State.Chain) do
    if State.Chain[I].TryGet(Key, Value) then
      Exit(True);
  Value := '';
  Result := False;
end;

function MissingText(const Key: string): string;
begin
  State.Missing.Add(Key);
  Result := MissingOpen + Key + MissingClose;
end;

{ ---------------------------------------------------------------------------------------------- }
{ Tr family                                                                                      }
{ ---------------------------------------------------------------------------------------------- }

function LangTryGet(const Key: string; out Value: string): Boolean;
begin
  Result := FindValue(LowerCase(Key), Value);
end;

function Tr(const Key: string): string;
var
  K: string;
begin
  K := LowerCase(Key);
  if not FindValue(K, Result) then
    Result := MissingText(K);
end;

function ValidPlaceholderName(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
      Exit(False);
end;

function FormatPlaceholders(const S: string; const Args: array of string): string;
var
  I, J, A: Integer;
  Name: string;
  Found: Boolean;
begin
  if Pos('{', S) = 0 then
    Exit(S);
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '{' then
    begin
      J := I + 1;
      while (J <= Length(S)) and (S[J] <> '}') and (S[J] <> '{') do
        Inc(J);
      if (J <= Length(S)) and (S[J] = '}') then
      begin
        Name := Copy(S, I + 1, J - I - 1);
        Found := False;
        if ValidPlaceholderName(Name) then
        begin
          A := 0;
          while A + 1 <= High(Args) do
          begin
            if SameText(Args[A], Name) then
            begin
              Result := Result + Args[A + 1];
              Found := True;
              Break;
            end;
            Inc(A, 2);
          end;
        end;
        if Found then
        begin
          I := J + 1;
          Continue;
        end;
      end;
    end;
    Result := Result + S[I];
    Inc(I);
  end;
end;

function TrF(const Key: string; const Args: array of string): string;
begin
  Result := FormatPlaceholders(Tr(Key), Args);
end;

function PluralText(const Key: string; N: Int64): string;
var
  K: string;
  I: Integer;
begin
  K := LowerCase(Key);
  EnsureEnglish;
  // the plural form is chosen inside one file: a language without '.one' uses its own '.other'
  for I := 0 to High(State.Chain) do
  begin
    if (N = 1) and State.Chain[I].TryGet(K + '.one', Result) then
      Exit;
    if State.Chain[I].TryGet(K + '.other', Result) then
      Exit;
    if State.Chain[I].TryGet(K, Result) then
      Exit;
  end;
  Result := MissingText(K + '.other');
end;

function TrN(const Key: string; N: Int64): string;
begin
  Result := FormatPlaceholders(PluralText(Key, N), ['n', IntToStr(N)]);
end;

function TrNF(const Key: string; N: Int64; const Args: array of string): string;
var
  All: array of string;
  I: Integer;
begin
  All := nil;
  SetLength(All, Length(Args) + 2);
  All[0] := 'n';
  All[1] := IntToStr(N);
  for I := 0 to High(Args) do
    All[I + 2] := Args[I];
  Result := FormatPlaceholders(PluralText(Key, N), All);
end;

function LangMissingKeys: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  if State.Missing = nil then
    Exit;
  SetLength(Result, State.Missing.Count);
  for I := 0 to State.Missing.Count - 1 do
    Result[I] := State.Missing[I];
end;

{ ---------------------------------------------------------------------------------------------- }
{ Codes, files and loading                                                                       }
{ ---------------------------------------------------------------------------------------------- }

function NormalizeLangCode(const S: string): string;
begin
  Result := StringReplace(LowerCase(Trim(S)), '_', '-', [rfReplaceAll]);
end;

function BaseLangCode(const Code: string): string;
var
  P: Integer;
begin
  Result := NormalizeLangCode(Code);
  P := Pos('-', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
end;

function ValidLangCode(const Code: string): Boolean;
var
  I: Integer;
begin
  Result := (Code <> '') and (Length(Code) <= 32) and (Code[1] in ['a'..'z']);
  for I := 1 to Length(Code) do
    if not (Code[I] in ['a'..'z', '0'..'9', '-']) then
      Exit(False);
end;

function LocaleToLangCode(const Locale: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(Locale);
  P := Pos('@', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos('.', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  if (S = 'C') or (S = 'POSIX') then
    Exit('en');
  Result := NormalizeLangCode(S);
  if not ValidLangCode(Result) then
    Result := '';
end;

function SystemLanguageCode: string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..15] of WideChar;
  Lcid: DWORD;
  Lang, Country: string;
begin
  Result := '';
  Lcid := GetUserDefaultUILanguage;   // MAKELCID(langid, SORT_DEFAULT) = langid
  Buf[0] := #0;
  if GetLocaleInfoW(Lcid, ZS_LOCALE_SISO639LANGNAME, @Buf[0], Length(Buf)) <= 1 then
    Exit;
  Lang := UTF16ToUTF8(UnicodeString(PWideChar(@Buf[0])));
  Buf[0] := #0;
  if GetLocaleInfoW(Lcid, ZS_LOCALE_SISO3166CTRYNAME, @Buf[0], Length(Buf)) > 1 then
    Country := UTF16ToUTF8(UnicodeString(PWideChar(@Buf[0])))
  else
    Country := '';
  if Country <> '' then
    Result := LocaleToLangCode(Lang + '_' + Country)
  else
    Result := LocaleToLangCode(Lang);
end;
{$ELSE}
const
  Vars: array[0..2] of string = ('LC_ALL', 'LC_MESSAGES', 'LANG');
var
  I: Integer;
  V: string;
begin
  Result := '';
  for I := 0 to High(Vars) do
  begin
    V := GetEnvironmentVariableUTF8(Vars[I]);
    if V <> '' then
      Exit(LocaleToLangCode(V));
  end;
end;
{$ENDIF}

function DefaultLangDir: string;
begin
  Result := ExtractFilePath(ParamStrUTF8(0)) + 'lang' + PathDelim;
end;

{ <dir>/<code>.zsl, matched without case on every platform; '' when absent }
function FindLangFile(const LangDir, Code: string): string;
var
  Dir: string;
  SR: TSearchRec;
begin
  Result := '';
  if (LangDir = '') or not ValidLangCode(Code) then
    Exit;
  Dir := IncludeTrailingPathDelimiter(LangDir);
  if FileExists(Dir + Code + LangFileExt) then
    Exit(Dir + Code + LangFileExt);
  if FindFirst(Dir + '*' + LangFileExt, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory = 0) and (LowerCase(SR.Name) = Code + LangFileExt) then
        Exit(Dir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    SysUtils.FindClose(SR);
  end;
end;

function LangAutoCode(const LangDir: string): string;
var
  Code: string;
begin
  Code := SystemLanguageCode;
  if Code = '' then
    Exit('en');
  if FindLangFile(LangDir, Code) <> '' then
    Exit(Code);
  if FindLangFile(LangDir, BaseLangCode(Code)) <> '' then
    Exit(BaseLangCode(Code));
  Result := 'en';
end;

function IsZslPath(const S: string): Boolean;
begin
  Result := (LowerCase(ExtractFileExt(S)) = LangFileExt) or (Pos('/', S) > 0) or (Pos('\', S) > 0);
end;

{ chain for a code: <code>.zsl, then <base>.zsl; True when at least one of them was loaded }
function AddCodeToChain(const LangDir, Code: string): Boolean;
var
  F: string;
begin
  Result := False;
  F := FindLangFile(LangDir, Code);
  if (F <> '') and AddFileToChain(F) then
  begin
    Result := True;
    State.Code := Code;
  end;
  if BaseLangCode(Code) <> Code then
  begin
    F := FindLangFile(LangDir, BaseLangCode(Code));
    if (F <> '') and AddFileToChain(F) then
    begin
      if not Result then
        State.Code := BaseLangCode(Code);
      Result := True;
    end;
  end;
end;

function LangLoad(const Choice, LangDir: string): Boolean;
var
  C, Code, InfoCode: string;
  N: Integer;
begin
  EnsureEnglish;
  FreeOwned;
  State.Chain := nil;
  State.Code := 'en';
  State.Failed := '';
  Result := True;
  C := Trim(Choice);
  if (C = '') or SameText(C, 'auto') then
  begin
    // a file exists for the system language (LangAutoCode found it) but cannot be read
    Code := LangAutoCode(LangDir);
    if not AddCodeToChain(LangDir, Code) and (BaseLangCode(Code) <> 'en') then
    begin
      State.Failed := Code;
      Result := False;
    end;
  end
  else if IsZslPath(C) then
  begin
    C := ExpandFileNameUTF8(C);
    if AddFileToChain(C) then
    begin
      if not State.Owned[0].TryGet('info.code', InfoCode) then
        InfoCode := ChangeFileExt(ExtractFileName(C), '');
      Code := NormalizeLangCode(InfoCode);
      if not ValidLangCode(Code) then
        Code := 'en';
      State.Code := Code;
      if (BaseLangCode(Code) <> Code) and (FindLangFile(LangDir, BaseLangCode(Code)) <> '') then
        AddFileToChain(FindLangFile(LangDir, BaseLangCode(Code)));
    end
    else
    begin
      State.Failed := C;
      Result := False;
    end;
  end
  else
  begin
    Code := NormalizeLangCode(C);
    if not AddCodeToChain(LangDir, Code) and (BaseLangCode(Code) <> 'en') then
    begin
      State.Failed := Code;
      Result := False;
    end;
  end;
  N := Length(State.Chain);
  SetLength(State.Chain, N + 1);
  State.Chain[N] := State.English;
end;

function LangCode: string;
begin
  EnsureEnglish;
  Result := State.Code;
end;

function LangName: string;
begin
  EnsureEnglish;
  if not State.Chain[0].TryGet('info.name', Result) or (Result = '') then
    Result := 'English';
end;

function LangFailed: string;
begin
  Result := State.Failed;
end;

function InfoOf(T: TLangTable; const Code, FileName: string): TLangInfo;
begin
  Result.Code := Code;
  Result.FileName := FileName;
  if not T.TryGet('info.name', Result.Name) or (Result.Name = '') then
    Result.Name := Code;
  T.TryGet('info.english_name', Result.EnglishName);
  T.TryGet('info.author', Result.Author);
end;

function ListLanguages(const LangDir: string): TLangInfoArray;
var
  SR: TSearchRec;
  Dir, Code: string;
  T: TLangTable;
  N, I, J: Integer;
  Known: Boolean;
  Tmp: TLangInfo;
begin
  EnsureEnglish;
  Result := nil;
  SetLength(Result, 1);
  Result[0] := InfoOf(State.English, 'en', '');
  if Result[0].Name = 'en' then
    Result[0].Name := 'English';
  if LangDir <> '' then
  begin
    Dir := IncludeTrailingPathDelimiter(LangDir);
    T := TLangTable.Create;
    try
      if FindFirst(Dir + '*' + LangFileExt, faAnyFile, SR) = 0 then
      try
        repeat
          if SR.Attr and faDirectory <> 0 then
            Continue;
          Code := NormalizeLangCode(ChangeFileExt(SR.Name, ''));
          if (Code = 'en') or not ValidLangCode(Code) then
            Continue;
          N := Length(Result);
          Known := False;
          for I := 0 to N - 1 do
            if Result[I].Code = Code then
              Known := True;
          if Known or not T.LoadFromFile(Dir + SR.Name) then
            Continue;
          SetLength(Result, N + 1);
          Result[N] := InfoOf(T, Code, Dir + SR.Name);
        until FindNext(SR) <> 0;
      finally
        SysUtils.FindClose(SR);
      end;
    finally
      T.Free;
    end;
  end;
  // a few entries: insertion sort by name
  for I := 1 to High(Result) do
  begin
    Tmp := Result[I];
    J := I - 1;
    while (J >= 0) and (UTF8CompareText(Result[J].Name, Tmp.Name) > 0) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;
    Result[J + 1] := Tmp;
  end;
end;

finalization
  FreeOwned;
  State.English.Free;
  State.Missing.Free;
end.
