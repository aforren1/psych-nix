# `matlab-install`: a shell in the same FHS environment as matlab-fhs, for
# the MathWorks installer. The installer is a MATLAB program and needs the
# same libraries as MATLAB.
{
  lib,
  buildFHSEnv,
  writeShellScript,
  matlabFhsLibs,
  prefix ? "/opt/matlab",
  release ? "R2024b",
  # Text added to the instructions, for example where the fleet keeps the
  # license file.
  installNotes ? "",
}:

buildFHSEnv {
  name = "matlab-install";
  targetPkgs = matlabFhsLibs;
  profile = import ./fhs-profile.nix;

  runScript = writeShellScript "matlab-install" ''
    cat <<'EOF'
    MATLAB installer shell (FHS environment).
      1. Extract the MATLAB installer from MathWorks into a writable folder.
      2. Run ./install. Set the destination folder to ${prefix}/${release}.
      3. Use your File Installation Key. Activation makes a license file
         that is locked to this computer.
    ${installNotes}
    Type exit to leave this shell.
    EOF
    exec bash
  '';

  passthru = {
    inherit prefix release;
  };

  meta = {
    description = "Shell in an FHS environment for the MATLAB installer";
    mainProgram = "matlab-install";
    platforms = [ "x86_64-linux" ];
  };
}
