{ test_zsconfig: fpcunit tests of src/core/zsconfig: defaults, the location rule (portable
  writable / read-only folder or file / absent), validation of every kind of value, BOM, CRLF and
  comments (the DESIGN §11.2 sample), and the merge-save (two writers, unknown lines and comments
  kept, lists, atomic write, failure -> Writable False with the system's reason). }
unit test_zsconfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, LazUTF8, zsconfig;

type
  TTestConfigLoad = class(TTestCase)
  published
    procedure Defaults;
    procedure UserDirName;
    procedure LocationAbsent;
    procedure LocationPortableWritable;
    procedure LocationPortableReadOnly;
    procedure LocationPortableReadOnlyFile;
    procedure ValidValues;
    procedure InvalidValuesKeepDefaults;
    procedure BomCrlfCommentsAndCase;
    procedure DesignSampleWithComments;
    procedure ThemeNames;
    procedure LastDuplicateWins;
    procedure Lists;
    procedure ColumnsAndWindow;
  end;

  TTestConfigSave = class(TTestCase)
  published
    procedure NothingChangedWritesNothing;
    procedure RoundTrip;
    procedure UnknownLinesKept;
    procedure CommentsOfEmptyValuesKept;
    procedure TwoWriters;
    procedure ListsRewritten;
    procedure AtomicNoTmpLeft;
    procedure FailureClearsWritable;
    procedure FailureReasonIsTheSystemsOwn;
    procedure AddRecentRules;
  end;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  test_zsutil;

function LoadFrom(const Dir: string): TConfig;
var
  C: TConfig;
begin
  ConfigDefaults(C);
  InitConfig(C, Dir + 'exe', Dir + 'user');
  Result := C;
end;

function Lines(const S: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(S) do
    Result := Result + S[I] + LineEnding;
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestConfigLoad.Defaults;
var
  C: TConfig;
begin
  ConfigDefaults(C);
  AssertEquals('auto', C.Language);
  AssertTrue(C.Theme = thAuto);
  AssertEquals('', C.Font);
  AssertEquals('100,80,900,560', FormatWindowGeometry(C.Window));
  AssertFalse(C.Maximized);
  AssertEquals(DefaultColumnsZpaq, C.ColumnsZpaq);
  AssertEquals(DefaultColumns7z, C.Columns7z);
  AssertEquals('name', C.Sort.Column);
  AssertFalse(C.Sort.Descending);
  AssertTrue(C.CreateFormat = cfZpaq);
  AssertEquals('1', C.ZpaqMethod);
  AssertEquals(0, C.ZpaqLevel);
  AssertEquals(0, C.ZpaqThreads);
  AssertEquals(5, C.ZipLevel);
  AssertTrue(C.Overwrite = owAsk);
  AssertTrue(C.Subfolder = sfSmart);
  AssertFalse(C.OpenFolder);
  AssertTrue(C.CloseWhenDone);
  AssertTrue(C.ConfirmCancel);
  AssertFalse(C.DetailsOpen);
  AssertFalse(C.Log);
  AssertEquals(700, C.CollectQuietMs);
  AssertTrue(C.Writable);
  AssertEquals(0, Length(C.Recent));
  // zsconfig writes the enum fields through a LongInt pointer ({$PACKENUM 4})
  AssertEquals(SizeOf(LongInt), SizeOf(C.Theme));
  AssertEquals(SizeOf(LongInt), SizeOf(C.CreateFormat));
  AssertEquals(SizeOf(LongInt), SizeOf(C.Overwrite));
  AssertEquals(SizeOf(LongInt), SizeOf(C.Subfolder));
end;

procedure TTestConfigLoad.UserDirName;
var
  D: string;
begin
  D := UserConfigDir;
  AssertEquals('trailing delimiter', PathDelim, Copy(D, Length(D), 1));
  {$IFDEF MSWINDOWS}
  AssertEquals('ZPAQ-std\', Copy(D, Length(D) - 8, 9));
  {$ELSE}
  AssertEquals('zpaq-std-gui/', Copy(D, Length(D) - 12, 13));
  {$ENDIF}
end;

procedure TTestConfigLoad.LocationAbsent;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('loc-absent');
  ForceDirectories(Dir + 'exe');
  C := LoadFrom(Dir);
  AssertEquals(Dir + 'user' + PathDelim + ConfigFileName, C.FileName);
  AssertFalse(C.Portable);
  AssertFalse(C.ReadOnlyPortable);
  AssertEquals('', C.DefaultsFile);
  AssertTrue(C.Writable);
  AssertFalse(C.LanguageKeyFound);
end;

procedure TTestConfigLoad.LocationPortableWritable;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('loc-portable');
  WriteTextFile(Dir + 'exe' + PathDelim + ConfigFileName, Lines(['[gui]', 'language=es']));
  C := LoadFrom(Dir);
  AssertEquals(Dir + 'exe' + PathDelim + ConfigFileName, C.FileName);
  AssertTrue(C.Portable);
  AssertFalse(C.ReadOnlyPortable);
  AssertEquals('es', C.Language);
  AssertTrue(C.LanguageKeyFound);
  // the probe file is gone
  AssertFalse(FileExists(Dir + 'exe' + PathDelim + '.zpaq-std-gui-probe-' + IntToStr(GetProcessID)
    + '.tmp'));
end;

procedure TTestConfigLoad.LocationPortableReadOnly;
{$IFDEF UNIX}
var
  Dir, Portable, UserIni: string;
  C: TConfig;
begin
  if fpGetEUid = 0 then
    Ignore('root can write into read-only folders');
  Dir := ScratchDir('loc-readonly');
  Portable := Dir + 'exe' + PathDelim + ConfigFileName;
  UserIni := Dir + 'user' + PathDelim + ConfigFileName;
  WriteTextFile(Portable, Lines(['[gui]', 'language=es', 'theme=dark', '[extract]',
    'overwrite=skip']));
  WriteTextFile(UserIni, Lines(['[gui]', 'theme=light']));
  AssertEquals(0, fpChmod(Dir + 'exe', &555));
  try
    C := LoadFrom(Dir);
    AssertFalse(C.Portable);
    AssertTrue(C.ReadOnlyPortable);
    AssertEquals(Portable, C.DefaultsFile);
    AssertEquals(UserIni, C.FileName);
    AssertEquals('from the portable file', 'es', C.Language);
    AssertTrue('the user file wins', C.Theme = thLight);
    AssertTrue(C.Overwrite = owSkip);
    C.Subfolder := sfNever;
    AssertTrue(SaveConfig(C));
    AssertEquals('portable file untouched', Lines(['[gui]', 'language=es', 'theme=dark',
      '[extract]', 'overwrite=skip']), ReadTextFile(Portable));
    AssertTrue(Pos('subfolder=never', ReadTextFile(UserIni)) > 0);
    AssertTrue('only the changed key is written', Pos('language', ReadTextFile(UserIni)) = 0);
  finally
    fpChmod(Dir + 'exe', &755);
  end;
end;
{$ELSE}
begin
  Ignore('needs a read-only folder (checked on the VMs by hand: Program Files)');
end;
{$ENDIF}

procedure TTestConfigLoad.LocationPortableReadOnlyFile;
var
  Dir, Portable, UserIni, Before: string;
  C: TConfig;
begin
  {$IFDEF UNIX}
  if fpGetEUid = 0 then
    Ignore('root can write into read-only files');
  {$ENDIF}
  // a writable folder with a read-only ini (copied from a CD or an ISO)
  Dir := ScratchDir('loc-readonly-file');
  Portable := Dir + 'exe' + PathDelim + ConfigFileName;
  UserIni := Dir + 'user' + PathDelim + ConfigFileName;
  Before := Lines(['[gui]', 'language=es']);
  WriteTextFile(Portable, Before);
  try
    {$IFDEF UNIX}
    AssertEquals(0, fpChmod(Portable, &444));
    {$ELSE}
    AssertEquals(0, FileSetAttr(Portable, faReadOnly));
    {$ENDIF}
    C := LoadFrom(Dir);
    AssertFalse(C.Portable);
    AssertTrue(C.ReadOnlyPortable);
    AssertEquals(Portable, C.DefaultsFile);
    AssertEquals(UserIni, C.FileName);
    AssertEquals('es', C.Language);
    C.Maximized := True;
    AssertTrue('saved to the user folder', SaveConfig(C));
    AssertEquals('portable file untouched', Before, ReadTextFile(Portable));
    AssertTrue(Pos('maximized=1', ReadTextFile(UserIni)) > 0);
  finally
    {$IFDEF UNIX}
    fpChmod(Portable, &644);
    {$ELSE}
    FileSetAttr(Portable, 0);
    {$ENDIF}
  end;
end;

procedure TTestConfigLoad.ValidValues;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('valid');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[gui]', 'language=es_PE', 'theme=white', 'font=Consolas', 'window=-1200,5,1024,700',
    'maximized=yes', 'columns_zpaq=name:300,-ver:40,size:90', 'sort=modified,desc',
    'last_open_dir=D:\Backups',
    '[create]', 'format=zip', 'zpaq_method=zstd', 'zpaq_level=19', 'zpaq_threads=2',
    'zpaq_multipart=true', 'zip_level=9', 'last_dir=/home/me/in',
    '[extract]', 'overwrite=rename', 'subfolder=always', 'open_folder=on',
    '[progress]', 'close_when_done=0', 'confirm_cancel=off', 'details_open=1',
    '[paths]', 'zpaq=C:\tools\zpaq-std.exe', 'sevenzip=/usr/bin/7zz',
    '[advanced]', 'log=1', 'collect_quiet_ms=5000']));
  C := LoadFrom(Dir);
  AssertEquals(0, Length(C.Warnings));
  AssertEquals('es-pe', C.Language);
  AssertTrue(C.Theme = thLight);
  AssertEquals('Consolas', C.Font);
  AssertEquals('-1200,5,1024,700', FormatWindowGeometry(C.Window));
  AssertTrue(C.Maximized);
  AssertEquals('name:300,-ver:40,size:90', C.ColumnsZpaq);
  AssertEquals(DefaultColumns7z, C.Columns7z);
  AssertEquals('modified', C.Sort.Column);
  AssertTrue(C.Sort.Descending);
  AssertEquals('D:\Backups', C.LastOpenDir);
  AssertTrue(C.CreateFormat = cfZip);
  AssertEquals('zstd', C.ZpaqMethod);
  AssertEquals(19, C.ZpaqLevel);
  AssertEquals(2, C.ZpaqThreads);
  AssertTrue(C.ZpaqMultipart);
  AssertEquals(9, C.ZipLevel);
  AssertEquals('/home/me/in', C.CreateLastDir);
  AssertTrue(C.Overwrite = owRename);
  AssertTrue(C.Subfolder = sfAlways);
  AssertTrue(C.OpenFolder);
  AssertFalse(C.CloseWhenDone);
  AssertFalse(C.ConfirmCancel);
  AssertTrue(C.DetailsOpen);
  AssertEquals('C:\tools\zpaq-std.exe', C.ZpaqPath);
  AssertEquals('/usr/bin/7zz', C.SevenZipPath);
  AssertTrue(C.Log);
  AssertEquals(5000, C.CollectQuietMs);
end;

procedure TTestConfigLoad.InvalidValuesKeepDefaults;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('invalid');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[gui]', 'language=Español!', 'theme=purple', 'window=1,2,3', 'maximized=maybe',
    'columns_zpaq=name:320,bogus:10', 'columns_7z=name:300,name:20', 'sort=size,up',
    '[create]', 'format=rar', 'zpaq_method=-m5', 'zpaq_level=100', 'zpaq_threads=-1',
    'zip_level=4',
    '[extract]', 'overwrite=always', 'subfolder=sometimes',
    '[advanced]', 'collect_quiet_ms=100']));
  C := LoadFrom(Dir);
  AssertEquals('one warning per invalid key', 15, Length(C.Warnings));
  AssertEquals('[gui] theme=purple', C.Warnings[1]);
  AssertEquals('auto', C.Language);
  AssertTrue('language key exists even if invalid', C.LanguageKeyFound);
  AssertTrue(C.Theme = thAuto);
  AssertEquals('100,80,900,560', FormatWindowGeometry(C.Window));
  AssertFalse(C.Maximized);
  AssertEquals(DefaultColumnsZpaq, C.ColumnsZpaq);
  AssertEquals(DefaultColumns7z, C.Columns7z);
  AssertEquals('name', C.Sort.Column);
  AssertTrue(C.CreateFormat = cfZpaq);
  AssertEquals('1', C.ZpaqMethod);
  AssertEquals(0, C.ZpaqLevel);
  AssertEquals(0, C.ZpaqThreads);
  AssertEquals(5, C.ZipLevel);
  AssertTrue(C.Overwrite = owAsk);
  AssertTrue(C.Subfolder = sfSmart);
  AssertEquals(700, C.CollectQuietMs);
  // an invalid value is not rewritten by a save of another key
  C.Log := True;
  AssertTrue(SaveConfig(C));
  AssertTrue(Pos('theme=purple', ReadTextFile(C.FileName)) > 0);
