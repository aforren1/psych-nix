{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # loaded with ctypes
  glibc,
  libx11,
  libxfixes,
  libxxf86vm,

  # build-system
  pdm-backend,
  distro,
  tomlkit,
  packaging,
  six,
  polib,
  typing-extensions,

  # dependencies
  arabic-reshaper,
  astunparse,
  beautifulsoup4,
  esprima,
  ffpyplayer,
  freetype-py,
  gevent,
  i18next,
  imageio,
  imageio-ffmpeg,
  jedi,
  matplotlib,
  meshpy,
  moviepy,
  msgpack,
  msgpack-numpy,
  numpy,
  opencv4,
  openpyxl,
  pandas,
  pillow,
  psutil,
  psychtoolbox,
  pyarrow,
  pyglet_1_5,
  pyparallel,
  pyqt6,
  pyserial,
  python-bidi,
  python-vlc,
  pyyaml,
  pyzmq,
  questplus,
  requests,
  scipy,
  sounddevice,
  soundfile,
  tables,
  ujson,
  websockets,
  xlib,
  xmlschema,
  zope-event,
  zope-interface,

  # Defaults for shared machines whose home directory is wiped; see postPatch.
  kioskDefaults ? false,
}:

buildPythonPackage rec {
  pname = "psychopy";
  version = "2026.2.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "psychopy";
    repo = "psychopy";
    tag = version;
    hash = "sha256-YL9NpDPxtOa3PSxOkoMe+EtDV4Xdf3nzlKCdisskEtY=";
  };

  # psychopy.app.psychopyApp no longer exists; the GUI moved to the separate
  # psychopy-app package, which installs its own `psychopy` script.
  #
  # kioskDefaults: lab kiosks wipe the home directory every boot, so
  # first-run dialogs would appear every session. It turns Tip of the Day off
  # by default; users can still enable it in Preferences. Linux.spec is the
  # file loaded at runtime; baseNoArch.spec is the source it is generated from.
  #
  # ctypes.util.find_library and bare sonames do not resolve on Nix
  # (https://github.com/NixOS/nixpkgs/issues/7307), so the Linux ctypes
  # loads get absolute paths: iohub mouse (X11, Xfixes), gamma ramps
  # (Xxf86vm) and core.rush (libc).
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail '[project.gui-scripts]' "" \
      --replace-fail 'psychopy = "psychopy.app.psychopyApp:main"' ""
    substituteInPlace psychopy/iohub/devices/mouse/linux2.py \
      --replace-fail "cdll.LoadLibrary('libX11.so')" \
                     "cdll.LoadLibrary('${lib.getLib libx11}/lib/libX11.so')" \
      --replace-fail "cdll.LoadLibrary('libXfixes.so')" \
                     "cdll.LoadLibrary('${lib.getLib libxfixes}/lib/libXfixes.so')"
    substituteInPlace psychopy/visual/backends/gamma.py \
      --replace-fail "ctypes.CDLL(ctypes.util.find_library('Xxf86vm'))" \
                     "ctypes.CDLL('${lib.getLib libxxf86vm}/lib/libXxf86vm.so')"
    substituteInPlace psychopy/platform_specific/linux.py \
      --replace-fail "ctypes.cdll.LoadLibrary(ctypes.util.find_library('c'))" \
                     "ctypes.cdll.LoadLibrary('${lib.getLib glibc}/lib/libc.so.6')"
  ''
  + lib.optionalString kioskDefaults ''
    substituteInPlace psychopy/preferences/Linux.spec psychopy/preferences/baseNoArch.spec \
      --replace-fail "showStartupTips = boolean(default='True')" \
                     "showStartupTips = boolean(default='False')"
  '';

  build-system = [
    pdm-backend
    distro
    tomlkit
    packaging
    six
    polib
    typing-extensions
  ];

  dependencies = [
    arabic-reshaper
    astunparse
    beautifulsoup4
    distro
    esprima
    ffpyplayer
    freetype-py
    gevent
    i18next
    imageio
    imageio-ffmpeg
    jedi
    matplotlib
    meshpy
    moviepy
    msgpack
    msgpack-numpy
    numpy
    opencv4
    openpyxl
    packaging
    pandas
    pillow
    psutil
    psychtoolbox
    pyarrow
    pyglet_1_5
    pyparallel
    pyqt6
    pyserial
    python-bidi
    python-vlc
    pyyaml
    pyzmq
    questplus
    requests
    scipy
    sounddevice
    soundfile
    tables
    ujson
    websockets
    xlib
    xmlschema
    zope-event
    zope-interface
  ];

  # Exact pins exist only for the macOS py2app build (see comments in
  # pyproject.toml); Debian relaxes the same ones.
  pythonRelaxDeps = [
    "gevent"
    "zope.event"
    "zope.interface"
  ];

  # nixpkgs builds OpenCV from source; it does not provide the
  # opencv-python wheel metadata, only the cv2 module.
  pythonRemoveDeps = [ "opencv-python" ];

  # The version getter and the import check import psychopy, which writes
  # preferences to ~/.psychopy3 and, unless PSYCHOPYNOPACKAGES=1, adds a user
  # plugin directory to sys.path.
  # psychopy.event imports pyglet.window, which opens a hidden shadow window
  # on import unless told not to; the build has no display.
  env = {
    PSYCHOPYNOPACKAGES = "1";
    PYGLET_SHADOW_WINDOW = "0";
  };

  preBuild = ''
    export HOME=$TMPDIR
  '';

  pythonImportsCheck = [
    "psychopy"
    "psychopy.core"
    "psychopy.data"
    "psychopy.event"
  ];

  # Upstream's suite needs a display, an OpenGL context, audio devices and
  # setcap'd binaries; it runs under xvfb in CI only.
  doCheck = false;

  meta = {
    description = "Library for running psychology and neuroscience experiments";
    homepage = "https://www.psychopy.org/";
    changelog = "https://github.com/psychopy/psychopy/blob/${src.tag}/psychopy/CHANGELOG.txt";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
