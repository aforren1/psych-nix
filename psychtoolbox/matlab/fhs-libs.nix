# Libraries that MATLAB needs to start, from doronbehar/nix-matlab. One list
# for matlab-fhs, matlab-install-fhs and ptb-matlab-mex-builder, so the
# builder starts MATLAB with the same libraries as the fleet's `matlab`.
p: with p; [
  cacert
  alsa-lib
  atk
  glib
  glibc
  cairo
  cups
  dbus
  fontconfig
  # The MathWorks Service Host (licensing, error 5201 without it) loads it
  # directly; fontconfig's dependency is not on the FHS library path.
  freetype
  gdk-pixbuf
  # MATLABWindow (the installer UI, help browser, App Designer) still links
  # GTK 2; without it the installer aborts with exit code 127.
  gtk2
  gtk3
  at-spi2-atk
  at-spi2-core
  nspr
  nss
  pam
  pango
  python3
  libselinux
  libsndfile
  glibcLocales
  procps
  unzip
  zlib
  libdrm
  mesa
  # nixpkgs moved libgbm out of mesa; MATLABWindow (Chromium) needs it.
  libgbm
  gcc
  gfortran
  udev
  ncurses
  libxkbcommon
  xkeyboard_config
  libglvnd
  libGL
  libuuid
  # Not in nix-matlab's list; found with ldd over an R2024a install.
  libcap.lib # core logging library (libmwmps_logging)
  libtool.lib # libltdl, for Database Toolbox ODBC
  gst_all_1.gstreamer # VideoReader
  gst_all_1.gst-plugins-base # libgstapp, also VideoReader
  libsm
  libx11
  libxcb
  libxcomposite
  libxcursor
  libxdamage
  libxext
  libxfixes
  libxft
  libxi
  libxinerama
  libxrandr
  libxrender
  libxt
  libxtst
  libxxf86vm
  libice
]
