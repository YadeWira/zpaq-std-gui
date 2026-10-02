# Icons: sources, names, sizes and how the program loads them

ZPAQ-std uses PeaZip's theme art, recoloured to coral (see `LICENSE-icons.txt`). This folder holds the
chosen source images, the files generated from them by `tools/make-icons.py`, and this map. The
generated files are committed, so building the program needs no Python.

```
icons/
  src/                    source art, copied unchanged from the extraction (one file per sheet index)
    il_dtheme_16/NN.png        48 px   PeaZip "dtheme" small list (list, menus, small toolbar glyphs)
    il_dtheme_16_dark/NN.png   48 px   the same indexes for dark backgrounds (only those that differ)
    il_dtheme_tool32/NN.png    96 px   PeaZip toolbar list
    il_dtheme_96/NN.png        96 px   PeaZip big list (type boxes, extract arrow)
    ImageListDlg/NN.png        96 px   PeaZip dialog glyphs (info, warning, error)
    app_fit.ico  app16_fit.ico  coral256.png      the coral application box
  gen/                    generated, committed
    16/ 24/ 32/ 36/ 48/ 72/ 96/   <name>.png (lower-case name), every name
    128/ 160/ 192/ 256/           app.png only (welcome panel)
    16-dark/ ... 96-dark/         only the names whose dark art differs
    zsicons.res                   every PNG above as an RCDATA resource: what the program links
    app.ico                       application icon, 16 20 24 32 40 48 64 96 256
    .gitignore                    re-includes zsicons.res (the top-level .gitignore ignores *.res)
  assoc/                  generated: zpaq.ico 7z.ico zip.ico rar.ico archive.ico (file types)
  MAPPING.md              this file (the tables between the markers are generated)
  LICENSE-icons.txt       credits and licence of the art
```

## Where the art comes from

- `il_dtheme_16`, `il_dtheme_16_dark`, `il_dtheme_tool32`, `il_dtheme_96` and `ImageListDlg` are
  `TImageList`s of PeaZip 11.3.0's `peach.lfm`, exported as one PNG per index to
  `/mnt/IA_LAB/agentes/zs-gui/new/icons-extract/` (the `*_sheet.png` contact sheets there show the
  indexes). In the four `il_dtheme*` lists the blue pixels were recoloured to coral by the old fork
  (hue 185-245 degrees with saturation above 0.25 moved to the coral hue). Yellow folders, tan boxes and
  `ImageListDlg` keep PeaZip's colours, so the blue "i" stays distinct from the red error.
- The application box (`app_fit.ico` with hand-fitted 16/24/32/48/256 frames, `app16_fit.ico`,
  `coral256.png`) is PeaZip's tan archive-box icon, recoloured to coral (#FF574B), trimmed and centred.
  `coral256.png` has wider margins than the `_fit` art. It is used for `TYPE_ZPAQ`, as DESIGN.md §14.2
  says.

## Sizes per DPI

| Role | 100 % (96 PPI) | 150 % | 200 % | Typical names |
|---|---|---|---|---|
| list, menus, path bar, warning and result strips | 16 | 24 | 32 | `FT_*`, `OV_LOCK`, `MI_*`, `DLG_*` |
| toolbar | 24 | 36 | 48 | `TB_*` |
| dialogs, progress header, Properties header | 48 | 72 | 96 | `DLG_*`, `OP_*`, `TYPE_*` |
| welcome panel | 128 | 192 | 256 | `APP` (160 for 125 %) |

Every name exists at all seven sizes (16 24 32 36 48 72 96), so any image list can hold any name with
no runtime scaling. A scaled `TImageList` with no exact resolution for the screen uses the LCL's rule
(`TCustomImageList.GetWidthForPPI`): up to 120 PPI (125 %) the 100 % images, up to 168 PPI (175 %) the
150 % images, above that 200 %, 300 %... So 20/30/60 px are not needed; adding a size is one entry in
`SIZES` in `tools/make-icons.py`. The PNGs are Lanczos-scaled from the sources with premultiplied alpha.
Sources of 48 px (`il_dtheme_16`) are upscaled at 72 and 96 px and look slightly soft there (of those,
only `DLG_KEY` is meant for the big sizes).

## Light and dark

