#!/bin/bash
# tools/build.sh: builds ZPAQ-std (src/zpaqstdgui.lpi) and its console tests for Linux GTK2,
# Windows x64 or Windows x86. Linux uses the system Lazarus; Windows is cross-compiled with the
# Lazarus copy and the FPC cross compilers in $ZSGUI_WIN (default /mnt/IA_LAB/agentes/zs-gui/win).
#
# usage: tools/build.sh linux|win64|win32|all [debug]
#   no mode (or "release"): build mode Release (-O2, no debug info, smart linking), then stripped
#   "debug":  build mode Debug (debug info, range/overflow/IO/stack checks, assertions, heaptrc;
#             the Windows exe writes heap.trc next to itself)
#   "all":    the three targets in that order, then the Linux tests and tools/check-lang.py
#             when present
# Output (DESIGN.md §15.2): bin/x86_64-linux/, bin/x86_64-win64/, bin/i386-win32/, each with the
# exe, the tests and lang/*.zsl (copied, so the exe finds its language files); logs in lib/logs/.
# environment: ZSGUI_WIN (cross toolchain folder), LAZBUILD (lazbuild 4.0, default "lazbuild"),
#              ZSGUI_VERBOSE=1 (show the whole lazbuild output instead of errors and warnings only)

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
W=${ZSGUI_WIN:-/mnt/IA_LAB/agentes/zs-gui/win}
LAZBUILD=${LAZBUILD:-lazbuild}
LPI=$ROOT/src/zpaqstdgui.lpi
LOGS=$ROOT/lib/logs

usage() { echo "usage: $0 linux|win64|win32|all [debug]" >&2; exit 2; }
die() { echo "build.sh: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || usage
TARGET=$1
case "${2:-release}" in
  release) MODE=Release ;;
  debug)   MODE=Debug ;;
  *)       usage ;;
esac
case "$TARGET" in linux|win64|win32|all) ;; *) usage ;; esac

# the folder lazbuild writes to: ../bin/$(TargetCPU)-$(TargetOS) in the .lpi files
out_dir() {
  case "$1" in
    linux) echo "$ROOT/bin/$(fpc -iTP 2>/dev/null || echo x86_64)-linux" ;;
    win64) echo "$ROOT/bin/x86_64-win64" ;;
    win32) echo "$ROOT/bin/i386-win32" ;;
  esac
}

# The .lpi version info must match src/version.inc (AppVersion '1.2.3' or '1.2.3-pre.4').
check_version() {
  local inc=$ROOT/src/version.inc ver num major minor rev lpi_ver lpi_major lpi_minor lpi_rev
  [ -f "$inc" ] || die "missing $inc"
  ver=$(sed -n "s/^[[:space:]]*AppVersion[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "$inc")
  [ -n "$ver" ] || die "no AppVersion in $inc"
  num=${ver%%-*}
  IFS=. read -r major minor rev _ <<<"$num"
  [[ "$major.$minor.$rev" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "AppVersion '$ver' is not N.N.N[-suffix]"
  lpi_field() {   # numeric field of <VersionInfo>; Lazarus omits a field whose value is 0
    local v
    v=$(sed -n "s/.*<$1 Value=\"\([0-9]*\)\".*/\1/p" "$LPI" | head -n 1)
    echo "${v:-0}"
  }
  lpi_major=$(lpi_field MajorVersionNr)
  lpi_minor=$(lpi_field MinorVersionNr)
  lpi_rev=$(lpi_field RevisionNr)
  lpi_ver=$(sed -n 's/.*<StringTable .*ProductVersion="\([^"]*\)".*/\1/p' "$LPI" | head -n 1)
  if [ "$lpi_major.$lpi_minor.$lpi_rev" != "$major.$minor.$rev" ] || [ "$lpi_ver" != "$ver" ]; then
    die "version mismatch: version.inc AppVersion='$ver' but the .lpi has $lpi_major.$lpi_minor.$lpi_rev" \
        "and ProductVersion='$lpi_ver' (Project Options > Version Info, or edit <VersionInfo> in $LPI)"
  fi
  echo "version $ver"
}

# Files the .lpi embeds as resources; lazbuild only logs a missing one, so check them first.
check_inputs() {
  local f missing=0
  for f in src/zpaqstdgui.lpr icons/gen/app.ico lang/en.zsl; do
    if [ ! -f "$ROOT/$f" ]; then echo "build.sh: missing $f" >&2; missing=1; fi
  done
  [ $missing = 0 ] || die "cannot build without the files above"
}

# $1 = target, $2 = .lpi; runs lazbuild with the options of that target.
run_lazbuild() {
  local t=$1 lpi=$2 log rc=0
  local -a cmd
  case "$t" in
    linux) cmd=("$LAZBUILD" --widgetset=gtk2) ;;
    win64) cmd=("$LAZBUILD" --lazarusdir="$W/lazarus" --pcp="$W/pcp-zsgui-x64" --os=win64 --cpu=x86_64
                --widgetset=win32 --compiler="$W/ppc-win64") ;;
    win32) cmd=("$LAZBUILD" --lazarusdir="$W/lazarus" --pcp="$W/pcp-zsgui-x86" --os=win32 --cpu=i386
                --widgetset=win32 --compiler="$W/ppc-win32") ;;
  esac
  cmd+=(--build-mode="$MODE")
  [ "$MODE" = Release ] && cmd+=(-B)   # rebuild every project unit (not the packages) for a release
  cmd+=("$lpi")
  mkdir -p "$LOGS"
  log=$LOGS/$t-$(basename "$lpi" .lpi)-$MODE.log
  echo "== $t $MODE: $(basename "$lpi")"
  if [ "${ZSGUI_VERBOSE:-0}" = 1 ]; then
    "${cmd[@]}" 2>&1 | tee "$log" || rc=$?
  else
    "${cmd[@]}" >"$log" 2>&1 || rc=$?
    # errors from anywhere; warnings only from our own sources (not from the Lazarus packages)
    grep -E '(Error|Fatal):' "$log" || true
    grep -E 'Warning:' "$log" | grep -v -E "^($W/lazarus|/usr/(lib|share)/lazarus)/|\(lazarus\)|TPCTargetConfigCache" || true
  fi
  if [ $rc != 0 ]; then
    if [ "${ZSGUI_VERBOSE:-0}" != 1 ] && ! grep -q -E '(Error|Fatal):' "$log"; then
      echo "---- last lines of $log" >&2
      tail -n 40 "$log" >&2
    fi
    die "$t $MODE build of $(basename "$lpi") failed (exit $rc; full output in ${log#"$ROOT"/})"
  fi
  # lazbuild exits 0 when a resource file is missing; such an exe would lack its icon or texts.
  if grep -q -E '^ ?Error: ' "$log"; then
    die "$t $MODE build of $(basename "$lpi") logged errors (full output in ${log#"$ROOT"/})"
  fi
}

