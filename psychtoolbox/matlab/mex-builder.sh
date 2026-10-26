#!/usr/bin/env bash
# Run script of the ptb-matlab-mex-builder FHS environment. mex-builder.nix
# fills in the @...@ values. It runs inside the environment, so gcc,
# pkg-config and the PTB headers are under /usr.
set -euo pipefail

ptbVersion='@ptbVersion@'
source='@source@'
matlabRoot='@matlabRoot@'
out='@defaultOut@'
read -r -a modes <<<'@modes@'
read -r -a pkgConfigModules <<<'@pkgConfigModules@'
rpath='@rpath@'
runtime='@runtime@'
datapixxMex='@datapixxMex@'
octave='@octave@'
dryRunStubs='@dryRunStubs@'
nixStore='@nixStore@'

# Mex file of each mode of linuxmakeit64.m.
declare -A mexOfMode=(
  [0]=Screen [1]=GetSecs [2]=WaitSecs [3]=PsychPortAudio [4]=Eyelink
  [5]=IOPort [6]=moglcore [8]=PsychHID [9]=moalcore [10]=PsychCV
  [11]=pnet [15]=PsychVulkanCore [16]=PsychOpenXRCore
)

usage() {
  cat <<EOF
Usage:
  ptb-matlab-mex-builder --release RELEASE [--out DIR] [--modes "0 1 ..."] [--keep]
  ptb-matlab-mex-builder --dry-run [--release RELEASE] [--out DIR] [--modes "0 1 ..."]
  ptb-matlab-mex-builder --check-env [--modes "0 1 ..."]
  ptb-matlab-mex-builder --mex-setup --release RELEASE

Compiles the Psychtoolbox-3 $ptbVersion MATLAB mex files with
$matlabRoot/RELEASE/bin/matlab and installs them into
DIR/$ptbVersion/RELEASE/PsychBasic. The default DIR is $out.

  --release RELEASE  MATLAB release folder under $matlabRoot, for example R2024b.
  --out DIR          Root of the installed mex files. Default: $out.
  --modes "LIST"     linuxmakeit64 modes. Default: ${modes[*]}.
  --keep             Keep the temporary build folder.
  --dry-run          Print the commands, and do not run MATLAB. Uses Octave
                     to expand the mex calls of linuxmakeit64.m.
  --check-env        Check that the environment has the compiler, the
                     pkg-config modules, the headers and the libraries that
                     the mex calls use. Does not need MATLAB.
  --mex-setup        Print how MATLAB's mex finds the compiler: mex -setup -v,
                     the installed compiler configurations, MATLAB's PATH and
                     gcc_glnxa64.xml. Does not build, and does not fail when
                     MATLAB reports an error.
EOF
}

die() {
  echo "ptb-matlab-mex-builder: $*" >&2
  exit 1
}

release=""
action=build
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --release) release=${2:?--release needs a value}; shift 2 ;;
    --out) out=${2:?--out needs a value}; shift 2 ;;
    --modes) read -r -a modes <<<"${2:?--modes needs a value}"; shift 2 ;;
    --keep) keep=1; shift ;;
    --dry-run) action=dry-run; shift ;;
    --check-env) action=check-env; shift ;;
    --mex-setup) action=mex-setup; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

for m in "${modes[@]}"; do
  [ -n "${mexOfMode[$m]:-}" ] || die "mode $m is not supported (supported: $(printf '%s\n' "${!mexOfMode[@]}" | sort -n | xargs))"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/ptb-matlab-mex.XXXXXX")
