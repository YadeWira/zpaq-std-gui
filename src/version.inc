{ version.inc: the program name, version and executable name, in one place.
  Included only by src/gui/zsui.pas; other units use zsui.AppName / AppVersion / AppExeName.
  tools/build.sh refuses to build when the .lpi version info differs from AppVersion. }

const
  AppName = 'ZPAQ-std';
  AppVersion = '0.0.1';
  AppExeName = 'zpaq-std-gui';
