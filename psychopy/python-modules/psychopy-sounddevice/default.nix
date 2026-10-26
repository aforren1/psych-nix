{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  numpy,
  psychopy,
  sounddevice,
  soundfile,
}:

buildPythonPackage rec {
  pname = "psychopy-sounddevice";
  version = "0.0.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+9a82vNlCpuGL9lflwZXoYyGW4ffSuaEpv+N0T3oLLY=";
  };

  build-system = [ setuptools ];

  dependencies = [
    numpy
    psychopy
    sounddevice
    soundfile
  ];

  # Importing the plugin imports psychopy, which writes ~/.psychopy3.
  env.PSYCHOPYNOPACKAGES = "1";
  preBuild = ''
    export HOME=$TMPDIR
  '';

  # Upstream tests need a display and PsychoPy's Builder.
  doCheck = false;

  pythonImportsCheck = [ "psychopy_sounddevice" ];

  meta = {
    description = "SoundDevice audio backend plugin for PsychoPy";
    homepage = "https://github.com/psychopy/psychopy-sounddevice";
    changelog = "https://github.com/psychopy/psychopy-sounddevice/blob/main/CHANGELOG.txt";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
