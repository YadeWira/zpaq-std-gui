{ test_zsutil: fpcunit tests of src/core/zsutil (sizes, durations, dates, natural sort, masks,
  base names, safe paths, text files, temp folders) and of the layering rule (no LCL in src/core).
  Also holds the helpers the other test units share: ScratchDir and RepoRoot. }
unit test_zsutil;

{$mode objfpc}{$H+}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, LazUTF8, zsutil;

type
  TTestFormat = class(TTestCase)
  published
    procedure FormatSizeUnits;
    procedure FormatSizeRoundsUpToNextUnit;
    procedure FormatSizeSeparatorAndUnknown;
    procedure FormatBytesExactGroups;
    procedure FormatDurationValues;
    procedure FormatIsoDateTimeValues;
    procedure UtcToLocalOfNow;
    procedure UtcToLocalMatchesSystemPerDate;
  end;

  TTestParse = class(TTestCase)
  published
    procedure ParseDottedValid;
    procedure ParseDottedInvalid;
  end;

  TTestNatural = class(TTestCase)
  published
    procedure NumbersByValue;
    procedure CaseInsensitive;
    procedure TiesAreDeterministic;
    procedure SortsAList;
    procedure UnicodeFolding;
    procedure OrderIsConsistent;
  end;

  TTestMask = class(TTestCase)
  published
    procedure StarAndQuestion;
    procedure CaseAndUnicode;
    procedure AnchoredAndBacktracking;
  end;

  TTestNames = class(TTestCase)
  published
    procedure BaseNames;
    procedure SafeRelPaths;
    procedure SplitAndDigits;
  end;

  TTestTextFiles = class(TTestCase)
  published
    procedure ReadWholeFile;
    procedure ReadMissingFile;
    procedure LinesBomAndLineEnds;
  end;

  TTestTemp = class(TTestCase)
  published
    procedure CreateTempFolderNames;
    procedure PurgeDeletesOnlyStaleOwnFolders;
    procedure PurgeOldFolderOfLiveProcess;
    procedure DeleteTreeNeverFollowsLinks;
    procedure ProcessAlive;
  end;

  TTestLayering = class(TTestCase)
  published
    procedure CoreUsesNoLclUnit;
  end;

{ a new empty folder for one test, under the run's scratch root (ZSTESTS_TMP, or the system
  temp folder); everything is deleted when the program ends }
function ScratchDir(const Name: string): string;
{ the repository root (the folder holding src/core/zsutil.pas), searched upwards from the exe;
  '' when the tests run outside a checkout (a Windows VM) }
function RepoRoot: string;
procedure WriteTextFile(const FileName, Text: string);
function ReadTextFile(const FileName: string): string;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix, Process,
  {$ENDIF}
  DateUtils;

var
  ScratchRoot: string;
  ScratchCount: Integer;

function ScratchDir(const Name: string): string;
var
  Base: string;
begin
  if ScratchRoot = '' then
  begin
    Base := GetEnvironmentVariableUTF8('ZSTESTS_TMP');
    if Base = '' then
      Base := GetTempDir(False);
    ScratchRoot := IncludeTrailingPathDelimiter(Base) + 'zstests-' + IntToStr(GetProcessID)
      + PathDelim;
    ForceDirectories(ScratchRoot);
  end;
  Inc(ScratchCount);
  Result := ScratchRoot + IntToStr(ScratchCount) + '-' + Name + PathDelim;
  if DirectoryExists(Result) then
    DeleteTree(Result);
  if not ForceDirectories(Result) then
    raise Exception.Create('cannot create ' + Result);
end;

function RepoRoot: string;
var
  Dir, Parent: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStrUTF8(0))));
  repeat
    if FileExists(Dir + PathDelim + 'src' + PathDelim + 'core' + PathDelim + 'zsutil.pas') then
      Exit(IncludeTrailingPathDelimiter(Dir));
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (Parent = Dir) or (Parent = '') then
      Break;
    Dir := Parent;
  until False;
  Result := '';
end;

procedure WriteTextFile(const FileName, Text: string);
var
  FS: TFileStream;
begin
  ForceDirectories(ExtractFileDir(FileName));
  FS := TFileStream.Create(FileName, fmCreate);
  try
    if Text <> '' then
      FS.WriteBuffer(Text[1], Length(Text));
  finally
    FS.Free;
  end;