end;

procedure TTestConfigLoad.BomCrlfCommentsAndCase;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('bom');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName,
    #$EF#$BB#$BF'; settings'#13#10'[GUI]'#13#10'  Language = es   ; auto | en | es'#13#10 +
    '# another comment'#13#10'Theme=Dark'#9'; dark: M8'#13#10 +
    'font=Segoe UI ; a comment after a font name'#13#10 + 'last_open_dir=D:\x ;y #z'#13#10 +
    '[Extract]'#13#10'overwrite = SKIP'#13#10'[paths]'#13#10'zpaq = D:\a ;b\zpaq-std.exe'#13#10);
  C := LoadFrom(Dir);
  AssertEquals(0, Length(C.Warnings));
  AssertEquals('es', C.Language);
  AssertTrue(C.Theme = thDark);
  AssertEquals('Segoe UI', C.Font);
  AssertEquals('a path keeps " ;" and " #"', 'D:\x ;y #z', C.LastOpenDir);
  AssertTrue(C.Overwrite = owSkip);
  AssertEquals('D:\a ;b\zpaq-std.exe', C.ZpaqPath);
end;

{ the [gui], [recent], [paths] and [advanced] lines of DESIGN.md §11.2, comments included; the
  portable zip ships its ini in this style }
procedure TTestConfigLoad.DesignSampleWithComments;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('design-sample');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[gui]',
    'language=auto            ; auto | en | es | <code of a lang/*.zsl file>',
    'theme=auto               ; auto | light | dark   (dark: M8, Windows 10 1809+; "white" = light)',
    'font=                    ; empty = system UI font; e.g. Consolas for the psycg look',
    'window=100,80,900,560    ; left,top,width,height at 96 PPI (clamped to a visible monitor)',
    'maximized=0',
    'columns_zpaq=name:320,size:100,modified:140,ver:50          ; "-" before an id = hidden',
    'columns_7z=name:300,size:100,packed:100,ratio:60,modified:140,method:120',
    'sort=name,asc            ; column id, asc|desc',
    'last_open_dir=',
    '[recent]',
    '1=                       ; 1..10, most recent first; missing files are dropped when shown',
    '[create]',
    'format=zpaq              ; zpaq | zip',
    'zpaq_method=1            ; 0..5 or a codec name (zstd, kanzi, lz6, ...)',
    'zpaq_level=0             ; 0 = codec default; clamped to the codec range',
    'zpaq_threads=0           ; 0 = automatic (x86: at most 2)',
    'zip_level=5              ; 0,1,3,5,7,9',
    'last_dir=',
    '[extract]',
    'overwrite=ask            ; ask | overwrite | skip | rename',
    'subfolder=smart          ; smart | always | never',
    '[extract.history]',
    '1=                       ; 1..10 destinations',
    '[paths]',
    'zpaq=                    ; empty = <exe dir>\bin\zpaq-std.exe',
    'sevenzip=                ; empty = <exe dir>\bin\7z.exe',
    '[advanced]',
    'log=0                    ; 1 = %LOCALAPPDATA%\ZPAQ-std\logs\, 5 x 1 MB, masked',
    'collect_quiet_ms=700     ; 200..5000']));
  C := LoadFrom(Dir);
  AssertEquals('no warnings', 0, Length(C.Warnings));
  AssertEquals('a comment-only value is empty', '', C.Font);
  AssertEquals('', C.ZpaqPath);
  AssertEquals('', C.SevenZipPath);
  AssertEquals('', C.LastOpenDir);
  AssertEquals('a comment-only item is no item', 0, Length(C.Recent));
  AssertEquals(0, Length(C.ExtractHistory));
  AssertEquals('auto', C.Language);
  AssertTrue(C.Theme = thAuto);
  AssertEquals('100,80,900,560', FormatWindowGeometry(C.Window));
  AssertEquals(DefaultColumnsZpaq, C.ColumnsZpaq);
  AssertEquals('name', C.Sort.Column);
  AssertEquals(5, C.ZipLevel);
  AssertEquals(700, C.CollectQuietMs);
