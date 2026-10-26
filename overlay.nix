# Overlay consumed by the fleet flake and by this flake's own `packages`.
# Python packages live in a python package overlay (psychopy/python-packages.nix)
# applied to a fixed interpreter, so every PsychoPy version in the fleet shares
# one dependency set and one binary-cache closure.
final: prev:
let
  # PsychoPy 2026.2.4 requires >=3.10,<3.13. 3.10 is gone from nixos-26.05.
  # 3.12, not 3.11: Hydra builds python312Packages but not python311Packages,
  # so 3.11 would compile scipy, pandas, PyQt6, OpenCV and Arrow locally, and
  # several 3.11 packages (xarray, pyarrow, tables) fail to evaluate because
  # their test inputs need Sphinx 9, which dropped 3.11.
  python = prev.python312.override {
    self = python;
    packageOverrides = import ./psychopy/python-packages.nix;
  };

  # Same package set with kiosk defaults (no first-run Tip of the Day or
  # "Changes in" dialogs) for lab machines whose home directory is wiped
  # every boot. A separate interpreter keeps the base packages identical to
  # upstream behavior for other consumers of this overlay.
  pythonLab = prev.python312.override {
    self = pythonLab;
    packageOverrides = prev.lib.composeExtensions (import ./psychopy/python-packages.nix) (
      self: super: {
        psychopy = super.psychopy.override { kioskDefaults = true; };
        psychopy-app = super.psychopy-app.override { kioskDefaults = true; };
      }
    );
  };
in
{
  psychopyPython = python;
  psychopyPackages = python.pkgs;
  psychopyPythonLab = pythonLab;
  psychopyPackagesLab = pythonLab.pkgs;

  psychopy-env = final.callPackage ./psychopy/env.nix { inherit python; };
  psychopy-app = final.callPackage ./psychopy/app.nix { inherit python; };
  psychopy-studio = final.callPackage ./psychopy/studio/package.nix { inherit python; };

  psychtoolbox-3 = final.callPackage ./psychtoolbox/package.nix { };
  octave-psychtoolbox = final.callPackage ./psychtoolbox/octave-env.nix { };

  # Vendor SDKs. All unfree; fetched from the vendors' public download URLs.
  # Do not push these to a public binary cache.
  eyelink-core = final.callPackage ./psychtoolbox/vendor/eyelink-core/package.nix { };
  eyelink-edfapi = final.callPackage ./psychtoolbox/vendor/eyelink-edfapi/package.nix { };

  # Psychtoolbox with the Eyelink mex, which links the SR Research SDK.
  psychtoolbox-3-eyelink = final.psychtoolbox-3.override { withEyelink = true; };
  octave-psychtoolbox-eyelink = final.octave-psychtoolbox.override {
    psychtoolbox-3 = final.psychtoolbox-3-eyelink;
  };

  vpixx-software-tools = final.callPackage ./psychtoolbox/vendor/vpixx-software-tools/package.nix { };

  # VPixx ships its Octave Datapixx mex prebuilt, built against Ubuntu's
  # Octave 5.2 with a 64-bit mwSize (64-bit indexing). nixpkgs Octave uses
  # 32-bit indexing, so mex calls that take mwSize arrays
  # (mxCreateStructArray and others) get wrong dimensions. The Datapixx and lab variants therefore use an Octave
  # with 64-bit indexing and ILP64 BLAS/LAPACK. Hydra does not build it:
  # the first local build takes about 25 minutes, plus about 7 for the
  # Octave packages in the environment.
  octave-ilp64 = final.octave.override {
    use64BitIdx = true;
    # qrupdate passes its ILP64 Fortran flags as one cmakeFlags string with a
    # space ("-std=legacy -fdefault-integer-8"). Without structured attrs,
    # the string is split and CMake fails on "-fdefault-integer-8".
    qrupdate = final.qrupdate.overrideAttrs { __structuredAttrs = true; };
  };

  # Adds VPixx's prebuilt Datapixx mex files (Octave and MATLAB).
  psychtoolbox-3-datapixx =
    (final.callPackage ./psychtoolbox/with-datapixx.nix { withOctaveMex = true; })
      (final.psychtoolbox-3.override { octave = final.octave-ilp64; });
  octave-psychtoolbox-datapixx = final.octave-psychtoolbox.override {
    octave = final.octave-ilp64;
    psychtoolbox-3 = final.psychtoolbox-3-datapixx;
  };

  # Lab variants: every vendor extra the lab machines need, and for PsychoPy
  # the kiosk-default package set (psychopyPythonLab). ILP64 Octave for
  # the Datapixx mex, see above.
  psychtoolbox-3-lab =
    (final.callPackage ./psychtoolbox/with-datapixx.nix { withOctaveMex = true; })
      (
        final.psychtoolbox-3.override {
          withEyelink = true;
          octave = final.octave-ilp64;
        }
      );
  octave-psychtoolbox-lab = final.octave-psychtoolbox.override {
    octave = final.octave-ilp64;
    psychtoolbox-3 = final.psychtoolbox-3-lab;
  };
  psychopy-env-lab = final.psychopy-env.override {
    python = final.psychopyPythonLab;
    extraPackages = import ./psychopy/vendor-list.nix;
  };
  psychopy-app-lab = final.psychopy-app.override {
    python = final.psychopyPythonLab;
    extraPackages = import ./psychopy/vendor-list.nix;
  };
  psychopy-studio-lab = final.psychopy-studio.override {
    python = final.psychopyPythonLab;
    extraPackages = import ./psychopy/vendor-list.nix;
  };

  # MATLAB: the mex files cannot be built in the store (MATLAB lives in
  # /opt/matlab). The builder runs MATLAB's mex inside an FHS env on a machine
  # that has MATLAB and installs the result under /opt/ptb-matlab; the wrapper
  # starts the fleet's `matlab` with PTB on the path. See psychtoolbox/matlab/.
  ptb-matlab-mex-builder = final.callPackage ./psychtoolbox/matlab/mex-builder.nix { };
  ptb-matlab-mex-builder-lab = final.callPackage ./psychtoolbox/matlab/mex-builder.nix {
    withEyelink = true;
    withDatapixx = true;
  };
  matlab-psychtoolbox = final.callPackage ./psychtoolbox/matlab/matlab-psychtoolbox.nix { };
  matlab-psychtoolbox-lab = final.callPackage ./psychtoolbox/matlab/matlab-psychtoolbox.nix {
    ptb-matlab-mex-builder = final.ptb-matlab-mex-builder-lab;
  };
}
