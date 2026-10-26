# PsychoPy 2024.2.4. In this release the wx GUI (Builder, Coder, Runner) is
# part of the library (psychopy.app), not a separate psychopy-app package.
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  fetchpatch,

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
  cryptography,
  esprima,
  ffpyplayer,
  freetype-py,
  future,
  gevent,
  gitpython,
  imageio,
  imageio-ffmpeg,
  javascripthon,
  jedi,
  markdown-it-py,
  matplotlib,
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
  pyglet_1_5,
  pyparallel,
  pyqt6,
  pyserial,
  python-bidi,
  python-gitlab,
  python-vlc,
  pyyaml,
  pyzmq,
  questplus,
  requests,
  scipy,
  setuptools,
  soundfile,
  tables,
  ujson,
  websockets,
  wxpython,
  xlib,
  xmlschema,

  # Defaults for shared machines whose home directory is wiped; see postPatch.
  kioskDefaults ? false,
}:

buildPythonPackage rec {
  pname = "psychopy";
  version = "2024.2.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "psychopy";
    repo = "psychopy";
    tag = version;
    hash = "sha256-8qgx+pC4fMBWlpVbrNgMfX7meUFy8kvmc3hhOv3Gj58=";
  };

  patches = [
    # The pypi-search package is gone from PyPI and GitHub, and Builder
    # imports the plugin manager module that imports it. Upstream removed
    # the PyPI search box after this release.
    (fetchpatch {
      name = "remove-pypi-search.patch";
      url = "https://github.com/psychopy/psychopy/commit/e0fda5682b495115e65451fd402c6af21a6ecf85.patch";
      hash = "sha256-cPOteiKGLi84KOIybMDownVChQTEKtrVzhuDCFPLMW4=";
    })
  ];

  # ctypes.util.find_library and bare sonames do not resolve on Nix
  # (https://github.com/NixOS/nixpkgs/issues/7307), so the Linux ctypes
  # loads get absolute paths: iohub mouse (X11, Xfixes), gamma ramps
  # (Xxf86vm) and core.rush (libc).
  #
  # GDK drops a single 256 px icon on X11 (too large for one X request), so
  # the frames end up with no icon; the bundle exports the sizes that fit.
  #
  # kioskDefaults: lab kiosks wipe the home directory every boot, so
  # first-run dialogs would appear every session. It turns Tip of the Day off
  # by default (Linux.spec is loaded at run time, baseNoArch.spec is its
  # source), and treats a first run (no lastVersion in appData, which
  # upstream takes as 1.73.04) as up to date, so no "Changes in" notices.
  postPatch = ''
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
    substituteInPlace psychopy/app/builder/builder.py \
      psychopy/app/coder/coder.py \
      psychopy/app/runner/runner.py \
      --replace-fail "self.SetIcon(wx.Icon(iconFile, wx.BITMAP_TYPE_ICO))" \
                     "self.SetIcons(wx.IconBundle(iconFile, wx.BITMAP_TYPE_ICO))"
  ''
  + lib.optionalString kioskDefaults ''
    substituteInPlace psychopy/preferences/Linux.spec psychopy/preferences/baseNoArch.spec \
      --replace-fail "showStartupTips = boolean(default='True')" \
                     "showStartupTips = boolean(default='False')"
    substituteInPlace psychopy/app/_psychopyApp.py \
      --replace-fail "last = self.prefs.appData['lastVersion'] = '1.73.04'" \
                     "last = self.prefs.appData['lastVersion'] = self.version"
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
    cryptography
    distro
    esprima
    ffpyplayer
    freetype-py
    future
    gevent
    gitpython
    imageio
    imageio-ffmpeg
    javascripthon
    jedi
    markdown-it-py
    matplotlib
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
    pyglet_1_5
    pyparallel
    pyqt6
    pyserial
    python-bidi
    python-gitlab
    python-vlc
    pyyaml
    pyzmq
    questplus
    requests
    scipy
    setuptools
    soundfile
    tables
    ujson
    websockets
    wxpython
    xlib
    xmlschema
  ];

  # setuptools==70.3.0 works around a py2app bug in the macOS build only.
  pythonRelaxDeps = [ "setuptools" ];

  # nixpkgs builds OpenCV from source; it does not provide the
  # opencv-python wheel metadata, only the cv2 module. pypi-search: see
  # patches.
  pythonRemoveDeps = [
    "opencv-python"
    "pypi-search"
  ];

  # The version getter and the import check import psychopy, which writes
  # preferences to ~/.psychopy3 and, unless PSYCHOPYNOPACKAGES=1, adds a user
  # plugin directory to sys.path. psychopy.event opens a pyglet shadow window
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
    description = "Library and wx GUI for running psychology and neuroscience experiments";
    homepage = "https://www.psychopy.org/";
    changelog = "https://github.com/psychopy/psychopy/blob/${src.tag}/psychopy/CHANGELOG.txt";
    license = lib.licenses.gpl3Plus;
    mainProgram = "psychopy";
    platforms = lib.platforms.linux;
  };
}