end;

procedure TTestConfigLoad.ThemeNames;
var
  T: TThemeChoice;
begin
  AssertTrue(ParseTheme('auto', T));
  AssertTrue(T = thAuto);
  AssertTrue(ParseTheme('LIGHT', T));
  AssertTrue(T = thLight);
  AssertTrue('white means light', ParseTheme(' white ', T));
  AssertTrue(T = thLight);
  AssertTrue(ParseTheme('Dark', T));
  AssertTrue(T = thDark);
  AssertFalse(ParseTheme('purple', T));
  AssertFalse(ParseTheme('', T));
  AssertFalse('an alias is not a name of its own', ParseTheme('white=light', T));
end;

procedure TTestConfigLoad.LastDuplicateWins;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('dups');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[gui]', 'language=en', 'language=es', '[extract]', 'overwrite=skip', '[gui]', 'theme=dark',
    'language=fr']));
  C := LoadFrom(Dir);
  AssertEquals('fr', C.Language);
  AssertTrue(C.Theme = thDark);
  C.Language := 'de';
  AssertTrue(SaveConfig(C));
  C := LoadFrom(Dir);
  AssertEquals('the line that wins was updated', 'de', C.Language);
end;

procedure TTestConfigLoad.Lists;
var
  Dir: string;
  C: TConfig;
  I: Integer;
  Text: string;