build_target() {
  local t=$1 out exe strip_tool lpi
  out=$(out_dir "$t")
  case "$t" in
    linux) exe=$out/zpaq-std-gui;       strip_tool=strip ;;
    win64) exe=$out/zpaq-std-gui.exe;   strip_tool=x86_64-w64-mingw32-strip ;;
    win32) exe=$out/zpaq-std-gui.exe;   strip_tool=i686-w64-mingw32-strip ;;
  esac
  command -v "$LAZBUILD" >/dev/null || die "lazbuild not found (set LAZBUILD)"
  case "$t" in
    linux) ;;
    win64) [ -x "$W/ppc-win64" ] && [ -d "$W/lazarus" ] || die "cross toolchain not found in $W (set ZSGUI_WIN)" ;;
    win32) [ -x "$W/ppc-win32" ] && [ -d "$W/lazarus" ] || die "cross toolchain not found in $W (set ZSGUI_WIN)" ;;
  esac
  rm -f "$exe"
  run_lazbuild "$t" "$LPI"
  [ -f "$exe" ] || die "lazbuild succeeded but $exe is missing"
  if [ "$MODE" = Release ]; then
    command -v "$strip_tool" >/dev/null || die "$strip_tool not found"
    "$strip_tool" "$exe"
  fi
  # the language files next to the exe (only en is compiled in): <out>/lang/*.zsl
  mkdir -p "$out/lang"
  rm -f "$out"/lang/*.zsl
  cp "$ROOT"/lang/*.zsl "$out/lang/"
  # Console projects (tests, fake backend, harness) are built the same way once they exist.
  for lpi in "$ROOT"/tests/zstests.lpi "$ROOT"/tests/fakebackend.lpi "$ROOT"/tests/zsrun.lpi; do
    if [ -f "$lpi" ]; then run_lazbuild "$t" "$lpi"; fi
  done
  echo "   $(du -h "$exe" | cut -f1)  ${exe#"$ROOT"/}  (+ lang/: $(cd "$out/lang" && echo *.zsl))"
}

check_version
check_inputs
if [ "$TARGET" = all ]; then
  for t in linux win64 win32; do build_target "$t"; done
  if [ -x "$(out_dir linux)/zstests" ]; then
    echo "== tests (linux)"
    "$(out_dir linux)/zstests" --all --format=plain
  fi
  if [ -f "$ROOT/tools/check-lang.py" ]; then
    echo "== check-lang"
    python3 "$ROOT/tools/check-lang.py"
  fi
else
  build_target "$TARGET"
fi
