# SR Research PyLink. Binary-only wheel that bundles its own copy of
# libeyelink_core and the SDL2 calibration graphics library.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  python,
  autoPatchelfHook,
  SDL2,
  SDL2_gfx,
  SDL2_mixer,
  SDL2_ttf,
}:

let
  pyTag = "cp${lib.replaceStrings [ "." ] [ "" ] python.pythonVersion}";
  # From the PyPI JSON API. cp312 is built and tested for psychopy-env,
  # cp310 for psychopy-2024-env (Python 3.10 from nixos-24.11).
  hashes = {
    cp310 = "sha256-ad5GpHQ2ZxdQD6s+KxZYkXIU2JyZ+AVnQYicVkiCB+Q=";
    cp312 = "sha256-WRVnT26PtqzYlYIuRLCj2juvZbOhiF6lUnJuCLJuy7U=";
    cp313 = "sha256-9+9QcwEKFsKV03XvWUz+gpOv0v70tL72xEGVZsXeH9I=";
    cp314 = "sha256-i1boN2tVgSm7e+q0agRW8P9LUMAAbqTEHnAs6xjt+Io=";
  };
in
buildPythonPackage rec {
  pname = "sr-research-pylink";
  version = "2.2.596.0";
  format = "wheel";

  src = fetchPypi {
    pname = "sr_research_pylink";
    inherit version format;
    dist = pyTag;
    python = pyTag;
    abi = pyTag;
    platform = "manylinux_2_28_x86_64";
    hash = hashes.${pyTag} or (throw "sr-research-pylink: no wheel hash for ${pyTag}");
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # NEEDED by the bundled libeyelink_core_graphics_sdl2, which pylink loads
  # for openGraphics() (calibration and camera image on the Display PC).
  buildInputs = [
    SDL2
    SDL2_gfx
    SDL2_mixer
    SDL2_ttf
  ];

  pythonImportsCheck = [ "pylink" ];

  meta = {
    description = "Python interface to SR Research EyeLink eye trackers";
    homepage = "https://www.sr-research.com/support/thread-48.html";
    # Free for non-commercial use; not redistributable.
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
