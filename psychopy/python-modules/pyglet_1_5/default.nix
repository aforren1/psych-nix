{
  lib,
  stdenv,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  libGL,
  libGLU,
  libxxf86vm,
  libxi,
  libxinerama,
  libxext,
  libx11,
  glibc,
  gtk2-x11,
  gdk-pixbuf,
  fontconfig,
  freetype,
  openal,
  libpulseaudio,
}:

buildPythonPackage rec {
  pname = "pyglet";
  version = "1.5.27";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    extension = "zip";
    hash = "sha256-TQDgZ0UfOxD9UbaXZP3atlRENyoto0TuKzXwqObr8AU=";
  };

  # The shipped pyproject.toml sets build-backend to a list, which no PEP 517
  # frontend accepts. Dropping it makes the frontend use setup.py.
  #
  # find_library does not work with nix (https://github.com/NixOS/nixpkgs/issues/7307),
  # so load_library is replaced by a lookup of absolute store paths. Names
  # that are not in the table raise ImportError, as upstream does for a
  # missing library, and pyglet then disables that feature.
  #
  # FFmpeg is left out on purpose: pyglet 1.5 only supports FFmpeg 4 and 5,
  # nixpkgs asks new packages not to depend on ffmpeg_4, and PsychoPy plays
  # movies through ffpyplayer, not pyglet.media.
  postPatch = ''
    rm pyproject.toml

    cat >> pyglet/lib.py <<PYEOF

    _nix_libraries = {
        'GL': '${lib.getLib libGL}/lib/libGL.so',
        'EGL': '${lib.getLib libGL}/lib/libEGL.so',
        'GLU': '${lib.getLib libGLU}/lib/libGLU.so',
        'c': '${lib.getLib glibc}/lib/libc.so.6',
        'X11': '${lib.getLib libx11}/lib/libX11.so',
        'Xext': '${lib.getLib libxext}/lib/libXext.so',
        'Xi': '${lib.getLib libxi}/lib/libXi.so',
        'Xinerama': '${lib.getLib libxinerama}/lib/libXinerama.so',
        'Xxf86vm': '${lib.getLib libxxf86vm}/lib/libXxf86vm.so',
        'gdk-x11-2.0': '${lib.getLib gtk2-x11}/lib/libgdk-x11-2.0.so',
        'gdk_pixbuf-2.0': '${lib.getLib gdk-pixbuf}/lib/libgdk_pixbuf-2.0.so',
        'fontconfig': '${lib.getLib fontconfig}/lib/libfontconfig.so',
        'freetype': '${lib.getLib freetype}/lib/libfreetype.so',
        'openal': '${lib.getLib openal}/lib/libopenal.so',
        'pulse': '${lib.getLib libpulseaudio}/lib/libpulse.so',
    }


    def load_library(*names, **kwargs):
        for name in names:
            path = _nix_libraries.get(name)
            if path is not None:
                lib = ctypes.cdll.LoadLibrary(path)
                if _debug_trace:
                    lib = _TraceLibrary(lib)
                return lib
        raise ImportError('Library "%s" not found.' % names[0])
    PYEOF
  '';

  build-system = [ setuptools ];

  # Tests need an OpenGL context and a display.
  doCheck = false;

  pythonImportsCheck = [ "pyglet" ];

  meta = {
    description = "Cross-platform windowing and multimedia library (1.5 series, as pinned by PsychoPy)";
    homepage = "https://pyglet.org/";
    changelog = "https://github.com/pyglet/pyglet/blob/v${version}/RELEASE_NOTES";
    license = lib.licenses.bsd3;
    # The load_library replacement only covers Linux.
    platforms = lib.platforms.linux;
  };
}
