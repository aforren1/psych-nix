{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  copyDesktopItems,
  imagemagick,
  makeDesktopItem,

  # build-system
  pdm-backend,
  distro,
  packaging,
  polib,
  psychopy,
  six,
  tomlkit,
  typing-extensions,

  # dependencies
  astunparse,
  beautifulsoup4,
  esprima,
  future,
  gitpython,
  jedi,
  markdown-it-py,
  python-gitlab,
  pytz,
  requests,
  setuptools,
  websockets,
  wxpython,

  # Defaults for shared machines whose home directory is wiped; see postPatch.
  kioskDefaults ? false,
}:

buildPythonPackage rec {
  pname = "psychopy-app";
  version = "2026.2.4";
  pyproject = true;

  # PyPI stops at 2026.2.1 and its metadata differs from the tagged tree.
  src = fetchFromGitHub {
    owner = "psychopy";
    repo = "psychopy-app";
    tag = version;
    hash = "sha256-nMzHfGraOe7SYCyQX8As9BceZFwtlIok9zI8iY2l3dQ=";
  };

  # The entry point names psychopy_app:main, but main() lives in
  # psychopy_app.psychopyApp and __init__ does not re-export it.
  #
  # kioskDefaults: lab kiosks wipe the home directory every boot, so
  # first-run dialogs would appear every session. On first run (no
  # lastVersion in appData) upstream assumes 1.73.04 and shows every
  # "Changes in x.y.z" notice since then; kioskDefaults treats a first run as
  # already up to date. Real upgrades still show their notices.
  #
  # GDK drops a single 256 px icon on X11 (too large for one X request), so the
  # frames end up with no icon; the bundle exports the sizes that fit.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'psychopy = "psychopy_app:main"' \
                     'psychopy = "psychopy_app.psychopyApp:main"'
    substituteInPlace src/psychopy_app/builder/builder.py \
      src/psychopy_app/coder/coder.py \
      src/psychopy_app/runner/runner.py \
      --replace-fail "self.SetIcon(wx.Icon(iconFile, wx.BITMAP_TYPE_ICO))" \
                     "self.SetIcons(wx.IconBundle(iconFile, wx.BITMAP_TYPE_ICO))"
  ''
  + lib.optionalString kioskDefaults ''
    substituteInPlace src/psychopy_app/_psychopyApp.py \
      --replace-fail "last = self.prefs.appData['lastVersion'] = '1.73.04'" \
                     "last = self.prefs.appData['lastVersion'] = self.version"
  '';

  build-system = [
    pdm-backend
    distro
    packaging
    polib
    psychopy
    six
    tomlkit
    typing-extensions
  ];

  nativeBuildInputs = [
    copyDesktopItems
    imagemagick
  ];

  dependencies = [
    astunparse
    beautifulsoup4
    esprima
    future
    gitpython
    jedi
    markdown-it-py
    packaging
    psychopy
    python-gitlab
    pytz
    requests
    setuptools
    websockets
    wxpython
  ];

  # Upstream pins every runtime dependency to an exact version. The wxPython
  # pin exists because newer wx releases break the app layout; the 4.2.4 in
  # nixpkgs is from the same 4.2 series.
  pythonRelaxDeps = true;

  # The version getter imports psychopy, which writes preferences to
  # ~/.psychopy3 and, unless PSYCHOPYNOPACKAGES=1, adds a user plugin
  # directory to sys.path. psychopy.event opens a pyglet shadow window on
  # import unless told not to; the build has no display.
  env = {
    PSYCHOPYNOPACKAGES = "1";
    PYGLET_SHADOW_WINDOW = "0";
  };

  preBuild = ''
    export HOME=$TMPDIR
  '';

  # Upstream's Resources/psychopy.desktop is stale (Exec=psychopyApp.py,
  # MimeType=text/x-python), so write a new one. text/x-psyexp is the type
  # that upstream's Resources/psychopy.xml declares for .psyexp files.
  desktopItems = [
    (makeDesktopItem {
      name = "psychopy";
      desktopName = "PsychoPy";
      genericName = "Experiment Builder";
      comment = "Create and run psychology and neuroscience experiments";
      exec = "psychopy %F";
      icon = "psychopy";
      categories = [
        "Science"
        "Education"
      ];
      mimeTypes = [ "text/x-psyexp" ];
      startupNotify = true;
    })
  ];

  # The upstream PNGs are 284 and 567 pixels square; hicolor lookups only
  # match the size directory, so scale them to standard sizes.
  postInstall = ''
    res=src/psychopy_app/Resources
    for size in 256 512; do
      mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
      magick $res/psychopy@2x.png -resize ''${size}x''${size} \
        $out/share/icons/hicolor/''${size}x''${size}/apps/psychopy.png
    done
    install -Dm644 $res/psychopy.xml $out/share/mime/packages/psychopy.xml
  '';

  pythonImportsCheck = [
    "psychopy_app"
    "psychopy_app.psychopyApp"
  ];

  # The tests drive the wx GUI and need a display, a GL context and network
  # access to Pavlovia.
  doCheck = false;

  meta = {
    description = "wxPython Builder, Coder and Runner GUI for PsychoPy";
    homepage = "https://www.psychopy.org/";
    downloadPage = "https://github.com/psychopy/psychopy-app";
    license = lib.licenses.gpl3Plus;
    mainProgram = "psychopy";
    platforms = lib.platforms.linux;
  };
}
