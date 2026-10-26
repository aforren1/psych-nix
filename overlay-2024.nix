# PsychoPy 2024.2.4 side by side with 2026.2.4, for experiments written for
# the 2024 release.
#
# The packages come from a second nixpkgs, nixos-24.11. That release is end
# of life since 2025-06-30 and gets no security fixes; it is used only for this
# legacy environment. It is the newest nixpkgs that fits 2024.2.4:
# - Python 3.10: upstream requires >=3.8,<3.11 and tested 3.8 and 3.10.
#   nixos-25.11 numpy dropped 3.10; nixos-25.05 python310 fails to evaluate
#   imageio, moviepy, OpenCV and tables (their test inputs need Sphinx 8.2).
# - numpy 1.26: upstream pins numpy<2.0, and 2024.2.4 calls functions that
#   numpy 2 removed (numpy.product in val2array, np.unicode_ in
#   importConditions). Experiment code written for it may too.
# - moviepy 1.x: Window.saveMovieFrames imports moviepy.editor, which
#   moviepy 2 removed.
# The binary cache has only part of python310Packages; SciPy, OpenCV, PyQt6
# and wxPython compile locally (about one hour on 8 cores). The closure
# (about 3.7 GiB) shares no store paths with the 2026 packages.
#
# The 24.11 user space cannot load the system's 26.05 Mesa, so the 2024
# interpreters bring Mesa 24.2 (psychopy/2024/gl-wrapper-args.nix).
{ nixpkgs }:
final: prev:
let
  inherit (prev) lib;

  old = import nixpkgs {
    system = prev.stdenv.hostPlatform.system;
    config = {
      allowUnfree = prev.config.allowUnfree or false;
    }
    // lib.optionalAttrs (prev.config ? allowUnfreePredicate) {
      inherit (prev.config) allowUnfreePredicate;
    };
    overlays = [
      (oldFinal: oldPrev: {
        # The shared modules use the top-level X11 names of newer nixpkgs.
        libx11 = oldPrev.xorg.libX11;
        libxext = oldPrev.xorg.libXext;
        libxfixes = oldPrev.xorg.libXfixes;
        libxi = oldPrev.xorg.libXi;
        libxinerama = oldPrev.xorg.libXinerama;
        libxxf86vm = oldPrev.xorg.libXxf86vm;
        # pypixxlib takes its sdist and libdpx from the 26.05 package. libdpx
        # needs at most GLIBC_2.30, so it loads in the 24.11 interpreter.
        inherit (final) vpixx-software-tools;
      })
    ];
  };

  python = old.python310.override {
    self = python;
    packageOverrides = import ./psychopy/2024/python-packages.nix;
  };

  # Kiosk defaults, as psychopyPythonLab in ./overlay.nix.
  pythonLab = old.python310.override {
    self = pythonLab;
    packageOverrides = lib.composeExtensions (import ./psychopy/2024/python-packages.nix) (
      self: super: {
        psychopy = super.psychopy.override { kioskDefaults = true; };
      }
    );
  };
in
{
  psychopy2024Python = python;
  psychopy2024Packages = python.pkgs;
  psychopy2024PythonLab = pythonLab;
  psychopy2024PackagesLab = pythonLab.pkgs;

  # old.callPackage: Mesa, the GTK wrapper and its schemas and GIO modules
  # must match the 24.11 glibc and GLib in the interpreter.
  psychopy-2024-env = old.callPackage ./psychopy/2024/env.nix { inherit python; };
  psychopy-2024-app = old.callPackage ./psychopy/2024/app.nix { inherit python; };

  psychopy-2024-env-lab = final.psychopy-2024-env.override {
    python = pythonLab;
    extraPackages = import ./psychopy/vendor-list.nix;
  };
  psychopy-2024-app-lab = final.psychopy-2024-app.override {
    python = pythonLab;
    extraPackages = import ./psychopy/vendor-list.nix;
  };
}
