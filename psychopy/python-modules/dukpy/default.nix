{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  mock,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "dukpy";
  version = "0.6.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+LHR91xqW+m1JdyA8FtshppnFIG+aJ2hRrLGk3s0UO4=";
  };

  build-system = [ setuptools ];

  nativeCheckInputs = [
    mock
    pytestCheckHook
  ];

  # The source tree's dukpy/ has no compiled _dukpy and would shadow the
  # installed package.
  preCheck = ''
    rm -r dukpy
  '';

  # The sdist omits the fixture files under tests/files.
  disabledTests = [
    "test_evaljs_accepts_file_like_source"
    "test_evaljs_accepts_multiple_file_like_sources"
    "test_less"
  ];

  disabledTestPaths = [
    # Optional webassets integration, not used by PsychoPy.
    "tests/test_webassets_filter.py"
  ];

  pythonImportsCheck = [ "dukpy" ];

  meta = {
    description = "JavaScript interpreter for Python, based on QuickJS";
    homepage = "https://github.com/amol-/dukpy";
    license = lib.licenses.mit;
    mainProgram = "dukpy";
    platforms = lib.platforms.all;
  };
}
