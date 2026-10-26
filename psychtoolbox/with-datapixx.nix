# Adds VPixx's prebuilt Datapixx mex files to a Psychtoolbox-3 package, at
# the paths where PTB's own prebuilt copies were (postPatch deletes those,
# and PTB has no Datapixx source). Usage:
#   (callPackage ./with-datapixx.nix { withOctaveMex = true; }) psychtoolbox-3
#
# The MATLAB mexa64 is always installed. The Octave mex needs two things
# that stock nixpkgs Octave does not give it, so it is opt-in:
# - It was built with a 64-bit mwSize. The PTB package must be built with an
#   Octave that uses 64-bit indexing (octave-ilp64 in overlay.nix). With
#   32-bit indexing, calls that pass mwSize arrays, such as
#   mxCreateStructArray, get wrong dimensions. The build fails if the
#   Octave has 32-bit indexing.
# - Octave 10.2 and later refuse mex files without the
#   __octave_mex_soversion__ symbol, which VPixx's Octave 5.2 build lacks.
#   A small library that contains only that symbol is linked into the mex,
#   see vendor/vpixx-software-tools/mex-soversion.c.
# Without the Octave mex, PTB's Datapixx.m placeholder reports the missing
# mex clearly.
{
  lib,
  vpixx-software-tools,
  withOctaveMex ? false,
}:
ptb:
ptb.overrideAttrs (old: {
  postInstall =
    (old.postInstall or "")
    + ''
      install -Dm755 ${vpixx-software-tools.datapixxMex.matlab} \
        $out/share/psychtoolbox-3/PsychBasic/Datapixx.mexa64
    ''
    + lib.optionalString withOctaveMex ''
      # sizemax() is 2^31 - 2 with 32-bit indexing.
      if ! HOME=$TMPDIR OCTAVE_HISTFILE=/dev/null octave-cli --no-init-file --quiet \
        --eval 'exit(sizemax() <= 2^31)'; then
        echo "error: withOctaveMex needs an Octave with 64-bit indexing" \
          "(use64BitIdx = true, octave-ilp64 in overlay.nix); VPixx's" \
          "Datapixx.mex uses a 64-bit mwSize" >&2
        exit 1
      fi

      mex=$out/share/psychtoolbox-3/PsychBasic/Octave5LinuxFiles64/Datapixx.mex
      install -Dm755 ${vpixx-software-tools.datapixxMex.octave} $mex

      cp ${./vendor/vpixx-software-tools/mex-soversion.c} mex-soversion.c
      HOME=$TMPDIR mkoctfile --mex -o mex-soversion mex-soversion.c
      install -Dm755 mex-soversion.mex $out/lib/libdatapixx-mex-soversion.so
      patchelf --add-needed libdatapixx-mex-soversion.so --add-rpath $out/lib $mex
    '';

  postInstallCheck =
    (old.postInstallCheck or "")
    + ''
      test -s $out/share/psychtoolbox-3/PsychBasic/Datapixx.mexa64
    ''
    # No device in the sandbox; these calls do not need one. A struct of the
    # wrong size or an empty cell means the mwSize ABI does not match.
    + lib.optionalString withOctaveMex ''
      HOME=$TMPDIR OCTAVE_HISTFILE=/dev/null octave-cli --no-init-file --quiet --eval "
        source('$out/share/octave-psychtoolbox-3/startup.m');
        assert(strcmp(which('Datapixx'), '$out/share/psychtoolbox-3/PsychBasic/Octave5LinuxFiles64/Datapixx.mex'));
        v = Datapixx('Version')
        assert(isstruct(v) && isequal(size(v), [1 1]), 'Datapixx Version did not return a 1x1 struct');
        names = Datapixx('DescribeModuleFunctionsHelper');
        assert(iscell(names) && numel(names) > 0, 'Datapixx DescribeModuleFunctionsHelper returned no names');
        printf('Datapixx has %d subfunctions\n', numel(names));
      "
    '';

  meta = old.meta // {
    description = old.meta.description + ", with the VPixx Datapixx mex files";
    license = [
      old.meta.license
      vpixx-software-tools.meta.license
    ];
  };
})
