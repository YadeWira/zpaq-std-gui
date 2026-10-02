#!/usr/bin/env python3
"""make-icons.py: builds the ZPAQ-std GUI icon set from the source art in icons/src.

Writes icons/gen/<size>[-dark]/<name>.png, icons/gen/zsicons.res (every PNG as an RCDATA
resource), icons/gen/app.ico, icons/assoc/*.ico and the generated tables of icons/MAPPING.md.
The outputs are committed, so building the program needs no Python. Needs Python 3 and Pillow.

usage:
  tools/make-icons.py                        regenerate the outputs that changed (and delete stale ones)
  tools/make-icons.py --check                change nothing; exit 1 if an output is missing or out of date
  tools/make-icons.py --import EXTRACT APPDIR
                                             first copy the chosen sources into icons/src from an
                                             icons-extract tree (PNG per sheet index) and the folder
                                             with app_fit.ico, app16_fit.ico and coral256.png
"""

import argparse
import io
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / 'icons'
SRC = ICONS / 'src'
GEN = ICONS / 'gen'
ASSOC = ICONS / 'assoc'
MAPPING = ICONS / 'MAPPING.md'
RES_FILE = GEN / 'zsicons.res'

# Sizes of every named PNG: list/menu 16 24 32, toolbar 24 36 48, dialog/operation 48 72 96
# (100 %, 150 % and 200 % of 16, 24 and 48). APP also gets the welcome-panel sizes (128 at 100 %).
SIZES = (16, 24, 32, 36, 48, 72, 96)
EXTRA_SIZES = {'APP': (128, 160, 192, 256)}
# Frames of every .ico written here (BMP below 256, PNG at 256, like app_fit.ico).
ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 256)

APP = 'app'   # pseudo source: the coral box of app16_fit.ico (16 px) and app_fit.ico (other sizes)
APP_FILES = ('app_fit.ico', 'app16_fit.ico', 'coral256.png')

