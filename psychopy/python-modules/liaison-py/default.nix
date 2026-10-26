{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  jsonschema,
  websockets,
}:

buildPythonPackage rec {
  pname = "liaison-py";
  version = "1.0.1";
  pyproject = true;

  src = fetchPypi {
    pname = "liaison_py";
    inherit version;
    hash = "sha256-OiMpMzBKi5+ehrrPKzQoVq6mEweR4f2bpqUuk2FWdww=";
  };

  build-system = [ setuptools ];

  dependencies = [ jsonschema ];

  optional-dependencies = {
    websocket = [ websockets ];
  };

  # The sdist does not ship the tests.
  doCheck = false;

  # liaison.websocket needs the optional websocket extra.
  pythonImportsCheck = [
    "liaison"
    "liaison.constants"
  ];

  meta = {
    description = "JSON command bridge between a frontend and a Python backend";
    homepage = "https://github.com/psychopy/liaison";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