Of the chosen indexes, PeaZip's `_dark` sheet differs only for `il_dtheme_16/76` (`TB_MENU`: dark grey
lines become light grey) and `il_dtheme_16/53` (`MI_SEARCH`). So only `TB_MENU` has
`TB_MENU_<SIZE>_DARK` resources and files in `gen/<size>-dark/`. `MI_SEARCH` keeps its light art in both
themes on purpose: PeaZip's dark magnifier is *darker* than the light one and would be hard to see on a
dark background (the reason is in the generated section below). Every other name, `ImageListDlg` and
the app box use the same art in both themes. The loader below tries the `_DARK` name first and falls
back to the light one, so a dark variant can be added later without touching the program.

## How the program loads an icon (contract for `src/gui/zsicons.pas`)

1. **Link the resources** once, in `src/gui/zsicons.pas` (the path is relative to the unit file):

   ```pascal
   {$R ../../icons/gen/zsicons.res}
   ```

   `zsicons.res` is an ordinary compiled Win32 resource file. FPC 3.2.2 links a compiled `.res`
   through `fpcres` on every target (ELF resources on Linux, PE resources on Windows), so it builds
   with lazbuild for Linux GTK2, win32 and win64 with no `windres` and nothing in the `.lpi`. FPC
   copies it into the unit output folder by itself. (An `.rc` file would not work: FPC 3.2.2 compiles
   `.rc` with `windres`, which Linux does not have.)

2. **Resource names** are `<NAME>_<SIZE>` and, for the names marked "dark" below,
   `<NAME>_<SIZE>_DARK`; upper case, type `RT_RCDATA`, data = the PNG file. Examples: `TB_OPEN_24`,
   `FT_FOLDER_16`, `DLG_WARN_48`, `TB_MENU_16_DARK`, `APP_128`. Use upper case (the lookup was
   case-insensitive in the tests on Linux and Windows, but the names are stored in upper case).

3. **Load one PNG** (`LCLType.RT_RCDATA` exists on every target; `TGraphic.LoadFromResourceName` reads
   `RT_RCDATA` and raises `EResNotFound` for an unknown name):

   ```pascal
   uses SysUtils, Graphics, LCLType;

   function IconResName(const Name: string; Size: Integer; Dark: Boolean): string;
   begin
     Result := Name + '_' + IntToStr(Size);
     if Dark and (FindResource(HInstance, PChar(Result + '_DARK'), RT_RCDATA) <> 0) then
       Result := Result + '_DARK';
   end;

   function LoadIconPng(const Name: string; Size: Integer; Dark: Boolean): TPortableNetworkGraphic;
   begin
     Result := TPortableNetworkGraphic.Create;
     try
       Result.LoadFromResourceName(HInstance, IconResName(Name, Size, Dark));
     except
       Result.Free;
       raise;
     end;
   end;
   ```

