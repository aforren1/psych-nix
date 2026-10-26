{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  psychopy,
}:

buildPythonPackage rec {
  pname = "psychopy-mri-emulator";
  version = "0.0.2";
  pyproject = true;

  src = fetchPypi {
    pname = "psychopy_mri_emulator";
    inherit version;
    hash = "sha256-oQtZVS7PAVdWdRKRe8rXCf6rwS/FtNvi5Ripj8rvWlA=";
  };

  build-system = [ setuptools ];

  dependencies = [ psychopy ];

  # Importing the plugin imports psychopy, which writes ~/.psychopy3, and
  # pyglet.window, which opens a shadow window unless disabled.
  env = {
    PSYCHOPYNOPACKAGES = "1";
    PYGLET_SHADOW_WINDOW = "0";
  };
  preBuild = ''
    export HOME=$TMPDIR
  '';

  # Upstream tests need a display and PsychoPy's Builder.
  doCheck = false;

  pythonImportsCheck = [ "psychopy_mri_emulator" ];

  meta = {
    description = "Software emulator for fMRI scanner sync pulses and responses, for PsychoPy";
    homepage = "https://github.com/psychopy/psychopy-mri-emulator";
    changelog = "https://github.com/psychopy/psychopy-mri-emulator/blob/main/CHANGELOG.txt";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
