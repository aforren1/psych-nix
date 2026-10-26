{
  lib,
  buildPythonPackage,
  fetchPypi,
  meson-python,
  numpy,
  pybind11,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "meshpy";
  version = "2026.1.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-ITdrM5qdnAF8m7HpEm9llbNEyMd5DgDObUbpKe3Z0v8=";
  };

  build-system = [
    meson-python
    numpy
    pybind11
  ];

  dependencies = [ numpy ];

  nativeCheckInputs = [ pytestCheckHook ];

  # examples/ also holds test_*.py files that need matplotlib.
  enabledTestPaths = [ "test" ];

  # Import the installed package, not the source tree that lacks _internals.
  preCheck = ''
    rm -r meshpy
  '';

  pythonImportsCheck = [
    "meshpy.triangle"
    "meshpy.tet"
  ];

  meta = {
    description = "Triangular and tetrahedral mesh generator (Python bindings for Triangle and TetGen)";
    homepage = "https://github.com/inducer/meshpy";
    changelog = "https://github.com/inducer/meshpy/releases/tag/v${version}";
    # Wrapper: MIT. TetGen: AGPL-3.0-or-later. Triangle: free for
    # non-commercial use only, which nixpkgs treats as unfree.
    license = with lib.licenses; [
      mit
      agpl3Plus
      unfree
    ];
    platforms = lib.platforms.unix;
  };
}
