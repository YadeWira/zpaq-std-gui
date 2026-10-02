{ zsutil: small helpers shared by every layer: sizes, durations, dates, natural sort, wildcard
  masks, archive base names, safe relative paths and text files read as lines, plus the
  per-process temporary folders under %TEMP%\ZPAQ-std and their start-up purge. RTL + LazUtils. }
unit zsutil;

{$mode objfpc}{$H+}
{$WARN SYMBOL_PLATFORM OFF}

(* Public API

  Constants
    SizeUnknown = -1          a size, count or duration that is not known
    UnknownText = '—'         what FormatSize/FormatBytesExact/FormatDuration show for it (U+2014)

  Formatting (output never depends on the locale, except the separators passed in)
    FormatSize(Bytes, DecimalSep = '.')      base 1024: '0 B', '1023 B', '1.5 KB', '4.1 MB',
                                             '2.00 GB', '1.25 TB'; a value that rounds up to 1024
                                             moves to the next unit; negative -> UnknownText
    FormatBytesExact(Bytes, ThousandSep=',') all digits, grouped: '3,000,008'; negative -> UnknownText
    FormatDuration(Seconds)                  'h:mm:ss' ('0:00:05', '100:00:00'); negative -> UnknownText
    FormatIsoDateTime(DT, WithSeconds=False) 'yyyy-mm-dd hh:nn[:ss]'; DT <= 0 (unknown) -> ''
                                             (named so that it does not hide SysUtils.FormatDateTime)
    UtcToLocal(UtcDT)                        local time using the UTC offset of THAT date (DST-correct;
                                             Windows: SystemTimeToTzSpecificLocalTime; Unix: the RTL's
                                             tzdata, /etc/localtime or TZ=':Area/City' - the RTL ignores
                                             TZ without the ':'; dates after 2038 use the 2038 offset)

  Parsing and comparing
    ParseDottedInt64(S, out Value): Boolean  zpaq-std sizes: '0', '999', '3.000.008' (groups of 3
                                             after the first; plain digits also accepted); False on
                                             anything else ('negative', '', '1.00', overflow)
    NaturalCompare(A, B): Integer            -1/0/1; case-insensitive (Unicode simple case folding),
                                             digit runs compared by value ('file2' < 'file10',
                                             'a' < 'Z'); ties broken by byte order, so 0 means A = B
    HasMaskChars(S): Boolean                 S contains '*' or '?'
    MatchMask(Name, Mask, CaseSensitive = False): Boolean
                                             whole-string match; '*' = any run of characters (also
                                             '/'), '?' = exactly one character (code point); UTF-8
    SplitAt(S, Sep): TStringArray            every piece between Seps: 'a//b' -> 'a', '', 'b'
    AllDigits(S): Boolean                    S is '0'..'9' only and not empty

  Text files (used by the settings and the language files)
    ReadFileText(FileName, out Text, out Err): Boolean
                                             the whole file as bytes; False with the system's
                                             (localised) reason in Err when it cannot be read
    TextToLines(Text): TStringList           a UTF-8 BOM dropped, split at LF, CRLF or a lone CR;
                                             a final line break adds no empty line. Caller frees

  Names and paths
    ArchiveBaseName(FileName): string        folder name for "extract to a new folder":
                                             'backup_???.zpaq' -> 'backup', 'x.tar.gz' -> 'x',
                                             'x.part1.rar' -> 'x', 'x.7z.001' -> 'x', 'a.b.zip' -> 'a.b'
    SafeRelPath(StoredName): string          stored archive name -> relative path with '/' separators:
                                             '\' is a separator, 'C:/x' -> 'C/x', leading '/' dropped,
                                             '.' and empty components dropped, '..' -> '__'

  Temporary folders (never touch anything outside <root>, never follow links)
    AppTempRoot: string                      %TEMP%\ZPAQ-std\  (Unix: $TMPDIR/ZPAQ-std-<uid>/), with
                                             the trailing delimiter; not created
    CreateTempFolder(Kind, Root = ''): string  creates <root><kind>-<pid>-<n>\ (n = 1, 2...) and
                                             returns it with the trailing delimiter; '' on failure.
                                             Kind is lower-case letters ('preview', 'stage')
    PurgeStaleTempFolders(Root = '', MaxAgeHours = 24): Integer
                                             deletes the <kind>-<pid>-<n> folders of <root> whose
                                             process is gone or that are older than MaxAgeHours
                                             (never this process's own); other names are kept.
                                             Returns the number of folders deleted
    DeleteTree(Dir): Boolean                 deletes Dir and its contents; a symlink or junction is
                                             removed itself, its target is never entered
    IsProcessAlive(Pid): Boolean             a process with that id exists (access denied = exists)
*)

interface

uses
  Classes, SysUtils, LazUTF8;

const
  SizeUnknown = -1;
  UnknownText = #$E2#$80#$94;   // U+2014 EM DASH

function FormatSize(Bytes: Int64; DecimalSep: Char = '.'): string;
function FormatBytesExact(Bytes: Int64; ThousandSep: Char = ','): string;
function FormatDuration(Seconds: Int64): string;
function FormatIsoDateTime(DT: TDateTime; WithSeconds: Boolean = False): string;
function UtcToLocal(UtcDT: TDateTime): TDateTime;

function ParseDottedInt64(const S: string; out Value: Int64): Boolean;
function NaturalCompare(const A, B: string): Integer;
function HasMaskChars(const S: string): Boolean;
function MatchMask(const Name, Mask: string; CaseSensitive: Boolean = False): Boolean;
function SplitAt(const S: string; Sep: Char): TStringArray;
function AllDigits(const S: string): Boolean;

function ReadFileText(const FileName: string; out Text, Err: string): Boolean;
function TextToLines(const Text: string): TStringList;

function ArchiveBaseName(const FileName: string): string;
function SafeRelPath(const StoredName: string): string;

function AppTempRoot: string;
function CreateTempFolder(const Kind: string; const Root: string = ''): string;
function PurgeStaleTempFolders(const Root: string = ''; MaxAgeHours: Integer = 24): Integer;
function DeleteTree(const Dir: string): Boolean;
function IsProcessAlive(Pid: Cardinal): Boolean;

implementation

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF UNIX}
  BaseUnix, Unix, UnixUtil,
  {$ENDIF}
  DateUtils, LazUTF16;