begin
  Dir := ScratchDir('lists');
  Text := '[recent]' + LineEnding + '3=C:\c.zpaq' + LineEnding + '1=C:\a.zpaq' + LineEnding +
    'x=not a number' + LineEnding + '2=' + LineEnding + '10=C:\j.zpaq' + LineEnding +
    '02=C:\b.zpaq' + LineEnding + '[extract.history]' + LineEnding;
  for I := 1 to 12 do
    Text := Text + IntToStr(I) + '=D:\out' + IntToStr(I) + LineEnding;
  Text := Text + '[recent]' + LineEnding + '20=D:\Music\Vol #2 ;live\x.zpaq' + LineEnding;
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Text);
  C := LoadFrom(Dir);
  AssertEquals(5, Length(C.Recent));
  AssertEquals('an item is a path: " #" and " ;" are part of it', 'D:\Music\Vol #2 ;live\x.zpaq',
    C.Recent[4]);
  AssertEquals('C:\a.zpaq', C.Recent[0]);
  AssertEquals('02 is 2 and wins over the empty 2', 'C:\b.zpaq', C.Recent[1]);
  AssertEquals('C:\c.zpaq', C.Recent[2]);
  AssertEquals('C:\j.zpaq', C.Recent[3]);
  AssertEquals('at most 10', MaxExtractHistory, Length(C.ExtractHistory));
  AssertEquals('D:\out1', C.ExtractHistory[0]);
  AssertEquals('D:\out10', C.ExtractHistory[9]);
