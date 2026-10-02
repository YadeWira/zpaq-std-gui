{ zpaqstdgui: the entry point of ZPAQ-std. Removes FRANZKEY from our own environment, reads the
  command line, loads the settings, the language and the theme, then runs manager mode (the main
  window) and sets the exit code. M0: the task-mode commands only say they are not available yet. }
program zpaqstdgui;

{$mode objfpc}{$H+}
{$ifdef CPU386}{$ifdef WINDOWS}{$SETPEFLAGS $20}{$endif}{$endif}

uses
  {$ifdef WINDOWS}
  Windows,
  {$endif}
  Interfaces, Forms, Dialogs, SysUtils, LazUTF8, LazFileUtils,
  zsconfig, zslang, zsui, zsicons, fmain;

{$R *.res}

type
  { what the command line asks for }
  TStartup = record
    LangChoice: string;   // --lang: a code or a .zsl path; '' = [gui] language
    HasTheme: Boolean;    // --theme was given: Theme overrides [gui] theme
    Theme: TThemeChoice;
    Archive: string;      // manager mode: the archive to open (absolute)
    Command: string;      // task mode: add | extract | test
    Help, Version: Boolean;
    ErrorKey: string;     // a bad command line (exit 4): the message key,
    ErrorParam: string;   // the name of its placeholder ('option' for {option})
    ErrorArg: string;     // and the text that replaces it
  end;

const
  ExitFailed = 2;         // DESIGN.md §8.2
  ExitUsage = 4;

{ M0 stand-in for zscmdline (M5): global options, then either a command word or one archive.
  The command word counts only as the first argument that is not a global option; '--' ends the
  options, so 'zpaq-std-gui -- test' opens a file named test. }
procedure ParseCommandLine(out S: TStartup);
var
  I: Integer;
  A, V: string;
  OptionsDone: Boolean;

  procedure Fail(const Key, Param, Arg: string);
  begin
    if S.ErrorKey = '' then
    begin
      S.ErrorKey := Key;
      S.ErrorParam := Param;
      S.ErrorArg := Arg;
    end;
  end;

  function TakeValue(out Value: string): Boolean;
  begin
    Result := I < ParamCount;
    if Result then
    begin
      Inc(I);
      Value := ParamStrUTF8(I);
    end
    else
    begin
      Value := '';
      Fail('cmdline.missing_value', 'option', A);
    end;
  end;

begin
  S := Default(TStartup);
  OptionsDone := False;
  I := 1;
  while (I <= ParamCount) and (S.ErrorKey = '') do
  begin
    A := ParamStrUTF8(I);
    if not OptionsDone and (A = '--') then
      OptionsDone := True
    else if not OptionsDone and (Length(A) > 1) and (A[1] = '-') then
    begin
      if A = '--lang' then
      begin
        if TakeValue(V) then
          S.LangChoice := V;
      end
      else if A = '--theme' then
      begin
        if TakeValue(V) then
        begin
          S.HasTheme := ParseTheme(V, S.Theme);
          if not S.HasTheme then
            Fail('cmdline.bad_theme', 'value', V);
        end;
      end
      else if (A = '--help') or (A = '-h') then
        S.Help := True
      else if A = '--version' then
        S.Version := True
      else
        Fail('cmdline.unknown_option', 'option', A);
    end
    else if not OptionsDone and (S.Archive = '')
      and ((A = 'add') or (A = 'extract') or (A = 'test')) then
    begin
      S.Command := A;
      Break;   // the rest belongs to the command (M5)
    end
    else if S.Archive = '' then
      S.Archive := ExpandFileNameUTF8(A)
    else
      Fail('cmdline.too_many', 'value', A);
    Inc(I);
  end;
end;

function UsageText: string;
begin
  Result := TrF('cmdline.usage', ['exe', AppExeName]);
end;

var
  Startup: TStartup;

begin
  {$ifdef WINDOWS}
  // children inherit our environment; zpaq-std reads FRANZKEY as a password (DESIGN.md §9.4)
  SetEnvironmentVariableW('FRANZKEY', nil);
  {$endif}
  {$if declared(UseHeapTrace)}
  {$ifdef WINDOWS}
  SetHeapTraceOutput(ExtractFilePath(ParamStr(0)) + 'heap.trc');   // a GUI exe has no console
  {$endif}
  {$endif}

  ParseCommandLine(Startup);
  InitConfig(Cfg);
  if Startup.LangChoice <> '' then
    LangLoad(Startup.LangChoice, GuiLangDir)
  else
    LangLoad(Cfg.Language, GuiLangDir);
  TranslateKeyNames;

  RequireDerivedFormResource := True;
  Application.Title := AppName;
  Application.Scaled := True;
  {$ifdef WINDOWS}
  {$push}{$warn 5044 off}   // "not portable": it is Windows-only on purpose
  Application.MainFormOnTaskBar := True;   // the taskbar button belongs to the main window
  {$pop}
  {$endif}
  Application.HintShortCuts := False;   // our hints already name the shortcut, translated
  Application.Initialize;
  if Startup.HasTheme then
    InitTheme(Startup.Theme)
  else
    InitTheme(Cfg.Theme);

  if Startup.ErrorKey <> '' then
  begin
    ShowMessageBox(TrF(Startup.ErrorKey, [Startup.ErrorParam, Startup.ErrorArg])
      + LineEnding + LineEnding + UsageText, mtError);
    ExitCode := ExitUsage;
  end
  else if Startup.Help then
    ShowMessageBox(UsageText, mtInformation)
  else if Startup.Version then
    ShowMessageBox(AppTitle, mtInformation)
  else if Startup.Command <> '' then
  begin
    // M5: zstask runs the command in the progress window (DESIGN.md §3, §8)
    ShowMessageBox(TrF('cmdline.task_not_available', ['command', Startup.Command]), mtInformation);
    ExitCode := ExitFailed;
  end
  else
  begin
    InitIcons(Pal.Dark);
    Application.CreateForm(TFormMain, FormMain);
    FormMain.StartupArchive := Startup.Archive;
    Application.Run;
  end;
end.
