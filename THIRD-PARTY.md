# Third-party components

ZPAQ-std itself is MIT licensed (see [LICENSE](LICENSE)). It uses, ships or credits the components
below, each under its own licence. The portable package and the installer carry the licence texts in
their `licenses` folder.

## Programs shipped next to the GUI

ZPAQ-std starts these as separate programs. It does not link them.

### zpaq-std (`bin/zpaq-std.exe`)

- Project: <https://github.com/YadeWira/zpaq-std>
- Licence: **MIT**. Portions copyright (c) 2022-2025 Franco Corbelli (zpaqfranz, which derives from
  zpaq 7.15 by Matt Mahoney). Modifications copyright (c) 2026 YadeWira (Yade Bravo).
- Its release binaries contain compressors and libraries under their own licences: zstd, brotli, LZMA
  SDK, fast-lzma2, ultra-fast-lzma2, lzlib, bzip2, libdeflate, Lizard, LZ5, lz6, Snappy, LZFSE,
  heatshrink, bzip3 (LGPL-3.0-or-later), libbsc (Apache-2.0), LZHAM, PPMd, kanzi (Apache-2.0) and
  libdivsufsort, plus the parts that zpaq-std inherits from zpaqfranz. They are listed, with every licence
  text, in the `THIRD-PARTY-LICENSES.txt` file that zpaq-std publishes with each release. That file and
  zpaq-std's `LICENSE` are shipped unchanged in `licenses/`.

### 7-Zip-zstd (`bin/7z.exe`, `bin/7z.dll`)

- Project: <https://github.com/mcmilk/7-Zip-zstd>, by Tino Reichardt, based on 7-Zip by Igor Pavlov.
- Licence: **GNU LGPL 2.1 or later**. Some code is under the BSD 3-clause and BSD 2-clause licences.
- **unRAR restriction**: the RAR decoder in `7z.dll` was developed from the unRAR source code, whose
  copyright belongs to Alexander Roshal. That code may not be used to re-create the RAR compression
  algorithm, which is proprietary, or to develop a RAR (WinRAR) compatible archiver. ZPAQ-std only
  extracts RAR archives and never creates them.
- Its `License.txt` is shipped unchanged in `licenses/`.

## Artwork

### Icons

- The application icon and the toolbar, list and dialog icons are PeaZip artwork by **Giorgio Tani**,
  licensed under the **GNU LGPL v3**. YadeWira recoloured them to coral. Source:
  <https://github.com/peazip/PeaZip>.
- ZPAQ-std is not affiliated with PeaZip.
- The credits and the licence are in `icons/LICENSE-icons.txt`. `icons/MAPPING.md` lists every icon
  and its source.

## Libraries compiled into the executable

### Free Pascal RTL and FCL, Lazarus LCL and LazUtils

- Projects: <https://www.freepascal.org>, <https://www.lazarus-ide.org>
- Licence: **modified LGPL**, which is the GNU LGPL with an exception that allows static linking.

### VirtualTreeView for Lazarus (`laz.virtualtreeview_package`)

- The copy shipped with Lazarus 4.0, in `components/virtualtreeview`. The original VirtualTrees is by
  Mike Lischke.
- Licence: **Mozilla Public License 1.1** or **GNU LGPL 2.1 or later**, at your choice.
- It draws the file list (from milestone M1).

### metadarkstyle (planned for milestone M8, not included yet)

- By Andrey Zubarev and Alexander Koblov: <https://github.com/zamtmn/metadarkstyle>
- Licence: **GNU LGPL 2.1 or later**.
- It will provide the dark mode on Windows 10 1809 and later. It will be vendored in
  `third_party/metadarkstyle/` with its licence.