end;

procedure TTestConfigLoad.ColumnsAndWindow;
var
  Cols: TColumnSpecArray;
  G: TWindowGeometry;
begin
  AssertTrue(ParseColumns(' name : 320 , -size:100,ver:0', Cols));
  AssertEquals(3, Length(Cols));
  AssertEquals('size', Cols[1].Id);
  AssertFalse(Cols[1].Visible);
  AssertEquals(100, Cols[1].Width);
  AssertEquals('name:320,-size:100,ver:0', FormatColumns(Cols));
  AssertFalse(ParseColumns('', Cols));
  AssertFalse(ParseColumns('name', Cols));
  AssertFalse(ParseColumns('name:x', Cols));
  AssertFalse(ParseColumns('name:5001', Cols));
  AssertFalse(ParseColumns('name:1,,size:2', Cols));
  AssertTrue(IsColumnId('folder'));
  AssertFalse(IsColumnId('Name'));
  AssertTrue(ParseWindowGeometry('100, 80, 900, 560', G));
  AssertEquals(900, G.Width);
  AssertFalse(ParseWindowGeometry('100,80,99,560', G));
  AssertFalse(ParseWindowGeometry('100,80,900,560,1', G));
  AssertFalse(ParseWindowGeometry('a,80,900,560', G));
  AssertFalse(ParseWindowGeometry('40000,80,900,560', G));
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestConfigSave.NothingChangedWritesNothing;
var
  Dir: string;
  C: TConfig;