end;

function ReadTextFile(const FileName: string): string;
var
  FS: TFileStream;
begin
  Result := '';
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Result[1], FS.Size);
  finally
    FS.Free;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestFormat.FormatSizeUnits;
begin
  AssertEquals('0 B', FormatSize(0));
  AssertEquals('6 B', FormatSize(6));
  AssertEquals('1023 B', FormatSize(1023));
  AssertEquals('1.0 KB', FormatSize(1024));
  AssertEquals('1.5 KB', FormatSize(1536));
  AssertEquals('1.2 MB', FormatSize(1258291));
  AssertEquals('3.8 MB', FormatSize(3970117));
  AssertEquals('2.00 GB', FormatSize(Int64(2) * 1024 * 1024 * 1024));
  AssertEquals('1.25 TB', FormatSize(Int64(1280) * 1024 * 1024 * 1024));
  AssertEquals('8388608.00 TB', FormatSize(High(Int64)));
end;

procedure TTestFormat.FormatSizeRoundsUpToNextUnit;
begin
  AssertEquals('1023.9 KB', FormatSize(1048471));
  AssertEquals('1.0 MB', FormatSize(1048575));
  AssertEquals('1.0 MB', FormatSize(1048576));
  AssertEquals('1.00 GB', FormatSize(Int64(1024) * 1024 * 1024 - 1));
end;

procedure TTestFormat.FormatSizeSeparatorAndUnknown;
begin
  AssertEquals('1,5 KB', FormatSize(1536, ','));
  AssertEquals(UnknownText, FormatSize(SizeUnknown));
  AssertEquals(UnknownText, FormatSize(-5));
end;

procedure TTestFormat.FormatBytesExactGroups;
begin
  AssertEquals('0', FormatBytesExact(0));
  AssertEquals('999', FormatBytesExact(999));
  AssertEquals('1,000', FormatBytesExact(1000));
  AssertEquals('3,000,008', FormatBytesExact(3000008));
  AssertEquals('3.000.008', FormatBytesExact(3000008, '.'));
  AssertEquals('9,223,372,036,854,775,807', FormatBytesExact(High(Int64)));
  AssertEquals(UnknownText, FormatBytesExact(-1));
end;

procedure TTestFormat.FormatDurationValues;
begin
  AssertEquals('0:00:00', FormatDuration(0));
  AssertEquals('0:00:59', FormatDuration(59));
  AssertEquals('0:01:01', FormatDuration(61));
  AssertEquals('1:01:01', FormatDuration(3661));
  AssertEquals('100:00:00', FormatDuration(360000));
  AssertEquals(UnknownText, FormatDuration(-1));
end;

procedure TTestFormat.FormatIsoDateTimeValues;
var
  DT: TDateTime;
begin
  DT := EncodeDateTime(2026, 10, 2, 12, 39, 5, 0);
  AssertEquals('2026-10-02 12:39', FormatIsoDateTime(DT));
  AssertEquals('2026-10-02 12:39:05', FormatIsoDateTime(DT, True));
  AssertEquals('1980-01-05 00:00', FormatIsoDateTime(EncodeDate(1980, 1, 5)));
  AssertEquals('', FormatIsoDateTime(0));
end;

procedure TTestFormat.UtcToLocalOfNow;
var
  LocalNow, Back: TDateTime;
begin
  LocalNow := Now;
  Back := UtcToLocal(LocalTimeToUniversal(LocalNow));
  AssertTrue('UtcToLocal(UTC now) = now', Abs(SecondSpan(LocalNow, Back)) < 2);
  // the RTL clock must be unchanged after converting a date of another season
  UtcToLocal(EncodeDate(2001, 1, 15));
  UtcToLocal(EncodeDate(2001, 7, 15));
  AssertTrue('Now unchanged', Abs(SecondSpan(Now, LocalNow)) < 5);
end;

procedure TTestFormat.UtcToLocalMatchesSystemPerDate;
{$IFDEF UNIX}
const
  Dates: array[0..5] of string = ('1999-01-15 12:00:00', '1999-07-15 12:00:00',
    '2024-01-15 10:20:30', '2024-07-15 10:20:30', '2026-03-29 01:30:00', '2030-10-27 00:59:59');
var
  I: Integer;
  Utc: TDateTime;
  Expected, Output: string;
  FS: TFormatSettings;
