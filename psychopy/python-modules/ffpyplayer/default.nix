{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  cython,
  pkg-config,
  ffmpeg_6,
  SDL2,
}:

buildPythonPackage rec {
  pname = "ffpyplayer";
  version = "4.5.3";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-i5Yj4EmXunu/VHYxOqjZ6uJmXGX0A7Xe/0rFHxYVXn4=";
  };

  # Upstream pins Cython 3.0; nixpkgs ships a newer 3.x.
  # The sws_scale cast is upstream commit f6240c3b (after 4.5.3); GCC 14
  # rejects the implicit pointer conversion. The sdist has CRLF line
  # endings, so the commit does not apply as a patch.
  postPatch = ''
    substituteInPlace pyproject.toml setup.py --replace-fail 'cython~=3.0.11' 'cython'
    substituteInPlace ffpyplayer/player/frame_queue.pyx \
      --replace-fail 'sws_scale(player.img_convert_ctx, src_frame.data,' \
                     'sws_scale(player.img_convert_ctx, <const unsigned char* const*>src_frame.data,'
  '';

  build-system = [
    setuptools
    cython
  ];

  nativeBuildInputs = [ pkg-config ];

  # 4.5.3 uses the channel layout API removed in FFmpeg 7 and avfft.h
  # removed in FFmpeg 8.
  buildInputs = [
    ffmpeg_6
    SDL2
  ];

  # Tests decode sample media and open an SDL audio device.
  doCheck = false;

  pythonImportsCheck = [
    "ffpyplayer"
    "ffpyplayer.player"
    "ffpyplayer.pic"
    "ffpyplayer.writer"
  ];

  meta = {
    description = "Cython bindings for FFmpeg-based media playback and writing";
    homepage = "https://matham.github.io/ffpyplayer/";
    changelog = "https://github.com/matham/ffpyplayer/releases/tag/v${version}";
    license = lib.licenses.lgpl3Only;
    platforms = lib.platforms.unix;
  };
}