{ ---------------------------------------------------------------------------------------------- }
{ Formatting                                                                                     }
{ ---------------------------------------------------------------------------------------------- }

function FormatSize(Bytes: Int64; DecimalSep: Char): string;
const
  Units: array[1..4] of string = ('KB', 'MB', 'GB', 'TB');
  Decimals: array[1..4] of Integer = (1, 1, 2, 2);
  Scales: array[1..4] of Double = (10.0, 10.0, 100.0, 100.0);
var
  FS: TFormatSettings;
  V: Double;
  U: Integer;
begin
  if Bytes < 0 then
    Exit(UnknownText);
  if Bytes < 1024 then
    Exit(IntToStr(Bytes) + ' B');
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := DecimalSep;
  FS.ThousandSeparator := #0;
  U := 1;
  V := Bytes / 1024.0;
  while U < 4 do
  begin
    // promote when the rounded value would print as 1024.0 (1048575 B is '1.0 MB', not '1024.0 KB')
    if Round(V * Scales[U]) / Scales[U] < 1024.0 then
      Break;
    V := V / 1024.0;
    Inc(U);
  end;
  Result := FloatToStrF(V, ffFixed, 18, Decimals[U], FS) + ' ' + Units[U];
end;

function FormatBytesExact(Bytes: Int64; ThousandSep: Char): string;
var
  Digits: string;
  I, N: Integer;
begin
  if Bytes < 0 then
    Exit(UnknownText);
  Digits := IntToStr(Bytes);
  Result := '';
  N := Length(Digits);
  for I := 1 to N do
  begin
    Result := Result + Digits[I];
    if ((N - I) mod 3 = 0) and (I < N) then
      Result := Result + ThousandSep;
  end;
end;

function FormatDuration(Seconds: Int64): string;
begin
  if Seconds < 0 then
    Exit(UnknownText);
  Result := Format('%d:%.2d:%.2d', [Seconds div 3600, (Seconds div 60) mod 60, Seconds mod 60]);
end;

function FormatIsoDateTime(DT: TDateTime; WithSeconds: Boolean): string;
var
  Y, Mo, D, H, Mi, S, Ms: Word;
