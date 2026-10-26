{
  description = "Nix packages for PsychoPy and Psychtoolbox-3 (lab experiment software)";

  inputs = {
    # Same pin as the lab fleet flake so machines share one package set.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Final nixos-24.11 commit, only for PsychoPy 2024.2.4 (Python 3.10,
    # numpy 1.26). See overlay-2024.nix. Consumers must not make it follow
    # their nixpkgs.
    nixpkgs-2411.url = "github:NixOS/nixpkgs/50ab793786d9de88ee30ec4e4c24fb4236fc2674";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-2411,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
          config.allowUnfree = true;
        };
    in
    {
      # One overlay, so consumers get the 2024 attributes without extra wiring.
      # The second nixpkgs is only evaluated when a 2024 attribute is used.
      overlays.default = nixpkgs.lib.composeExtensions (import ./overlay.nix) (
        import ./overlay-2024.nix { nixpkgs = nixpkgs-2411; }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Populated by ./overlay.nix. Keep this list in sync with the overlay.
          inherit (pkgs)
            psychopy-env
            psychopy-app
            psychopy-studio
            psychtoolbox-3
            octave-psychtoolbox
            eyelink-core
            eyelink-edfapi
            psychtoolbox-3-eyelink
            octave-psychtoolbox-eyelink
            vpixx-software-tools
            octave-ilp64
            psychtoolbox-3-datapixx
            octave-psychtoolbox-datapixx
            ptb-matlab-mex-builder
            ptb-matlab-mex-builder-lab
            matlab-psychtoolbox
            matlab-psychtoolbox-lab
            psychtoolbox-3-lab
            octave-psychtoolbox-lab
            psychopy-env-lab
            psychopy-app-lab
            psychopy-studio-lab
            psychopy-2024-env
            psychopy-2024-app
            psychopy-2024-env-lab
            psychopy-2024-app-lab
            ;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          psychopy-env = pkgs.psychopy-env;
          psychopy-app = pkgs.psychopy-app;
          psychopy-studio = pkgs.psychopy-studio;
          psychtoolbox-3 = pkgs.psychtoolbox-3;
          octave-psychtoolbox = pkgs.octave-psychtoolbox;
          psychtoolbox-3-lab = pkgs.psychtoolbox-3-lab;
          octave-psychtoolbox-lab = pkgs.octave-psychtoolbox-lab;
          ptb-matlab-mex-builder = pkgs.ptb-matlab-mex-builder;
          psychtoolbox-3-datapixx = pkgs.psychtoolbox-3-datapixx;
          psychopy-env-lab = pkgs.psychopy-env-lab;
          vpixx-software-tools = pkgs.vpixx-software-tools;
          pypixxlib = pkgs.psychopyPackages.pypixxlib;
          psychopy-2024-env = pkgs.psychopy-2024-env;
          psychopy-2024-app = pkgs.psychopy-2024-app;
          psychopy-2024-env-lab = pkgs.psychopy-2024-env-lab;
          psychopy-2024-app-lab = pkgs.psychopy-2024-app-lab;
          psychtoolbox-module = pkgs.testers.runNixOSTest (
            import ./psychtoolbox/nixos-test.nix self.nixosModules.psychtoolbox
          );
          psychtoolbox-x11 = pkgs.testers.runNixOSTest (import ./tests/psychtoolbox-x11.nix);
          psychopy-pytest = pkgs.callPackage ./tests/psychopy-pytest.nix { };
        }
      );

      nixosModules.psychtoolbox = import ./psychtoolbox/nixos-module.nix;

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix-prefetch-git
              nix-prefetch-github
              nixfmt
              xvfb-run
            ];
          };
        }
      );
    };
}