begin
  Dir := ScratchDir('nochange');
  C := LoadFrom(Dir);
  AssertTrue(SaveConfig(C));
  AssertFalse('no file for unchanged defaults', FileExists(C.FileName));
  AssertFalse('the user folder is not even created', DirectoryExists(Dir + 'user'));
end;

procedure TTestConfigSave.RoundTrip;
var
  Dir: string;
  C, D: TConfig;
  Cols: TColumnSpecArray;
begin
  Dir := ScratchDir('roundtrip');
  C := LoadFrom(Dir);
  C.Language := 'es';
  C.Theme := thDark;
  C.Font := 'Consolas';
  C.Window.Left := -5;
  C.Window.Width := 1200;
  C.Maximized := True;
  ParseColumns('name:400,-size:80', Cols);
  C.ColumnsZpaq := FormatColumns(Cols);
  C.Sort.Column := 'size';
  C.Sort.Descending := True;
  C.LastOpenDir := 'C:\Users\me\ñandú 日本';
  C.CreateFormat := cfZip;
  C.ZpaqMethod := 'kanzi';
  C.ZpaqLevel := 9;
  C.ZpaqThreads := 4;
  C.ZpaqMultipart := True;
  C.ZipLevel := 1;
  C.CreateLastDir := '/srv/x';
  C.Overwrite := owOverwrite;
  C.Subfolder := sfNever;
  C.OpenFolder := True;
  C.CloseWhenDone := False;
  C.ConfirmCancel := False;
  C.DetailsOpen := True;
  C.ZpaqPath := 'z.exe';
  C.SevenZipPath := '7z.exe';
  C.Log := True;
  C.CollectQuietMs := 200;
  AddRecent(C, 'D:\one.zpaq');
  AddExtractHistory(C, 'D:\out');
  AssertTrue(SaveConfig(C));
  AssertTrue(FileExists(C.FileName));
  D := LoadFrom(Dir);
  AssertEquals(0, Length(D.Warnings));
  AssertEquals('es', D.Language);
  AssertTrue(D.Theme = thDark);
  AssertEquals('Consolas', D.Font);
  AssertEquals('-5,80,1200,560', FormatWindowGeometry(D.Window));
  AssertTrue(D.Maximized);
  AssertEquals('name:400,-size:80', D.ColumnsZpaq);
  AssertEquals('size', D.Sort.Column);
  AssertTrue(D.Sort.Descending);
  AssertEquals('C:\Users\me\ñandú 日本', D.LastOpenDir);
  AssertTrue(D.CreateFormat = cfZip);
  AssertEquals('kanzi', D.ZpaqMethod);
  AssertEquals(9, D.ZpaqLevel);
  AssertEquals(4, D.ZpaqThreads);
  AssertTrue(D.ZpaqMultipart);
  AssertEquals(1, D.ZipLevel);
  AssertEquals('/srv/x', D.CreateLastDir);
  AssertTrue(D.Overwrite = owOverwrite);
  AssertTrue(D.Subfolder = sfNever);
  AssertTrue(D.OpenFolder);
  AssertFalse(D.CloseWhenDone);
  AssertFalse(D.ConfirmCancel);
  AssertTrue(D.DetailsOpen);
  AssertEquals('z.exe', D.ZpaqPath);
  AssertEquals('7z.exe', D.SevenZipPath);
  AssertTrue(D.Log);
  AssertEquals(200, D.CollectQuietMs);
  AssertEquals(1, Length(D.Recent));
  AssertEquals('D:\one.zpaq', D.Recent[0]);
  AssertEquals('D:\out', D.ExtractHistory[0]);
  // the file is UTF-8 without BOM, with the native line ending
  AssertTrue(Copy(ReadTextFile(C.FileName), 1, 1) = '[');
  AssertTrue(Pos('[gui]' + LineEnding + 'language=es' + LineEnding, ReadTextFile(C.FileName)) > 0);
end;

procedure TTestConfigSave.UnknownLinesKept;
var
  Dir, Text: string;
  C: TConfig;