begin
  if DT <= 0 then
    Exit('');
  DecodeDateTime(DT, Y, Mo, D, H, Mi, S, Ms);
  Result := Format('%.4d-%.2d-%.2d %.2d:%.2d', [Y, Mo, D, H, Mi]);
  if WithSeconds then
    Result := Result + Format(':%.2d', [S]);
end;

{$IFDEF MSWINDOWS}
function UtcToLocal(UtcDT: TDateTime): TDateTime;
var
  StUtc, StLocal: TSystemTime;
begin
  DateTimeToSystemTime(UtcDT, StUtc);
  StLocal := Default(TSystemTime);
  if SystemTimeToTzSpecificLocalTime(nil, StUtc, StLocal) then
    Result := SystemTimeToDateTime(StLocal)
  else
    // before 1601 or another failure: the offset of today
    Result := IncMinute(UtcDT, -GetLocalTimeOffset);
end;
{$ENDIF}

{$IFDEF UNIX}
function UtcToLocal(UtcDT: TDateTime): TDateTime;
var
  T: Int64;
  SavedSeconds: LongInt;
  SavedDaylight: Boolean;
  SavedNames: array[Boolean] of PChar;
  Offset: LongInt;
begin
  T := DateTimeToUnix(UtcDT);
  if T < Low(LongInt) then
    T := Low(LongInt)
  else if T > High(LongInt) then
    T := High(LongInt);
  // GetLocalTimezone sets the RTL globals that Now() uses: keep them as they were
  SavedSeconds := TZSeconds;
  SavedDaylight := tzdaylight;
  SavedNames[False] := tzname[False];
  SavedNames[True] := tzname[True];
  GetLocalTimezone(LongInt(T));
  Offset := TZSeconds;
  TZSeconds := SavedSeconds;
  tzdaylight := SavedDaylight;
  tzname[False] := SavedNames[False];
  tzname[True] := SavedNames[True];
  Result := IncSecond(UtcDT, Offset);
end;
{$ENDIF}

{ ---------------------------------------------------------------------------------------------- }
{ Parsing and comparing                                                                          }
{ ---------------------------------------------------------------------------------------------- }

function ParseDottedInt64(const S: string; out Value: Int64): Boolean;
var
  I, N, GroupLen, Groups: Integer;
  HasDots: Boolean;
  D: Int64;
begin
  Value := 0;
  N := Length(S);
  if N = 0 then
    Exit(False);
  HasDots := Pos('.', S) > 0;
  GroupLen := 0;
  Groups := 0;
  for I := 1 to N + 1 do
  begin
    if (I > N) or (S[I] = '.') then
    begin
      // the first group has 1..3 digits, every later group exactly 3
      if GroupLen = 0 then
        Exit(False);
      if HasDots and ((GroupLen > 3) or ((Groups > 0) and (GroupLen <> 3))) then
        Exit(False);
      Inc(Groups);
      GroupLen := 0;
      Continue;
    end;
    if not (S[I] in ['0'..'9']) then
      Exit(False);
    Inc(GroupLen);
    D := Ord(S[I]) - Ord('0');
    if Value > (High(Int64) - D) div 10 then
      Exit(False);
    Value := Value * 10 + D;
  end;
  Result := True;
end;

{ Reads one code point at P (P < E), folded to lower case; advances P. Invalid UTF-8 bytes map
  above the Unicode range so that they sort last and never equal a real character. }
function NextFolded(var P: PChar; E: PChar): Cardinal; inline;
var
  Len: Integer;
begin
  if Ord(P^) < $80 then
  begin
    Result := Ord(P^);
    if (Result >= Ord('A')) and (Result <= Ord('Z')) then
      Inc(Result, 32);
    Inc(P);
    Exit;
  end;
  if UTF8CodepointSize(P) > E - P then
  begin
    Result := $110000 + Ord(P^);
    Inc(P);
    Exit;
  end;
  Result := UTF8CodepointToUnicode(P, Len);
  if (Result = 0) or (Len < 1) then
  begin
    Result := $110000 + Ord(P^);
    Len := 1;
  end
  else
    Result := UnicodeLowercase(Result);
  Inc(P, Len);
end;

function NaturalCompare(const A, B: string): Integer;
var
  PA, PB, EA, EB, SA, SB, DA, DB: PChar;
  CA, CB: Cardinal;
