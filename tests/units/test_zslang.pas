{ test_zslang: fpcunit tests of src/core/zslang: the .zsl parser (BOM, CRLF, comments, sections,
  escapes, duplicates), Tr/TrF/TrN, the fallback chain es-pe -> es -> embedded en -> ⟨key⟩,
  LangLoad choices, locale codes, ListLanguages and the embedded LANG_EN resource. }
unit test_zslang;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, LazUTF8, zslang;

type
  TTestZslParser = class(TTestCase)
  published
    procedure BomCrlfCommentsSections;
    procedure FirstEqualsAndTrim;
    procedure Escapes;
    procedure DuplicatesAndOddLines;
  end;

  TTestTr = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Placeholders;
    procedure Plurals;
    procedure PluralsStayInOneFile;
    procedure MissingKey;
    procedure CaseInsensitiveKeys;
  end;

  TTestLangLoad = class(TTestCase)
  private
    FDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure FallbackChain;
    procedure BaseOnlyWhenRegionMissing;
    procedure UnknownCodeFails;
    procedure EnglishNeverFails;
    procedure PathChoice;
    procedure RelativePathChoice;
    procedure MissingPathFails;
    procedure AutoPicksAnInstalledLanguage;
    procedure AutoReportsAnUnreadableFile;
    procedure FileNamesWithoutCase;
    procedure ListOfLanguages;
  end;

  TTestLangCodes = class(TTestCase)
  published
    procedure Locales;
    procedure Normalize;
    procedure SystemCode;
  end;

  TTestLangResource = class(TTestCase)
  published
    procedure EmbeddedEnglish;
    procedure ShippedFilesParse;
  end;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  test_zsutil;

const
  EnglishText =
    '[info]' + LineEnding + 'code = en' + LineEnding + 'name = English' + LineEnding +
    '[status]' + LineEnding + 'ready = Ready' + LineEnding +
    'files.one = {n} file' + LineEnding + 'files.other = {n} files' + LineEnding +
    'items.one = {n} item' + LineEnding + 'items.other = {n} items' + LineEnding +
    'only_en = Only in English' + LineEnding + 'in_base = English base' + LineEnding +
    'in_region = English region' + LineEnding +
    '[prog]' + LineEnding + 'done = Completed in {time}.' + LineEnding +
    'pair = {a} then {b}' + LineEnding;

  SpanishText =
    #$EF#$BB#$BF'; Spanish'#13#10'[info]'#13#10'code = es'#13#10'name = Español'#13#10 +
    'english_name = Spanish'#13#10'author = YadeWira'#13#10'[status]'#13#10'ready = Listo'#13#10 +
    'files.one = {n} archivo'#13#10'files.other = {n} archivos'#13#10 +
    'in_base = Base española'#13#10'in_region = Región base'#13#10 +
    '[prog]'#13#10'done = Completado en {time}.'#13#10'pair = {b} y antes {a}'#13#10;

  PeruText =
    '[info]' + LineEnding + 'code = es-pe' + LineEnding + 'name = Español (Perú)' + LineEnding +
    '[status]' + LineEnding + 'in_region = Región Perú' + LineEnding;

  JapaneseText =
    '[info]' + LineEnding + 'code = ja' + LineEnding + 'name = 日本語' + LineEnding +
    '[status]' + LineEnding + 'files.other = {n} 個のファイル' + LineEnding;

function Table(const Text: string): TLangTable;
begin
  Result := TLangTable.Create;
  Result.LoadFromText(Text);
end;

function Get(T: TLangTable; const Key: string): string;
begin
  if not T.TryGet(Key, Result) then
    Result := '<none>';
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestZslParser.BomCrlfCommentsSections;
var
  T: TLangTable;
