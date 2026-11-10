# Lab Streaming Layer for Octave: the liblsl-Matlab bindings (lsl_loadlib,
# lsl_outlet, lsl_inlet, ...), with their mex files built for one Octave.
# octave-env.nix rebuilds it for the Octave of each octave-psychtoolbox
# variant, because a mex file only loads in the Octave it was built for.
#
# The upstream build_mex.m looks for liblsl under bin/ or /usr/lib and
# otherwise downloads a release, so this builds the mex files directly.
# At run time, lsl_loadlib() opens bin/liblsl.so next to the m-files, which
# links to the nixpkgs liblsl.
{
  lib,
  stdenv,
  fetchFromGitHub,
  octave,
  liblsl,
}:

stdenv.mkDerivation {
  pname = "octave-liblsl";
  # No release since v1.14.0 (2020). Master has the pointer-width fixes
  # from December 2024.
  version = "1.14.0-unstable-2025-02-17";

  src = fetchFromGitHub {
    owner = "labstreaminglayer";
    repo = "liblsl-Matlab";
    rev = "76db65cba884bcb365dce8d5ec4803cf4e1dade0";
    hash = "sha256-D39Zg5YR61mh2f0MH+up2R2eCQ07eMEuCs7zzZTkAbg=";
  };

  nativeBuildInputs = [ octave ];

  # Each mex file reads a function address from the library handle and casts
  # it as `(lsl_x_t*)*pTmp`. The type is one level of indirection off, but
  # the value is the address, so the call is correct. GCC 14 made this
  # warning an error.
  env.NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types";

  # The mex files call liblsl through function pointers that lsl_loadlib_
  # gets from dlopen, so they do not link liblsl.
  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    mkdir -p build
    for f in mex/*.c; do
      mkoctfile --mex -Imex -o "build/$(basename "$f" .c).mex" "$f"
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    dir=$out/share/octave-liblsl
    mkdir -p $dir/bin
    # The mex files go next to the m-files, so one directory on the path is
    # enough. bin/ only holds what lsl_get_dll.m looks for.
    cp -r *.m build/*.mex examples $dir/
    # build_mex.m would try to build again or download liblsl.
    rm $dir/build_mex.m
    # lsl_get_dll.m accepts bin/ only if it has both the library and an
    # include directory.
    ln -s ${liblsl}/lib/liblsl.so $dir/bin/liblsl.so
    ln -s ${liblsl}/include $dir/bin/include
    runHook postInstall
  '';

  doInstallCheck = true;
  # A stream must resolve through the loopback interface, which is the only
  # interface in the build sandbox.
  installCheckPhase = ''
    runHook preInstallCheck
    # Octave finds m-files in the current directory first, and the source
    # tree has the same m-files without the mex files.
    mkdir -p $TMPDIR/check && cd $TMPDIR/check
    OCTAVE_HISTFILE=/dev/null octave-cli --no-init-file --quiet --eval "
      addpath('$out/share/octave-liblsl');
      lib = lsl_loadlib();
      printf('liblsl %d\n', lsl_library_version(lib));
      info = lsl_streaminfo(lib, 'NixCheck', 'Markers', 1, 0, 'cf_string', 'octave-liblsl-check');
      outlet = lsl_outlet(info);
      found = lsl_resolve_byprop(lib, 'source_id', 'octave-liblsl-check', 1, 10);
      assert(numel(found) == 1, 'the outlet did not resolve');
      inlet = lsl_inlet(found{1});
      inlet.open_stream(10);
      pause(0.5);
      outlet.push_sample({'hello'});
      [sample, ts] = inlet.pull_sample(10);
      assert(isequal(sample, {'hello'}), 'the sample did not arrive');
    "
    runHook postInstallCheck
  '';

  passthru = {
    inherit octave liblsl;
    # Add this directory to the Octave path.
    mPath = "share/octave-liblsl";
  };

  meta = {
    description = "Lab Streaming Layer (liblsl-Matlab) bindings built for GNU Octave";
    homepage = "https://github.com/labstreaminglayer/liblsl-Matlab";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