# name, source (relative to icons/src, or APP), use, looks like
TABLE = [
    ('TB_OPEN', 'il_dtheme_tool32/00.png', 'Toolbar Open', 'yellow folder'),
    ('TB_CREATE', 'il_dtheme_tool32/01.png', 'Toolbar Create', 'open cardboard box'),
    ('TB_ADD', 'il_dtheme_16/49.png', 'Toolbar Add', 'coral plus'),
    ('TB_EXTRACT', 'il_dtheme_96/37.png', 'Toolbar Extract', 'coral arrow down onto a bar'),
    ('TB_EXTRACT_TO', 'il_dtheme_tool32/04.png', 'Toolbar Extract to...', 'orange folder'),
    ('TB_TEST', 'il_dtheme_tool32/05.png', 'Toolbar Test', 'green check'),
    ('TB_INFO', 'ImageListDlg/00.png', 'Toolbar Info (Properties)', 'blue "i"'),
    ('TB_CLOSE', 'il_dtheme_tool32/12.png', 'Toolbar Close', 'coral X'),
    ('TB_SETTINGS', 'il_dtheme_16/62.png', 'Toolbar Settings', 'sliders'),
    ('TB_MENU', 'il_dtheme_16/76.png', 'Toolbar menu (three lines)', 'list lines'),
    ('MI_UP', 'il_dtheme_16/55.png', 'Path bar Up', 'coral arrow up'),
    ('MI_SEARCH', 'il_dtheme_16/53.png', 'Search', 'grey magnifier'),
    ('MI_RELOAD', 'il_dtheme_16/51.png', 'Reload', 'coral circular arrow'),
    ('MI_COPY', 'il_dtheme_16/04.png', 'Copy names', 'two sheets'),
    ('MI_DELETE', 'il_dtheme_16/03.png', 'Delete (later)', 'trash'),
    ('DLG_KEY', 'il_dtheme_16/45.png', 'Password dialog', 'gold key'),
    ('OV_LOCK', 'il_dtheme_16/46.png', 'Encrypted overlay (list)',
     'closed lock at half size in the bottom-right corner, rest transparent'),
    ('DLG_OK', 'il_dtheme_tool32/05.png', 'Result OK', 'green check'),
    ('DLG_WARN', 'ImageListDlg/01.png', 'Result warning, warning strip', 'orange triangle'),
    ('DLG_ERROR', 'ImageListDlg/02.png', 'Result error', 'red X'),
    ('DLG_INFO', 'ImageListDlg/00.png', 'Result info, messages', 'blue "i"'),
    ('OP_ADD', 'il_dtheme_tool32/01.png', 'Progress header: Create / Add', 'box'),
    ('OP_EXTRACT', 'il_dtheme_96/37.png', 'Progress header: Extract', 'down arrow'),
    ('OP_TEST', 'il_dtheme_tool32/05.png', 'Progress header: Test', 'check'),
    ('TYPE_ZPAQ', 'coral256.png', 'Big type icon: zpaq', 'coral box'),
    ('TYPE_7Z', 'il_dtheme_96/29.png', 'Big type icon: 7z', 'box "7Z"'),
    ('TYPE_RAR', 'il_dtheme_96/30.png', 'Big type icon: rar', 'box "RAR"'),
    ('TYPE_ZIP', 'il_dtheme_96/31.png', 'Big type icon: zip', 'box "ZIP"'),
    ('TYPE_ARCHIVE', 'il_dtheme_96/32.png', 'Big type icon: tar gz xz zst bz2 cab wim', 'multicolour box'),
    ('TYPE_DISC', 'il_dtheme_96/33.png', 'Big type icon: iso img', 'box with disc'),
    ('TYPE_OTHER', 'il_dtheme_96/06.png', 'Big type icon: any other archive', 'plain box'),
    ('FT_FOLDER', 'il_dtheme_16/06.png', 'List: folder', 'yellow folder'),
    ('FT_ZPAQ', APP, 'List: zpaq', 'coral box'),
    ('FT_7Z', 'il_dtheme_16/82.png', 'List: 7z', 'olive box'),
    ('FT_RAR', 'il_dtheme_16/83.png', 'List: rar', 'rose box'),
    ('FT_ZIP', 'il_dtheme_16/84.png', 'List: zip zipx jar apk', 'yellow box'),
    ('FT_ARCHIVE', 'il_dtheme_16/85.png',
     'List: tar gz tgz xz txz bz2 tbz2 zst tzst lz lz4 br cab wim cpio', 'multicolour box'),
    ('FT_DISC', 'il_dtheme_16/86.png', 'List: iso img udf dmg vhd vhdx', 'box with disc'),
    ('FT_TEXT', 'il_dtheme_16/38.png', 'List: txt md log nfo rtf doc docx odt', 'lined page'),
    ('FT_CONFIG', 'il_dtheme_16/22.png', 'List: ini cfg conf reg inf toml yaml yml', 'page with gear'),
    ('FT_CODE', 'il_dtheme_16/41.png',
     'List: pas pp lpr inc c h cpp hpp py js ts html htm css xml json java cs go rs php lua',
     '"</>" page'),
    ('FT_IMAGE', 'il_dtheme_16/26.png', 'List: png jpg jpeg gif bmp webp tif tiff ico svg heic',
     'red picture'),
    ('FT_AUDIO', 'il_dtheme_16/21.png', 'List: mp3 flac wav ogg opus m4a aac wma', 'red note'),
    ('FT_VIDEO', 'il_dtheme_16/40.png', 'List: mp4 mkv avi mov webm wmv flv m4v', 'film frame'),
    ('FT_PDF', 'il_dtheme_16/33.png', 'List: pdf', 'pdf page'),
    ('FT_SHEET', 'il_dtheme_16/36.png', 'List: xls xlsx ods csv tsv', 'green grid'),
    ('FT_SLIDES', 'il_dtheme_16/24.png', 'List: ppt pptx odp', 'red layered page'),
    ('FT_EXE', 'il_dtheme_16/35.png', 'List: exe dll sys com msi bat cmd ps1 sh', 'console window'),
    ('FT_LINK', 'il_dtheme_16/31.png', 'List: lnk url desktop', 'arrow page'),
    ('FT_MAIL', 'il_dtheme_16/32.png', 'List: eml msg mbox', 'envelope'),
    ('FT_FILE', 'il_dtheme_16/39.png', 'List: anything else', 'blank page'),
    ('APP', APP, 'Application: welcome panel (128 px at 100 %), About', 'coral box'),
]

# Names that keep their light art in Dark although their sheet has a different _dark index, and why.
NO_DARK = {
    'MI_SEARCH': 'PeaZip\'s `il_dtheme_16_dark/53` is darker (#5C5C5C) than the light one (#A1A1A1),\n'
                 'contrast 2.0:1 against 5.3:1 on the dark list background #2E2E2E, so the light art is\n'
                 'used in both themes',
}