begin
  T := Table(#$EF#$BB#$BF'[INFO]'#13#10'code = es'#13#10'; comment = no'#13#10 +
    '# hash = no'#13#10'   ; indented = no'#13#10#13#10'[FormMain]'#13#10'TbOpen = Abrir'#13#10 +
    'tbopen.hint = Abrir un archivo (Ctrl+O)'#10'[ status ]'#13'ready = Listo');
  try
    AssertEquals('es', Get(T, 'info.code'));
    AssertEquals('Abrir', Get(T, 'formmain.tbopen'));
    AssertEquals('Abrir un archivo (Ctrl+O)', Get(T, 'formmain.tbopen.hint'));
    AssertEquals('CR-only line ends work too', 'Listo', Get(T, 'status.ready'));
    AssertFalse(T.Has('info.comment'));
    AssertFalse(T.Has('info.hash'));
    AssertFalse(T.Has('info.indented'));
    AssertEquals(4, T.Count);
  finally
    T.Free;
  end;
end;

procedure TTestZslParser.FirstEqualsAndTrim;
var
  T: TLangTable;
begin
  T := Table('[a]' + LineEnding + '  key  =  x = y  ' + LineEnding + 'empty =' + LineEnding +
    'inner = ✓  Completed in {time}' + LineEnding + 'top = level' + LineEnding);
  try
    AssertEquals('x = y', Get(T, 'a.key'));
    AssertEquals('', Get(T, 'a.empty'));
    AssertEquals('✓  Completed in {time}', Get(T, 'a.inner'));
    AssertEquals('level', Get(T, 'a.top'));
  finally
    T.Free;
  end;
  T := Table('before = section' + LineEnding);
  try
    AssertEquals('no section: plain key', 'section', Get(T, 'before'));
  finally
    T.Free;
  end;
end;

procedure TTestZslParser.Escapes;
var
  T: TLangTable;
begin
  T := Table('[e]' + LineEnding + 'nl = one\ntwo' + LineEnding + 'tab = a\tb' + LineEnding +
    'bs = C:\\out\\' + LineEnding + 'sp = \sspaced\s' + LineEnding + 'other = \q \' +
    LineEnding + 'path = C:\temp' + LineEnding);
  try
    AssertEquals('one' + LineEnding + 'two', Get(T, 'e.nl'));
    AssertEquals('a'#9'b', Get(T, 'e.tab'));
    AssertEquals('C:\out\', Get(T, 'e.bs'));
    AssertEquals(' spaced ', Get(T, 'e.sp'));
    AssertEquals('unknown escapes stay', '\q \', Get(T, 'e.other'));
    AssertEquals('\t is an escape', 'C:'#9'emp', Get(T, 'e.path'));
  finally
    T.Free;
  end;
end;

procedure TTestZslParser.DuplicatesAndOddLines;
var
  T: TLangTable;
begin
  T := Table('[d]' + LineEnding + 'k = first' + LineEnding + 'no equals here' + LineEnding +
    '= no key' + LineEnding + 'k = last' + LineEnding + '[d2' + LineEnding + 'x = 1' + LineEnding);
  try
    AssertEquals('last one wins', 'last', Get(T, 'd.k'));
    AssertEquals('"[d2" is not a header, so x stays in [d]', '1', Get(T, 'd.x'));
    AssertEquals(2, T.Count);
  finally
    T.Free;
  end;
  T := Table('');
  try
    AssertEquals(0, T.Count);
  finally
    T.Free;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestTr.SetUp;
begin
  LangSetEmbeddedEnglish(EnglishText);
  LangLoad('en', '');
end;

procedure TTestTr.TearDown;
begin
  LangUseResourceEnglish;
  LangLoad('en', '');
end;

procedure TTestTr.Placeholders;
begin
  AssertEquals('Completed in 0:01:05.', TrF('prog.done', ['time', '0:01:05']));
  AssertEquals('1 then 2', TrF('prog.pair', ['b', '2', 'a', '1']));
  AssertEquals('a value is never substituted again', '{b} then x',
    TrF('prog.pair', ['a', '{b}', 'b', 'x']));
  AssertEquals('unknown placeholders stay visible', 'Completed in {time}.', TrF('prog.done', []));
  AssertEquals('odd argument count', 'Completed in {time}.', TrF('prog.done', ['time']));
  AssertEquals('x {y} {} { z} {', FormatPlaceholders('{a} {y} {} { z} {', ['a', 'x']));
  AssertEquals('{{a}}', FormatPlaceholders('{{a}}', ['b', 'x']));
  AssertEquals('{x}', FormatPlaceholders('{{a}}', ['a', 'x']));
end;

procedure TTestTr.Plurals;
begin
  AssertEquals('0 files', TrN('status.files', 0));
  AssertEquals('1 file', TrN('status.files', 1));
  AssertEquals('2 files', TrN('status.files', 2));
  AssertEquals('1000000 files', TrN('status.files', 1000000));
  AssertEquals('a plain key used with TrN', 'Ready', TrN('status.ready', 3));
  AssertEquals('3 items: Completed', FormatPlaceholders('{n} items: {w}', ['n', '3', 'w',
    'Completed']));
  AssertEquals('1 item', TrNF('status.items', 1, ['x', 'y']));
end;

procedure TTestTr.PluralsStayInOneFile;
var
  Dir: string;
begin
  Dir := ScratchDir('plural');
  WriteTextFile(Dir + 'ja.zsl', JapaneseText);
  AssertTrue(LangLoad('ja', Dir));
  // ja has no files.one: it uses its own .other, not the English .one
  AssertEquals('1 個のファイル', TrN('status.files', 1));
  AssertEquals('ja lacks items: English', '1 item', TrN('status.items', 1));
end;

function CountOf(const L: TStringArray; const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(L) do
    if L[I] = S then
      Inc(Result);
end;

procedure TTestTr.MissingKey;
var
  V: string;
begin
  AssertEquals(MissingOpen + 'status.nowhere' + MissingClose, Tr('status.nowhere'));
  AssertEquals(MissingOpen + 'status.nowhere' + MissingClose, Tr('Status.Nowhere'));
  AssertEquals(MissingOpen + 'status.nothing.other' + MissingClose, TrN('status.nothing', 2));
  AssertEquals('recorded once', 1, CountOf(LangMissingKeys, 'status.nowhere'));
  AssertEquals(1, CountOf(LangMissingKeys, 'status.nothing.other'));
  AssertFalse(LangTryGet('status.ghost', V));
  AssertEquals('LangTryGet records nothing', 0, CountOf(LangMissingKeys, 'status.ghost'));
end;

procedure TTestTr.CaseInsensitiveKeys;
var
  V: string;
begin
  AssertEquals('Ready', Tr('STATUS.READY'));
  AssertTrue(LangTryGet('Status.Ready', V));
  AssertEquals('Ready', V);
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestLangLoad.SetUp;
begin
  LangSetEmbeddedEnglish(EnglishText);
  FDir := ScratchDir('langs');
  WriteTextFile(FDir + 'es.zsl', SpanishText);
  WriteTextFile(FDir + 'es-pe.zsl', PeruText);
  WriteTextFile(FDir + 'ja.zsl', JapaneseText);
  WriteTextFile(FDir + 'broken name!.zsl', '[info]' + LineEnding + 'name = Broken');
  WriteTextFile(FDir + 'readme.txt', 'not a language');
end;

procedure TTestLangLoad.TearDown;
begin
  LangUseResourceEnglish;
  LangLoad('en', '');
end;

procedure TTestLangLoad.FallbackChain;
begin
  AssertTrue(LangLoad('es-pe', FDir));
  AssertEquals('es-pe', LangCode);
  AssertEquals('Español (Perú)', LangName);
  AssertEquals('', LangFailed);
  AssertEquals('from es-pe', 'Región Perú', Tr('status.in_region'));
  AssertEquals('from es', 'Base española', Tr('status.in_base'));
  AssertEquals('from es', 'Listo', Tr('status.ready'));
  AssertEquals('from the embedded English', 'Only in English', Tr('status.only_en'));
  AssertEquals(MissingOpen + 'status.nowhere' + MissingClose, Tr('status.nowhere'));
  AssertEquals('Completado en 0:00:01.', TrF('prog.done', ['time', '0:00:01']));
  AssertEquals('translators reorder placeholders', '2 y antes 1', TrF('prog.pair', ['a', '1', 'b', '2']));
  AssertEquals('1 archivo', TrN('status.files', 1));
  AssertEquals('5 archivos', TrN('status.files', 5));
  AssertTrue(LangLoad('es_PE', FDir));
  AssertEquals('es-pe', LangCode);
end;

procedure TTestLangLoad.BaseOnlyWhenRegionMissing;
begin
  AssertTrue('es-mx falls back to es without an error', LangLoad('es-mx', FDir));
  AssertEquals('es', LangCode);
  AssertEquals('', LangFailed);
  AssertEquals('Región base', Tr('status.in_region'));
  AssertTrue(LangLoad('es', FDir));
  AssertEquals('es', LangCode);
  AssertEquals('Español', LangName);
end;

procedure TTestLangLoad.UnknownCodeFails;
begin
  AssertFalse(LangLoad('fr', FDir));
  AssertEquals('fr', LangFailed);
  AssertEquals('en', LangCode);
  AssertEquals('English', LangName);
  AssertEquals('Ready', Tr('status.ready'));
  AssertFalse(LangLoad('fr', ''));
  AssertFalse('an invalid code', LangLoad('../es', FDir + 'nowhere'));
  AssertTrue('a later success clears it', LangLoad('es', FDir));
  AssertEquals('', LangFailed);
end;

procedure TTestLangLoad.EnglishNeverFails;
begin
  AssertTrue(LangLoad('en', FDir));
  AssertTrue(LangLoad('en-gb', FDir));
  AssertEquals('en', LangCode);
  AssertEquals('Ready', Tr('status.ready'));
  AssertTrue(LangLoad('', FDir));
  AssertTrue(LangLoad('AUTO', FDir));
end;

procedure TTestLangLoad.PathChoice;
var
  Other: string;
begin
  Other := ScratchDir('langpath');
  WriteTextFile(Other + 'mine.zsl', PeruText);
  // a path: the file itself, then the base language of its [info] code from LangDir
  AssertTrue(LangLoad(Other + 'mine.zsl', FDir));
  AssertEquals('es-pe', LangCode);
  AssertEquals('Región Perú', Tr('status.in_region'));
  AssertEquals('Base española', Tr('status.in_base'));
  AssertEquals('Only in English', Tr('status.only_en'));
end;

procedure TTestLangLoad.RelativePathChoice;
var
  Other, Saved: string;
begin
  Other := ScratchDir('langrel');
  WriteTextFile(Other + 'sub' + PathDelim + 'mine.zsl', PeruText);
  Saved := GetCurrentDir;
  AssertTrue(SetCurrentDir(Other));
  try
    // relative to the current folder, not to LangDir
    AssertTrue(LangLoad('sub' + PathDelim + 'mine.zsl', FDir));
    AssertEquals('es-pe', LangCode);
    AssertTrue(LangLoad('mine.zsl', FDir) = False);
    AssertEquals('the failure names the full path', Other + 'mine.zsl', LangFailed);
  finally
    SetCurrentDir(Saved);
  end;
end;

procedure TTestLangLoad.MissingPathFails;
begin
  AssertFalse(LangLoad(FDir + 'nope.zsl', FDir));
  AssertEquals(FDir + 'nope.zsl', LangFailed);
  AssertEquals('Ready', Tr('status.ready'));
end;

procedure TTestLangLoad.AutoPicksAnInstalledLanguage;
var
  Code, Sys, Expected: string;
begin
  Code := LangAutoCode(FDir);
  Sys := SystemLanguageCode;
  if (Sys <> '') and FileExists(FDir + Sys + '.zsl') then
    Expected := Sys
  else if (Sys <> '') and FileExists(FDir + BaseLangCode(Sys) + '.zsl') then
    Expected := BaseLangCode(Sys)
  else
    Expected := 'en';
  AssertEquals('system language "' + Sys + '"', Expected, Code);
  AssertTrue('auto never fails', LangLoad('auto', FDir));
  AssertEquals(Code, LangCode);
  AssertEquals('en', LangAutoCode(''));
end;

procedure TTestLangLoad.AutoReportsAnUnreadableFile;
{$IFDEF UNIX}
var
  Dir, Sys, F: string;
begin
  if fpGetEUid = 0 then
    Ignore('root can read any file');
  Sys := SystemLanguageCode;
  if (Sys = '') or (BaseLangCode(Sys) = 'en') then
    Ignore('the system language is English or unknown ("' + Sys + '")');
  Dir := ScratchDir('langunreadable');
  F := Dir + BaseLangCode(Sys) + '.zsl';
  WriteTextFile(F, SpanishText);
  AssertEquals(0, fpChmod(F, &000));
  try
    AssertEquals('auto picks the file', BaseLangCode(Sys), LangAutoCode(Dir));
    AssertFalse('it cannot be read: a failure, not a silent English', LangLoad('auto', Dir));
    AssertEquals(BaseLangCode(Sys), LangFailed);
    AssertEquals('en', LangCode);
    AssertEquals('Ready', Tr('status.ready'));
    AssertTrue('no file for the system language is no failure', LangLoad('auto', FDir + 'none'));
    AssertEquals('', LangFailed);
  finally
    fpChmod(F, &644);
  end;
end;
{$ELSE}
begin
  Ignore('needs an unreadable file (Unix permissions)');
end;
{$ENDIF}

procedure TTestLangLoad.FileNamesWithoutCase;
var
  Dir: string;
begin
  Dir := ScratchDir('langcase');
  WriteTextFile(Dir + 'ES.zsl', SpanishText);
  AssertTrue(LangLoad('es', Dir));
  AssertEquals('Listo', Tr('status.ready'));
end;

procedure TTestLangLoad.ListOfLanguages;
var
  L: TLangInfoArray;
  I: Integer;
  Names: string;
begin
  L := ListLanguages(FDir);
  Names := '';
  for I := 0 to High(L) do
    Names := Names + L[I].Code + '=' + L[I].Name + ';';
  AssertEquals('sorted by name; the invalid file name is skipped',
    'en=English;es=Español;es-pe=Español (Perú);ja=日本語;', Names);
  AssertEquals('', L[0].FileName);
  AssertEquals(FDir + 'es.zsl', L[1].FileName);
  AssertEquals('Spanish', L[1].EnglishName);
  AssertEquals('YadeWira', L[1].Author);
  AssertEquals(1, Length(ListLanguages('')));
  AssertEquals(1, Length(ListLanguages(FDir + 'missing')));
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestLangCodes.Locales;
begin
  AssertEquals('es-pe', LocaleToLangCode('es_PE.UTF-8'));
  AssertEquals('es-pe', LocaleToLangCode('es_PE.UTF-8@euro'));
  AssertEquals('de-de', LocaleToLangCode('de_DE@euro'));
  AssertEquals('sr-rs', LocaleToLangCode('sr_RS@latin'));
  AssertEquals('pt-br', LocaleToLangCode('pt_BR'));
  AssertEquals('es', LocaleToLangCode('es'));
  AssertEquals('en', LocaleToLangCode('C'));
  AssertEquals('en', LocaleToLangCode('C.UTF-8'));
  AssertEquals('en', LocaleToLangCode('POSIX'));
  AssertEquals('', LocaleToLangCode(''));
  AssertEquals('', LocaleToLangCode('../../etc'));
end;

procedure TTestLangCodes.Normalize;
begin
  AssertEquals('es-pe', NormalizeLangCode(' ES_pe '));
  AssertEquals('es', BaseLangCode('es-PE'));
  AssertEquals('es', BaseLangCode('es'));
  AssertEquals('zh', BaseLangCode('zh_TW'));
end;

procedure TTestLangCodes.SystemCode;
var
  S: string;
  I: Integer;
begin
  S := SystemLanguageCode;
  for I := 1 to Length(S) do
    AssertTrue('"' + S + '" is a normalised code', S[I] in ['a'..'z', '0'..'9', '-']);
end;

{ ---------------------------------------------------------------------------------------------- }

procedure TTestLangResource.EmbeddedEnglish;
var
  Res, Shipped, Name: string;
  T: TLangTable;
begin
  Res := LangResourceEnglish;
  if Res = '' then
    Fail('the test program has no RCDATA resource LANG_EN (tests/zstests.lpi embeds lang/en.zsl)');
  T := Table(Res);
  try
    AssertEquals('en', Get(T, 'info.code'));
    AssertTrue('it has texts', T.Count > 3);
    Name := Get(T, 'info.name');
  finally
    T.Free;
  end;
  if (RepoRoot <> '') and FileExists(RepoRoot + 'lang' + PathDelim + 'en.zsl') then
  begin
    Shipped := ReadTextFile(RepoRoot + 'lang' + PathDelim + 'en.zsl');
    AssertTrue('the resource is lang/en.zsl', Res = Shipped);
  end;
  LangUseResourceEnglish;
  AssertTrue(LangLoad('en', ''));
  AssertEquals('English from the resource', Name, LangName);
end;

procedure TTestLangResource.ShippedFilesParse;
var
  Root: string;
  T: TLangTable;
  Code: string;
const
  Codes: array[0..1] of string = ('en', 'es');
var
  I: Integer;
begin
  Root := RepoRoot;
  if Root = '' then
    Ignore('not run from a checkout');
  for I := 0 to High(Codes) do
  begin
    if not FileExists(Root + 'lang' + PathDelim + Codes[I] + '.zsl') then
      Ignore('lang/' + Codes[I] + '.zsl is not there yet');
    T := TLangTable.Create;
    try
      AssertTrue(T.LoadFromFile(Root + 'lang' + PathDelim + Codes[I] + '.zsl'));
      AssertTrue(T.TryGet('info.code', Code));
      AssertEquals(Codes[I] + '.zsl declares its code', Codes[I], Code);
      AssertTrue(T.Has('info.name'));
    finally
      T.Free;
    end;
  end;
end;

initialization
  RegisterTest('zslang', TTestZslParser);
  RegisterTest('zslang', TTestTr);
  RegisterTest('zslang', TTestLangLoad);
  RegisterTest('zslang', TTestLangCodes);
  RegisterTest('zslang', TTestLangResource);
end.
