{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  glfw,
  psychopy,
  python,
  mesa,
  xvfb-run,
}:

buildPythonPackage rec {
  pname = "psychopy-glfw";
  version = "0.0.2";
  pyproject = true;

  src = fetchPypi {
    pname = "psychopy_glfw";
    inherit version;
    hash = "sha256-+yT+2a4Lly7yZwOQndND27P23nh+Zcu4Q7p5lljg9QY=";
  };

  # The window icon lives in psychopy_app, not the library, so without the GUI
  # installed the module raised FileNotFoundError on import and PsychoPy
  # reported a plugin load error at every start. The icon is cosmetic.
  postPatch = ''
    substituteInPlace psychopy_glfw/glfwbackend.py \
      --replace-fail "_WINDOW_ICON_ = Image.open(" \
        "_WINDOW_ICON_ = None
    if os.path.exists(os.path.join(prefs.paths['resources'], 'psychopy.png')): _WINDOW_ICON_ = Image.open(" \
      --replace-fail "if hasattr(glfw, 'set_window_icon'):" \
        "if hasattr(glfw, 'set_window_icon') and _WINDOW_ICON_ is not None:"
  '';

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    glfw
    psychopy
  ];

  # Upstream tests need PsychoPy's Builder. The module calls glfw.init() on
  # import, which needs an X display, so the import check runs under Xvfb
  # instead of pythonImportsCheck.
  # Importing psychopy imports pyglet.window, whose shadow window needs GLX;
  # the sandbox has no GL driver, so use Mesa llvmpipe.
  nativeCheckInputs = [
    mesa.llvmpipeHook
    xvfb-run
  ];

  checkPhase = ''
    runHook preCheck
    export HOME=$TMPDIR PSYCHOPYNOPACKAGES=1
    pushd $TMPDIR
    PYTHONPATH=$out/${python.sitePackages}:$PYTHONPATH \
      xvfb-run -a ${python.interpreter} -c "import psychopy_glfw"
    popd
    runHook postCheck
  '';

  meta = {
    description = "GLFW window backend plugin for PsychoPy";
    homepage = "https://github.com/psychopy/psychopy-glfw";
    changelog = "https://github.com/psychopy/psychopy-glfw/releases/tag/${version}";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