# icons/assoc/<file>.ico: file-type icons for the installer's ProgIDs
ASSOC_ICONS = [
    ('zpaq', APP),
    ('7z', 'il_dtheme_96/29.png'),
    ('zip', 'il_dtheme_96/31.png'),
    ('rar', 'il_dtheme_96/30.png'),
    ('archive', 'il_dtheme_96/32.png'),
]

GITIGNORE = (b'# zsicons.res is generated by tools/make-icons.py and committed, so the build needs no\n'
             b'# Python. The top-level .gitignore ignores *.res (the project resource file that\n'
             b'# lazbuild writes), so this file is re-included here.\n'
             b'!zsicons.res\n')

BEGIN_MARK = '<!-- BEGIN GENERATED BY tools/make-icons.py: do not edit by hand -->'
END_MARK = '<!-- END GENERATED -->'


def die(msg):
    print('make-icons.py: ' + msg, file=sys.stderr)
    sys.exit(1)


def dark_path(rel):
    """il_dtheme_16/53.png -> il_dtheme_16_dark/53.png; None when the source has no dark sheet."""
    if rel == APP or '/' not in rel or not rel.startswith('il_'):
        return None
    folder, name = rel.split('/', 1)
    return folder + '_dark/' + name


def open_rgba(path):
    if not path.is_file():
        die(f'missing source {path} (run with --import first)')
    im = Image.open(path)
    im.load()
    im = im.convert('RGBA')
    if im.width != im.height:
        die(f'{path} is not square ({im.width}x{im.height})')
    return im


def scale(im, size):
    """Lanczos resize with premultiplied alpha (no dark fringes); same size returns a copy."""
    if im.width == size:
        return im.copy()
    return im.convert('RGBa').resize((size, size), Image.LANCZOS).convert('RGBA')


def read_ico(path):
    """{size: (raw frame bytes, RGBA image)} of an .ico file."""
    data = path.read_bytes()
    _, kind, count = struct.unpack_from('<HHH', data, 0)
    if kind != 1:
        die(f'{path} is not an icon file')
    frames = {}
    decoded = Image.open(path)
    for i in range(count):
        w, h, _, _, _, _, size, offset = struct.unpack_from('<BBBBHHII', data, 6 + 16 * i)
        w = w or 256
        im = decoded.ico.getimage((w, w)).convert('RGBA')
        frames[w] = (data[offset:offset + size], im)
    return frames


class AppArt:
    """The coral box: app16_fit.ico at 16 px, the hand-fitted frames of app_fit.ico, else its 256 frame."""

    def __init__(self):
        self.frames = read_ico(SRC / 'app_fit.ico')
        self.small = read_ico(SRC / 'app16_fit.ico')[16][1]
        if 256 not in self.frames:
            die('app_fit.ico has no 256 px frame')

    def image(self, size):
        if size == 16:
            return self.small.copy()
        if size in self.frames:
            return self.frames[size][1].copy()
        return scale(self.frames[256][1], size)

    def raw_frame(self, size):
        """The original encoded frame of app_fit.ico, or None when the size is generated."""
        frame = self.frames.get(size)
        return frame[0] if frame else None


class Sources:
    def __init__(self):
        self.cache = {}
        self.app = AppArt()

    def get(self, rel):
        if rel not in self.cache:
            self.cache[rel] = open_rgba(SRC / rel)
        return self.cache[rel]

    def render(self, name, rel, size):
        if rel == APP:
            return self.app.image(size)
        im = self.get(rel)
        if name == 'OV_LOCK':
            # the overlay is drawn over the type icon at full size: lock in the bottom-right quarter
            half = size // 2
            out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            out.alpha_composite(scale(im, half), (size - half, size - half))
            return out
        return scale(im, size)


