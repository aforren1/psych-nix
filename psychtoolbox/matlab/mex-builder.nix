# FHS environment that compiles the Psychtoolbox-3 MATLAB mex files with a
# MATLAB installed outside the store. Run `ptb-matlab-mex-builder --help`.
#
# MATLAB is not in the store, so a derivation cannot run `mex`. This
# environment has what MATLAB needs to start (fhs-libs.nix, the same list as
# matlab-fhs) plus the PTB headers and libraries. The mex files are built without license
# management (PSYCH_NOLM) and get a DT_RPATH to the store libraries below, so
# they load in any MATLAB that runs on the same glibc.
{
  lib,
  stdenv,
  stdenvNoCC,
  buildFHSEnv,
  replaceVarsWith,
  writeText,
  psychtoolbox-3,
  pkg-config,
  patchelf,
  octave,
  nix,
  matlabRoot ? "/opt/matlab",
  defaultOut ? "/opt/ptb-matlab",
  # Adds mode 4 (Eyelink.mexa64), which links the unfree SR Research SDK.
  withEyelink ? false,
  eyelink-core ? null,
  # Copies VPixx's prebuilt Datapixx.mexa64 (unfree) into the output.
  withDatapixx ? false,
  vpixx-software-tools ? null,
  # Default of --release. null: a build needs --release.
  release ? null,
  # Libraries that MATLAB itself needs (fhs-libs.nix, from the overlay).
  # matlab-fhs uses the same list, so mex runs with the libraries that
  # MATLAB has on the fleet.
  matlabFhsLibs,
}:

assert withEyelink -> eyelink-core != null;
assert withDatapixx -> vpixx-software-tools != null;

let
  ptbVersion = psychtoolbox-3.version;

  # Same source, patches and postPatch as the Octave package, so both builds
  # compile the same C code. postPatch deletes the prebuilt mexa64 files and
  # libLexActivator. The Octave patches also change C headers (system GLEW)
  # that the MATLAB build needs.
  source = stdenvNoCC.mkDerivation {
    pname = "psychtoolbox-3-matlab-source";
    inherit (psychtoolbox-3) version src postPatch;
    patches = psychtoolbox-3.patches ++ [ ./patches/matlab-nolm.patch ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      cp -r . $out
    '';
  };

  # The libraries of the Octave package, including its apriltag without
  # opencv. One list keeps the MATLAB and Octave builds in step.
  ptbLibs = lib.unique (psychtoolbox-3.buildInputs ++ lib.optional withEyelink eyelink-core);

  # mkDerivation stores the dev output of each build input, with
  # outputSpecified set. lib.getLib then returns that dev output unchanged,
  # and buildFHSEnv installs only it, so select the outputs here.
  libOutput = d: d.lib or d.out or d;
  devOutput = d: d.dev or d;

  # Modes of linuxmakeit64.m. Not built: 7 PsychKinectCore (no libfreenect),
  # 12 PsychOculusVRCore (Oculus SDK), 14 PsychOpenHMDVRCore (no openhmd).
  # 13 does not exist in the MATLAB script.
  modes = [
    0
    1
    2
    3
    5
    6
    8
    9
    10
    11
    15
    16
  ]
  ++ lib.optional withEyelink 4;

  # Modules whose flags the mex calls use, directly or through -l. The
  # --check-env action checks each of them.
  pkgConfigModules = [
    "gl"
    "glu"
    "glew"
    "glut"
    "x11"
    "xext"
    "x11-xcb"
    "xcb"
    "xcb-dri3"
    "xcb-present"
    "xxf86vm"
    "xi"
    "xrandr"
    "xfixes"
    "xcomposite"
    "gstreamer-1.0"
    "gstreamer-base-1.0"
    "gstreamer-app-1.0"
    "gstreamer-video-1.0"
    "gstreamer-pbutils-1.0"
    "glib-2.0"
    "gobject-2.0"
    "gmodule-2.0"
    "gthread-2.0"
    "libxml-2.0"
    "libdc1394-2"
    "libusb-1.0"
    "pciaccess"
    "portaudio-2.0"
    "alsa"
    "openal"
    "vulkan"
    "openxr"
    "apriltag"
  ]
  ++ lib.optional withEyelink "eyelink_core";

  # DT_RPATH of the mex files. libstdc++ is for tinyexr in Screen.
  rpath = lib.concatMapStringsSep ":" (d: "${libOutput d}/lib") (
    ptbLibs ++ [ (lib.getLib stdenv.cc.cc) ]
  );

  # Its closure holds the libraries in rpath. The builder registers it as a
  # GC root next to the installed files; matlab-psychtoolbox depends on it.
  runtime = writeText "ptb-matlab-mex-runtime-${ptbVersion}" rpath;

  script = replaceVarsWith {
    name = "ptb-matlab-mex-builder";
    src = ./mex-builder.sh;
    isExecutable = true;
    replacements = {
      inherit
        ptbVersion
        source
        matlabRoot
        defaultOut
        rpath
        runtime
        octave
        ;
      defaultRelease = if release == null then "" else release;
      modes = toString modes;
      pkgConfigModules = toString pkgConfigModules;
      datapixxMex = lib.optionalString withDatapixx vpixx-software-tools.datapixxMex.matlab;
      # Interpolated, not toString: with lazy trees (newer Nix) a toString path
      # inside the flake stays a virtual path and does not exist at run time.
      dryRunStubs = "${./dry-run}";
      nixStore = "${lib.getBin nix}/bin/nix-store";
    };
  };
in
buildFHSEnv {
  name = "ptb-matlab-mex-builder";

  targetPkgs =
    p:
    matlabFhsLibs p
    ++ map libOutput ptbLibs
    ++ map devOutput ptbLibs
    ++ [
      # Propagated by the libx* dev outputs; buildFHSEnv does not follow
      # propagated inputs.
      p.xorgproto
      # MATLAB's compiler configurations (bin/glnxa64/mexopts/gcc_glnxa64.xml
      # and g++_glnxa64.xml) find the compiler with `which gcc` and
      # `which g++`. buildFHSEnv and fhs-libs.nix have no `which`, so
      # mex reports "Supported compiler not detected" (MATLAB:mex:NoCompilerFound).
      p.which
      pkg-config
      patchelf
    ];

  # Headers and .pc files are in the dev outputs.
  extraOutputsToInstall = [ "dev" ];

  # Some packages, for example xorgproto and vulkan-headers, install their
  # .pc files in share/pkgconfig.
  profile = ''
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:/usr/share/pkgconfig"
  ''
  + import ./fhs-profile.nix;

  runScript = script;

  passthru = {
    inherit
      source
      modes
      rpath
      runtime
      defaultOut
      matlabRoot
      release
      ;
    psychtoolbox = psychtoolbox-3;
  };

  meta = {
    description = "Builds the Psychtoolbox-3 MATLAB mex files with a MATLAB installed outside the store";
    license = psychtoolbox-3.meta.license;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ptb-matlab-mex-builder";
  };
}
