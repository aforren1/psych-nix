{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  wheel,
  numpy,
  alsa-lib,
  gamemode,
  libusb1,
  libx11,
  libxext,
  libxfixes,
  libxi,
  portaudio,
  pulseaudio,
}:

buildPythonPackage rec {
  pname = "psychtoolbox";
  version = "3.0.22.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-Fk1jjoLwWVwWYxDHHXKFn+RD+YjDigvIpCpcBfvw4zo=";
  };

  # setup.py hardcodes the FHS include path for libusb.
  # gamemode is optional and loaded with dlopen at run time; an absolute path
  # makes it work without LD_LIBRARY_PATH.
  # PsychPortAudio runs `pactl` through the shell to suspend PulseAudio (or
  # pipewire-pulse) so it can open the ALSA device exclusively.
  postPatch = ''
    substituteInPlace setup.py \
      --replace-fail "/usr/include/libusb-1.0" "${lib.getDev libusb1}/include/libusb-1.0"
    substituteInPlace PsychSourceGL/Source/Linux/Base/gamemode_client.h \
      --replace-fail '"libgamemode.so.0"' '"${lib.getLib gamemode}/lib/libgamemode.so.0"'
    substituteInPlace PsychSourceGL/Source/Common/PsychPortAudio/PsychPortAudio.c \
      --replace-fail 'system("pactl ' 'system("${lib.getBin pulseaudio}/bin/pactl '

    # Upstream calls _exit(123) if /sys/firmware/devicetree exists, to refuse
    # x86 builds under emulation on ARM. Kernels with CONFIG_OF, such as the
    # NixOS default, create a minimal tree on x86 too. A real ARM device tree
    # always has a root compatible property.
    substituteInPlace PsychSourceGL/Source/Common/Base/MiniBox.c \
      --replace-fail '"/sys/firmware/devicetree"' '"/sys/firmware/devicetree/base/compatible"'
  '';

  build-system = [
    setuptools
    wheel
    numpy
  ];

  buildInputs = [
    alsa-lib
    libusb1
    libx11
    libxext
    libxfixes
    libxi
    portaudio
  ];

  dependencies = [ numpy ];

  # Upstream wheels pin numpy below the next minor release.
  pythonRelaxDeps = [ "numpy" ];

  # PsychPortAudio and PsychHID load without audio or HID hardware.
  pythonImportsCheck = [
    "psychtoolbox"
    "psychtoolbox.GetSecs"
    "psychtoolbox.WaitSecs"
    "psychtoolbox.PsychPortAudio"
    "psychtoolbox.PsychHID"
    "psychtoolbox.IOPort"
  ];

  meta = {
    description = "Python bindings for parts of Psychtoolbox-3 (GetSecs, WaitSecs, PsychPortAudio, PsychHID, IOPort)";
    homepage = "https://psychtoolbox.org";
    changelog = "https://github.com/Psychtoolbox-3/Psychtoolbox-3/releases/tag/${version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
