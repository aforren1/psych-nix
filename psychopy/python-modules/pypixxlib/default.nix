{
  lib,
  buildPythonPackage,
  python,
  autoPatchelfHook,
  setuptools,
  numpy,
  pypng,
  vpixx-software-tools,
}:

buildPythonPackage {
  pname = "pypixxlib";
  inherit (vpixx-software-tools) version;
  pyproject = true;

  # Not on PyPI. VPixx ships the sdist only inside the software tools deb.
  src = vpixx-software-tools.pypixxlibSrc;

  build-system = [ setuptools ];

  dependencies = [
    numpy
    pypng
  ];

  nativeBuildInputs = [ autoPatchelfHook ];

  # iOne.so (i1Display colorimeter) links against libdpx.so.
  buildInputs = [ vpixx-software-tools ];

  # _libdpx.py loads lib/linux_x86_64/libdpx.so next to itself. That copy is
  # byte-identical to the one in vpixx-software-tools, so link it instead of
  # keeping a second copy. testutilities.so is not used by any module and
  # needs Debian's split libtinfo.
  postInstall = ''
    pkg=$out/${python.sitePackages}/pypixxlib
    rm -r $pkg/lib/mac $pkg/lib/win_amd64 \
      $pkg/lib/linux_x86_64/libdpx.so \
      $pkg/lib/linux_x86_64/testutilities.so
    ln -s ${vpixx-software-tools}/lib/libdpx.so $pkg/lib/linux_x86_64/libdpx.so
    # i1.py looks for the X-Rite calibration files here, but the sdist omits them.
    ln -s ${vpixx-software-tools}/share/vpixx/i1d3Files $pkg/i1d3Files
  '';

  # pypixxlib.shaders needs PsychoPy and PyOpenGL; it is optional.
  pythonImportsCheck = [
    "pypixxlib"
    "pypixxlib.datapixx"
    "pypixxlib.viewpixx"
    "pypixxlib.propixx"
    "pypixxlib.i1"
  ];

  meta = {
    description = "Python interface to VPixx DATAPixx, VIEWPixx and PROPixx devices";
    homepage = "https://www.vpixx.com/manuals/python/html/index.html";
    license = lib.licenses.unfree;
    sourceProvenance = [
      lib.sourceTypes.fromSource
      lib.sourceTypes.binaryNativeCode
    ];
    platforms = [ "x86_64-linux" ];
  };
}