begin
  PA := PChar(A);
  PB := PChar(B);
  EA := PA + Length(A);
  EB := PB + Length(B);
  // fast path: skip the byte-identical prefix (never into a digit run, which needs its value),
  // then step back to the start of a code point
  while (PA < EA) and (PB < EB) and (PA^ = PB^) and not (PA^ in ['0'..'9']) do
  begin
    Inc(PA);
    Inc(PB);
  end;
  while (PA > PChar(A)) and (Ord(PA^) and $C0 = $80) do
  begin
    Dec(PA);
    Dec(PB);
  end;
  while (PA < EA) and (PB < EB) do
  begin
    if (PA^ in ['0'..'9']) and (PB^ in ['0'..'9']) then
    begin
      // digit runs: skip leading zeros, the longer significant run is bigger, else digit by digit
      SA := PA;
      while (SA < EA) and (SA^ = '0') do
        Inc(SA);
      SB := PB;
      while (SB < EB) and (SB^ = '0') do
        Inc(SB);
      DA := SA;
      while (DA < EA) and (DA^ in ['0'..'9']) do
        Inc(DA);
      DB := SB;
      while (DB < EB) and (DB^ in ['0'..'9']) do
        Inc(DB);
      if DA - SA <> DB - SB then
        Exit(Ord(DA - SA > DB - SB) * 2 - 1);
      while SA < DA do
      begin
        if SA^ <> SB^ then
          Exit(Ord(SA^ > SB^) * 2 - 1);
        Inc(SA);
        Inc(SB);
      end;
      PA := DA;
      PB := DB;
      Continue;
    end;
    CA := NextFolded(PA, EA);
    CB := NextFolded(PB, EB);
    if CA <> CB then
      Exit(Ord(CA > CB) * 2 - 1);
  end;
  if PA < EA then
    Exit(1);
  if PB < EB then
    Exit(-1);
  // equal for a human ('a01' / 'a1', 'ABC' / 'abc'): byte order makes the order total
  Result := CompareStr(A, B);
  if Result < 0 then
    Result := -1
  else if Result > 0 then
    Result := 1;
end;

function HasMaskChars(const S: string): Boolean;
begin
  Result := (Pos('*', S) > 0) or (Pos('?', S) > 0);
end;

function CodepointLen(P, E: PChar): Integer; inline;
begin
  Result := UTF8CodepointSize(P);
  if (Result < 1) or (Result > E - P) then
    Result := 1;
end;

function MatchMask(const Name, Mask: string; CaseSensitive: Boolean): Boolean;
var
  N, M: string;
  PN, EN, PM, EM, StarM, StarN: PChar;
begin
  if CaseSensitive then
  begin
    N := Name;
    M := Mask;
  end
  else
  begin
    N := UTF8LowerCase(Name);
    M := UTF8LowerCase(Mask);
  end;
  PN := PChar(N);
  EN := PN + Length(N);
  PM := PChar(M);
  EM := PM + Length(M);
  StarM := nil;
  StarN := nil;
  // iterative matcher with one backtrack point; positions in N stay on code point boundaries
  while PN < EN do
  begin
    if (PM < EM) and (PM^ = '*') then
    begin
      while (PM < EM) and (PM^ = '*') do
        Inc(PM);
      if PM = EM then
        Exit(True);
      StarM := PM;
      StarN := PN;
    end
    else if (PM < EM) and (PM^ = '?') then
    begin
      Inc(PM);
      Inc(PN, CodepointLen(PN, EN));
    end
    else if (PM < EM) and (PM^ = PN^) then
    begin
      Inc(PM);
      Inc(PN);
    end
    else if StarM <> nil then
    begin
      Inc(StarN, CodepointLen(StarN, EN));
      PN := StarN;
      PM := StarM;
    end
    else
      Exit(False);
  end;
  while (PM < EM) and (PM^ = '*') do
    Inc(PM);
  Result := PM = EM;
end;

{ ---------------------------------------------------------------------------------------------- }
{ Names and paths                                                                                }
{ ---------------------------------------------------------------------------------------------- }

function StripExt(const S: string; out Ext: string): string;
var
  I: Integer;
