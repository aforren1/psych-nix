{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  psychopy,
}:

buildPythonPackage rec {
  pname = "psychopy-visionscience";
  version = "0.0.10";
  pyproject = true;

  src = fetchPypi {
    pname = "psychopy_visionscience";
    inherit version;
    hash = "sha256-zKELVSPs64X1/GkM0TBdXS1uKICrKhQXZrso328x/70=";
  };

  build-system = [ setuptools ];

  dependencies = [ psychopy ];

  # Upstream tests need a display and PsychoPy's Builder.
  doCheck = false;

  pythonImportsCheck = [ "psychopy_visionscience" ];

  meta = {
    description = "Vision science stimuli and Builder components for PsychoPy";
    homepage = "https://github.com/psychopy/psychopy-visionscience";
    changelog = "https://github.com/psychopy/psychopy-visionscience/blob/main/CHANGELOG.txt";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
