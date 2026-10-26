# SR Research EyeLink core SDK: the network library between the Display PC
# and the EyeLink Host PC. Psychtoolbox's Eyelink.mex links it.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "eyelink-core";
  version = "2.2.596.0";

  # SR Research's public apt repository; the Packages index lists this file.
  src = fetchurl {
    url = "https://apt.sr-research.com/dists/release_2026/main/binary-amd64/api64/linuxDisplaySoftwareRelease/deb/eyelinkcore_${finalAttrs.version}_amd64.deb";
    hash = "sha256-lH9FVhe6JzaD+0j7etoUWnPVMEC2AEfj+T7ka0ZpCtk=";
  };

  outputs = [
    "out"
    "doc"
  ];

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Keeps the compatibility symlinks (libeyelink_core-1.x.so.*) that the deb
    # ships for programs linked against older SDKs. The static library and
    # the libtool archive are not useful in the store.
    mkdir -p $out/lib
    cp -P usr/lib/x86_64-linux-gnu/libeyelink_core*.so* $out/lib/
    install -Dm644 usr/lib/x86_64-linux-gnu/pkgconfig/eyelink_core.pc -t $out/lib/pkgconfig
    substituteInPlace $out/lib/pkgconfig/eyelink_core.pc \
      --replace-fail "prefix=/usr" "prefix=$out" \
      --replace-fail "libdir=\''${prefix}/lib/x86_64-linux-gnu" "libdir=\''${prefix}/lib"

    mkdir -p $out/include
    cp -r usr/include/EyeLink $out/include/

    mkdir -p $doc/share/doc
    cp -r usr/share/EyeLink/Docs $doc/share/doc/eyelink-core

    runHook postInstall
  '';

  meta = {
    description = "SR Research EyeLink core SDK library (eyelink_core)";
    homepage = "https://www.sr-research.com/support/thread-13.html";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
