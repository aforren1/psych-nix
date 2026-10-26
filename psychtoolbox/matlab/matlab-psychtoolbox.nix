# `matlab-psychtoolbox`: starts MATLAB with Psychtoolbox-3 on the path.
#
# A plain script around the fleet's `matlab` command, not a second FHS
# environment. The fleet's environment stays the only place that knows how
# to run MATLAB (libraries, license file). The mex files do not need it: their
# DT_RPATH points to the store (see mex-builder.nix). Environment variables
# set here pass through bubblewrap into MATLAB.
{
  lib,
  stdenv,
  runCommand,
  replaceVars,
  writeShellScriptBin,
  jdk_headless,
  gst_all_1,
  psychtoolbox-3,
  ptb-matlab-mex-builder,
  release ? "R2024b",
  # PsychBasic folder that ptb-matlab-mex-builder --release <release> made.
  mexDir ? "${ptb-matlab-mex-builder.defaultOut}/${psychtoolbox-3.version}/${release}/PsychBasic",
  # The fleet's `matlab` FHS environment. null: `matlab` from PATH.
  matlab ? null,
  # MATLAB loads its own libstdc++ before any mex file, and a loaded soname
  # wins over the rpath. Store libraries can need a newer one (openal-soft
  # needs GLIBCXX_3.4.29). The preload applies to every process that the
  # wrapper starts, so the store GCC must use the same glibc as the host and
  # the FHS environment: true when the fleet uses this overlay.
  preloadLibstdcxx ? true,
}:

assert lib.assertMsg (psychtoolbox-3.version == ptb-matlab-mex-builder.psychtoolbox.version)
  "matlab-psychtoolbox: psychtoolbox-3 ${psychtoolbox-3.version} and the mex builder (${ptb-matlab-mex-builder.psychtoolbox.version}) differ";

let
  matlabExe = if matlab == null then "matlab" else lib.getExe' matlab "matlab";

  # The package deletes the prebuilt class files. MATLAB's Java 8 runtime
  # needs class file version 52.
  getCharJava =
    runCommand "psychtoolbox-getcharjava-${psychtoolbox-3.version}"
      {
        nativeBuildInputs = [ jdk_headless ];
      }
      ''
        mkdir -p $out
        javac --release 8 -nowarn -d $out \
          ${psychtoolbox-3}/share/psychtoolbox-3/PsychJava/GetCharJava.java
      '';

  startup = replaceVars ./startup.m {
    ptbRoot = "${psychtoolbox-3}/share/psychtoolbox-3";
    inherit mexDir getCharJava;
  };

  # Same plugin set as octave-psychtoolbox.
  gstPluginPath = lib.makeSearchPathOutput "out" "lib/gstreamer-1.0" (
    with gst_all_1;
    [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
    ]
  );
  gstPluginScanner = "${lib.getOutput "out" gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner";
in
(writeShellScriptBin "matlab-psychtoolbox" ''
  # Run the PTB startup script before the user's -r or -batch command. A
  # startup.m on MATLABPATH would depend on the path order of userpath.
  args=()
  hasCommand=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -r | -batch)
        if [ $# -lt 2 ]; then
          echo "matlab-psychtoolbox: $1 needs a command" >&2
          exit 1
        fi
        args+=("$1" "run('${startup}'); $2")
        hasCommand=1
        shift 2
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done
  if [ "$hasCommand" = 0 ]; then
    args+=(-r "run('${startup}')")
  fi

  # The rpath of the mex files names exact store paths. Files from another
  # package set still load while those paths exist, but can break after
  # garbage collection.
  runtimePath=${lib.escapeShellArg (dirOf mexDir)}/runtime-path
  if [ -r "$runtimePath" ] && [ "$(cat "$runtimePath")" != ${lib.escapeShellArg ptb-matlab-mex-builder.rpath} ]; then
    echo "matlab-psychtoolbox: the mex files in ${mexDir} were built for other store libraries." >&2
    echo "matlab-psychtoolbox: rebuild them with ptb-matlab-mex-builder --release ${release}." >&2
  fi

  export GST_PLUGIN_SYSTEM_PATH_1_0=${gstPluginPath}''${GST_PLUGIN_SYSTEM_PATH_1_0:+:$GST_PLUGIN_SYSTEM_PATH_1_0}
  export GST_PLUGIN_SCANNER=${gstPluginScanner}
  ${lib.optionalString preloadLibstdcxx ''
    export LD_PRELOAD=${lib.getLib stdenv.cc.cc}/lib/libstdc++.so.6''${LD_PRELOAD:+:$LD_PRELOAD}
  ''}
  exec ${matlabExe} "''${args[@]}"
'').overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit startup getCharJava mexDir;
    };
    meta = (old.meta or { }) // {
      description = "MATLAB with Psychtoolbox-3 on the path";
      mainProgram = "matlab-psychtoolbox";
      platforms = [ "x86_64-linux" ];
    };
  })
