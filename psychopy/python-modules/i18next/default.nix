{
  lib,
  buildPythonPackage,
  fetchPypi,
  flit-core,
}:

buildPythonPackage rec {
  pname = "i18next";
  version = "0.0.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-aTh5KOOw7ArmVd0nYd1IZWeHbOxehp0/OHkbieifK9c=";
  };

  build-system = [ flit-core ];

  # The sdist does not ship the tests.
  doCheck = false;

  pythonImportsCheck = [ "i18next" ];

  meta = {
    description = "Minimal i18next-style translation helper for Python";
    homepage = "https://github.com/lemon-markets/pip-i18next";
    changelog = "https://github.com/lemon-markets/pip-i18next/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "i18next";
    platforms = lib.platforms.all;
  };
}