begin
  if not FileExists('/bin/date') and not FileExists('/usr/bin/date') then
    Ignore('no date(1) to compare with');
  // the FPC RTL reads TZ only in the ':Area/City' form; date(1) also reads 'Area/City'
  Expected := GetEnvironmentVariableUTF8('TZ');
  if (Expected <> '') and (Expected[1] <> ':') then
    Ignore('TZ=' + Expected + ' is not read by the FPC RTL: use TZ=:' + Expected);
  FS := DefaultFormatSettings;
  FS.DateSeparator := '-';
  FS.TimeSeparator := ':';
  FS.ShortDateFormat := 'yyyy-mm-dd';
  FS.LongTimeFormat := 'hh:nn:ss';
  for I := 0 to High(Dates) do
  begin
    Utc := StrToDateTime(Dates[I], FS);
    // date(1) converts with the same TZ / tzdata, for that date
    AssertTrue('date ran', RunCommand('date', ['-d', '@' + IntToStr(DateTimeToUnix(Utc)),
      '+%Y-%m-%d %H:%M:%S'], Output, [poWaitOnExit, poUsePipes]));
    Expected := Trim(Output);
    AssertEquals('UTC ' + Dates[I], Expected, FormatIsoDateTime(UtcToLocal(Utc), True));
  end;
end;
{$ELSE}
var
  Jan, Jul: TDateTime;
begin
  // Windows: the offset of each date comes from the time zone rules (DST-aware); only sanity here
  Jan := UtcToLocal(EncodeDateTime(2024, 1, 15, 12, 0, 0, 0));
  Jul := UtcToLocal(EncodeDateTime(2024, 7, 15, 12, 0, 0, 0));
  AssertTrue('offset within 14 h', Abs(HourSpan(Jan, EncodeDateTime(2024, 1, 15, 12, 0, 0, 0))) <= 14);
  AssertTrue('offset within 14 h', Abs(HourSpan(Jul, EncodeDateTime(2024, 7, 15, 12, 0, 0, 0))) <= 14);
end;
{$ENDIF}

{ ---------------------------------------------------------------------------------------------- }

procedure TTestParse.ParseDottedValid;
var
  V: Int64;
begin
  AssertTrue(ParseDottedInt64('0', V));
  AssertEquals(0, V);
  AssertTrue(ParseDottedInt64('999', V));
  AssertEquals(999, V);
  AssertTrue(ParseDottedInt64('3.000.008', V));
  AssertEquals(3000008, V);
  AssertTrue(ParseDottedInt64('1.288.895', V));
  AssertEquals(1288895, V);
  AssertTrue(ParseDottedInt64('3.970.117', V));
  AssertEquals(3970117, V);
  AssertTrue('plain digits are accepted', ParseDottedInt64('1234', V));
  AssertEquals(1234, V);
  AssertTrue(ParseDottedInt64('9.223.372.036.854.775.807', V));
  AssertEquals(High(Int64), V);
end;

procedure TTestParse.ParseDottedInvalid;
const
  Bad: array[0..12] of string = ('', '.', '1.', '.123', '1.00', '1.0000', '1234.567', '1..000',
    'negative', '-1', ' 12', '12 ', '9.223.372.036.854.775.808');
var
  I: Integer;
  V: Int64;
begin
  for I := 0 to High(Bad) do
    AssertFalse('"' + Bad[I] + '"', ParseDottedInt64(Bad[I], V));
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestNatural.NumbersByValue;
begin
  AssertEquals(-1, NaturalCompare('file2', 'file10'));
  AssertEquals(1, NaturalCompare('file10', 'file2'));
  AssertEquals(-1, NaturalCompare('a9b', 'a10a'));
  AssertEquals(-1, NaturalCompare('x', 'x1'));
  AssertEquals(-1, NaturalCompare('', 'a'));
  AssertEquals(0, NaturalCompare('', ''));
  AssertEquals(0, NaturalCompare('file10', 'file10'));
  AssertEquals(1, NaturalCompare('12345678901234567890123', '99999999999999999999'));
  AssertEquals(-1, NaturalCompare('v1.9.2', 'v1.10.0'));
  AssertEquals('a shared prefix inside a number', -1, NaturalCompare('x109', 'x1007'));
  AssertEquals(1, NaturalCompare('x1007', 'x109'));
  AssertEquals(-1, NaturalCompare('x05', 'x007'));