begin
  Dir := ScratchDir('unknown');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '; hand-written header', '[gui]', '  Language = en   ; auto | en | es', 'mystery=42',
    'theme=auto', '', '[custom]', 'foo = bar', '; trailing comment', '', '[extract]',
    'overwrite=ask', '']));
  C := LoadFrom(Dir);
  C.Language := 'es';
  C.Overwrite := owSkip;
  C.Maximized := True;
  C.ZipLevel := 7;
  AssertTrue(SaveConfig(C));
  Text := ReadTextFile(C.FileName);
  AssertEquals(Lines([
    '; hand-written header', '[gui]', '  Language = es   ; auto | en | es', 'mystery=42',
    'theme=auto', 'maximized=1', '', '[custom]', 'foo = bar', '; trailing comment', '',
    '[extract]', 'overwrite=skip', '', '[create]', 'zip_level=7']), Text);
end;

procedure TTestConfigSave.CommentsOfEmptyValuesKept;
var
  Dir, Text: string;
  C: TConfig;
begin
  Dir := ScratchDir('emptycomments');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[gui]', 'theme=   ; auto | light | dark', 'font=   ; empty = system font',
    'last_open_dir = ; a folder', '[recent]', '1=   ; most recent first', '[paths]',
    'zpaq=   ; empty = bin\zpaq-std.exe']));
  C := LoadFrom(Dir);
  AssertEquals('an empty theme is invalid', 1, Length(C.Warnings));
  AssertEquals('[gui] theme=', C.Warnings[0]);
  C.Theme := thDark;
  C.Font := 'Consolas';
  C.LastOpenDir := 'D:\in';
  AddRecent(C, 'D:\a.zpaq');
  C.Log := True;   // [paths] zpaq stays empty: its line is not touched
  AssertTrue(SaveConfig(C));
  Text := ReadTextFile(C.FileName);
  AssertEquals(Lines([
    '[gui]', 'theme=dark   ; auto | light | dark', 'font=Consolas   ; empty = system font',
    '; a folder', 'last_open_dir = D:\in', '[recent]', '; most recent first', '1=D:\a.zpaq',
    '[paths]', 'zpaq=   ; empty = bin\zpaq-std.exe', '', '[advanced]', 'log=1']), Text);
  C := LoadFrom(Dir);
  AssertEquals(0, Length(C.Warnings));
  AssertTrue(C.Theme = thDark);
  AssertEquals('Consolas', C.Font);
  AssertEquals('D:\in', C.LastOpenDir);
  AssertEquals(1, Length(C.Recent));
  AssertEquals('', C.ZpaqPath);
  // emptied again: the comment stays; a path's comment stays on its own line
  C.Font := '';
  C.LastOpenDir := '';
  AssertTrue(SaveConfig(C));
  Text := ReadTextFile(C.FileName);
  AssertTrue(Pos(LineEnding + 'font=   ; empty = system font' + LineEnding, Text) > 0);
  AssertTrue(Pos(LineEnding + '; a folder' + LineEnding + 'last_open_dir = ' + LineEnding, Text) > 0);
  C := LoadFrom(Dir);
  AssertEquals(0, Length(C.Warnings));
  AssertEquals('', C.Font);
  AssertEquals('', C.LastOpenDir);
end;

procedure TTestConfigSave.TwoWriters;
var
  Dir: string;
  A, B, C: TConfig;
begin
  Dir := ScratchDir('twowriters');
  A := LoadFrom(Dir);
  B := LoadFrom(Dir);
  A.Language := 'es';
  A.Window.Width := 1000;
  AssertTrue(SaveConfig(A));
  B.Theme := thDark;
  B.Overwrite := owSkip;
  AssertTrue(SaveConfig(B));
  // A again: changes only what it changed since its own last save
  A.ZipLevel := 9;
  AssertTrue(SaveConfig(A));
  C := LoadFrom(Dir);
  AssertEquals('es', C.Language);
  AssertEquals(1000, C.Window.Width);
  AssertTrue('B kept by A', C.Theme = thDark);
  AssertTrue(C.Overwrite = owSkip);
  AssertEquals(9, C.ZipLevel);
end;

procedure TTestConfigSave.ListsRewritten;
var
  Dir, Text: string;
  C: TConfig;