cleanup() {
  if [ "$keep" = 1 ]; then
    echo "Build folder kept: $work"
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

# Expands the mex calls of linuxmakeit64.m with Octave and stub functions
# (see dry-run/). Prints them in MATLAB syntax. With an argument, also
# writes one record for each call to that file.
listMex() {
  # The stubs are loaded with addpath inside the evaluated code, not with the
  # --path option: on a GitHub runner the option left IsLinux undefined.
  [ -f "$dryRunStubs/IsLinux.m" ] || die "dry-run stubs not found: $dryRunStubs"
  (
    cd "$source/PsychSourceGL/Source"
    PTB_SOURCE=$source PTB_ROOT=$work/ptb/Psychtoolbox/ PTB_MEX_RECORDS=${1:-} \
      HOME=$work OCTAVE_HISTFILE=/dev/null \
      "$octave/bin/octave-cli" --no-init-file --quiet --no-window-system \
      --eval "addpath('$dryRunStubs'); \
              if exist('IsLinux', 'file') ~= 2, disp(path()); error('IsLinux is not on the path'); end; \
              for m = [${modes[*]}]; linuxmakeit64(m); end"
  )
}

checkEnv() {
  local failed=0 records=$work/records

  echo "== Tools"
  for tool in gcc g++ pkg-config patchelf ldd; do
    if command -v "$tool" >/dev/null; then
      printf '%-10s %s\n' "$tool" "$("$tool" --version 2>&1 | head -n 1)"
    else
      echo "MISSING: $tool"
      failed=1
    fi
  done

  # The probes of MATLAB's compiler configuration (bin/glnxa64/mexopts/
  # gcc_glnxa64.xml and g++_glnxa64.xml, <locationFinder>): mex runs them
  # through a shell. If one returns nothing, mex reports "Supported compiler
  # not detected".
  echo "== mex compiler probes"
  local probe
  for probe in "which gcc" "which g++" "gcc -dumpversion" "gcc -dumpmachine" \
    "gcc -print-file-name=libstdc++.so" "g++ -print-file-name=libstdc++.so"; do
    if result=$(env -i PATH=/usr/bin:/bin /bin/sh -c "$probe" 2>&1) && [ -n "$result" ]; then
      echo "ok   $probe: $result"
    else
      echo "FAIL $probe: $result"
      failed=1
    fi
  done

  echo "== pkg-config modules"
  for m in "${pkgConfigModules[@]}"; do
    if flags=$(pkg-config --cflags --libs "$m" 2>&1); then
      echo "ok   $m: $flags"
    else
      echo "FAIL $m: $flags"
      failed=1
    fi
  done

  echo "== mex calls"
  listMex "$records" >/dev/null || failed=1
  [ -s "$records" ] || die "no mex calls found"

  # Preprocess every source file with the flags of its mex call. This
  # resolves every #include. mex.h comes from MATLAB, so an empty stand-in
  # is used; the C code is not compiled.
  mkdir -p "$work/stub-include"
  : >"$work/stub-include/mex.h"
  local libs=()
  while IFS=$'\x1f' read -r -a rec; do
    local dir=${rec[0]} cflags=() defs=() srcs=() name="" arg next=""
    for arg in "${rec[@]:1}"; do
      if [ "$next" = output ]; then name=$arg; next=""; continue; fi
      if [ "$next" = skip ]; then next=""; continue; fi
      case "$arg" in
        -output) next=output ;;
        -outdir) next=skip ;;
        CFLAGS=*) read -r -a extra <<<"${arg#CFLAGS=\$CFLAGS}"; cflags+=("${extra[@]}") ;;
        -c | -O | -g | -largeArrayDims) ;;
        -D* | -I*) defs+=("$arg") ;;
        -l*) libs+=("$arg") ;;
        *.c | *.cc) srcs+=("$arg") ;;
        *.o) ;;
        *) echo "note: argument not checked: $arg" ;;
      esac
    done
    [ -n "$name" ] || name=$(basename "${srcs[0]}" | sed 's/\.[^.]*$//')
    local n=0 bad=0 file
    shopt -s nullglob
    for pattern in "${srcs[@]}"; do
      for file in "$dir"/$pattern; do
        local cc=gcc
        [[ "$file" == *.cc ]] && cc=g++
        n=$((n + 1))
        if ! (cd "$dir" && "$cc" -E -o /dev/null "${cflags[@]}" "${defs[@]}" \
          -I"$work/stub-include" "$file" 2>"$work/cpp.err"); then
          bad=$((bad + 1))
          echo "FAIL $name: $file"
          grep -m 5 -E 'error' "$work/cpp.err" || true
        fi
      done
    done
    shopt -u nullglob
    if [ "$bad" = 0 ] && [ "$n" -gt 0 ]; then
      echo "ok   $name: $n source files preprocess"
    else
      failed=1
    fi
  done <"$records"

  echo "== Libraries"
  local lib
  for lib in $(printf '%s\n' "${libs[@]}" | sort -u); do
    if gcc -shared -o "$work/link-test.so" -Wl,--no-as-needed "$lib" 2>"$work/ld.err"; then
      echo "ok   $lib"
    else
      echo "FAIL $lib: $(head -n 1 "$work/ld.err")"
      failed=1
    fi
  done

  echo "== rpath directories"
  local d
  IFS=: read -r -a dirs <<<"$rpath"
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || echo "note: not a directory (header-only package): $d"
  done

  if [ "$failed" = 0 ]; then
    echo "check-env: all checks passed"
  else
    die "check-env: some checks failed"
  fi
}