end;

procedure TTestNatural.CaseInsensitive;
begin
  AssertEquals('a < Z', -1, NaturalCompare('a', 'Z'));
  AssertEquals('Z > a', 1, NaturalCompare('Z', 'a'));
  AssertEquals(-1, NaturalCompare('apple', 'Banana'));
  AssertEquals(-1, NaturalCompare('File2', 'file10'));
end;

procedure TTestNatural.TiesAreDeterministic;
begin
  // equal for a human: ordered by bytes, never 0
  AssertTrue(NaturalCompare('ABC', 'abc') <> 0);
  AssertEquals(-NaturalCompare('ABC', 'abc'), NaturalCompare('abc', 'ABC'));
  AssertTrue(NaturalCompare('a01', 'a1') <> 0);
  AssertEquals(-NaturalCompare('a01', 'a1'), NaturalCompare('a1', 'a01'));
end;

procedure TTestNatural.SortsAList;
const
  Input: array[0..9] of string = ('file10.txt', 'File2.txt', 'file1.txt', 'b', 'A', 'file2a.txt',
    'z10', 'Z9', '10', '9');
  Expected: array[0..9] of string = ('9', '10', 'A', 'b', 'file1.txt', 'File2.txt', 'file2a.txt',
    'file10.txt', 'Z9', 'z10');
var
  L: TStringList;
  I, J: Integer;
  T: string;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(Input) do
      L.Add(Input[I]);
    // insertion sort with NaturalCompare
    for I := 1 to L.Count - 1 do
    begin
      T := L[I];
      J := I - 1;
      while (J >= 0) and (NaturalCompare(L[J], T) > 0) do
      begin
        L[J + 1] := L[J];
        Dec(J);
      end;
      L[J + 1] := T;
    end;
    for I := 0 to High(Expected) do
      AssertEquals('position ' + IntToStr(I), Expected[I], L[I]);
  finally
    L.Free;
  end;
end;

