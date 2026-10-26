{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  gevent,
  numpy,
  psychopy,
  sr-research-pylink,
}:

buildPythonPackage rec {
  pname = "psychopy-eyetracker-sr-research";
  version = "0.0.6";
  pyproject = true;

  src = fetchPypi {
    pname = "psychopy_eyetracker_sr_research";
    inherit version;
    hash = "sha256-e0Hs6GMTe8Wm5IXieRrSkQZ/8FfvNfViLUI9QHp6atw=";
  };

  build-system = [ setuptools ];

  # The ioHub device module imports gevent, numpy and psychopy.iohub, which
  # upstream lists only as test and docs extras.
  dependencies = [
    gevent
    numpy
    psychopy
    sr-research-pylink
  ];

  # Importing the plugin imports psychopy, which writes ~/.psychopy3.
  env.PSYCHOPYNOPACKAGES = "1";
  preBuild = ''
    export HOME=$TMPDIR
  '';

  # No tests in the sdist.
  doCheck = false;

  pythonImportsCheck = [
    "psychopy_eyetracker_sr_research"
    "psychopy_eyetracker_sr_research.sr_research.eyelink"
  ];

  meta = {
    description = "SR Research EyeLink support for PsychoPy ioHub";
    homepage = "https://github.com/psychopy/psychopy-eyetracker-sr-research";
    changelog = "https://github.com/psychopy/psychopy-eyetracker-sr-research/blob/main/CHANGELOG.txt";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
