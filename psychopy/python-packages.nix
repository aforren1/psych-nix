# Python package overlay for the PsychoPy dependency set.
# One attribute per directory under ./python-modules, nixpkgs style.
self: super: {
  # blosc2 (via tables) runs its tests against torch, which is not cached for
  # python312 and would compile torch and triton from source.
  blosc2 = super.blosc2.override { runTorchTests = false; };

  dukpy = self.callPackage ./python-modules/dukpy { };
  ffpyplayer = self.callPackage ./python-modules/ffpyplayer { };
  i18next = self.callPackage ./python-modules/i18next { };
  javascripthon = self.callPackage ./python-modules/javascripthon { };
  liaison-py = self.callPackage ./python-modules/liaison-py { };
  meshpy = self.callPackage ./python-modules/meshpy { };
  psychopy = self.callPackage ./python-modules/psychopy { };
  psychopy-app = self.callPackage ./python-modules/psychopy-app { };
  psychopy-eyetracker-sr-research =
    self.callPackage ./python-modules/psychopy-eyetracker-sr-research
      { };
  # mesa inside the python set is a removed alias; the check needs llvmpipe.
  psychopy-glfw = self.callPackage ./python-modules/psychopy-glfw { inherit (self.pkgs) mesa; };
  psychopy-legacy = self.callPackage ./python-modules/psychopy-legacy { };
  psychopy-mri-emulator = self.callPackage ./python-modules/psychopy-mri-emulator { };
  psychopy-sounddevice = self.callPackage ./python-modules/psychopy-sounddevice { };
  psychopy-visionscience = self.callPackage ./python-modules/psychopy-visionscience { };
  # The python set has its own libusb1 (python-libusb1); PTB needs the C library.
  psychtoolbox = self.callPackage ./python-modules/psychtoolbox { inherit (self.pkgs) libusb1; };
  pyglet_1_5 = self.callPackage ./python-modules/pyglet_1_5 { };
  pyparallel = self.callPackage ./python-modules/pyparallel { };
  pypixxlib = self.callPackage ./python-modules/pypixxlib {
    inherit (self.pkgs) vpixx-software-tools;
  };
  questplus = self.callPackage ./python-modules/questplus { };
  sr-research-pylink = self.callPackage ./python-modules/sr-research-pylink { };
}
