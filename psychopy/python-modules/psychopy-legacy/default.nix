{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  psychopy,
}:

buildPythonPackage rec {
  pname = "psychopy-legacy";
  version = "1.2.1";
  pyproject = true;

  src = fetchPypi {
    pname = "psychopy_legacy";
    inherit version;
    hash = "sha256-2AQ4Nb29SxbrqF6FPNmHjucvfXppJo51UIndR3JxcTo=";
  };

  build-system = [ setuptools ];

  dependencies = [ psychopy ];

  # Upstream tests need a display and PsychoPy's Builder.
  doCheck = false;

  pythonImportsCheck = [ "psychopy_legacy" ];

  meta = {
    description = "Legacy stimuli and Builder components for PsychoPy";
    homepage = "https://github.com/psychopy/psychopy-legacy";
    changelog = "https://github.com/psychopy/psychopy-legacy/blob/main/CHANGELOG.md";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