def png_bytes(im):
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def bmp_frame(im):
    """32-bit BGRA DIB icon frame (bottom-up) with its 1-bit AND mask (1 = transparent)."""
    w, h = im.size
    px = im.load()
    xor = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            xor += bytes((b, g, r, a))
    row = ((w + 31) // 32) * 4
    mask = bytearray()
    for y in range(h - 1, -1, -1):
        bits = bytearray(row)
        for x in range(w):
            if px[x, y][3] == 0:
                bits[x // 8] |= 0x80 >> (x % 8)
        mask += bits
    header = struct.pack('<IiiHHIIiiII', 40, w, h * 2, 1, 32, 0, len(xor) + len(mask), 0, 0, 0, 0)
    return header + bytes(xor) + bytes(mask)


def ico_bytes(frames):
    """frames: [(size, encoded frame)], written largest first."""
    frames = sorted(frames, key=lambda f: -f[0])
    out = struct.pack('<HHH', 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    body = b''
    for size, blob in frames:
        wh = 0 if size >= 256 else size
        out += struct.pack('<BBBBHHII', wh, wh, 0, 0, 1, 32, len(blob), offset + len(body))
        body += blob
    return out + body


def encode_frame(im):
    return png_bytes(im) if im.width >= 256 else bmp_frame(im)


def app_ico(src):
    frames = []
    for size in ICO_SIZES:
        raw = src.app.raw_frame(size)
        frames.append((size, raw if raw is not None else encode_frame(src.app.image(size))))
    return ico_bytes(frames)


def png_ico(src, rel):
    im = src.get(rel)
    return ico_bytes([(size, encode_frame(scale(im, size))) for size in ICO_SIZES])


def res_bytes(entries):
    """Win32 .res file: an empty first entry, then one RCDATA entry per (name, data), in order."""
    out = bytearray(struct.pack('<II', 0, 32) + b'\xff\xff\x00\x00\xff\xff\x00\x00' + bytes(16))
    for name, data in entries:
        name_field = name.encode('utf-16-le') + b'\x00\x00'
        name_field += bytes(-len(name_field) % 4)
        type_field = struct.pack('<HH', 0xFFFF, 10)                     # RT_RCDATA
        tail = struct.pack('<IHHII', 0, 0x1010, 0x0409, 0, 0)           # as fpcres writes them
        header_size = 8 + len(type_field) + len(name_field) + len(tail)
        out += struct.pack('<II', len(data), header_size) + type_field + name_field + tail + data
        out += bytes(-len(data) % 4)
    return bytes(out)


def sizes_of(name):
    return SIZES + EXTRA_SIZES.get(name, ())


def source_label(rel):
    if rel == APP:
        return '`app16_fit.ico` (16) / `app_fit.ico`'
    return f'`{rel}`'


def mapping_block(dark_names):
    lines = [BEGIN_MARK, '']
    lines.append(f'Every name exists at {" ".join(map(str, SIZES))} px'
                 + ''.join(f'; `{n}` also at {" ".join(map(str, s))}' for n, s in EXTRA_SIZES.items())
                 + '.')
    lines.append('A name marked "dark" also has `<NAME>_<SIZE>_DARK` resources (and `gen/<size>-dark/` files);')
    lines.append('every other name uses the same art in both themes.')
    lines.append('')
    lines.append('| Name | Use | Source (`icons/src/`) | Looks like | Dark |')
    lines.append('|---|---|---|---|---|')
    for name, rel, use, looks in TABLE:
        lines.append(f'| `{name}` | {use} | {source_label(rel)} | {looks} | '
                     f'{"dark" if name in dark_names else ""} |')
    lines.append('')
    for name, why in sorted(NO_DARK.items()):
        lines.append(f'`{name}` has no dark variant on purpose:')
        lines.append(f'{why}.')
        lines.append('')
    lines.append('Source index -> names (sheets in `icons-extract/`, see the `*_sheet.png` contact sheets there):')
    lines.append('')
    lines.append('| Source | Names |')
    lines.append('|---|---|')
    by_src = {}
    for name, rel, _, _ in TABLE:
        by_src.setdefault(rel, []).append(name)
    for _, rel in ASSOC_ICONS:
        by_src.setdefault(rel, [])
    for rel in sorted(by_src, key=lambda r: (r == APP, r)):
        names = [f'`{n}`' for n in by_src[rel]]
        names += [f'`assoc/{f}.ico`' for f, r in ASSOC_ICONS if r == rel]
        lines.append(f'| {source_label(rel)} | {", ".join(names)} |')
        d = dark_path(rel)
        if d and (SRC / d).is_file():
            lines.append(f'| `{d}` | dark variant of {", ".join(f"`{n}`" for n in by_src[rel])} |')
    lines.append('')
    lines.append(END_MARK)
    return '\n'.join(lines)


def build_outputs():
    """{path: bytes} of every generated file."""
    src = Sources()
    out = {}
    res = []
    dark_names = set()
    for name, rel, _, _ in TABLE:
        if not name.replace('_', '').isalnum() or name.upper() != name:
            die(f'bad icon name {name!r}')
        drel = dark_path(rel)
        has_dark = False
        if name not in NO_DARK and drel and (SRC / drel).is_file():
            has_dark = src.get(drel).tobytes() != src.get(rel).tobytes()
        if has_dark:
            dark_names.add(name)
        for size in sizes_of(name):
            data = png_bytes(src.render(name, rel, size))
            out[GEN / str(size) / (name.lower() + '.png')] = data
            res.append((f'{name}_{size}', data))
            if has_dark:
                ddata = png_bytes(src.render(name, drel, size))
                out[GEN / f'{size}-dark' / (name.lower() + '.png')] = ddata
                res.append((f'{name}_{size}_DARK', ddata))
    names = [n for n, _ in res]
    if len(names) != len(set(names)):
        die('duplicate resource names')
    res.sort(key=lambda e: e[0])
    out[RES_FILE] = res_bytes(res)
    out[GEN / '.gitignore'] = GITIGNORE
    out[GEN / 'app.ico'] = app_ico(src)
    for fname, rel in ASSOC_ICONS:
        out[ASSOC / (fname + '.ico')] = app_ico(src) if rel == APP else png_ico(src, rel)
    # MAPPING.md: only the block between the markers is generated
    if not MAPPING.is_file():
        die(f'missing {MAPPING}')
    text = MAPPING.read_text(encoding='utf-8')
    i, j = text.find(BEGIN_MARK), text.find(END_MARK)
    if i < 0 or j < i:
        die(f'{MAPPING} has no generated block (markers {BEGIN_MARK!r} ... {END_MARK!r})')
    text = text[:i] + mapping_block(dark_names) + text[j + len(END_MARK):]
    out[MAPPING] = text.encode('utf-8')
    return out, len(res), dark_names


def stale_files(out):
    """Files under gen/ and assoc/ that the current table no longer produces."""
    stale = []
    for top in (GEN, ASSOC):
        if top.is_dir():
            for p in sorted(top.rglob('*')):
                if p.is_file() and p not in out:
                    stale.append(p)
    return stale


def do_import(extract, appdir):
    extract, appdir = Path(extract), Path(appdir)
    wanted = {rel for _, rel, _, _ in TABLE} | {rel for _, rel in ASSOC_ICONS}
    wanted -= {APP, 'coral256.png'}
    # a _dark index is copied only when a name that may use it (not in NO_DARK) has that source
    dark_wanted = {rel for name, rel, _, _ in TABLE if name not in NO_DARK}
    copied = 0
    for rel in sorted(wanted):
        s = extract / rel
        if not s.is_file():
            die(f'missing {s}')
        (SRC / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(s, SRC / rel)
        copied += 1
        d = dark_path(rel)
        if rel in dark_wanted and d and (extract / d).is_file():
            if open_rgba(extract / d).tobytes() != open_rgba(s).tobytes():
                (SRC / d).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(extract / d, SRC / d)
                copied += 1
    for f in APP_FILES:
        if not (appdir / f).is_file():
            die(f'missing {appdir / f}')
        shutil.copyfile(appdir / f, SRC / f)
        copied += 1
    print(f'imported {copied} source files into {SRC.relative_to(ROOT)}')


def main():
    ap = argparse.ArgumentParser(description='Build the ZPAQ-std GUI icon set from icons/src.')
    ap.add_argument('--check', action='store_true', help='report out-of-date outputs, change nothing')
    ap.add_argument('--import', dest='imp', nargs=2, metavar=('EXTRACT', 'APPDIR'),
                    help='copy the chosen source PNGs and the app icons into icons/src first')
    args = ap.parse_args()
    if args.imp:
        if args.check:
            die('--import and --check do not go together')
        do_import(*args.imp)
    out, nres, dark_names = build_outputs()
    changed = [p for p, data in sorted(out.items()) if not p.is_file() or p.read_bytes() != data]
    stale = stale_files(out)
    rel = lambda p: str(p.relative_to(ROOT))
    if args.check:
        for p in changed:
            print('out of date: ' + rel(p))
        for p in stale:
            print('stale: ' + rel(p))
        if changed or stale:
            print('make-icons.py: run tools/make-icons.py to update', file=sys.stderr)
            return 1
        print(f'icons up to date: {len(TABLE)} names, {nres} resources')
        return 0
    for p in changed:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(out[p])
    for p in stale:
        p.unlink()
    for top in (GEN, ASSOC):   # drop folders left empty by a removed size
        for d in sorted((d for d in top.rglob('*') if d.is_dir()), reverse=True):
            if not any(d.iterdir()):
                d.rmdir()
    print(f'{len(TABLE)} names, {nres} resources ({RES_FILE.stat().st_size} bytes in {rel(RES_FILE)}), '
          f'dark: {", ".join(sorted(dark_names)) or "none"}; {len(changed)} files written, '
          f'{len(stale)} stale files removed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