ptb=$work/ptb/Psychtoolbox

# One MATLAB session for all modes, because MATLAB starts slowly. Upstream
# catches most mex errors itself, so the mex files are checked after the
# build.
batch="addpath('$ptb/PsychOneliners', '$ptb/PsychBasic');"
batch+=" failed = [];"
batch+=" for m = [${modes[*]}],"
batch+=" try, linuxmakeit64(m);"
batch+=" catch err, fprintf(2, 'mode %d: %s\n', m, err.message); failed(end+1) = m; end,"
batch+=" end,"
batch+=" if ~isempty(failed), error('ptb:mexbuild', 'Failed modes: %s', mat2str(failed)); end"

case "$action" in
  mex-setup)
    [ -n "$release" ] || die "--mex-setup needs --release"
    matlab=$matlabRoot/$release/bin/matlab
    echo "== Shell (outside MATLAB)"
    for c in "command -v which gcc g++" "gcc -dumpversion" "gcc -dumpmachine" \
      "gcc -print-file-name=libstdc++.so"; do
      echo "\$ $c"
      sh -c "$c" 2>&1 || true
    done
    # Each step in its own try, so that a failed mex -setup does not hide
    # the rest. type() prints MathWorks' compiler configurations of this
    # release, with their <locationFinder> probes.
    setup="for lang = {'C', 'C++'},"
    setup+=" fprintf('== mex -setup -v %s\n', lang{1});"
    setup+=" try, mex('-v', '-setup', lang{1}); catch e, disp(getReport(e)); end,"
    setup+=" try, disp(mex.getCompilerConfigurations(lang{1}, 'Installed')); catch e, disp(getReport(e)); end,"
    setup+=" end,"
    setup+=" fprintf('== MATLAB environment\n');"
    setup+=" fprintf('PATH=%s\nLD_LIBRARY_PATH=%s\nSHELL=%s\n', getenv('PATH'), getenv('LD_LIBRARY_PATH'), getenv('SHELL'));"
    setup+=" system('command -v which; which gcc; which g++; gcc -dumpversion; gcc -dumpmachine; gcc -print-file-name=libstdc++.so; ls -la /usr/bin/gcc /usr/lib/libstdc++.so');"
    setup+=" for f = {'gcc_glnxa64.xml', 'g++_glnxa64.xml'},"
    setup+=" x = fullfile(matlabroot, 'bin', computer('arch'), 'mexopts', f{1});"
    setup+=" fprintf('== %s\n', x); try, type(x); catch e, disp(getReport(e)); end,"
    setup+=" end"
    if [ ! -x "$matlab" ]; then
      echo "MATLAB not found at $matlab. It would run:"
      echo "$matlab -batch \"$setup\""
      exit 1
    fi
    echo "== MATLAB ($matlab)"
    "$matlab" -batch "$setup" || echo "MATLAB exited with status $?"
    exit 0
    ;;
  check-env)
    checkEnv
    exit 0
    ;;
  dry-run)
    release=${release:-RELEASE}
    matlab=$matlabRoot/$release/bin/matlab
    dest=$out/$ptbVersion/$release
    [ -x "$matlab" ] || echo "# note: $matlab does not exist; a real build would stop here."
    echo "cp -r --no-preserve=mode,ownership $source $work/ptb"
    echo "cd $work/ptb/PsychSourceGL/Source"
    echo "$matlab -batch \"$batch\""
    echo "# linuxmakeit64 runs these mex calls (paths relative to the source root):"
    listMex
    echo "# Then, for each mex file:"
    echo "patchelf --force-rpath --set-rpath '$rpath' FILE.mexa64"
    [ -z "$datapixxMex" ] || echo "cp $datapixxMex $dest/PsychBasic/Datapixx.mexa64"
    echo "# Install into: $dest/PsychBasic"
    exit 0
    ;;
