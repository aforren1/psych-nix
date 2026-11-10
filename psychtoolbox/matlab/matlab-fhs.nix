# `matlab`: starts a MATLAB that is installed outside the store, at
# <prefix>/<release>, in an FHS environment.
#
# MathWorks does not permit redistribution, so MATLAB cannot be a store
# path. The environment supplies the libraries that the MATLAB launcher
# expects in /usr/lib (fhs-libs.nix).
{
  lib,
  buildFHSEnv,
  writeShellScript,
  matlabFhsLibs,
  prefix ? "/opt/matlab",
  release ? "R2024b",
}:

let
  root = "${prefix}/${release}";
in
buildFHSEnv {
  name = "matlab";
  targetPkgs = matlabFhsLibs;
  profile = import ./fhs-profile.nix;

  runScript = writeShellScript "matlab-run" ''
    if [ -x ${lib.escapeShellArg root}/bin/matlab ]; then
      exec ${lib.escapeShellArg root}/bin/matlab "$@"
    fi
    echo "matlab: MATLAB not found at ${root}." >&2
    echo "matlab: install it with matlab-install, or copy it from a machine that has it." >&2
    exit 1
  '';

  passthru = {
    inherit prefix release root;
  };

  meta = {
    description = "Runs MATLAB ${release} from ${root} in an FHS environment";
    mainProgram = "matlab";
    platforms = [ "x86_64-linux" ];
  };
}
