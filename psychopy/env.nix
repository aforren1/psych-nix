# Runnable PsychoPy library environment: one interpreter with the library,
# the plugins the lab uses, and Lab Streaming Layer.
{
  python,
  # Function from the Python package set to extra packages, for example
  # import ./vendor-list.nix. Appended to the packages in ./packages-list.nix.
  extraPackages ? (ps: [ ]),
}:

(python.buildEnv.override {
  extraLibs = import ./packages-list.nix python.pkgs ++ extraPackages python.pkgs;
}).overrideAttrs
  { name = "psychopy-env"; }