esac

[ -n "$release" ] || {
  usage >&2
  die "--release is required"
}
matlab=$matlabRoot/$release/bin/matlab
[ -x "$matlab" ] || die "MATLAB not found at $matlab. Install it, or check --release."
dest=$out/$ptbVersion/$release
mkdir -p "$out" 2>/dev/null && [ -w "$out" ] ||
  die "cannot write to $out. Run as a user who can, or use --out."

echo "Copying the patched PTB source to $work/ptb"
cp -r --no-preserve=mode,ownership "$source" "$work/ptb"
(cd "$work/ptb/PsychSourceGL/Source" && "$matlab" -batch "$batch")

stage=$work/stage
mkdir -p "$stage/PsychBasic"
for m in "${modes[@]}"; do
  f=$ptb/PsychBasic/${mexOfMode[$m]}.mexa64
  [ -s "$f" ] || die "${mexOfMode[$m]}.mexa64 (mode $m) was not built. See the MATLAB output above."
  install -m 755 "$f" "$stage/PsychBasic/"
done

# DT_RPATH, not DT_RUNPATH: the MATLAB launcher sets LD_LIBRARY_PATH to its
# own library folders, and only DT_RPATH is searched before it. The libraries
# come from the store, so the files do not depend on the FHS environment
# that runs MATLAB.
for f in "$stage"/PsychBasic/*.mexa64; do
  patchelf --force-rpath --set-rpath "$rpath" "$f"
  # libmx, libmex and libmat are in the MATLAB process already.
  missing=$(env -u LD_LIBRARY_PATH ldd "$f" | grep 'not found' |
    grep -vE '^\s*lib(mx|mex|mat)\.so' || true)
  [ -z "$missing" ] || die "unresolved libraries in $(basename "$f"):
$missing"
done

if [ -n "$datapixxMex" ]; then
  install -m 755 "$datapixxMex" "$stage/PsychBasic/Datapixx.mexa64"
fi

echo "$rpath" >"$stage/runtime-path"
{
  echo "psychtoolbox: $ptbVersion"
  echo "matlab: $release ($matlab)"
  echo "modes: ${modes[*]}"
  echo "source: $source"
  echo "compiler: $(gcc --version | head -n 1)"
  echo "date: $(date --iso-8601=seconds)"
} >"$stage/build-info.txt"

# Replace the old files in one step, so that a failed build keeps them.
mkdir -p "$(dirname "$dest")"
rm -rf "$dest.new" "$dest.old"
cp -r "$stage" "$dest.new"
[ ! -e "$dest" ] || mv "$dest" "$dest.old"
mv "$dest.new" "$dest"
rm -rf "$dest.old"

# The rpath points into the store. Register a GC root, so that
# nix-collect-garbage does not delete the libraries while the files exist.
if ! "$nixStore" --add-root "$dest/runtime" --realise "$runtime" >/dev/null; then
  echo "warning: could not register a GC root for $runtime." >&2
  echo "Keep matlab-psychtoolbox installed; its closure has the same libraries." >&2
fi

echo "Installed into $dest/PsychBasic:"
ls "$dest/PsychBasic"
