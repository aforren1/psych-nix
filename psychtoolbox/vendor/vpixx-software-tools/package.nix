{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  libedit,
  libusb-compat-0_1,
  libusb1,
  ncurses,
  pkg-config,
}:

let
  # The binaries were linked on Ubuntu against the narrow (non-widec)
  # libncurses.so.6 and need its symbol versions, such as
  # wgetch@NCURSES6_5.0.19991023. nixpkgs ncurses is the wide build.
  ncursesNarrow = ncurses.override { unicodeSupport = false; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "vpixx-software-tools";
  version = "1.13.0";

  # No apt repository and no published checksum. Pin the versioned URL, not
  # the "latest" redirect.
  src = fetchurl {
    url = "https://dqpig6o87oure.cloudfront.net/software/vpixx-setup-${
      lib.replaceStrings [ "." ] [ "-" ] finalAttrs.version
    }.deb";
    hash = "sha256-8m8+fBnMl0xrV1EVtZd8P/3Blg8szkaKtsVh5t5cyDo=";
  };

  # The firmware images are 230 MB and only `vputil` reflashing uses them.
  outputs = [
    "out"
    "firmware"
  ];

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  buildInputs = [
    # First, so that autoPatchelf picks it over the wide ncurses that libedit
    # propagates.
    ncursesNarrow
    (lib.getLib stdenv.cc.cc)
    libedit
    libusb-compat-0_1
    libusb1
  ];

  # The MATLAB mex file links against MATLAB's own libraries.
  autoPatchelfIgnoreMissingDeps = [
    "libmex.so"
    "libmx.so"
  ];

  # LabMaestro (1.2 GB, a Qt app with its own bundled libraries), the PDF
  # manuals and the 3D demo pictures are not needed to drive the hardware.
  unpackPhase = ''
    runHook preUnpack
    mkdir root
    dpkg-deb --fsys-tarfile "$src" | tar --extract --directory=root \
      --exclude=./usr/local/LabMaestro \
      --exclude='*/Documentation' \
      --exclude='*/datafiles'
    runHook postUnpack
  '';

  sourceRoot = "root";

  installPhase = ''
    runHook preInstall

    tools="usr/local/share/VPixx Software Tools/Software Tools"
    share=$out/share/vpixx

    mkdir -p $out/lib/pkgconfig $out/lib/systemd/system $out/lib/udev/rules.d

    install -Dm755 -t $out/bin usr/local/bin/vputil usr/local/bin/vpixxdeviceserver

    install -Dm755 "$tools/libdpx/lib/libdpx.so" -t $out/lib
    # The headers have generic names (error.h, debug.h, libusb.h) that would
    # shadow other libraries in a shared include directory.
    install -Dm644 "$tools/libdpx/include/"*.h -t $out/include/libdpx
    # Every header includes vpmacros.h, but upstream does not ship it. Its
    # only use is the Windows export macro.
    cat > $out/include/libdpx/vpmacros.h <<'H'
    #pragma once
    #define EX_DLL
    H
    # Upstream's CMake config needs a safestring_static target that it does
    # not ship, so supply pkg-config instead.
    cat > $out/lib/pkgconfig/libdpx.pc <<PC
    Name: libdpx
    Description: VPixx DATAPixx, VIEWPixx and PROPixx device library
    Version: ${finalAttrs.version}
    Libs: -L$out/lib -ldpx
    Cflags: -I$out/include/libdpx
    PC

    # Colorimeter SDKs that vpixxdeviceserver links against, under their
    # sonames.
    for l in libi1Pro libi1Pro3 libi1d3; do
      install -Dm755 usr/lib/x86_64-linux-gnu/$l.so $out/lib/$l.so.0
      ln -s $l.so.0 $out/lib/$l.so
    done

    # Only adds the comma that udevadm verify expects between tokens.
    substitute lib/udev/rules.d/70-vpixx.rules $out/lib/udev/rules.d/70-vpixx.rules \
      --replace-fail '" MODE:=' '", MODE:='
    substitute lib/systemd/system/vpixx-device-server.service \
      $out/lib/systemd/system/vpixx-device-server.service \
      --replace-fail /usr/local/bin/vpixxdeviceserver $out/bin/vpixxdeviceserver

    install -Dm644 usr/share/applications/vputil.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/vputil.desktop \
      --replace-fail /usr/local/bin/vputil vputil \
      --replace-fail /usr/share/pixmaps/vputil.png vputil
    install -Dm644 usr/share/pixmaps/vputil.png -t $out/share/pixmaps

    install -Dm755 "$tools/Matlab/mexfiles/linux/matlab/Datapixx.mexa64" -t $share/mex
    install -Dm755 "$tools/Matlab/mexfiles/linux/octave/Datapixx_octave5.mex" $share/mex/Datapixx.mex
    cp -r "$tools/Matlab/DatapixxToolbox" "$tools/i1d3Files" $share/
    install -Dm644 "$tools/pypixxlib/pypixxlib-${finalAttrs.version}.tar.gz" -t $share

    mkdir -p $firmware/share/vpixx
    cp -r "$tools/firmware" $firmware/share/vpixx/

    runHook postInstall
  '';

  # Debian names the libedit soname libedit.so.2; upstream and nixpkgs use
  # libedit.so.0 for the same ABI. Debian splits libtinfo out of libncurses;
  # nixpkgs keeps it in libncurses with the same symbol versions.
  preFixup = ''
    patchelf --replace-needed libedit.so.2 libedit.so.0 $out/bin/vputil
    for f in $out/bin/*; do
      patchelf --replace-needed libtinfo.so.6 libncurses.so.6 "$f"
    done
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    (lib.getBin stdenv.cc.libc)
    pkg-config
  ];
  installCheckPhase = ''
    runHook preInstallCheck

    for f in $out/bin/* $out/lib/*.so* $out/share/vpixx/mex/Datapixx.mex; do
      if ldd "$f" | grep -q 'not found'; then
        echo "error: unresolved libraries in $f" >&2
        ldd "$f" >&2
        exit 1
      fi
    done

    # Proves that the headers and pkg-config file work. The sandbox has no
    # device, so DPxIsReady() returns 0 after DPxOpen().
    cat > test.c <<'C'
    #include "libdpx.h"
    int main(void) { DPxOpen(); return DPxIsReady(); }
    C
    $CC test.c -o test $(pkg-config --cflags --libs $out/lib/pkgconfig/libdpx.pc) -Wl,-rpath,$out/lib
    ./test

    runHook postInstallCheck
  '';

  passthru = {
    datapixxMex = {
      octave = "${finalAttrs.finalPackage}/share/vpixx/mex/Datapixx.mex";
      matlab = "${finalAttrs.finalPackage}/share/vpixx/mex/Datapixx.mexa64";
    };
    pypixxlibSrc = "${finalAttrs.finalPackage}/share/vpixx/pypixxlib-${finalAttrs.version}.tar.gz";
  };

  meta = {
    description = "VPixx DATAPixx, VIEWPixx and PROPixx library, vputil and device server";
    homepage = "https://vpixx.com/our-products/software-tools/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "vputil";
  };
})
