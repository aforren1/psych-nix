{
  lib,
  buildPythonPackage,
  fetchFromGitLab,
  setuptools,
  dukpy,
  pytestCheckHook,
}:

buildPythonPackage {
  pname = "javascripthon";
  version = "0.13-unstable-2025-05-20";
  pyproject = true;

  # PsychoPy's CI uses this fork. The PyPI 0.13 release pins dukpy<=0.2.3,
  # which is why PsychoPy Studio installs it with --no-deps; the fork works
  # with current dukpy.
  src = fetchFromGitLab {
    owner = "peircej";
    repo = "metapensiero.pj";
    rev = "4bdd1c0bfad67bc820b38faf3b22dacb87fc2a45";
    hash = "sha256-z9J/xxNT/aPvwyebDYBsDRV86ksiMpBHmOJ4TIINJ/c=";
  };

  build-system = [ setuptools ];

  dependencies = [ dukpy ];

  # Listed in install_requires but never imported at runtime.
  pythonRemoveDeps = [ "setuptools" ];

  nativeCheckInputs = [ pytestCheckHook ];

  # Needs the `meta` bytecode decompiler, which nixpkgs does not package.
  disabledTests = [ "test_ast_dump" ];

  pythonImportsCheck = [
    "metapensiero.pj"
    "metapensiero.pj.api"
  ];

  meta = {
    description = "Python 3 to ES6 JavaScript translator";
    homepage = "https://gitlab.com/peircej/metapensiero.pj";
    license = lib.licenses.gpl3Plus;
    mainProgram = "pj";
    platforms = lib.platforms.all;
  };
}
