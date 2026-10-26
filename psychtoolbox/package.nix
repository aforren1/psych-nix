{
  lib,
  stdenv,
  fetchFromGitHub,
  octave,
  pkg-config,
  libGL,
  libGLU,
  glew,
  freeglut,
  libx11,
  libxext,
  libxi,
  libxrandr,
  libxfixes,
  libxcomposite,
  libxxf86vm,
  libxcb,
  gst_all_1,
  glib,
  libxml2,
  libdc1394,
  libraw1394,
  libusb1,
  libpciaccess,
  alsa-lib,
  portaudio,
  openal,
  apriltag,
  openxr-loader,
  vulkan-loader,
  vulkan-headers,
  freetype,
  fontconfig,
  gamemode,
  pulseaudio,
  # Eyelink.mex links the SR Research SDK, which is unfree; off by default.
  withEyelink ? false,
  eyelink-core ? null,
}:

assert withEyelink -> eyelink-core != null;

let
  # nixpkgs apriltag has a single output whose demos and Python module pull
  # opencv (about 1 GB) into the closure of anything that links libapriltag.
  apriltag' = apriltag.overrideAttrs (old: {
    buildInputs = [ ];
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      (lib.cmakeBool "BUILD_EXAMPLES" false)
      (lib.cmakeBool "BUILD_PYTHON_WRAPPER" false)
    ];
  });

  # Plugin types of PsychSourceGL/Source/linuxmakeitoctave3.m. Not built:
  # 4 Eyelink (unless withEyelink), 7 PsychKinectCore (no libfreenect),
  # 12 PsychOculusVRCore (Oculus SDK), 13 RPiGPIOMex (Raspberry Pi only),
  # 14 PsychOpenHMDVRCore (no openhmd), and the Wayland/Waffle variants.
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

  mexFiles = [
    "Screen"
    "GetSecs"
    "WaitSecs"
    "PsychPortAudio"
    "IOPort"
    "moglcore"
    "PsychHID"
    "moalcore"
    "PsychCV"
    "pnet"
    "PsychVulkanCore"
    "PsychOpenXRCore"
  ]
  ++ lib.optional withEyelink "Eyelink";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "psychtoolbox-3";
  version = "3.0.22.3";

  src = fetchFromGitHub {
    owner = "Psychtoolbox-3";
    repo = "Psychtoolbox-3";
    tag = finalAttrs.version;
    hash = "sha256-Q3UMlcxLMzX+HOMAeXoSMOkQHUuFySgXcka7V8Xeuhk=";
  };

  patches = [
    ./patches/use-pkg-config.patch
    ./patches/use-system-glew.patch
    ./patches/no-nvstusb.patch
    ./patches/build-optional-modules.patch
    ./patches/nix-immutable.patch
  ]
  ++ lib.optional withEyelink ./patches/eyelink-pkg-config.patch;

  postPatch = ''
    # Prebuilt binaries: rebuilt below from source, for other platforms, or
    # not redistributable. Mirrors Debian's Files-Excluded list.
    find . -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.a' \
      -o -name '*.dll' -o -name '*.dylib' -o -name '*.lib' -o -name '*.exe' \
      -o -name '*.mex*' -o -name '*.class' -o -name '*.zip' -o -name '*.o' \) -delete
    rm -r Psychtoolbox/PsychBasic/Octave*Files* \
      Psychtoolbox/PsychContributed/ATIRadeonperf_Linux* \
      Psychtoolbox/PsychContributed/gpuclockctl \
      Psychtoolbox/PsychHardware/nvstusb-extractfw \
      PsychSourceGL/Cohorts/libnvstusb-code-32 \
      PsychSourceGL/Cohorts/OculusSDK \
      PsychSourceGL/Cohorts/libDC1394 \
      PsychSourceGL/Cohorts/libwaffle

    # Embedded GLEW would shadow the system one via -ICommon/Screen, and the
    # glew.c files would be globbed into Screen and moglcore.
    rm -r PsychSourceGL/Source/Common/Screen/glew.c \
      PsychSourceGL/Source/Common/Screen/GL \
      Psychtoolbox/PsychOpenGL/MOGL/source/glew.c \
      Psychtoolbox/PsychOpenGL/MOGL/source/GL

    # Installers and updaters that write into the Psychtoolbox folder.
    rm Psychtoolbox/SetupPsychtoolbox.m \
      Psychtoolbox/UpdatePsychtoolbox.m \
      Psychtoolbox/DownloadPsychtoolbox.m \
      Psychtoolbox/DownloadAdditionsForLinux.m
    find . \( -name simplepsychtoolboxsetup.sh -o -name setupdate.sh \) -delete

    # libgamemode is not on the library search path on NixOS.
    substituteInPlace PsychSourceGL/Source/Linux/Base/gamemode_client.h \
      --replace-fail '"libgamemode.so.0"' '"${lib.getLib gamemode}/lib/libgamemode.so.0"'

    # Upstream calls _exit(123) if /sys/firmware/devicetree exists, to refuse
    # x86 builds under emulation on ARM. Kernels with CONFIG_OF, such as the
    # NixOS default, create a minimal tree on x86 too. A real ARM device tree
    # always has a root compatible property.
    substituteInPlace PsychSourceGL/Source/Common/Base/MiniBox.c \
      --replace-fail '"/sys/firmware/devicetree"' '"/sys/firmware/devicetree/base/compatible"'

    # PsychPortAudio runs pactl through the shell to suspend PulseAudio (or
    # pipewire-pulse) for exclusive ALSA access; pactl is not on PATH by default.
    substituteInPlace PsychSourceGL/Source/Common/PsychPortAudio/PsychPortAudio.c \
      --replace-fail 'system("pactl ' 'system("${lib.getBin pulseaudio}/bin/pactl '

    # The file date is 1970 in the store. Use the date in Contents.m instead.
    substituteInPlace Psychtoolbox/PsychBasic/PsychtoolboxVersion.m \
      --replace-fail 'Psychtoolbox.date = fileinfo.date;' 'Psychtoolbox.date = contentsdate;'

    mkdir -p Psychtoolbox/PsychBasic/Octave5LinuxFiles64
  '';

  # The mex files derive their build number from __DATE__. The 1980 default
  # makes it negative, so use the release date (2026-08-14) instead.
  env.SOURCE_DATE_EPOCH = "1786718859";

  nativeBuildInputs = [
    octave
    pkg-config
  ];

  buildInputs = [
    libGL
    libGLU
    glew
    freeglut
    libx11
    libxext
    libxi
    libxrandr
    libxfixes
    libxcomposite
    libxxf86vm
    libxcb
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    glib
    libxml2
    libdc1394
    libraw1394
    libusb1
    libpciaccess
    alsa-lib
    portaudio
    openal
    apriltag'
    openxr-loader
    vulkan-loader
    vulkan-headers
    freetype
    fontconfig
  ]
  ++ lib.optional withEyelink eyelink-core;

  buildPhase = ''
    runHook preBuild

    export HOME=$TMPDIR OCTAVE_HISTFILE=/dev/null

    # The build script swallows most compile errors, so check its output below.
    pushd PsychSourceGL/Source
    for mode in ${toString modes}; do
      octave-cli --no-init-file --quiet \
        --path "$PWD/../../Psychtoolbox/PsychOneliners" \
        --eval "linuxmakeitoctave3($mode, 1)"
    done
    popd

    for mex in ${toString mexFiles}; do
      if [ ! -s "Psychtoolbox/PsychBasic/Octave5LinuxFiles64/$mex.mex" ]; then
        echo "error: $mex.mex was not built" >&2
        exit 1
      fi
    done

    # Text renderer plugin that Screen dlopen()s from PsychPlugins. Same
    # command as Debian's debian/rules.
    pushd PsychSourceGL/Cohorts/FTGLTextRenderer
    $CXX -I. $(pkg-config --cflags freetype2) -O2 -shared -fPIC \
      -Wl,-Bsymbolic -Wl,-Bsymbolic-functions \
      -Wl,--version-script=linuxexportlist.txt \
      -o libptbdrawtext_ftgl64.so.1 \
      libptbdrawtext_ftgl.cpp qstringqcharemulation.cpp OGLFT.cpp \
      -lGL -lGLU -lfontconfig -lfreetype
    install -Dm755 libptbdrawtext_ftgl64.so.1 -t ../../../Psychtoolbox/PsychBasic/PsychPlugins
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -r Psychtoolbox $out/share/psychtoolbox-3
    # Objects left behind by the mex builds that run inside the m-file tree.
    find $out/share/psychtoolbox-3 \( -name '*.o' -o -name octave-workspace \) -delete

    mkdir -p $out/share/octave-psychtoolbox-3

    substitute ${./octave-startup.m} $out/share/octave-psychtoolbox-3/startup.m \
      --subst-var out

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ (lib.getBin stdenv.cc.libc) ];
  installCheckPhase = ''
    runHook preInstallCheck

    for f in $out/share/psychtoolbox-3/PsychBasic/Octave5LinuxFiles64/*.mex \
      $out/share/psychtoolbox-3/PsychBasic/PsychPlugins/libptbdrawtext_ftgl64.so.1; do
      if ldd "$f" | grep -q 'not found'; then
        echo "error: unresolved libraries in $f" >&2
        ldd "$f" >&2
        exit 1
      fi
    done

    # Screen needs an X display, so it is not called here.
    HOME=$TMPDIR OCTAVE_HISTFILE=/dev/null octave-cli --no-init-file --quiet --eval "
      source('$out/share/octave-psychtoolbox-3/startup.m');
      PsychtoolboxVersion
      GetSecs
      WaitSecs(0.01);
      PsychPortAudio('Version')
    "

  ''
  # No tracker in the sandbox. Dummy mode runs the SDK without a network
  # connection, so it checks that the mex and libeyelink_core work together.
  + lib.optionalString withEyelink ''
    HOME=$TMPDIR OCTAVE_HISTFILE=/dev/null octave-cli --no-init-file --quiet --eval "
      source('$out/share/octave-psychtoolbox-3/startup.m');
      assert(strcmp(which('Eyelink'), '$out/share/psychtoolbox-3/PsychBasic/Octave5LinuxFiles64/Eyelink.mex'));
      Eyelink('Version')
      assert(Eyelink('IsConnected') == 0);
      assert(Eyelink('InitializeDummy') == 0);
      assert(Eyelink('IsConnected') == -1);
      Eyelink('Shutdown');
    "

  ''
  + ''
    runHook postInstallCheck
  '';

  passthru = {
    # Octave script that puts this package on the path. Source it from an
    # octaverc, for example: source("${psychtoolbox-3.octaveStartup}").
    octaveStartup = "${finalAttrs.finalPackage}/share/octave-psychtoolbox-3/startup.m";
  };

  meta = {
    description = "Toolbox for vision and neuroscience experiments in GNU Octave";
    homepage = "https://psychtoolbox.org";
    changelog = "https://github.com/Psychtoolbox-3/Psychtoolbox-3/releases/tag/${finalAttrs.version}";
    # Mostly MIT, with GPL/LGPL parts and some non-commercial material in
    # PsychContributed. See Psychtoolbox/License.txt.
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
