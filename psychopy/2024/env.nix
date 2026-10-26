# Runnable PsychoPy 2024 library environment, like ../env.nix, with the
# packages in ./packages-list.nix and the Mesa of its own nixpkgs (see
# ./gl-wrapper-args.nix).
{
  mesa,
  python,
  # Function from the Python package set to extra packages, for example
  # import ../vendor-list.nix. Appended to the packages in ./packages-list.nix.
  extraPackages ? (ps: [ ]),
}:

(python.buildEnv.override {
  extraLibs = import ./packages-list.nix python.pkgs ++ extraPackages python.pkgs;
  makeWrapperArgs = import ./gl-wrapper-args.nix { inherit mesa; };
}).overrideAttrs
  { name = "psychopy-2024-env"; }
