# SR Research EDF Access API: reads EyeLink data files (.edf).
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "eyelink-edfapi";
  version = "5.1.607.0";

  # SR Research's public apt repository; the Packages index lists this file.
  src = fetchurl {
    url = "https://apt.sr-research.com/dists/release_2026/main/binary-amd64/api64/linuxDisplaySoftwareRelease/deb/edfapi_${finalAttrs.version}_amd64.deb";
    hash = "sha256-ox/YoFs3Cnzw8wU1knY9xuavBgpCnn1ZarwSAuVgQIg=";
  };

  outputs = [
    "out"
    "doc"
  ];

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The static library is not useful in the store.
    install -Dm755 usr/lib/x86_64-linux-gnu/libedfapi.so -t $out/lib
    install -Dm644 usr/lib/x86_64-linux-gnu/pkgconfig/edfapi.pc -t $out/lib/pkgconfig
    substituteInPlace $out/lib/pkgconfig/edfapi.pc \
      --replace-fail "prefix=/usr" "prefix=$out" \
      --replace-fail "libdir=\''${prefix}/lib/x86_64-linux-gnu" "libdir=\''${prefix}/lib"

    mkdir -p $out/include
    cp -r usr/include/EyeLink $out/include/

    # Manual, C and Java examples, and the Java binding (edfapi.jar).
    mkdir -p $doc/share/doc
    cp -r usr/share/EyeLink/EDF_Access_API $doc/share/doc/eyelink-edfapi

    runHook postInstall
  '';

  meta = {
    description = "SR Research EDF Access API for EyeLink data files";
    homepage = "https://www.sr-research.com/support/thread-13.html";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
