# Python package overlay for PsychoPy 2024.2.4 on python310 from nixos-24.11.
# Reuses the shared modules in ../python-modules and changes only what this
# older package set needs.
self: super:
let
  # Upstream test suites of these packages fail in the old tree today:
  # imageio pulls astropy, whose IERS table test depends on the current date;
  # ndindex (via blosc2 and tables) has hypothesis deadline tests that fail
  # under load. The binary cache does not have them for python310, so they
  # build here.
  noCheck = name: super.${name}.overridePythonAttrs { doCheck = false; };

  # Plugin releases from before the 2024.2.4 tag (2024-10-25). Newer
  # releases target newer PsychoPy APIs. Their import checks import psychopy,
  # which writes ~/.psychopy3 and opens a pyglet shadow window unless told
  # not to; the build has no home directory and no display.
  pinPlugin =
    name: pypiName: version: hash:
    (self.callPackage ../python-modules/${name} { }).overridePythonAttrs {
      inherit version;
      src = self.fetchPypi {
        pname = pypiName;
        inherit version hash;
      };
      env = {
        PSYCHOPYNOPACKAGES = "1";
        PYGLET_SHADOW_WINDOW = "0";
      };
      preBuild = ''
        export HOME=$TMPDIR
      '';
    };
in
# blosc2: the shared override uses an argument that 24.11 does not have.
# dukpy: the shared 0.6.0 needs setuptools >= 77; nixpkgs 24.11 has dukpy 0.4.0.
# psychopy-app: the 2024 GUI is part of psychopy.
# liaison-py: only PsychoPy Studio uses it.
(removeAttrs (import ../python-packages.nix self super) [
  "blosc2"
  "dukpy"
  "liaison-py"
  "psychopy"
  "psychopy-app"
])
// {
  blosc2 = noCheck "blosc2";
  imageio = noCheck "imageio";
  moviepy = noCheck "moviepy";
  ndindex = noCheck "ndindex";
  tables = noCheck "tables";

  # pytestCheckHook in 24.11 has no enabledTestPaths; examples/ holds
  # test_*.py files that need matplotlib.
  meshpy = (self.callPackage ../python-modules/meshpy { }).overridePythonAttrs {
    pytestFlagsArray = [ "test" ];
  };

  # The sdist asks for numpy >= 2 at build time (upstream wheels are built
  # against numpy 2 headers and run on numpy 1.x). Building against the
  # numpy 1.26 of this set gives the same runtime compatibility.
  psychtoolbox =
    (self.callPackage ../python-modules/psychtoolbox { inherit (self.pkgs) libusb1; })
    .overridePythonAttrs
      (old: {
        postPatch = old.postPatch + ''
          substituteInPlace pyproject.toml \
            --replace-fail "\"numpy>=2,<3; python_version>='3.9'\"," "\"numpy\","
        '';
      });

  psychopy = self.callPackage ./psychopy { };

  psychopy-legacy =
    pinPlugin "psychopy-legacy" "psychopy_legacy" "1.0.0"
      "sha256-0lCEhQ0l71y/JHZs30dGuQ7oRbhV1e5VCfFWDybIMPU=";
  psychopy-visionscience =
    pinPlugin "psychopy-visionscience" "psychopy_visionscience" "0.0.7"
      "sha256-ZHwZ4l+4xV9bqgtnPn7j4GHuzc6PLDnhKc+f0Epwnao=";
  psychopy-eyetracker-sr-research =
    pinPlugin "psychopy-eyetracker-sr-research" "psychopy_eyetracker_sr_research" "0.0.4"
      "sha256-TfyseuevzmDoWOYzvdmYDrAi+lfBEcRaIS1B6pbXOI8=";
}
