# Changelog

All notable changes to ZPAQ-std are listed here. Versions follow `MAJOR.MINOR.PATCH`, and pre-releases
are `X.Y.Z-pre.N`.

## 0.0.1 (in development)

A rewrite from scratch in Free Pascal and Lazarus. Nothing is shared with the earlier PeaZip-based fork
(0.1.0-pre1 to 0.1.0-pre7).

### Milestone M0: skeleton

- Repository layout, Lazarus project `src/zpaqstdgui.lpi` with the build modes Debug and Release.
- `tools/build.sh linux|win64|win32|all [debug]` builds Linux GTK2 and cross-builds Windows x64 and
  x86 (Release unless `debug` is given) into `bin/<cpu>-<os>/`, with a copy of `lang/` next to the exe.
- Windows executable: version info "ZPAQ-std", coral application icon, manifest with common controls 6,
  system DPI awareness and Windows 7 to 10 compatibility.
- Settings file, language files `lang/en.zsl` and `lang/es.zsl` (window texts), icon pipeline.
- Main window with toolbar, path bar, status bar and welcome panel; About box. The window size,
  position and maximised state are remembered; a window that no longer fits a monitor is moved and
  shrunk onto one.
