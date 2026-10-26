{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  setuptools-scm,
  numpy,
  scipy,
  xarray,
  json-tricks,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "questplus";
  version = "2023.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-iTN9YTg0+jZdxKGyVJbM8X3rsNbVpWxrEqZH2oGVyo4=";
  };

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    numpy
    scipy
    xarray
    json-tricks
  ];

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "questplus" ];

  meta = {
    description = "QUEST+ adaptive staircase procedure for psychophysics";
    homepage = "https://github.com/hoechenberger/questplus";
    changelog = "https://github.com/hoechenberger/questplus/blob/${version}/CHANGES.md";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