procedure TTestNatural.UnicodeFolding;
begin
  AssertEquals('ñu < Ñv', -1, NaturalCompare('ñu', 'Ñv'));
  AssertEquals('Ñv > ñu', 1, NaturalCompare('Ñv', 'ñu'));
  AssertEquals('Éa < éb', -1, NaturalCompare('Éa', 'éb'));
  AssertEquals(-1, NaturalCompare('日本2', '日本10'));
  AssertEquals('folding after a shared prefix', -1, NaturalCompare('caé1', 'caÉ2'));
  AssertEquals(1, NaturalCompare('caÉ2', 'caé1'));
  AssertTrue('invalid UTF-8 does not crash', NaturalCompare(#$C3, #$C3#$B1) <> 0);
end;

procedure TTestNatural.OrderIsConsistent;
const
  Alphabet = 'aAbB01 9._-' + #$C3#$B1 + #$C3#$91;
var
  S: array of string;
  I, J, K, N: Integer;
  Word: string;
begin
  RandSeed := 12345;
  N := 300;
  S := nil;
  SetLength(S, N);
  for I := 0 to N - 1 do
  begin
    Word := '';
    for J := 1 to Random(6) do
    begin
      K := Random(Length(Alphabet)) + 1;
      if Ord(Alphabet[K]) >= $C3 then
        Word := Word + Copy(Alphabet, K, 2)
      else if Ord(Alphabet[K]) < $80 then
        Word := Word + Alphabet[K];
    end;
    S[I] := Word;
  end;
  for I := 0 to N - 1 do
    for J := 0 to N - 1 do
    begin
      AssertEquals('antisymmetric ' + S[I] + ' / ' + S[J], -NaturalCompare(S[J], S[I]),
        NaturalCompare(S[I], S[J]));
      if (NaturalCompare(S[I], S[J]) = 0) and (S[I] <> S[J]) then
        Fail('0 for different strings: ' + S[I] + ' / ' + S[J]);
    end;
  // transitivity on triples
  for I := 0 to 59 do
    for J := 0 to 59 do
      for K := 0 to 59 do
        if (NaturalCompare(S[I], S[J]) < 0) and (NaturalCompare(S[J], S[K]) < 0) then
          AssertTrue('transitive', NaturalCompare(S[I], S[K]) < 0);
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestMask.StarAndQuestion;
begin
  AssertTrue(MatchMask('a.txt', '*.txt'));
  AssertFalse(MatchMask('a.txt.bak', '*.txt'));
  AssertTrue(MatchMask('abc', 'a?c'));
  AssertFalse(MatchMask('ac', 'a?c'));
  AssertTrue(MatchMask('', '*'));
  AssertTrue(MatchMask('', ''));
  AssertFalse(MatchMask('a', ''));
  AssertFalse(MatchMask('', '?'));
  AssertTrue(MatchMask('anything', '**'));
  AssertTrue('star crosses /', MatchMask('src/sub/a.txt', 'src/*.txt'));
  AssertTrue(MatchMask('a/x/bc', 'a/*/b?'));
  AssertTrue(HasMaskChars('*.txt'));
  AssertTrue(HasMaskChars('a?'));
  AssertFalse(HasMaskChars('plain'));
end;

procedure TTestMask.CaseAndUnicode;
begin
  AssertTrue(MatchMask('A.TXT', '*.txt'));
  AssertFalse(MatchMask('A.TXT', '*.txt', True));
  AssertTrue('? is one code point', MatchMask('ñ', '?'));
  AssertFalse(MatchMask('ñ', '??'));
  AssertTrue(MatchMask('xÑy', '*ñ*'));
  AssertTrue(MatchMask('日本', '日*'));
  AssertTrue(MatchMask('日本', '?本'));
  AssertTrue(MatchMask('ünï €.txt', '*€.TXT'));
  AssertTrue(MatchMask('€', '*?'));
  AssertFalse(MatchMask('ñ', '*a'));
end;

procedure TTestMask.AnchoredAndBacktracking;
begin
  AssertTrue(MatchMask('aXbYc', 'a*b*c'));
  AssertTrue(MatchMask('ab', 'a*b'));
  AssertTrue(MatchMask('abab', '*ab'));
  AssertTrue(MatchMask('aaab', 'a*ab'));
  AssertFalse(MatchMask('abc', 'a*d'));
  AssertTrue(MatchMask('mississippi', 'm*iss*ppi'));
  AssertFalse(MatchMask('mississippi', 'm*iss*ppx'));
  AssertTrue(MatchMask('ñañb', '*ñb'));
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestNames.BaseNames;
begin
  AssertEquals('backup', ArchiveBaseName('backup_???.zpaq'));
  AssertEquals('backup', ArchiveBaseName('D:\Backups\backup???.zpaq'));
  AssertEquals('backup', ArchiveBaseName('backup_*.zpaq'));
  AssertEquals('backup_001', ArchiveBaseName('backup_001.zpaq'));
  AssertEquals('x', ArchiveBaseName('x.tar.gz'));
  AssertEquals('x', ArchiveBaseName('/home/me/x.tar.zst'));
  AssertEquals('x', ArchiveBaseName('x.tgz'));
  AssertEquals('x', ArchiveBaseName('x.tar'));
  AssertEquals('x', ArchiveBaseName('x.part1.rar'));
  AssertEquals('x', ArchiveBaseName('x.part01.rar'));
  AssertEquals('x', ArchiveBaseName('x.7z.001'));
  AssertEquals('x', ArchiveBaseName('x.zip.001'));
  AssertEquals('x', ArchiveBaseName('x.001'));
  AssertEquals('a.b', ArchiveBaseName('a.b.zip'));
  AssertEquals('docs 2024', ArchiveBaseName('docs 2024.7z'));
  AssertEquals('ñandú 日本', ArchiveBaseName('ñandú 日本.zpaq'));
  AssertEquals('noext', ArchiveBaseName('noext'));
  AssertEquals('.zpaq', ArchiveBaseName('.zpaq'));
  AssertEquals('trailing', ArchiveBaseName('trailing..zip'));
end;

procedure TTestNames.SafeRelPaths;
begin
  AssertEquals('C/x', SafeRelPath('C:/x'));
  AssertEquals('C/t/src/a.txt', SafeRelPath('C:/t/src/a.txt'));
  AssertEquals('C', SafeRelPath('C:'));
  AssertEquals('C/x', SafeRelPath('C:x'));
  AssertEquals('tmp/x/big.bin', SafeRelPath('/tmp/x/big.bin'));
  AssertEquals('__/evil.txt', SafeRelPath('../evil.txt'));
  AssertEquals('a/__/b', SafeRelPath('a/../b'));
  AssertEquals('a/b', SafeRelPath('a\b'));
  AssertEquals('a/b', SafeRelPath('./a//b/'));
  AssertEquals('server/share/f', SafeRelPath('\\server\share\f'));
  AssertEquals('src/ñandú 日本/ünï €.txt', SafeRelPath('src/ñandú 日本/ünï €.txt'));
  AssertEquals('.../x', SafeRelPath('.../x'));
  AssertEquals('d/e:f', SafeRelPath('d/e:f'));
  AssertEquals('', SafeRelPath('/'));
  AssertEquals('', SafeRelPath(''));
end;

procedure TTestNames.SplitAndDigits;
var
  P: TStringArray;
begin
  P := SplitAt('a//b', '/');
  AssertEquals(3, Length(P));
  AssertEquals('a', P[0]);
  AssertEquals('', P[1]);
  AssertEquals('b', P[2]);
  AssertEquals('one empty piece', 1, Length(SplitAt('', ',')));
  AssertEquals(2, Length(SplitAt('x,', ',')));
  AssertTrue(AllDigits('0123'));
  AssertFalse(AllDigits(''));
  AssertFalse(AllDigits('12a'));
  AssertFalse(AllDigits('-1'));
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestTextFiles.ReadWholeFile;
var
  Dir, Text, Err, Big: string;
  I: Integer;
begin
  Dir := ScratchDir('readtext');
  WriteTextFile(Dir + 'ñandú.txt', #$EF#$BB#$BF'a'#0'b'#13#10);
  AssertTrue(ReadFileText(Dir + 'ñandú.txt', Text, Err));
  AssertEquals('', Err);
  AssertEquals('bytes as they are', #$EF#$BB#$BF'a'#0'b'#13#10, Text);
  Big := '';
  SetLength(Big, 200000);
  for I := 1 to Length(Big) do
    Big[I] := Chr(Ord('a') + I mod 26);
  WriteTextFile(Dir + 'big.txt', Big);
  AssertTrue(ReadFileText(Dir + 'big.txt', Text, Err));
  AssertEquals('more than one read chunk', Length(Big), Length(Text));
  AssertTrue(Big = Text);
  WriteTextFile(Dir + 'empty.txt', '');
  AssertTrue(ReadFileText(Dir + 'empty.txt', Text, Err));
  AssertEquals('', Text);
end;

procedure TTestTextFiles.ReadMissingFile;
var
  Text, Err: string;
begin
  AssertFalse(ReadFileText(ScratchDir('readmissing') + 'nope.txt', Text, Err));
  AssertEquals('', Text);
  AssertTrue('the system gives a reason', Err <> '');
end;

procedure TTestTextFiles.LinesBomAndLineEnds;
var
  L: TStringList;
begin
  L := TextToLines(#$EF#$BB#$BF'one'#13#10'two'#10'three'#13'four'#13#10);
  try
    AssertEquals('BOM dropped, CRLF, LF and CR', 'one|two|three|four', L[0] + '|' + L[1] + '|' +
      L[2] + '|' + L[3]);
    AssertEquals('the final line break adds no line', 4, L.Count);
  finally
    L.Free;
  end;
  L := TextToLines('a'#10#10'b');
  try
    AssertEquals(3, L.Count);
    AssertEquals('', L[1]);
  finally
    L.Free;
  end;
  L := TextToLines('');
  try
    AssertEquals(0, L.Count);
  finally
    L.Free;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }

const
  DeadPid = 2147483644;   // never a live process id (beyond pid_max; a multiple of 4)

procedure TTestTemp.CreateTempFolderNames;
var
  Root, A, B: string;
begin
  Root := ScratchDir('tempnames');
  A := CreateTempFolder('preview', Root);
  B := CreateTempFolder('preview', Root);
  AssertEquals(Root + 'preview-' + IntToStr(GetProcessID) + '-1' + PathDelim, A);
  AssertEquals(Root + 'preview-' + IntToStr(GetProcessID) + '-2' + PathDelim, B);
  AssertTrue(DirectoryExists(A));
  AssertTrue(DirectoryExists(B));
  AssertEquals('kind must be lower-case letters', '', CreateTempFolder('../x', Root));
  AssertEquals('', CreateTempFolder('', Root));
  AssertTrue(Copy(AppTempRoot, Length(AppTempRoot), 1) = PathDelim);
  AssertTrue(Pos('ZPAQ-std', AppTempRoot) > 0);
end;

procedure TTestTemp.PurgeDeletesOnlyStaleOwnFolders;
var
  Root, Dead, Mine, Other, Loose: string;
begin
  Root := ScratchDir('purge');
  Dead := Root + 'preview-' + IntToStr(DeadPid) + '-1';
  WriteTextFile(Dead + PathDelim + 'sub' + PathDelim + 'deep' + PathDelim + 'f.txt', 'x');
  WriteTextFile(Dead + PathDelim + 'g.txt', 'y');
  Mine := CreateTempFolder('preview', Root);
  WriteTextFile(Mine + 'keep.txt', 'mine');
  Other := Root + 'not-ours';
  ForceDirectories(Other);
  Loose := Root + 'preview-' + IntToStr(DeadPid) + '-x';
  ForceDirectories(Loose);
  WriteTextFile(Root + 'stage-' + IntToStr(DeadPid) + '-3', 'a file, not a folder');
  AssertEquals('one folder deleted', 1, PurgeStaleTempFolders(Root));
  AssertFalse('stale folder gone', DirectoryExists(Dead));
  AssertTrue('own folder kept', FileExists(Mine + 'keep.txt'));
  AssertTrue('other names kept', DirectoryExists(Other));
  AssertTrue('malformed name kept', DirectoryExists(Loose));
  AssertTrue('files kept', FileExists(Root + 'stage-' + IntToStr(DeadPid) + '-3'));
  AssertEquals('nothing left to delete', 0, PurgeStaleTempFolders(Root));
  AssertEquals('missing root', 0, PurgeStaleTempFolders(Root + 'missing'));
end;

procedure TTestTemp.PurgeOldFolderOfLiveProcess;
var
  Root, Fresh, Old: string;
  LivePid: Cardinal;
begin
  {$IFDEF MSWINDOWS}
  LivePid := 4;     // System
  {$ELSE}
  LivePid := 1;     // init
  {$ENDIF}
  if not IsProcessAlive(LivePid) then
    Ignore('no well-known live process id here');
  Root := ScratchDir('purgeage');
  Fresh := Root + 'preview-' + IntToStr(LivePid) + '-1';
  Old := Root + 'preview-' + IntToStr(LivePid) + '-2';
  ForceDirectories(Fresh);
  ForceDirectories(Old);
  if FileSetDate(Old, DateTimeToFileDate(IncHour(Now, -30))) <> 0 then
    Ignore('cannot set the date of a folder here');
  AssertEquals(1, PurgeStaleTempFolders(Root, 24));
  AssertTrue('fresh folder of a live process kept', DirectoryExists(Fresh));
  AssertFalse('folder older than 24 h deleted', DirectoryExists(Old));
end;

procedure TTestTemp.DeleteTreeNeverFollowsLinks;
{$IFDEF UNIX}
var
  Root, Outside, Victim: string;
begin
  Root := ScratchDir('links');
  Outside := Root + 'outside';
  WriteTextFile(Outside + PathDelim + 'precious.txt', 'PRECIOUS');
  Victim := Root + 'preview-' + IntToStr(DeadPid) + '-1';
  WriteTextFile(Victim + PathDelim + 'a.txt', 'a');
  AssertEquals('symlink to a folder', 0, fpSymlink(PChar(Outside), PChar(Victim + PathDelim + 'link')));
  AssertEquals('symlink to a file', 0,
    fpSymlink(PChar(Outside + PathDelim + 'precious.txt'), PChar(Victim + PathDelim + 'flink')));
  AssertEquals(1, PurgeStaleTempFolders(Root));
  AssertFalse(DirectoryExists(Victim));
  AssertEquals('target untouched', 'PRECIOUS', ReadTextFile(Outside + PathDelim + 'precious.txt'));
  // a link given as the tree itself is removed, its target is not entered
  AssertEquals(0, fpSymlink(PChar(Outside), PChar(Root + 'rootlink')));
  AssertTrue(DeleteTree(Root + 'rootlink'));
  AssertFalse(FileExists(Root + 'rootlink'));
  AssertEquals('PRECIOUS', ReadTextFile(Outside + PathDelim + 'precious.txt'));
end;
{$ELSE}
var
  Root, Victim: string;
begin
  // junctions need mklink; the attribute rule (reparse point = remove the link only) is in code
  Root := ScratchDir('links');
  Victim := Root + 'tree';
  WriteTextFile(Victim + PathDelim + 'a' + PathDelim + 'b.txt', 'b');
  FileSetAttr(Victim + PathDelim + 'a' + PathDelim + 'b.txt', faReadOnly);
  AssertTrue(DeleteTree(Victim));
  AssertFalse(DirectoryExists(Victim));
end;
{$ENDIF}

procedure TTestTemp.ProcessAlive;
begin
  AssertTrue('this process', IsProcessAlive(GetProcessID));
  AssertFalse('a pid that cannot exist', IsProcessAlive(DeadPid));
  AssertFalse('pid 0', IsProcessAlive(0));
end;

{ ---------------------------------------------------------------------------------------------- }

{ the unit names of every 'uses' clause of a Pascal source, lower case; comments and strings
  are skipped }
function UsedUnits(const Src: string): TStringList;
var
  I, N: Integer;
  Word: string;
  InUses: Boolean;
begin
  Result := TStringList.Create;
  N := Length(Src);
  I := 1;
  InUses := False;
  while I <= N do
  begin
    if Src[I] = '{' then
    begin
      while (I <= N) and (Src[I] <> '}') do
        Inc(I);
      Inc(I);
    end
    else if (Src[I] = '(') and (I < N) and (Src[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < N) and not ((Src[I] = '*') and (Src[I + 1] = ')')) do
        Inc(I);
      Inc(I, 2);
    end
    else if (Src[I] = '/') and (I < N) and (Src[I + 1] = '/') then
    begin
      while (I <= N) and not (Src[I] in [#10, #13]) do
        Inc(I);
    end
    else if Src[I] = '''' then
    begin
      Inc(I);
      while (I <= N) and (Src[I] <> '''') do
        Inc(I);
      Inc(I);
    end
    else if Src[I] in ['A'..'Z', 'a'..'z', '_'] then
    begin
      Word := '';
      while (I <= N) and (Src[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
      begin
        Word := Word + Src[I];
        Inc(I);
      end;
      Word := LowerCase(Word);
      if Word = 'uses' then
        InUses := True
      else if InUses and (Word <> 'in') then
        Result.Add(Word);
    end
    else
    begin
      if Src[I] = ';' then
        InUses := False;
      Inc(I);
    end;
  end;
end;

procedure TTestLayering.CoreUsesNoLclUnit;
const
  Forbidden: array[0..19] of string = ('forms', 'controls', 'graphics', 'dialogs', 'stdctrls',
    'extctrls', 'comctrls', 'buttons', 'menus', 'actnlist', 'imglist', 'lcltype', 'lclintf',
    'lclproc', 'lresources', 'interfaces', 'lmessages', 'clipbrd', 'virtualtrees',
    'laz.virtualtrees');
var
  Root: string;
  SR: TSearchRec;
  Units: TStringList;
  I, Checked: Integer;
begin
  Root := RepoRoot;
  if Root = '' then
    Ignore('not run from a checkout: src/core not found');
  Checked := 0;
  if FindFirst(Root + 'src' + PathDelim + 'core' + PathDelim + '*.pas', faAnyFile, SR) = 0 then
  try
    repeat
      Units := UsedUnits(ReadTextFile(Root + 'src' + PathDelim + 'core' + PathDelim + SR.Name));
      try
        for I := Low(Forbidden) to High(Forbidden) do
          AssertTrue(SR.Name + ' uses the LCL unit ' + Forbidden[I],
            Units.IndexOf(Forbidden[I]) < 0);
      finally
        Units.Free;
      end;
      Inc(Checked);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  AssertTrue('at least zsutil, zsconfig and zslang checked', Checked >= 3);
end;

initialization
  RegisterTest('zsutil', TTestFormat);
  RegisterTest('zsutil', TTestParse);
  RegisterTest('zsutil', TTestNatural);
  RegisterTest('zsutil', TTestMask);
  RegisterTest('zsutil', TTestNames);
  RegisterTest('zsutil', TTestTextFiles);
  RegisterTest('zsutil', TTestTemp);
  RegisterTest('layering', TTestLayering);

finalization
  if ScratchRoot <> '' then
    DeleteTree(ScratchRoot);
end.