4. **Fill a multi-resolution image list** (the pattern of the LCL's own `dialogres.pas`): set the base
   size, register the resolutions, then add each name with one PNG per resolution, smallest first. The
   LCL then picks the resolution for the monitor's PPI.

   ```pascal
   procedure AddIcon(List: TImageList; const Name: string; const Sizes: array of Integer;
     Dark: Boolean);
   var
     Pngs: array of TCustomBitmap;
     i: Integer;
   begin
     SetLength(Pngs, Length(Sizes));   // entries start as nil, so the finally block is safe
     try
       for i := 0 to High(Sizes) do
         Pngs[i] := LoadIconPng(Name, Sizes[i], Dark);
       List.AddMultipleResolutions(Pngs);
     finally
       for i := 0 to High(Pngs) do
         Pngs[i].Free;
     end;
   end;

   // toolbar list: 24 px at 100 %, 36 at 150 %, 48 at 200 %
   ilToolbar := TImageList.Create(Self);
   ilToolbar.Width := 24;
   ilToolbar.Height := 24;
   ilToolbar.Scaled := True;
   ilToolbar.RegisterResolutions([24, 36, 48]);
   AddIcon(ilToolbar, 'TB_OPEN', [24, 36, 48], Dark);   // index 0, and so on in a fixed order
   ToolBar1.Images := ilToolbar;
   ToolBar1.ImagesWidth := 24;
   ```

   Small list: `Width := 16`, `RegisterResolutions([16, 24, 32])`; big list: `Width := 48`,
   `RegisterResolutions([48, 72, 96])`. A menu that shares the action list's small images uses
   `ImagesWidth := 16`.

5. **One picture** (welcome panel, Properties header): load the size nearest to the scaled size, for
   example `LoadIconPng('APP', 128, False)` at 100 % and `'APP', 192` at 150 %
   (`APP` exists at 16 24 32 36 48 72 96 128 160 192 256).

6. **Encrypted overlay**: `OV_LOCK` is a full-size image (lock in the bottom-right quarter, the rest
   transparent), so it is drawn at the same position and size as the type icon, for example as the
   `ikOverlay` image of the file list. Keep it in the same image list as the `FT_*` names.

7. **Application icon**: `icons/gen/app.ico` (16 20 24 32 40 48 64 96 256; the 16/24/32/48/256 frames
   are byte-identical to `app_fit.ico`, the others are scaled from its 256 frame for 125 % DPI and
   Explorer's large view). `icons/src/app_fit.ico` also works as the project icon.

8. **Association icons**: `icons/assoc/zpaq.ico` (= `app.ico`), `7z.ico`, `zip.ico`, `rar.ico`,
   `archive.ico` (same nine frames), for the package's `icons\` folder and the installer's ProgIDs.

## Changing an icon

1. Edit `TABLE` (name, source, use, looks like) or `ASSOC_ICONS` in `tools/make-icons.py`.
2. Put the source PNG in `icons/src/` (same path as in `icons-extract/`), or re-import everything with
   `python3 tools/make-icons.py --import /mnt/IA_LAB/agentes/zs-gui/new/icons-extract /mnt/IA_LAB/agentes/zs-gui/icons`.
3. Run `python3 tools/make-icons.py`. It rewrites only what changed, deletes outputs that no longer
   exist, and regenerates the tables below. `--check` changes nothing and exits 1 when something is out
   of date (byte comparison, so run it with the same Pillow version that wrote the files).
4. Commit `icons/` and `tools/make-icons.py` together. A new name also needs its index in
   `zsicons.pas`.

## Names, uses and sources

<!-- BEGIN GENERATED BY tools/make-icons.py: do not edit by hand -->

Every name exists at 16 24 32 36 48 72 96 px; `APP` also at 128 160 192 256.
A name marked "dark" also has `<NAME>_<SIZE>_DARK` resources (and `gen/<size>-dark/` files);
every other name uses the same art in both themes.

| Name | Use | Source (`icons/src/`) | Looks like | Dark |
|---|---|---|---|---|
| `TB_OPEN` | Toolbar Open | `il_dtheme_tool32/00.png` | yellow folder |  |
| `TB_CREATE` | Toolbar Create | `il_dtheme_tool32/01.png` | open cardboard box |  |
| `TB_ADD` | Toolbar Add | `il_dtheme_16/49.png` | coral plus |  |
| `TB_EXTRACT` | Toolbar Extract | `il_dtheme_96/37.png` | coral arrow down onto a bar |  |
| `TB_EXTRACT_TO` | Toolbar Extract to... | `il_dtheme_tool32/04.png` | orange folder |  |
| `TB_TEST` | Toolbar Test | `il_dtheme_tool32/05.png` | green check |  |
| `TB_INFO` | Toolbar Info (Properties) | `ImageListDlg/00.png` | blue "i" |  |
| `TB_CLOSE` | Toolbar Close | `il_dtheme_tool32/12.png` | coral X |  |
| `TB_SETTINGS` | Toolbar Settings | `il_dtheme_16/62.png` | sliders |  |
| `TB_MENU` | Toolbar menu (three lines) | `il_dtheme_16/76.png` | list lines | dark |
| `MI_UP` | Path bar Up | `il_dtheme_16/55.png` | coral arrow up |  |
| `MI_SEARCH` | Search | `il_dtheme_16/53.png` | grey magnifier |  |
| `MI_RELOAD` | Reload | `il_dtheme_16/51.png` | coral circular arrow |  |
| `MI_COPY` | Copy names | `il_dtheme_16/04.png` | two sheets |  |
| `MI_DELETE` | Delete (later) | `il_dtheme_16/03.png` | trash |  |
| `DLG_KEY` | Password dialog | `il_dtheme_16/45.png` | gold key |  |
| `OV_LOCK` | Encrypted overlay (list) | `il_dtheme_16/46.png` | closed lock at half size in the bottom-right corner, rest transparent |  |
| `DLG_OK` | Result OK | `il_dtheme_tool32/05.png` | green check |  |
| `DLG_WARN` | Result warning, warning strip | `ImageListDlg/01.png` | orange triangle |  |
| `DLG_ERROR` | Result error | `ImageListDlg/02.png` | red X |  |
| `DLG_INFO` | Result info, messages | `ImageListDlg/00.png` | blue "i" |  |
| `OP_ADD` | Progress header: Create / Add | `il_dtheme_tool32/01.png` | box |  |
| `OP_EXTRACT` | Progress header: Extract | `il_dtheme_96/37.png` | down arrow |  |
| `OP_TEST` | Progress header: Test | `il_dtheme_tool32/05.png` | check |  |
| `TYPE_ZPAQ` | Big type icon: zpaq | `coral256.png` | coral box |  |
| `TYPE_7Z` | Big type icon: 7z | `il_dtheme_96/29.png` | box "7Z" |  |
| `TYPE_RAR` | Big type icon: rar | `il_dtheme_96/30.png` | box "RAR" |  |
| `TYPE_ZIP` | Big type icon: zip | `il_dtheme_96/31.png` | box "ZIP" |  |
| `TYPE_ARCHIVE` | Big type icon: tar gz xz zst bz2 cab wim | `il_dtheme_96/32.png` | multicolour box |  |
| `TYPE_DISC` | Big type icon: iso img | `il_dtheme_96/33.png` | box with disc |  |
| `TYPE_OTHER` | Big type icon: any other archive | `il_dtheme_96/06.png` | plain box |  |
| `FT_FOLDER` | List: folder | `il_dtheme_16/06.png` | yellow folder |  |
| `FT_ZPAQ` | List: zpaq | `app16_fit.ico` (16) / `app_fit.ico` | coral box |  |
| `FT_7Z` | List: 7z | `il_dtheme_16/82.png` | olive box |  |
| `FT_RAR` | List: rar | `il_dtheme_16/83.png` | rose box |  |
| `FT_ZIP` | List: zip zipx jar apk | `il_dtheme_16/84.png` | yellow box |  |
| `FT_ARCHIVE` | List: tar gz tgz xz txz bz2 tbz2 zst tzst lz lz4 br cab wim cpio | `il_dtheme_16/85.png` | multicolour box |  |
| `FT_DISC` | List: iso img udf dmg vhd vhdx | `il_dtheme_16/86.png` | box with disc |  |
| `FT_TEXT` | List: txt md log nfo rtf doc docx odt | `il_dtheme_16/38.png` | lined page |  |
| `FT_CONFIG` | List: ini cfg conf reg inf toml yaml yml | `il_dtheme_16/22.png` | page with gear |  |
| `FT_CODE` | List: pas pp lpr inc c h cpp hpp py js ts html htm css xml json java cs go rs php lua | `il_dtheme_16/41.png` | "</>" page |  |
| `FT_IMAGE` | List: png jpg jpeg gif bmp webp tif tiff ico svg heic | `il_dtheme_16/26.png` | red picture |  |
| `FT_AUDIO` | List: mp3 flac wav ogg opus m4a aac wma | `il_dtheme_16/21.png` | red note |  |
| `FT_VIDEO` | List: mp4 mkv avi mov webm wmv flv m4v | `il_dtheme_16/40.png` | film frame |  |
| `FT_PDF` | List: pdf | `il_dtheme_16/33.png` | pdf page |  |
| `FT_SHEET` | List: xls xlsx ods csv tsv | `il_dtheme_16/36.png` | green grid |  |
| `FT_SLIDES` | List: ppt pptx odp | `il_dtheme_16/24.png` | red layered page |  |
| `FT_EXE` | List: exe dll sys com msi bat cmd ps1 sh | `il_dtheme_16/35.png` | console window |  |
| `FT_LINK` | List: lnk url desktop | `il_dtheme_16/31.png` | arrow page |  |
| `FT_MAIL` | List: eml msg mbox | `il_dtheme_16/32.png` | envelope |  |
| `FT_FILE` | List: anything else | `il_dtheme_16/39.png` | blank page |  |
| `APP` | Application: welcome panel (128 px at 100 %), About | `app16_fit.ico` (16) / `app_fit.ico` | coral box |  |

`MI_SEARCH` has no dark variant on purpose:
PeaZip's `il_dtheme_16_dark/53` is darker (#5C5C5C) than the light one (#A1A1A1),
contrast 2.0:1 against 5.3:1 on the dark list background #2E2E2E, so the light art is
used in both themes.

Source index -> names (sheets in `icons-extract/`, see the `*_sheet.png` contact sheets there):

| Source | Names |
|---|---|
| `ImageListDlg/00.png` | `TB_INFO`, `DLG_INFO` |
| `ImageListDlg/01.png` | `DLG_WARN` |
| `ImageListDlg/02.png` | `DLG_ERROR` |
| `coral256.png` | `TYPE_ZPAQ` |
| `il_dtheme_16/03.png` | `MI_DELETE` |
| `il_dtheme_16/04.png` | `MI_COPY` |
| `il_dtheme_16/06.png` | `FT_FOLDER` |
| `il_dtheme_16/21.png` | `FT_AUDIO` |
| `il_dtheme_16/22.png` | `FT_CONFIG` |
| `il_dtheme_16/24.png` | `FT_SLIDES` |
| `il_dtheme_16/26.png` | `FT_IMAGE` |
| `il_dtheme_16/31.png` | `FT_LINK` |
| `il_dtheme_16/32.png` | `FT_MAIL` |
| `il_dtheme_16/33.png` | `FT_PDF` |
| `il_dtheme_16/35.png` | `FT_EXE` |
| `il_dtheme_16/36.png` | `FT_SHEET` |
| `il_dtheme_16/38.png` | `FT_TEXT` |
| `il_dtheme_16/39.png` | `FT_FILE` |
| `il_dtheme_16/40.png` | `FT_VIDEO` |
| `il_dtheme_16/41.png` | `FT_CODE` |
| `il_dtheme_16/45.png` | `DLG_KEY` |
| `il_dtheme_16/46.png` | `OV_LOCK` |
| `il_dtheme_16/49.png` | `TB_ADD` |
| `il_dtheme_16/51.png` | `MI_RELOAD` |
| `il_dtheme_16/53.png` | `MI_SEARCH` |
| `il_dtheme_16/55.png` | `MI_UP` |
| `il_dtheme_16/62.png` | `TB_SETTINGS` |
| `il_dtheme_16/76.png` | `TB_MENU` |
| `il_dtheme_16_dark/76.png` | dark variant of `TB_MENU` |
| `il_dtheme_16/82.png` | `FT_7Z` |
| `il_dtheme_16/83.png` | `FT_RAR` |
| `il_dtheme_16/84.png` | `FT_ZIP` |
| `il_dtheme_16/85.png` | `FT_ARCHIVE` |
| `il_dtheme_16/86.png` | `FT_DISC` |
| `il_dtheme_96/06.png` | `TYPE_OTHER` |
| `il_dtheme_96/29.png` | `TYPE_7Z`, `assoc/7z.ico` |
| `il_dtheme_96/30.png` | `TYPE_RAR`, `assoc/rar.ico` |
| `il_dtheme_96/31.png` | `TYPE_ZIP`, `assoc/zip.ico` |
| `il_dtheme_96/32.png` | `TYPE_ARCHIVE`, `assoc/archive.ico` |
| `il_dtheme_96/33.png` | `TYPE_DISC` |
| `il_dtheme_96/37.png` | `TB_EXTRACT`, `OP_EXTRACT` |
| `il_dtheme_tool32/00.png` | `TB_OPEN` |
| `il_dtheme_tool32/01.png` | `TB_CREATE`, `OP_ADD` |
| `il_dtheme_tool32/04.png` | `TB_EXTRACT_TO` |
| `il_dtheme_tool32/05.png` | `TB_TEST`, `DLG_OK`, `OP_TEST` |
| `il_dtheme_tool32/12.png` | `TB_CLOSE` |
| `app16_fit.ico` (16) / `app_fit.ico` | `FT_ZPAQ`, `APP`, `assoc/zpaq.ico` |

<!-- END GENERATED -->