begin
  Ext := '';
  Result := S;
  I := Length(S);
  while (I > 1) and (S[I] <> '.') do
    Dec(I);
  if (I > 1) and (S[I] = '.') and (I < Length(S)) then
  begin
    Ext := LowerCase(Copy(S, I + 1, MaxInt));
    Result := Copy(S, 1, I - 1);
  end;
end;

function AllDigits(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit(False);
end;

function ArchiveBaseName(const FileName: string): string;
const
  ArchiveExts = ',zpaq,7z,zip,rar,tar,gz,tgz,xz,txz,bz2,tbz,tbz2,zst,tzst,lz4,lzma,lz,iso,cab,wim,arj,z,';
var
  Name, Ext, Ext2, Rest: string;
  I: Integer;
begin
  Name := FileName;
  I := Length(Name);
  while (I > 0) and not (Name[I] in ['/', '\']) do
    Dec(I);
  Name := Copy(Name, I + 1, MaxInt);
  Result := StripExt(Name, Ext);
  // split volumes: x.7z.001, x.zip.001, x.001
  if (Length(Ext) >= 3) and AllDigits(Ext) then
  begin
    Rest := StripExt(Result, Ext2);
    if (Ext2 <> '') and (Pos(',' + Ext2 + ',', ArchiveExts) > 0) then
    begin
      Result := Rest;
      Ext := Ext2;
    end;
  end;
  // x.tar.gz, x.tar.xz, x.tar.zst ...
  if (Ext <> 'tar') and (Ext <> '') then
  begin
    Rest := StripExt(Result, Ext2);
    if Ext2 = 'tar' then
      Result := Rest;
  end;
  // x.part1.rar, x.part01.rar
  if Ext = 'rar' then
  begin
    Rest := StripExt(Result, Ext2);
    if (Length(Ext2) > 4) and (Copy(Ext2, 1, 4) = 'part') and AllDigits(Copy(Ext2, 5, MaxInt)) then
      Result := Rest;
  end;
  // multipart zpaq patterns: backup_???.zpaq, backup???.zpaq, backup_*.zpaq
  I := Length(Result);
  if (I > 0) and (Result[I] in ['?', '*']) then
  begin
    while (I > 0) and (Result[I] in ['?', '*']) do
      Dec(I);
    while (I > 0) and (Result[I] in ['_', '-', '.', ' ']) do
      Dec(I);
    Result := Copy(Result, 1, I);
  end;
  // Windows cannot create a folder whose name ends with a dot or a space
  I := Length(Result);
  while (I > 0) and (Result[I] in ['.', ' ']) do
    Dec(I);
  Result := Copy(Result, 1, I);
  if Result = '' then
    Result := Name;
end;

function SplitAt(const S: string; Sep: Char): TStringArray;
var
  I, Start, N: Integer;
begin
  Result := nil;
  N := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = Sep) then
    begin
      SetLength(Result, N + 1);
      Result[N] := Copy(S, Start, I - Start);
      Inc(N);
      Start := I + 1;
    end;
end;

function SafeRelPath(const StoredName: string): string;
var
  Parts: TStringArray;
  Comp: string;
  I: Integer;
  First: Boolean;
begin
  Parts := SplitAt(StringReplace(StoredName, '\', '/', [rfReplaceAll]), '/');
  Result := '';
  First := True;
  for I := 0 to High(Parts) do
  begin
    Comp := Parts[I];
    if (Comp = '') or (Comp = '.') then
      Continue;
    if Comp = '..' then
      Comp := '__'
    else if (I = 0) and (Length(Comp) >= 2) and (Comp[2] = ':') and
      (Comp[1] in ['A'..'Z', 'a'..'z']) then
    begin
      // drive letter: 'C:' -> 'C' (zpaq-std's own rule); 'C:x' -> 'C/x'
      if Length(Comp) > 2 then
        Comp := Comp[1] + '/' + Copy(Comp, 3, MaxInt)
      else
        Comp := Comp[1];
    end;
    if not First then
      Result := Result + '/';
    Result := Result + Comp;
    First := False;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }
{ Text files                                                                                     }
{ ---------------------------------------------------------------------------------------------- }

function ReadFileText(const FileName: string; out Text, Err: string): Boolean;
const
  Chunk = 65536;
var
  H: THandle;
  Len, N: Integer;
begin
  Text := '';
  Err := '';
  H := FileOpen(FileName, fmOpenRead or fmShareDenyNone);
  if H = feInvalidHandle then
  begin
    Err := SysErrorMessageUTF8(GetLastOSError);
    Exit(False);
  end;
  Len := 0;
  repeat
    SetLength(Text, Len + Chunk);
    N := FileRead(H, Text[Len + 1], Chunk);
    if N > 0 then
      Inc(Len, N);
  until N <= 0;
  if N < 0 then
    Err := SysErrorMessageUTF8(GetLastOSError);
  FileClose(H);
  Result := N = 0;
  if Result then
    SetLength(Text, Len)
  else
    Text := '';
end;

function TextToLines(const Text: string): TStringList;
var
  P, E, LineStart: PChar;
  Line: string;
begin
  Result := TStringList.Create;
  P := PChar(Text);
  E := P + Length(Text);
  if (Length(Text) >= 3) and (Text[1] = #$EF) and (Text[2] = #$BB) and (Text[3] = #$BF) then
    Inc(P, 3);
  while P < E do
  begin
    LineStart := P;
    while (P < E) and not (P^ in [#10, #13]) do
      Inc(P);
    SetString(Line, LineStart, P - LineStart);
    Result.Add(Line);
    if (P < E) and (P^ = #13) then
      Inc(P);
    if (P < E) and (P^ = #10) then
      Inc(P);
  end;
end;

{ ---------------------------------------------------------------------------------------------- }
{ Temporary folders                                                                              }
{ ---------------------------------------------------------------------------------------------- }

function SystemTempDir: string;
{$IFDEF MSWINDOWS}
var
  Buf: array[0..MAX_PATH + 1] of WideChar;
  N: DWORD;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  N := GetTempPathW(Length(Buf), @Buf[0]);
  if (N > 0) and (N < Length(Buf)) then
    Result := UTF16ToUTF8(PWideChar(@Buf[0]), N)
  else
    Result := GetEnvironmentVariableUTF8('TEMP');
  {$ELSE}
  Result := GetEnvironmentVariableUTF8('TMPDIR');
  if (Result = '') or (Result[1] <> '/') then
    Result := '/tmp';
  {$ENDIF}
  Result := IncludeTrailingPathDelimiter(Result);
end;

function AppTempRoot: string;
begin
  {$IFDEF UNIX}
  // /tmp is shared by every user: one folder per user
  Result := SystemTempDir + 'ZPAQ-std-' + IntToStr(fpGetUid) + PathDelim;
  {$ELSE}
  Result := SystemTempDir + 'ZPAQ-std' + PathDelim;
  {$ENDIF}
end;

function ValidKind(const Kind: string): Boolean;
var
  I: Integer;
begin
  Result := Kind <> '';
  for I := 1 to Length(Kind) do
    if not (Kind[I] in ['a'..'z']) then
      Exit(False);
end;

function CreateTempFolder(const Kind: string; const Root: string): string;
var
  Base, Dir: string;
  N: Integer;
begin
  Result := '';
  if not ValidKind(Kind) then
    Exit;
  if Root = '' then
    Base := AppTempRoot
  else
    Base := IncludeTrailingPathDelimiter(Root);
  if not ForceDirectories(Base) then
    Exit;
  for N := 1 to 10000 do
  begin
    Dir := Base + Kind + '-' + IntToStr(GetProcessID) + '-' + IntToStr(N);
    if DirectoryExists(Dir) or FileExists(Dir) then
      Continue;
    if CreateDir(Dir) then
      Exit(IncludeTrailingPathDelimiter(Dir));
  end;
end;

{ '<kind>-<pid>-<n>' -> pid; False for any other name }
function ParseTempName(const Name: string; out Pid: Cardinal): Boolean;
var
  Parts: TStringArray;
  V: Int64;
begin
  Result := False;
  Pid := 0;
  Parts := SplitAt(Name, '-');
  if Length(Parts) <> 3 then
    Exit;
  if not ValidKind(Parts[0]) or not AllDigits(Parts[1]) or not AllDigits(Parts[2]) then
    Exit;
  if (Length(Parts[1]) > 10) or not TryStrToInt64(Parts[1], V) or (V > High(Cardinal)) then
    Exit;
  Pid := Cardinal(V);
  Result := True;
end;

function PurgeStaleTempFolders(const Root: string; MaxAgeHours: Integer): Integer;
var
  Base: string;
  SR: TSearchRec;
  Pid: Cardinal;
  Stale: Boolean;
  Victims: TStringList;
  I: Integer;
begin
  Result := 0;
  if Root = '' then
    Base := AppTempRoot
  else
    Base := IncludeTrailingPathDelimiter(Root);
  if not DirectoryExists(Base) then
    Exit;
  Victims := TStringList.Create;
  try
    if FindFirst(Base + '*', faAnyFile or faSymLink, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        if (SR.Attr and faDirectory = 0) or (SR.Attr and faSymLink <> 0) then
          Continue;
        if not ParseTempName(SR.Name, Pid) or (Pid = GetProcessID) then
          Continue;
        Stale := not IsProcessAlive(Pid);
        if not Stale and (MaxAgeHours >= 0) then
          Stale := HoursBetween(Now, FileDateToDateTime(SR.Time)) >= MaxAgeHours;
        if Stale then
          Victims.Add(Base + SR.Name);
      until FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
    for I := 0 to Victims.Count - 1 do
      if DeleteTree(Victims[I]) then
        Inc(Result);
  finally
    Victims.Free;
  end;
end;

{ True when Path itself is a symlink (Unix) or a reparse point such as a junction (Windows) }
function IsLink(const Path: string): Boolean;
{$IFDEF UNIX}
var
  St: Stat;
begin
  St := Default(Stat);
  Result := (fpLStat(Path, St) = 0) and fpS_ISLNK(St.st_mode);
end;
{$ELSE}
var
  Attr: LongInt;
begin
  Attr := FileGetAttr(Path);
  Result := (Attr <> -1) and (Attr and faSymLink <> 0);
end;
{$ENDIF}

function DeleteTree(const Dir: string): Boolean;
var
  Base: string;
  SR: TSearchRec;
  Path: string;
begin
  Base := ExcludeTrailingPathDelimiter(Dir);
  if IsLink(Base) then
  begin
    // a link given as the tree itself: remove the link, never its target
    {$IFDEF MSWINDOWS}
    Exit(RemoveDir(Base) or SysUtils.DeleteFile(Base));
    {$ELSE}
    Exit(SysUtils.DeleteFile(Base));
    {$ENDIF}
  end;
  Result := True;
  if FindFirst(Base + PathDelim + '*', faAnyFile or faSymLink, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Path := Base + PathDelim + SR.Name;
      {$IFDEF MSWINDOWS}
      if SR.Attr and faReadOnly <> 0 then
        SysUtils.FileSetAttr(Path, SR.Attr and not faReadOnly);
      {$ENDIF}
      if SR.Attr and faSymLink <> 0 then
      begin
        // a link (Unix) or a reparse point (Windows): remove the link, never its target
        {$IFDEF MSWINDOWS}
        if SR.Attr and faDirectory <> 0 then
        begin
          if not RemoveDir(Path) then
            Result := False;
        end
        else
        {$ENDIF}
        if not SysUtils.DeleteFile(Path) then
          Result := False;
      end
      else if SR.Attr and faDirectory <> 0 then
      begin
        if not DeleteTree(Path) then
          Result := False;
      end
      else if not SysUtils.DeleteFile(Path) then
        Result := False;
    until FindNext(SR) <> 0;
  finally
    SysUtils.FindClose(SR);
  end;
  if not RemoveDir(Base) then
    Result := False;
end;

function IsProcessAlive(Pid: Cardinal): Boolean;
{$IFDEF MSWINDOWS}
var
  H: THandle;
{$ENDIF}
begin
  if Pid = 0 then
    Exit(False);
  {$IFDEF MSWINDOWS}
  H := OpenProcess(SYNCHRONIZE, False, Pid);
  if H = 0 then
    Exit(GetLastError = ERROR_ACCESS_DENIED);
  Result := WaitForSingleObject(H, 0) = WAIT_TIMEOUT;
  CloseHandle(H);
  {$ELSE}
  if Pid > Cardinal(High(LongInt)) then
    Exit(False);
  if fpKill(TPid(Pid), 0) = 0 then
    Exit(True);
  Result := fpgeterrno = ESysEPERM;
  {$ENDIF}
end;

end.
