{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
}:

buildPythonPackage rec {
  pname = "pyparallel";
  version = "0.2.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-tVUCk69CpC17LhraEiTTw84vCbgOhUIYIOBoZVkIxhE=";
  };

  build-system = [ setuptools ];

  # No tests in the sdist; real tests need /dev/parport*.
  doCheck = false;

  pythonImportsCheck = [ "parallel" ];

  meta = {
    description = "Python parallel port access library";
    homepage = "https://github.com/pyserial/pyparallel";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux ++ lib.platforms.windows;
  };
}