begin
  Dir := ScratchDir('listsave');
  WriteTextFile(Dir + 'user' + PathDelim + ConfigFileName, Lines([
    '[recent]', '; most recent first', '1=C:\old1.zpaq', '2=C:\old2.zpaq', '[gui]', 'theme=dark',
    '[recent]', '7=C:\old3.zpaq']));
  C := LoadFrom(Dir);
  AssertEquals(3, Length(C.Recent));
  AddRecent(C, 'C:\new.zpaq');
  AddRecent(C, 'C:\old2.zpaq');
  AssertTrue(SaveConfig(C));
  Text := ReadTextFile(C.FileName);
  AssertEquals(Lines(['[recent]', '; most recent first', '1=C:\old2.zpaq', '2=C:\new.zpaq',
    '3=C:\old1.zpaq', '4=C:\old3.zpaq', '[gui]', 'theme=dark', '[recent]']), Text);
  // an emptied list keeps its section, so it also hides a portable default list
  C.Recent := nil;
  AssertTrue(SaveConfig(C));
  C := LoadFrom(Dir);
  AssertEquals(0, Length(C.Recent));
  AssertTrue(Pos('[recent]', ReadTextFile(C.FileName)) > 0);
end;

procedure TTestConfigSave.AtomicNoTmpLeft;
var
  Dir: string;
  C: TConfig;
  SR: TSearchRec;
  Count: Integer;
begin
  Dir := ScratchDir('atomic');
  C := LoadFrom(Dir);
  C.Language := 'es';
  AssertTrue(SaveConfig(C));
  C.Language := 'en';
  AssertTrue(SaveConfig(C));
  AssertFalse(FileExists(C.FileName + '.tmp'));
  Count := 0;
  if FindFirst(Dir + 'user' + PathDelim + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
        Inc(Count);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  AssertEquals('only the ini in the folder', 1, Count);
  AssertEquals(Lines(['[gui]', 'language=en']), ReadTextFile(C.FileName));
end;

procedure TTestConfigSave.FailureClearsWritable;
var
  Dir: string;
  C: TConfig;
begin
  ConfigDefaults(C);
  Dir := ScratchDir('failure');
  // a FILE where the settings folder should be: the folder cannot be created
  WriteTextFile(Dir + 'blocker', 'x');
  ForceDirectories(Dir + 'exe');
  InitConfig(C, Dir + 'exe', Dir + 'blocker' + PathDelim + 'sub');
  C.Language := 'es';
  AssertFalse(SaveConfig(C));
  AssertFalse(C.Writable);
  AssertTrue('a reason is given', C.SaveError <> '');
  AssertEquals('values in memory kept', 'es', C.Language);
  AssertFalse('later saves do nothing', SaveConfig(C));
end;

procedure TTestConfigSave.FailureReasonIsTheSystemsOwn;
{$IFDEF UNIX}
var
  Dir: string;
  C: TConfig;
begin
  if fpGetEUid = 0 then
    Ignore('root can write into read-only folders');
  Dir := ScratchDir('failreason');
  ForceDirectories(Dir + 'exe');
  ForceDirectories(Dir + 'user');
  AssertEquals(0, fpChmod(Dir + 'user', &555));
  try
    InitConfig(C, Dir + 'exe', Dir + 'user');
    C.Language := 'es';
    AssertFalse(SaveConfig(C));
    AssertTrue('a reason is given', C.SaveError <> '');
    // the system's message (localised on Windows), not the RTL's English text with the path
    AssertEquals('no path in the reason: ' + C.SaveError, 0, Pos('.tmp', C.SaveError));
  finally
    fpChmod(Dir + 'user', &755);
  end;
end;
{$ELSE}
begin
  Ignore('needs a read-only folder (checked on the VMs by hand)');
end;
{$ENDIF}

procedure TTestConfigSave.AddRecentRules;
var
  C: TConfig;
  I: Integer;
begin
  ConfigDefaults(C);
  for I := 1 to 12 do
    AddRecent(C, 'f' + IntToStr(I));
  AssertEquals(MaxRecent, Length(C.Recent));
  AssertEquals('f12', C.Recent[0]);
  AssertEquals('f3', C.Recent[9]);
  AddRecent(C, 'f5');
  AssertEquals(MaxRecent, Length(C.Recent));
  AssertEquals('f5', C.Recent[0]);
  AssertEquals('f12', C.Recent[1]);
  AddRecent(C, '');
  AssertEquals('f5', C.Recent[0]);
  {$IFDEF MSWINDOWS}
  AddRecent(C, 'F5');
  AssertEquals('same file on Windows', MaxRecent, Length(C.Recent));
  {$ENDIF}
end;

initialization
  RegisterTest('zsconfig', TTestConfigLoad);
  RegisterTest('zsconfig', TTestConfigSave);
end.
