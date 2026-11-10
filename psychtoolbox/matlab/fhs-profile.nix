# Shell profile shared by matlab-fhs, matlab-install-fhs and
# ptb-matlab-mex-builder, next to the shared library list (fhs-libs.nix).
#
# The MathWorks Service Host (licensing; MATLAB stops with error 5201 without
# it) dlopens libraries that request an executable stack. glibc 2.41 and
# later refuse that by default ("cannot enable executable stack"); mode 2
# restores the old behavior for processes in this environment only.
''
  export GLIBC_TUNABLES="glibc.rtld.execstack=2''${GLIBC_TUNABLES:+:$GLIBC_TUNABLES}"
''
