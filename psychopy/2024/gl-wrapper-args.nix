# makeWrapper arguments that give the 24.11 user space its own Mesa.
# The system's Mesa in /run/opengl-driver comes from nixos-26.05 and needs
# the GLIBC_ABI_GNU2_TLS symbol version of glibc 2.42; glibc 2.40 of 24.11
# cannot load it, so GLX finds no vendor library. LD_LIBRARY_PATH comes before
# the /run/opengl-driver run path of libglvnd, so GLX loads the 24.11 Mesa;
# other GLX vendors (NVIDIA) still load from /run/opengl-driver. EGL (WebKitGTK
# in the Pavlovia login) reads vendor files from the 24.11 Mesa first.
# Limit: Mesa 24.2 predates RDNA4 (gfx12) support, which came in Mesa 25.0.
{ mesa }:
[
  "--prefix"
  "LD_LIBRARY_PATH"
  ":"
  "${mesa.drivers}/lib"
  "--set-default"
  "__EGL_VENDOR_LIBRARY_DIRS"
  "${mesa.drivers}/share/glvnd/egl_vendor.d:/run/opengl-driver/share/glvnd/egl_vendor.d"
]
