{ zstests: console fpcunit runner for the units of src/core (RTL, FCL and LazUtils only, no LCL
  and no widgetset). Run "zstests --all --format=plain"; the exit code is 0 only when every test
  passes. Embeds lang/en.zsl as RCDATA LANG_EN, like the program, for the zslang tests. }
program zstests;

{$mode objfpc}{$H+}

uses
  LazUTF8, Classes, SysUtils, consoletestrunner,
  test_zsutil, test_zsconfig, test_zslang;

{$R *.res}

var
  App: TTestRunner;

begin
  DefaultRunAllTests := True;
  DefaultFormat := fPlain;
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'zstests';
    App.Run;
  finally
    App.Free;
  end;
end.
