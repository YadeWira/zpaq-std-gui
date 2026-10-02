# ZPAQ-std

A graphical archive manager for [zpaq-std](https://github.com/YadeWira/zpaq-std). It browses, extracts,
tests and creates `.zpaq` archives (versions, multipart sets, AES-256 encryption) and creates `.zip`. With
[7-Zip-zstd](https://github.com/mcmilk/7-Zip-zstd) it also opens and extracts 7z, rar, zip, tar, gz, xz,
zst, iso, cab, wim and the other formats that 7-Zip reads. RAR is extract-only.

Windows 7 SP1 and later, x86 and x64, come first; Linux comes later. It is written in Free Pascal 3.2.2
with Lazarus 4.0 (LCL).

## Status

**Early development: milestone M0, version 0.0.1.** The program starts and shows its main window, in
English or Spanish, and remembers its size. Archive operations arrive in the next milestones.

This is a rewrite from scratch. It replaces the earlier PeaZip-based fork (the 0.1.0-pre releases).
Planned for version 1:

- extracting a selection relative to the current folder, as 7-Zip and WinRAR do;
- a portable zip and one installer for x86 and x64. The installer keeps the fork's AppId, so it
  replaces an installed 0.1.0-pre version.

## Building

Linux (GTK2) needs Free Pascal 3.2.2 and Lazarus 4.0 (`lazbuild`). The Windows builds are cross-compiled
from Linux. They need FPC 3.2.2 cross compilers for win32 and win64, a Lazarus 4.0 tree with the LCL built
for them, and the mingw-w64 `strip` tools.

```sh
tools/build.sh linux          # Release build, stripped: bin/x86_64-linux/zpaq-std-gui
tools/build.sh win64          #                          bin/x86_64-win64/zpaq-std-gui.exe
tools/build.sh win32          #                          bin/i386-win32/zpaq-std-gui.exe
tools/build.sh all            # the three targets, then the Linux unit tests
tools/build.sh win32 debug    # Debug build: checks, assertions, heaptrc (writes heap.trc)
```

Each output folder also gets the tests (`zstests`) and a copy of `lang/` (`en.zsl`, `es.zsl`). Only
English is compiled into the program, so copy the `lang` folder next to the exe together with it:
without it the program runs in English. `ZSGUI_WIN` sets the folder of the cross toolchain (`lazarus/`,
`ppc-win32`, `ppc-win64`), and `LAZBUILD` sets the Linux `lazbuild`; the build logs go to `lib/logs/`.
The project `src/zpaqstdgui.lpi` also opens in the Lazarus IDE, with the build modes `Debug` and
`Release`.

At run time the program looks for its backends in a `bin` folder next to the executable:
`bin\zpaq-std.exe`, plus `bin\7z.exe` and `bin\7z.dll` (7-Zip-zstd, same bitness).

## License

MIT, see [LICENSE](LICENSE). Third-party components and their licences are listed in
[THIRD-PARTY.md](THIRD-PARTY.md).
