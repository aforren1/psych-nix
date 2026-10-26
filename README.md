# PsychoPy and Psychtoolbox-3 for Nix

This flake packages PsychoPy and Psychtoolbox-3 (PTB) for the lab NixOS fleet.
It supplies an overlay, a NixOS module, and NixOS VM tests.
It also packages the SR Research (EyeLink) and VPixx vendor software. These packages are unfree.
For MATLAB, it supplies a builder for the PTB mex files and a MATLAB wrapper. MATLAB itself is not in the store.

- nixpkgs: `nixos-26.05`. This is the same pin as the fleet flake (`~/claude-nix-mgmt`).
- Second nixpkgs: `nixos-24.11`, only for PsychoPy 2024.2.4. See [PsychoPy 2024.2.4](#psychopy-202424).
- System: `x86_64-linux` only.
- Python: 3.12 (3.10 for PsychoPy 2024.2.4). Octave: 11.1.

The document has four parts:

1. [Tutorial](#tutorial-get-started): build and run each package one time.
2. [How-to guides](#how-to-guides): do specific tasks.
3. [Reference](#reference): inputs, outputs, attributes, options, files, and variables.
4. [Explanation](#explanation): design decisions, patches, and known limits.

## Tutorial: get started

You need Nix with flakes enabled. Run all commands from the repository root.

1. Build the PsychoPy library environment:

   ```sh
   nix build .#psychopy-env
   ```

2. Import PsychoPy with the environment's interpreter:

   ```sh
   result/bin/python -c "from psychopy import visual"
   ```

3. Start the PsychoPy GUI (Builder, Coder, and Runner). This step needs a display.

   ```sh
   nix run .#psychopy-app
   ```

4. Build Octave with Psychtoolbox and show the PTB version:

   ```sh
   nix build .#octave-psychtoolbox
   result/bin/octave --eval "PsychtoolboxVersion"
   ```

## How-to guides

### Run the VM tests

The VM tests need `/dev/kvm`.

- Test a real X server: a PsychoPy window, a PTB `Screen` window, a sweep of PTB demos and tests, the wx app, and Studio (offline), all as a normal user.
  The wx app subtest runs `psychopy-app-lab` and makes sure that no first-run dialogs show (see [Patches](#patches)).
  The test also runs a PsychoPy 2024 window and `psychopy-2024-app-lab`, and makes sure that the 2024 and 2026 GUIs install side by side.
  The screenshots go into the `result` directory. The sweep takes about 3 minutes, and the full check about 9 minutes. See [Upstream tests](#upstream-tests).

  ```sh
  nix build .#checks.x86_64-linux.psychtoolbox-x11
  ```

- Test the NixOS module (groups, udev rules, PAM limits, modprobe, drirc, GameMode, Octave):

  ```sh
  nix build .#checks.x86_64-linux.psychtoolbox-module
  ```

- Build all packages and run all tests:

  ```sh
  nix flake check
  ```

### Run the PsychoPy test suite

The `psychopy-pytest` check runs the PsychoPy upstream tests in the build sandbox. It does not need `/dev/kvm`. It takes about 6.5 minutes.

```sh
nix build .#checks.x86_64-linux.psychopy-pytest
```

The `result` directory contains `junit.xml`, `pytest.log`, and `summary.txt`. `summary.txt` lists the unexpected failures and the expected failures that now pass.
To update the baseline after a PsychoPy or nixpkgs update, follow the steps in the header comment of `tests/psychopy-pytest.nix`. See also [Upstream tests](#upstream-tests).

### Use the packages in the fleet flake

1. Add this flake as an input. Make it follow the fleet's nixpkgs, because the pins are the same:

   ```nix
   inputs.lab-pkgs = {
     url = "github:aforren1/psych-nix";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

   Do not add a `follows` for `nixpkgs-2411`. The PsychoPy 2024 packages need the 24.11 pin. See [Run PsychoPy 2024.2.4 next to 2026](#run-psychopy-202424-next-to-2026).

2. In the NixOS configuration of each lab machine, add the overlay and the module:

   ```nix
   { inputs, pkgs, ... }:
   {
     nixpkgs.overlays = [ inputs.lab-pkgs.overlays.default ];
     imports = [ inputs.lab-pkgs.nixosModules.psychtoolbox ];

     programs.psychtoolbox = {
       enable = true;
       users = [ "bw" ];
     };

     environment.systemPackages = [ pkgs.psychopy-app ];
   }
   ```

   `psychopy-app` shows the upstream first-run dialogs. On machines that erase the home directory at each boot, use `psychopy-app-lab` (step 3). It has the kiosk defaults. See [Patches](#patches).

3. On machines with an EyeLink or VPixx device, use the `-lab` variants and the VPixx tools. Replace the settings from step 2 with:

   ```nix
   programs.psychtoolbox = {
     enable = true;
     users = [ "bw" ];
     package = pkgs.psychtoolbox-3-lab;
     octavePackage = pkgs.octave-psychtoolbox-lab;
     vpixx.enable = true;
   };

   environment.systemPackages = [ pkgs.psychopy-app-lab ];
   ```

   `octave-psychtoolbox-lab` uses `octave-ilp64`, an Octave with 64-bit indexes. The Octave Datapixx mex file needs it.
   Hydra does not build `octave-ilp64`. The first local build takes about 24 minutes. See [Vendor SDKs](#vendor-sdks).

4. Allow unfree licenses, for example with `nixpkgs.config.allowUnfree = true;`.
   PsychoPy depends on `meshpy` (the Triangle library), which is unfree.
   All vendor packages and `-lab` variants are unfree. Do not push them to a public binary cache.
5. Remove the fleet modules that this flake replaces:
   - `ptb-realtime.nix`: the module sets the same group and PAM limits. It also installs the udev rules that `ptb-realtime.nix` has as a TODO. Keep the `threadirqs` kernel parameter if you need it. The module does not set it.
   - `experiment-software.nix`: the FHS environment that installs PsychoPy with pip at first run. `psychopy-app` and `psychopy-env` replace it.
6. Resolve the GameMode settings. The fleet's `gamemode.nix` sets `renice = 10` and `softrealtime = "auto"`. The module sets `renice = 20` and `softrealtime = "off"`, from PTB's `gamemode.ini`. Different values at the same priority cause an evaluation error. Remove the fleet settings, or set `programs.psychtoolbox.enableGamemode = false;`.

Use the same module on machines that run only PsychoPy. The Python `PsychHID` and `PsychPortAudio` modules need the same device access and realtime limits.

### Run PsychoPy 2024.2.4 next to 2026

Use PsychoPy 2024.2.4 only for experiments that do not run on 2026.2.4. Its packages come from nixos-24.11, which is end of life. For the reasons and the costs, see [PsychoPy 2024.2.4](#psychopy-202424).

1. Add the flake as in step 1 of [Use the packages in the fleet flake](#use-the-packages-in-the-fleet-flake). Make only `nixpkgs` follow the fleet. Do not make `nixpkgs-2411` follow a different nixpkgs.
2. Add `pkgs.psychopy-2024-app-lab` to `environment.systemPackages`, next to `pkgs.psychopy-app-lab`. On machines without EyeLink or VPixx devices that keep the home directory, you can use `psychopy-2024-app` and `psychopy-app`.
3. Start PsychoPy 2024 with `psychopy-2024`, or from the desktop menu entry "PsychoPy 2024.2.4". Its interpreter is `python3.10`. The commands `psychopy`, `python`, and `python3` stay with 2026. For `.psyexp` files, the file manager shows 2024 under "Open with". 2026 stays the default application.
4. Do not add `psychopy-2024-env` to `environment.systemPackages`. It has `bin/python` and `bin/psychopy`, the same file names as the 2026 package. NixOS ignores the collision, so one package hides the file of the other. Use `psychopy-2024-env` only with its full path, for example from `nix build .#psychopy-2024-env`.

### Build the Psychtoolbox mex files for MATLAB

MATLAB is not in the store, so Nix cannot build the PTB mex files for MATLAB. Build them one time on a reference machine that has MATLAB, then copy them to the other machines. For the design, see [MATLAB](#matlab).

1. In the fleet flake, add `pkgs.matlab-psychtoolbox-lab` to `environment.systemPackages` of each machine that has MATLAB at `/opt/matlab/<release>` (fleet module `lab.matlab`). Add `pkgs.ptb-matlab-mex-builder-lab` only on the reference machine, because its closure is about 3.7 GiB. Use one flake revision on all machines, because the mex files refer to exact store paths.
   Without EyeLink or VPixx devices, you can use `matlab-psychtoolbox` and `ptb-matlab-mex-builder`. Both pairs write to the same folder, so use one pair on all machines. If your release is not `R2024b`, use `pkgs.matlab-psychtoolbox-lab.override { release = "<release>"; }`.
2. On the reference machine, check the build environment. This step does not start MATLAB. The last line must be `check-env: all checks passed`.

   ```sh
   ptb-matlab-mex-builder --check-env
   ```

3. Make the output folder, then build and install the mex files. Replace `R2024b` with your release. To show the commands without a build, add `--dry-run`.

   ```sh
   sudo install -d -o "$USER" /opt/ptb-matlab
   ptb-matlab-mex-builder --release R2024b
   ```

   If a mex file is missing after the build, the builder stops and keeps the old files. To keep the temporary build folder for examination, add `--keep`.
4. Make sure that MATLAB loads the mex files. The output must show `/opt/ptb-matlab/3.0.22.3/R2024b/PsychBasic/Screen.mexa64`.

   ```sh
   matlab-psychtoolbox -batch "disp(which('Screen')); disp(GetSecs); PsychtoolboxVersion"
   ```

5. Copy `/opt/ptb-matlab` to the other machines in the same way as `/opt/matlab`, for example with `rsync -a`.

After a flake update, `matlab-psychtoolbox` can print that the mex files "were built for other store libraries". Then do steps 2 to 5 again.

### Use the flake from Git

After you push the repository to a Git host, Nix can use the flake from its URL. In the examples, replace `<owner>/<repo>` with the repository path.

- Run or build a package without a local copy:

  ```sh
  nix run github:<owner>/<repo>#psychopy-app
  nix build github:<owner>/<repo>#psychtoolbox-3
  ```

- Use the flake as an input of a different flake: set `url = "github:<owner>/<repo>";` and add the overlay and the module. See [Use the packages in the fleet flake](#use-the-packages-in-the-fleet-flake).

Know these limits:

- Unfree licenses: the flake's own outputs allow unfree packages. If you apply the overlay to your nixpkgs, you must allow unfree packages, for example with `nixpkgs.config.allowUnfree = true;`. `meshpy` and all vendor packages are unfree.
- Tracked files: Nix copies only the files that Git tracks. Commit and push each new file, for example a patch, a `.m` file, or a `.c` file. If Git does not track a file, the build cannot find it.
- Binary cache: without a cache that has these packages, Nix builds wxPython (about 10 minutes), `octave-ilp64` (about 24 minutes), and the PsychoPy 2024 packages (about 66 minutes on 8 cores) locally. If you make a public cache, do not push the vendor packages or the `-lab` variants to it.
- Other sites: the base attributes, for example `psychopy-app`, have the upstream behavior. To make a site variant, override the Python set, for example `psychopyPython.override { packageOverrides = ...; }`. `psychopyPythonLab` in `overlay.nix` is an example.
- VM tests: the two VM checks need `/dev/kvm`. GitHub-hosted Linux runners supply it. See [Run the checks on GitHub Actions](#run-the-checks-on-github-actions).

### Run the checks on GitHub Actions

After you push the repository to GitHub, two workflows in `.github/workflows/` run. For the design, see [Continuous integration](#continuous-integration).

- `Checks` (`checks.yml`) runs `nix flake check` for each push and pull request. It needs no secrets.
- `MATLAB mex files` (`matlab-mex.yml`) builds the PTB mex files for MATLAB and loads them in MATLAB. It runs for each push that changes a file in `psychtoolbox/`. To select a MATLAB release, start it manually (`workflow_dispatch`) and set `release`, for example `R2025a`. The default is `R2024b`. The mex files are in the artifact `ptb-matlab-mex-<release>`. In a public repository, the workflow needs no secret. In a private repository, add a MATLAB batch licensing token as the repository secret `MLM_LICENSE_TOKEN`.

### Add a PsychoPy plugin

1. Make a directory `psychopy/python-modules/<name>/` with a `default.nix`. Copy `psychopy/python-modules/psychopy-legacy/default.nix` as a start.
2. If `pythonImportsCheck` imports `psychopy`, set `env.PSYCHOPYNOPACKAGES = "1";` and `export HOME=$TMPDIR` in `preBuild`. See `psychopy/python-modules/psychopy-sounddevice/default.nix`.
3. Add one line to `psychopy/python-packages.nix`:

   ```nix
   <name> = self.callPackage ./python-modules/<name> { };
   ```

4. Add `<name>` to the list in `psychopy/packages-list.nix`. `psychopy-env` and `psychopy-app` both use this list.
5. Build `psychopy-env` and `psychopy-app`.

PsychoPy 2024 uses its own list, `psychopy/2024/packages-list.nix`. To add the plugin there, use a release from before the 2024.2.4 tag (2024-10-25). See `pinPlugin` in `psychopy/2024/python-packages.nix`.

### Add a vendor package

Vendor packages are unfree. Thus `psychopy-env`, `psychopy-app`, and `psychopy-studio` do not contain them.
The vendor Python packages are in a separate list, `psychopy/vendor-list.nix`. The `-lab` variants of `psychopy-env`, `psychopy-app`, and `psychopy-studio` are the base packages plus this list. They also use `psychopyPythonLab`, which has the kiosk defaults.
`psychopy-2024-env-lab` and `psychopy-2024-app-lab` add the same list on Python 3.10. Thus a new vendor Python package must also build for Python 3.10.

1. Write the package. Fetch the file from the vendor's public URL with a fixed hash, for example with `fetchurl` or `fetchPypi`.
   Set `meta.license = lib.licenses.unfree;` and `meta.sourceProvenance`.
   - Python package: write `psychopy/python-modules/<name>/default.nix` and add one line to `psychopy/python-packages.nix`. See `psychopy/python-modules/sr-research-pylink/default.nix`.
   - C library or tool: write `psychtoolbox/vendor/<name>/package.nix`. Add the attribute to `overlay.nix` and to the `packages` list in `flake.nix`. See `psychtoolbox/vendor/eyelink-core/package.nix`.
2. Add a Python package to `psychopy/vendor-list.nix`. Do not add it to `psychopy/packages-list.nix`.
3. Build `psychopy-env-lab` and `psychopy-app-lab`.

The `-lab` variants set the `python` and `extraPackages` arguments of `psychopy/env.nix`, `psychopy/app.nix`, and `psychopy/studio/package.nix`.
`extraPackages` is a function from the Python package set to a list of packages. The function result is added to the packages from `psychopy/packages-list.nix`.

In the machine configuration, select the lab variant:

```nix
environment.systemPackages = [ pkgs.psychopy-app-lab ];
```

To add only some vendor packages, override the base package:

```nix
environment.systemPackages = [
  (pkgs.psychopy-app.override { extraPackages = ps: [ ps.pypixxlib ]; })
];
```

If a vendor supplies a file only after a login, use `requireFile` instead of a fetcher. Each user then adds the file to the store manually.

### Update a version

| Package | File | Attributes to change |
|---|---|---|
| `psychopy` | `psychopy/python-modules/psychopy/default.nix` | `version`, `src.hash` |
| `psychopy-app` | `psychopy/python-modules/psychopy-app/default.nix` | `version`, `src.hash` |
| `psychtoolbox-3` | `psychtoolbox/package.nix` | `version`, `src.hash`, `env.SOURCE_DATE_EPOCH` (release date) |
| `psychtoolbox` (Python) | `psychopy/python-modules/psychtoolbox/default.nix` | `version`, `src.hash` |
| `psychopy-studio` | `psychopy/studio/package.nix` | `version`, `src.hash`, `npmDepsHash` |
| `eyelink-core`, `eyelink-edfapi` | `psychtoolbox/vendor/<name>/package.nix` | `version`, `src.hash`. The `src.url` path contains the release year. |
| `vpixx-software-tools`, `pypixxlib` | `psychtoolbox/vendor/vpixx-software-tools/package.nix` | `version`, `src.hash`. `pypixxlib` uses the same version. |
| `sr-research-pylink` | `psychopy/python-modules/sr-research-pylink/default.nix` | `version`, each hash in `hashes` |
| `psychopy-eyetracker-sr-research` | `psychopy/python-modules/psychopy-eyetracker-sr-research/default.nix` | `version`, `src.hash` |

1. Set the new `version`.
2. Set each hash to `lib.fakeHash`.
3. Build the package. The build fails and prints the correct hash after `got:`.
4. Copy the hash into the file. Do steps 3 and 4 again for each hash.
5. If a `substituteInPlace --replace-fail` or a patch fails, examine the upstream change and update the substitution or the patch.
6. Run `nix flake check`.

### Do a headless smoke test of PsychoPy

Xvfb can run PsychoPy windows. It cannot run PTB `Screen` windows (see [Known limits](#known-limits)).

```sh
nix build .#psychopy-env
nix develop --command xvfb-run -a -s "-screen 0 1280x1024x24" \
  result/bin/python -c "from psychopy import visual; w = visual.Window(size=(400, 300)); w.flip(); w.close()"
```

Without `gamemoded`, the output contains `GameMode ERROR: D-Bus error` lines. You can ignore them. For an explanation, see [Patches](#patches).

## Reference

### Flake inputs

| Input | Pin | Use |
|---|---|---|
| `nixpkgs` | Branch `nixos-26.05` | All packages except PsychoPy 2024.2.4. Same pin as the fleet. A consumer can make it follow its nixpkgs. |
| `nixpkgs-2411` | Commit `50ab793786d9de88ee30ec4e4c24fb4236fc2674`, the last nixos-24.11 commit | Only PsychoPy 2024.2.4. End of life since 2025-06-30. Do not make it follow a different nixpkgs. |

### Flake outputs

| Output | Content |
|---|---|
| `overlays.default` | The overlays in `overlay.nix` and `overlay-2024.nix`, composed. Nix evaluates `nixpkgs-2411` only when you use a 2024 attribute. |
| `packages.x86_64-linux.psychopy-env` | Python environment with PsychoPy, the lab plugins, and `pylsl`. |
| `packages.x86_64-linux.psychopy-app` | PsychoPy wx GUI (`bin/psychopy`), with the same interpreter as `bin/python`. |
| `packages.x86_64-linux.psychopy-studio` | PsychoPy Studio (Electron GUI). Runs offline with a venv on the Nix Python. |
| `packages.x86_64-linux.psychtoolbox-3` | PTB m-file tree, Octave mex files, and plugins. |
| `packages.x86_64-linux.octave-psychtoolbox` | Octave environment with PTB on the path. |
| `packages.x86_64-linux.psychopy-env-lab`, `psychopy-app-lab`, `psychopy-studio-lab` | The base package with the kiosk defaults (`psychopyPythonLab`) plus the vendor Python packages in `psychopy/vendor-list.nix`. Unfree. |
| `packages.x86_64-linux.psychopy-2024-env`, `psychopy-2024-app` | PsychoPy 2024.2.4 on Python 3.10 from `nixpkgs-2411`. The app command is `psychopy-2024`. See [PsychoPy 2024.2.4](#psychopy-202424). |
| `packages.x86_64-linux.psychopy-2024-env-lab`, `psychopy-2024-app-lab` | The 2024 package with the kiosk defaults and the vendor Python packages. Unfree. |
| `packages.x86_64-linux.psychtoolbox-3-lab`, `octave-psychtoolbox-lab` | PTB with the Eyelink mex file and the Datapixx mex files for MATLAB and Octave. Uses `octave-ilp64`. Unfree. |
| `packages.x86_64-linux.psychtoolbox-3-eyelink`, `octave-psychtoolbox-eyelink` | PTB with the Eyelink mex file. Unfree. |
| `packages.x86_64-linux.psychtoolbox-3-datapixx`, `octave-psychtoolbox-datapixx` | PTB with the Datapixx mex files for MATLAB and Octave. Uses `octave-ilp64`. Unfree. |
| `packages.x86_64-linux.octave-ilp64` | Octave 11.1 with 64-bit indexes, for the Octave Datapixx mex file. |
| `packages.x86_64-linux.eyelink-core`, `eyelink-edfapi`, `vpixx-software-tools` | Vendor SDKs. Unfree. |
| `packages.x86_64-linux.ptb-matlab-mex-builder`, `ptb-matlab-mex-builder-lab` | Command `ptb-matlab-mex-builder`: builds the PTB mex files with a MATLAB outside the store. The `-lab` variant adds Eyelink and Datapixx. It is unfree. |
| `packages.x86_64-linux.matlab-psychtoolbox`, `matlab-psychtoolbox-lab` | Command `matlab-psychtoolbox`: starts the fleet's MATLAB with PTB on the path. |
| `checks.x86_64-linux.<package>` | Builds of `psychopy-env`, `psychopy-app`, `psychopy-studio`, `psychtoolbox-3`, `octave-psychtoolbox`, `psychtoolbox-3-lab`, `octave-psychtoolbox-lab`, `ptb-matlab-mex-builder`, `psychtoolbox-3-datapixx`, `psychopy-env-lab`, `vpixx-software-tools`, `pypixxlib` (`psychopyPackages.pypixxlib`), and the four `psychopy-2024-*` packages. |
| `checks.x86_64-linux.psychtoolbox-module` | NixOS VM test of the module. |
| `checks.x86_64-linux.psychtoolbox-x11` | NixOS VM test with a real X server. Includes the PTB demo sweep and the PsychoPy 2024 subtests. See [Upstream tests](#upstream-tests). |
| `checks.x86_64-linux.psychopy-pytest` | PsychoPy upstream test suite against `psychopy-env`, in the build sandbox. See [Upstream tests](#upstream-tests). |
| `nixosModules.psychtoolbox` | The `programs.psychtoolbox` module. |
| `formatter.x86_64-linux` | `nixfmt-tree`. Run `nix fmt` from a Git checkout to format every Nix file in the repository. Outside Git, treefmt cannot find the project root and walks the parent directories. |
| `devShells.x86_64-linux.default` | `nix-prefetch-git`, `nix-prefetch-github`, `nixfmt`, `xvfb-run`. |

### Overlay attributes

| Attribute | Version | Content |
|---|---|---|
| `psychopyPython` | 3.12 | `python312` with the package overrides in `psychopy/python-packages.nix`. |
| `psychopyPackages` | | `psychopyPython.pkgs`. See the table below. |
| `psychopyPythonLab` | 3.12 | `psychopyPython` with `kioskDefaults = true` for `psychopy` and `psychopy-app`. |
| `psychopyPackagesLab` | | `psychopyPythonLab.pkgs`. |
| `psychopy-env` | 2026.2.4 | `psychopyPython.buildEnv` with `psychopy/packages-list.nix`. |
| `psychopy-app` | 2026.2.4 | Wrapped `psychopy` launcher and `python`. |
| `psychopy-studio` | 2026.2.3 | Electron 42 app. Its Python venv uses the packages of `psychopy-env`. |
| `psychtoolbox-3` | 3.0.22.3 | Mex files built from source against the nixpkgs Octave 11.1 (32-bit indexes). |
| `octave-psychtoolbox` | 3.0.22.3 | Octave with PTB, the Octave packages `image`, `signal`, `statistics`, `optim`, and `io` (installed, not loaded), GStreamer plugins, and gnuplot for the plotting demos. |
| `psychtoolbox-3-eyelink` | 3.0.22.3 | `psychtoolbox-3` with `withEyelink = true`: adds the Eyelink mex file, linked to `eyelink-core`. |
| `octave-psychtoolbox-eyelink` | 3.0.22.3 | `octave-psychtoolbox` with `psychtoolbox-3-eyelink`. |
| `octave-ilp64` | 11.1 | nixpkgs `octave` with `use64BitIdx = true` (64-bit indexes, ILP64 BLAS and LAPACK). Sets `__structuredAttrs = true` on `qrupdate` (see [Vendor SDKs](#vendor-sdks)). Hydra does not build it. |
| `psychtoolbox-3-datapixx` | 3.0.22.3 | `psychtoolbox-3` built against `octave-ilp64`, with `Datapixx.mexa64` and `Datapixx.mex` from `vpixx-software-tools`. See `psychtoolbox/with-datapixx.nix`. |
| `octave-psychtoolbox-datapixx` | 3.0.22.3 | `octave-psychtoolbox` on `octave-ilp64` with `psychtoolbox-3-datapixx`. |
| `psychtoolbox-3-lab` | 3.0.22.3 | `psychtoolbox-3` with `withEyelink = true`, built against `octave-ilp64`, with both Datapixx mex files. |
| `octave-psychtoolbox-lab` | 3.0.22.3 | `octave-psychtoolbox` on `octave-ilp64` with `psychtoolbox-3-lab`. The Octave packages are built for `octave-ilp64`. |
| `ptb-matlab-mex-builder` | 3.0.22.3 | FHS environment that builds modes 0, 1, 2, 3, 5, 6, 8, 9, 10, 11, 15, and 16 of `linuxmakeit64.m` with `/opt/matlab/<release>/bin/matlab`. Arguments: `matlabRoot` (default `"/opt/matlab"`), `defaultOut` (default `"/opt/ptb-matlab"`), `withEyelink`, `withDatapixx`, and `matlabFhsLibs` (keep it the same as `fhsLibs` in the fleet's `matlab.nix`). |
| `ptb-matlab-mex-builder-lab` | 3.0.22.3 | `ptb-matlab-mex-builder` with `withEyelink = true` (mode 4, `Eyelink.mexa64`) and `withDatapixx = true` (VPixx's prebuilt `Datapixx.mexa64`). Unfree. |
| `matlab-psychtoolbox` | 3.0.22.3 | Shell script around the fleet's `matlab`. Runs `startup.m` before the `-r` or `-batch` command. Arguments: `release` (default `"R2024b"`), `mexDir` (default `/opt/ptb-matlab/<ptbVersion>/<release>/PsychBasic`), `matlab` (default `null`: `matlab` from `PATH`), and `preloadLibstdcxx` (default `true`, see [MATLAB](#matlab)). |
| `matlab-psychtoolbox-lab` | 3.0.22.3 | `matlab-psychtoolbox` for the mex files of `ptb-matlab-mex-builder-lab`. |
| `psychopy-env-lab`, `psychopy-app-lab`, `psychopy-studio-lab` | | The base package with the kiosk defaults (`python = psychopyPythonLab`) and the vendor extras (`extraPackages = import ./psychopy/vendor-list.nix`). |
| `psychopy2024Python`, `psychopy2024Packages` | 3.10 | `python310` from `nixpkgs-2411` with the package overrides in `psychopy/2024/python-packages.nix`, and its package set (`.pkgs`). |
| `psychopy2024PythonLab`, `psychopy2024PackagesLab` | 3.10 | `psychopy2024Python` with `kioskDefaults = true` for `psychopy`, and its package set. |
| `psychopy-2024-env` | 2024.2.4 | `psychopy2024Python.buildEnv` with `psychopy/2024/packages-list.nix` and the 24.11 Mesa. Has `bin/python` and `bin/psychopy`. |
| `psychopy-2024-app` | 2024.2.4 | Command `psychopy-2024`, `bin/python3.10`, `psychopy-2024.desktop`, and the icon `psychopy-2024`. No `bin/python`, no MIME definition. |
| `psychopy-2024-env-lab`, `psychopy-2024-app-lab` | 2024.2.4 | The 2024 package with `python = psychopy2024PythonLab` and `extraPackages = import ./psychopy/vendor-list.nix`. |
| `eyelink-core` | 2.2.596.0 | SR Research EyeLink core SDK: `libeyelink_core`, headers in `include/EyeLink`, and a pkg-config file. The manuals are in the `doc` output. |
| `eyelink-edfapi` | 5.1.607.0 | SR Research EDF Access API (`libedfapi`) to read EyeLink data files. The manual, examples, and Java binding are in the `doc` output. |
| `vpixx-software-tools` | 1.13.0 | `libdpx` (headers in `include/libdpx`, pkg-config file), `vputil`, `vpixxdeviceserver` and its systemd unit, and `70-vpixx.rules`. `share/vpixx/` has `mex`, `DatapixxToolbox`, the `pypixxlib` sdist, and `i1d3Files`. The firmware images are in the `firmware` output. LabMaestro is not installed. |

Packages added to `psychopyPackages`:

| Package | Version | Note |
|---|---|---|
| `psychopy` | 2026.2.4 | Library. Argument `kioskDefaults` (default `false`). |
| `psychopy-app` | 2026.2.4 | wx GUI. Argument `kioskDefaults` (default `false`). |
| `pyglet_1_5` | 1.5.27 | Upstream pins pyglet 1.5.27 on Linux. |
| `psychtoolbox` | 3.0.22.2 | PTB Python bindings: GetSecs, WaitSecs, PsychPortAudio, PsychHID, IOPort. |
| `ffpyplayer` | 4.5.3 | Linked to FFmpeg 6. 4.5.3 does not build with FFmpeg 7 or 8. |
| `questplus`, `meshpy`, `i18next`, `pyparallel` | | Dependencies of `psychopy`. |
| `psychopy-sounddevice`, `psychopy-legacy`, `psychopy-visionscience`, `psychopy-mri-emulator` | | Plugins in `psychopy-env` and `psychopy-app`. |
| `psychopy-glfw` | 0.0.2 | GLFW window backend plugin. Not in `psychopy/packages-list.nix` (see [Known limits](#known-limits)). |
| `javascripthon` | | In `psychopy/packages-list.nix`. Builder's PsychoJS export needs it. |
| `liaison-py`, `dukpy` | | Dependencies of `psychopy-studio`. |
| `sr-research-pylink` | 2.2.596.0 | SR Research PyLink. PyPI wheel that bundles `libeyelink_core` and the SDL2 calibration graphics library. The file has hashes for cp310, cp312, cp313, and cp314. Only cp312 and cp310 (PsychoPy 2024) are built and tested. Unfree. In `psychopy/vendor-list.nix`. |
| `psychopy-eyetracker-sr-research` | 0.0.6 | ioHub EyeLink plugin. GPL-3.0, but it depends on `sr-research-pylink`. In `psychopy/vendor-list.nix`. |
| `pypixxlib` | 1.13.0 | VPixx Python library. Built from the sdist in `vpixx-software-tools`. Its `libdpx.so` is a symlink into `vpixx-software-tools`. Unfree. In `psychopy/vendor-list.nix`. |

`psychopy2024Packages` uses the same overrides, without `blosc2`, `dukpy`, `liaison-py`, and `psychopy-app`. It changes `psychopy` (2024.2.4, library and wx GUI), `psychtoolbox` (built against NumPy 1.26), and `psychopy-legacy` 1.0.0, `psychopy-visionscience` 0.0.7, and `psychopy-eyetracker-sr-research` 0.0.4. See [PsychoPy 2024.2.4](#psychopy-202424).

PTB mex files in `psychtoolbox-3`: `Screen`, `GetSecs`, `WaitSecs`, `PsychPortAudio`, `IOPort`, `PsychHID`, `moglcore`, `moalcore`, `pnet`, `PsychCV`, `PsychVulkanCore`, `PsychOpenXRCore`.
Built only in the `-eyelink` and `-lab` variants: `Eyelink`.
Added only in the `-datapixx` and `-lab` variants: `Datapixx.mexa64` for MATLAB and `Datapixx.mex` for Octave, prebuilt by VPixx. The Octave file works only on `octave-ilp64` (see [Vendor SDKs](#vendor-sdks)).
Not built: PsychKinectCore, PsychOpenHMDVRCore, PsychOculusVRCore, RPiGPIOMex, and the Wayland variants.

### Options of `ptb-matlab-mex-builder`

`--release RELEASE` selects the MATLAB release folder under `/opt/matlab`. A build needs it. `--out DIR` sets the root of the output (default `/opt/ptb-matlab`). `--modes "LIST"` selects modes of `linuxmakeit64.m`, separated by spaces. Modes 7, 12, 13, and 14 are not supported. `--keep` keeps the temporary build folder. `--dry-run` prints the commands and the `mex` calls, which Octave expands with the stub functions in `dry-run/`. `--check-env` checks the tools, the pkg-config modules, the `#include` lines of each source file (`gcc -E` with the flags of its `mex` call), and the library of each `-l` flag, and that the probes of MATLAB's compiler detection (`which gcc`, `gcc -dumpversion`, `gcc -print-file-name=libstdc++.so`) work under a clean `PATH`. `--dry-run` and `--check-env` do not start MATLAB. `--mex-setup --release RELEASE` starts MATLAB and prints how `mex` finds the compiler (`mex -v -setup`, MATLAB's `PATH`, and the release's `gcc_glnxa64.xml`); it does not build and does not fail when MATLAB reports an error.

A build writes to `<out>/<ptbVersion>/<release>/`: `PsychBasic/*.mexa64`, `runtime-path` (the `DT_RPATH` value), `runtime` (GC root), and `build-info.txt`.

### NixOS module options

| Option | Type | Default | Effect |
|---|---|---|---|
| `programs.psychtoolbox.enable` | bool | `false` | Enables the module. |
| `programs.psychtoolbox.package` | package | `pkgs.psychtoolbox-3` | Source of the udev rules, drirc, and modprobe files. |
| `programs.psychtoolbox.octavePackage` | package | `pkgs.octave-psychtoolbox` | Added to `environment.systemPackages`. |
| `programs.psychtoolbox.group` | string | `"psychtoolbox"` | Group with realtime limits and GPU register access. |
| `programs.psychtoolbox.users` | list of strings | `[ ]` | Users added to the group and to `dialout`, `lp`, `video`, and `gamemode`. An empty list causes a warning. |
| `programs.psychtoolbox.enableGamemode` | bool | `true` | Enables GameMode with the settings from PTB's `gamemode.ini`. |
| `programs.psychtoolbox.enableDeepColor` | bool | `true` | Sets `deep_color=1` for `amdgpu` and `radeon`, and installs PTB's drirc as `/etc/drirc`. |
| `programs.psychtoolbox.enableOpenXR` | bool | `false` | Enables Monado as the default OpenXR runtime. |
| `programs.psychtoolbox.vpixx.enable` | bool | `false` | Installs `vpixx.package` and its udev rules (`70-vpixx.rules`, which also cover X-Rite i1Display and i1Pro colorimeters). Does not need `programs.psychtoolbox.enable`. |
| `programs.psychtoolbox.vpixx.package` | package | `pkgs.vpixx-software-tools` | VPixx software tools package. |
| `programs.psychtoolbox.vpixx.deviceServer.enable` | bool | `false` | Starts `vpixx-device-server.service` as the system user `vpixxds`. Needs `vpixx.enable`. The server listens on `0.0.0.0:9827`. The module does not open this port in the firewall. |

When enabled, the module also does these steps:

- Installs `psychtoolbox.rules`, `60-vpixx-permissions.rules`, and `60-cambridgeresearch-permissions.rules`. The `chmod` and `chgrp` paths point to `coreutils`.
- Sets PAM limits for the group: `nice -20`, `rtprio 50`, `memlock unlimited`.
- Blacklists the `lp` kernel module, so that PTB can use the parallel port through `ppdev`.

### Files

| Path | Content |
|---|---|
| `flake.nix` | Inputs and outputs. Composes the two overlays. |
| `overlay.nix` | Overlay. Selects the Python interpreter. |
| `overlay-2024.nix` | Overlay for PsychoPy 2024.2.4. Imports `nixpkgs-2411` and selects `python310`. |
| `psychopy/python-packages.nix` | Python package overrides. One line for each package. |
| `psychopy/python-modules/<name>/default.nix` | One Python package. |
| `psychopy/packages-list.nix` | Python packages in each PsychoPy environment. |
| `psychopy/vendor-list.nix` | Unfree vendor Python packages. The `-lab` variants add them through `extraPackages`. |
| `psychopy/env.nix` | `psychopy-env`. |
| `psychopy/app.nix` | `psychopy-app`. |
| `psychopy/studio/` | `psychopy-studio` and its patch. |
| `psychopy/2024/python-packages.nix` | Python package overrides for 2024. Imports `psychopy/python-packages.nix` and changes some packages. |
| `psychopy/2024/psychopy/default.nix` | `psychopy` 2024.2.4 (library and wx GUI). |
| `psychopy/2024/packages-list.nix` | Python packages in each PsychoPy 2024 environment. |
| `psychopy/2024/env.nix`, `psychopy/2024/app.nix` | `psychopy-2024-env`, `psychopy-2024-app`. |
| `psychopy/2024/gl-wrapper-args.nix` | Wrapper arguments that give the 2024 interpreters the 24.11 Mesa. |
| `psychtoolbox/package.nix` | `psychtoolbox-3`. |
| `psychtoolbox/patches/` | PTB patches. `eyelink-pkg-config.patch` applies only with `withEyelink = true`. |
| `psychtoolbox/vendor/<name>/package.nix` | Vendor SDKs: `eyelink-core`, `eyelink-edfapi`, `vpixx-software-tools`. |
| `psychtoolbox/with-datapixx.nix` | Function that adds the VPixx Datapixx mex files to a `psychtoolbox-3` package. `withOctaveMex = true` adds the Octave file. |
| `psychtoolbox/vendor/vpixx-software-tools/mex-soversion.c` | Empty C file. `with-datapixx.nix` compiles it into the library that supplies `__octave_mex_soversion__` to the Octave Datapixx mex file. |
| `psychtoolbox/octave-startup.m` | Octave script that puts PTB on the path. |
| `psychtoolbox/matlab/mex-builder.nix` | `ptb-matlab-mex-builder`. |
| `psychtoolbox/matlab/mex-builder.sh` | Run script of `ptb-matlab-mex-builder`. |
| `psychtoolbox/matlab/patches/matlab-nolm.patch` | Changes `linuxmakeit64.m` for a build without license management. |
| `psychtoolbox/matlab/dry-run/` | Octave stub functions for `--dry-run` and `--check-env`. |
| `psychtoolbox/matlab/matlab-psychtoolbox.nix` | `matlab-psychtoolbox`. |
| `psychtoolbox/matlab/startup.m` | MATLAB script that puts PTB and the mex folder on the path. |
| `psychtoolbox/octave-env.nix` | `octave-psychtoolbox`. |
| `psychtoolbox/nixos-module.nix` | `programs.psychtoolbox`. |
| `psychtoolbox/nixos-test.nix` | `psychtoolbox-module` check. |
| `tests/psychtoolbox-x11.nix` | `psychtoolbox-x11` check. `expectedPass` lists the sweep entries that must pass. |
| `tests/ptb-sweep.m` | PTB demo and test sweep of the `psychtoolbox-x11` check. The header comment tells how to run it with a different list. |
| `tests/psychopy-pytest.nix` | `psychopy-pytest` check. The header comment tells how to update the baseline. |
| `.github/workflows/checks.yml` | Workflow that runs `nix flake check`. |
| `.github/workflows/matlab-mex.yml` | Workflow that builds the PTB mex files with a MATLAB from `setup-matlab`, then loads them. |

### Environment variables set by wrappers

| Variable | Value | Set in |
|---|---|---|
| `GST_PLUGIN_SYSTEM_PATH_1_0` | GStreamer base, good, bad, ugly, and libav plugins, prepended | `octave` and `octave-cli` in `octave-psychtoolbox` and its variants, `matlab-psychtoolbox` |
| `GST_PLUGIN_SCANNER` | `gst-plugin-scanner` of the same GStreamer | `octave` and `octave-cli` in `octave-psychtoolbox` and its variants, `matlab-psychtoolbox` |
| `LD_PRELOAD` | `libstdc++.so.6` of the store GCC, prepended | `matlab-psychtoolbox` with `preloadLibstdcxx = true` |
| `UV_OFFLINE`, `UV_NO_CACHE`, `UV_NO_CONFIG` | `1` | `psychopy-studio` |
| `UV_PYTHON_DOWNLOADS` | `never` | `psychopy-studio` |
| `LD_LIBRARY_PATH` | `lib` of the 24.11 Mesa drivers, prepended | All programs in `psychopy-2024-env`, `psychopy-2024-app`, and their `-lab` variants |
| `__EGL_VENDOR_LIBRARY_DIRS` | EGL vendor files of the 24.11 Mesa, then `/run/opengl-driver/share/glvnd/egl_vendor.d`. Set only if the variable is not set. | Same as `LD_LIBRARY_PATH` |
| `XDG_DATA_DIRS` | `adwaita-icon-theme`, appended | `psychopy` in `psychopy-app`, `psychopy-2024` in `psychopy-2024-app`, and their `-lab` variants |

The wrappers do not set `PYGLET_SHADOW_WINDOW`. Some package builds set `PYGLET_SHADOW_WINDOW=0` only for their import checks. See [Patches](#patches).

### Closure sizes

| Package | Closure |
|---|---|
| `psychopy-env` | about 3.5 GiB |
| `psychopy-app` | about 4.0 GiB |
| `psychopy-studio` | about 4.2 GiB |
| `psychopy-2024-env`, `psychopy-2024-app` | about 3.7 GiB each. Shares no store paths with the 2026 packages. |
| `psychopy-2024-app-lab` | about 3.8 GiB |
| `psychtoolbox-3` | about 2.5 GiB, mostly Octave |
| `ptb-matlab-mex-builder` | about 3.7 GiB. Install it only on the machine that builds the mex files. |
| `vpixx-software-tools` | about 78 MiB. The `firmware` output (about 232 MiB) is separate. Only `vputil` uses it, to reflash devices. |

## Explanation

### Package set design

The overlay applies the Python package overrides to one interpreter. All PsychoPy packages share one dependency set and one binary cache closure. `psychopyPythonLab` is a second package set that changes only `psychopy` and `psychopy-app` (`kioskDefaults = true`). Thus only these packages and the packages that depend on them are different derivations. The other packages, for example NumPy and wxPython, are the same. `psychopy-env`, `psychopy-app`, and `psychopy-studio` read the same list, `psychopy/packages-list.nix`. Thus an experiment runs with the same packages in each of them. The Runner and Coder start experiments with `sys.executable`. Thus `psychopy-app` puts the GUI and the library in one interpreter.

PsychoPy 2026.2.4 requires Python `>=3.10,<3.13`. nixos-26.05 does not have Python 3.10. Python 3.11 is not satisfactory for two reasons:

- Hydra does not build `python311Packages`. Thus SciPy, pandas, PyQt6, OpenCV, and Arrow would compile locally.
- `xarray`, `pyarrow`, `tables`, `moviepy`, and `pyzmq` do not evaluate for 3.11. Their test inputs need Sphinx 9, which does not support 3.11.

### Patches

PTB (Octave package and Python bindings):

- **Device tree check.** PTB calls `_exit(123)` if `/sys/firmware/devicetree` exists. This prevents x86 builds under emulation on ARM. NixOS kernels have `CONFIG_OF`, so x86 machines also have this directory. The patch checks `/sys/firmware/devicetree/base/compatible`. A real ARM device tree always has this file.
- **pactl.** `PsychPortAudio` runs `pactl` to suspend PulseAudio for exclusive ALSA access. `pactl` is not on `PATH` by default, so the patch uses an absolute path.
- **GameMode.** PTB loads `libgamemode` with `dlopen`. The patch uses an absolute path. As a result, `libgamemode` always loads. If `gamemoded` does not run, `libgamemode` prints `GameMode ERROR: D-Bus error` lines. These lines are harmless.
- **PsychLinuxConfiguration.m.** The original script uses `sudo` to write to `/etc`. The patched script only prints a hint to use the NixOS module.
- **Installers removed.** `SetupPsychtoolbox.m`, `UpdatePsychtoolbox.m`, `DownloadPsychtoolbox.m`, and `DownloadAdditionsForLinux.m` write into the PTB folder. The store is read-only, so the build removes them.
- **Debian patches.** Ported from Debian 3.0.22.3+dfsg-4: pkg-config instead of FHS include paths, system GLEW instead of the embedded copy, no NVIDIA 3D Vision (`libnvstusb`).
- **PsychCV.** Upstream builds PsychCV only if `/usr/include/apriltag` exists, and links `libapriltag-utils`. Upstream apriltag does not install that library. The patch builds PsychCV always and links only `libapriltag`.
- **apriltag override.** The nixpkgs apriltag includes demos and a Python module that add OpenCV (about 1 GB) to the closure. The override removes them.

PsychoPy:

- **pyglet 1.5.27.** `ctypes.util.find_library` does not work with Nix. The patch replaces `load_library` with a table of store paths. pyglet's FFmpeg support is not in the table, because PsychoPy plays movies through `ffpyplayer`. The upstream `dev` branch requires `pyglet >= 2, < 3` and Python `<3.15`; 2026.2.4 fails on pyglet 2.1 (`pyglet.canvas` was removed). At the next release, drop `pyglet_1_5` and use the nixpkgs pyglet.
- **ctypes library paths.** Four Linux `ctypes` loads use `ctypes.util.find_library` or a bare soname. These do not resolve on Nix. The patch uses store paths: `libX11` and `libXfixes` for the ioHub mouse, `libXxf86vm` for gamma ramps, and `libc` for `core.rush`. Without the patch, the ioHub mouse and gamma ramps fail.
- **wxPython.** `psychopy-app` pins `wxPython==4.2.5`. Newer wx releases break the app layout. nixpkgs has 4.2.4, from the same 4.2 series, and the package uses it.
- **gevent, zope.event, zope.interface.** Upstream pins exact versions only for the macOS build. Debian relaxes the same pins.
- **pyglet shadow window.** pyglet opens a hidden shadow window. PsychoPy uses it to share the GL context between windows. With `PYGLET_SHADOW_WINDOW=0`, a window that opens after another window closes has no GL context, and TextBox2 text in it is garbled (8 tests failed). Thus the run-time wrappers do not set the variable. The `psychopy`, `psychopy-app`, and `psychopy-mri-emulator` builds set it only for the import checks, because the build has no display.
  Rigs with separate X screens for each display (PTB style, the fleet's `dual` machines) still need `PYGLET_SHADOW_WINDOW=0`: the shadow window opens on the default X screen, and GL contexts cannot share across X screens. Set it in the machine configuration of those rigs, for example `environment.variables.PYGLET_SHADOW_WINDOW = "0";`, and keep the trade-off in mind: on such a rig, do not close and reopen windows in one session, and do not use TextBox2 in more than one window. This is not yet verified on a dual-screen rig.
- **javascripthon.** Builder's PsychoJS export uses `javascripthon` to translate Python code components to JavaScript. Without it, the export of auto-translated code fails. Thus `psychopy/packages-list.nix` includes it.
- **psychopy-glfw.** The package exists, but `psychopy/packages-list.nix` does not include it. Its only release, 0.0.2, is older than the PsychoPy 2026 backend API: `GLFWBackend` has no `mouseVisible`, so `winType='glfw'` fails. The patch makes the window icon optional, because the icon is in `psychopy-app`. Without the patch, the import fails when `psychopy-app` is not installed. The module calls `glfw.init()` at import, so the import check runs under Xvfb with Mesa llvmpipe.
- **First-run dialogs (opt-in).** Lab kiosks erase the home directory at each boot. Thus first-run dialogs would show at each session. The `kioskDefaults` argument of the `psychopy` and `psychopy-app` Python packages changes two defaults: Tip of the Day is off by default, and on a first run, the app does not show the "Changes in" notices. Real upgrades still show them. The default is `false`, so the base packages have the upstream behavior. The `-lab` variants use `psychopyPythonLab`, which sets `kioskDefaults = true`. The `psychtoolbox-x11` test checks these defaults in `psychopy-app-lab`.

### PsychoPy 2024.2.4

Some experiments need PsychoPy 2024.2.4. `overlay-2024.nix` builds it from a second nixpkgs, `nixpkgs-2411`, the last nixos-24.11 commit. nixos-24.11 is end of life since 2025-06-30 and gets no security fixes. The flake uses it only for this environment. It is the newest nixpkgs that satisfies three requirements of 2024.2.4. First, Python `<3.11`: nixos-26.05 does not have Python 3.10, the nixos-25.11 NumPy does not support 3.10, and the nixos-25.05 `python310` cannot evaluate imageio, moviepy, OpenCV, and tables (their test inputs need Sphinx 8.2). Second, NumPy `<2`: 2024.2.4 calls functions that NumPy 2 removed, for example `numpy.product` and `np.unicode_`, and experiment code written for 2024 can call them too. Upstream completed NumPy 2 support only in 2026. Third, moviepy 1.x: `Window.saveMovieFrames` imports `moviepy.editor`, which moviepy 2 removed.

Mesa: the fleet's Mesa 26.1 in `/run/opengl-driver` needs the `GLIBC_ABI_GNU2_TLS` symbol version of glibc 2.42. The glibc 2.40 of 24.11 cannot load it. Thus the 2024 wrappers bring Mesa 24.2.8 from 24.11 (`psychopy/2024/gl-wrapper-args.nix`). `LD_LIBRARY_PATH` comes before the `/run/opengl-driver` run path of libglvnd, so GLX loads the 24.11 Mesa. Other GLX vendors, for example NVIDIA, still load from `/run/opengl-driver`. For EGL (WebKitGTK in the Pavlovia login), `__EGL_VENDOR_LIBRARY_DIRS` puts the 24.11 Mesa first. `bin/python3.10` has the same wrapper as the launcher, because the Runner and Coder start experiments with `sys.executable`.

Side by side: NixOS merges `environment.systemPackages` and ignores file name collisions. Thus a shared file name lets one package hide the file of the other package without an error. Each file name in `psychopy-2024-app` is different from the 2026 package: `bin/psychopy-2024`, `bin/python3.10`, `psychopy-2024.desktop` (name "PsychoPy 2024.2.4"), and the icon `psychopy-2024`. The desktop file lists `text/x-psyexp`, but the package has no MIME XML. Thus the 2026 package owns the MIME type and stays the default application. Both versions use `~/.psychopy3`, as the upstream standalone installers do. There is no Studio for 2024.

Patches and changes for 2024:

- **pypi-search.** The package is no longer on PyPI, but Builder imports the plugin manager, which imports it. The package applies upstream commit `e0fda5682b`, which removes the PyPI search box, and removes `pypi-search` from the requirements.
- **Same as 2026.** The ctypes library paths, `SetIcons`, and `kioskDefaults` apply as in [Patches](#patches). In 2024, the wx GUI is part of `psychopy`, so `kioskDefaults` is an argument of `psychopy` only.
- **Requirements.** The macOS-only setuptools pin is relaxed. `opencv-python` is removed, because nixpkgs supplies only the `cv2` module. The `psychtoolbox` 3.0.22.2 sdist requires NumPy `>=2` at build time. The package relaxes this pin and builds against NumPy 1.26, which gives the same run-time compatibility as the upstream wheels.
- **Plugins.** `psychopy-legacy` 1.0.0, `psychopy-visionscience` 0.0.7, and `psychopy-eyetracker-sr-research` 0.0.4 are the releases before the 2024.2.4 tag. Newer releases use newer PsychoPy APIs. The sounddevice backend is in the 2024 core, so the list has `sounddevice`, not `psychopy-sounddevice`.
- **Tests off.** `blosc2`, `imageio`, `moviepy`, `ndindex`, and `tables` set `doCheck = false`. Their test suites fail in the old tree today, for example a date-dependent astropy test and hypothesis deadline tests.

Costs and tests: the binary cache has only part of `python310Packages`. OpenCV, PyQt6, wxPython, and SciPy compile locally. A cold build takes about 66 minutes on 8 cores. Tested: a window and the app frames under Xvfb for the base and lab variants, and the `psychtoolbox-x11` subtests "PsychoPy 2024 window", "wx app 2024 starts without first-run or realtime dialogs" (lab variant), and "2024 and 2026 GUIs install side by side". The last subtest checks which package owns `bin/psychopy`, `bin/psychopy-2024`, `bin/python3.10`, the desktop files, and the icon. Not tested: the Pavlovia login, real AMD GPUs, and hardware with the pinned plugins.

### PsychoPy Studio

Studio is the Electron GUI. Upstream downloads `uv` and installs PsychoPy into a venv at run time. The Nix package uses the `uv` from nixpkgs and blocks downloads. It makes the venv with `--system-site-packages` from a Python environment that has the packages of `psychopy-env`. If a venv comes from an older Nix generation, Studio makes it again. The code editor loads Monaco from the app, not from a CDN. The `psychtoolbox-x11` test starts Studio without network and checks the venv and the liaison connection. Known limit: the plugin manager cannot install plugins, because `UV_OFFLINE=1` blocks PyPI. Add plugins through `psychopy/packages-list.nix` instead.

### Upstream tests

Two checks run upstream tests: `psychopy-pytest` for PsychoPy, and the demo sweep in `psychtoolbox-x11` for PTB.

The `psychopy-pytest` check (`tests/psychopy-pytest.nix`) runs the PsychoPy upstream test suite against `psychopy-env`. The suite found the shadow window, `javascripthon`, and `psychopy-glfw` problems in [Patches](#patches), and the PsychHID crash in [Known limits](#known-limits).

The check uses the marker selection of upstream CI on Ubuntu: `-m "not needs_sound and not needs_wx and not needs_qt and not needs_pygame and not emulator"`.
It runs in the build sandbox, under Xvfb with Mesa llvmpipe. The sandbox has no network, no audio device, and no realtime priority. The suite writes into its own directory, so the check runs a writable copy of the installed tests. The test environment adds `javascripthon` (as upstream CI does), the test dependencies that the suite imports, and `pytest-timeout`. The check sets `GITHUB_WORKFLOW`, as upstream CI does. Thus the suite skips the timing, refresh rate, and gamma tests. A run takes about 6.5 minutes.

Baseline (PsychoPy 2026.2.4, nixos-26.05): 812 passed, 10 expected failures, 125 skipped, 41 deselected.
The check fails if a test fails that is not in `expectedFailures`, or if fewer than `minPassed` tests pass. Expected failures:

- One test writes into the PsychoPy install, which is read-only in the store.
- Three tests start an experiment subprocess that creates a PsychHID keyboard. The subprocess has no realtime priority and stops with SIGSEGV. See [Known limits](#known-limits).
- Six TextBox2 tests have small glyph raster differences from the upstream screenshots. The system FreeType is not the FreeType in the upstream `freetype-py` wheel.

In addition to the marker selection, the check deselects tests that need the network (psychopy.org, Google Fonts), `git` and a Git checkout, or codecov. It also deselects the `TestKeyboardComponent` class, because its PsychHID crash stops the full pytest session. It ignores `test_gui/test_DlgFromDictWx.py`, because that file imports wx.

PTB demo sweep: the "Psychtoolbox demo sweep" subtest of `psychtoolbox-x11` runs `tests/ptb-sweep.m` as the logged-in user, with zink on lavapipe. The sweep follows the Debian package test (`debian/rules` and `debian/run_tests`). Each entry runs in its own `octave-cli` process with a time limit, so that a demo that hangs or crashes does not stop the sweep. For demos that end only on a key press, `xdotool` sends the keys. Each entry prints one line, `SWEEP <name> ok|fail|skip <seconds>`. The subtest fails only if an entry in `expectedPass` is not `ok`. The log shows the other entries for information. The sweep takes about 3 minutes.

Baseline (PTB 3.0.22.3, nixos-26.05): 25 ok, 4 skipped. The `ok` entries are checks without a window (for example `PsychtoolboxVersion`, `WaitSecs`, `PsychHID`, `KbCheck`, and the `PsychPortAudio` device list), sound output (`BasicSoundOutputDemo`), window demos (for example `DriftDemo`, `FastNoiseDemo`, `HelloWorldDemo`, `GratingDemo`, `ClutAnimDemo`, and the text demos), and GStreamer movie playback and writing (`SimpleMovieDemo`, `LosslessMovieWritingTest`). `ProceduralGaborDemo` plots with gnuplot. The skipped entries need a mouse click, do not end on a key press, or run only on Windows. The sweep does not include Debian entries that need user input, that do not end even with key presses, that need hardware (camera, photometer, Vulkan display, OpenXR runtime, touch screen), or that take too long.

To update `expectedPass` after a PTB, Mesa, or nixpkgs update, run the check and find the `SWEEP <name> ok` lines in the log. Copy their names into `expectedPass` in `tests/psychtoolbox-x11.nix`. Before you remove a name, find the cause of the failure.
Note for test authors: `systemd-run -p PAMName=login` resets `PATH`. Thus the subtest sets `PATH` with `env`, not with `--setenv`.

### Continuous integration

`checks.yml` runs `nix flake check` on `ubuntu-24.04`. `cachix/install-nix-action` enables KVM for the VM tests, and a step stops the job early if KVM is not available. A step deletes preinstalled tools to free disk space.

The workflow keeps the Nix store in the GitHub Actions cache with `nix-community/cache-nix-action`. Thus a warm run does not build wxPython, `octave-ilp64`, and PsychoPy 2024 again. The cache key is a hash of `flake.lock` and of all `.nix`, `.patch`, `.m`, `.sh`, and `.c` files. If no cache has this key, the job restores an older cache with the prefix `nix-store-` and builds only the changed derivations. When the inputs of a check did not change, the check does not run again. Only pushes to the default branch save a cache, because one cache is about 7 GB and GitHub keeps at most 10 GB per repository. Before the save, a step makes GC roots for the local builds, and the action collects garbage until the store is at most 20 GiB. GitHub deletes a cache that no run used for 7 days.

The vendor packages must not go into the cache. The cache is not public, but pull request runs from forks can restore the caches of the base branch. Thus the last step of the job deletes from the store all outputs of the vendor packages, their source files, the `-eyelink`, `-datapixx`, and `-lab` variants, and all paths that refer to them. If a vendor path stays in the store, the step fails, and the action does not save the cache. The base packages stay in the cache. They contain `meshpy` (Triangle), which is free only for non-commercial use.


`matlab-mex.yml` builds `ptb-matlab-mex-builder` and runs `--check-env` before the MATLAB download. Then `matlab-actions/setup-matlab@v3` installs MATLAB (product `MATLAB`, with `cache`). A "Diagnose mex compiler detection" step then runs `--mex-setup` and continues on error, so the log shows the detection even when the build fails. In public repositories, `setup-matlab` gives a license only through the `run-*` actions and their `run-matlab-command` helper. The builder calls `matlab -batch`, so the workflow installs a shim at `/opt/matlab/<release>/bin/matlab` that sends the command to `run-matlab-command`. The helper is not documented and can change. The workflow builds the mex files into `$RUNNER_TEMP`, and makes sure that `ldd` finds all libraries except `libmx`, `libmex`, and `libmat`. Then it loads `Screen`, `GetSecs`, `WaitSecs`, and `PsychPortAudio` through `matlab-psychtoolbox` in an FHS environment, because the runner's glibc 2.39 is older than the glibc of the store. It uploads the mex files as an artifact.

Neither workflow has run yet, because the repository is not on GitHub. Open questions: if the public-repository license lets `mex` run, if MATLAB's compiler check accepts GCC 15, and if `run-matlab-command` works inside bubblewrap.

### Vendor SDKs

Sources:

- SR Research: `eyelink-core` and `eyelink-edfapi` come from the debs in the public apt repository at https://apt.sr-research.com/. `sr-research-pylink` and `psychopy-eyetracker-sr-research` come from PyPI.
- VPixx: `vpixx-software-tools` comes from the versioned deb on VPixx's CloudFront server (302 MB download). VPixx has no apt repository and publishes no checksum, so the package pins the versioned URL, not the "latest" redirect. `pypixxlib` is not on PyPI. The package builds it from the sdist in the deb.

Licensing: all vendor packages are unfree, so they need `allowUnfree`. The flake's own package set sets it. The licenses do not permit redistribution, so do not push these packages to a public binary cache. SR Research PyLink is free for non-commercial use.

The packages do not use `requireFile`. Both vendors publish their files at public URLs without a login. Thus a fetcher with a fixed hash downloads them, and users do not add files to the store manually.

Eyelink: Debian builds skip the Eyelink mex file, because the SR Research SDK is not free. This package builds with the same Debian flag. `eyelink-pkg-config.patch` builds Eyelink when `withEyelink = true` and gets the include path from pkg-config. The install check runs Eyelink in dummy mode, because the sandbox has no tracker. Tests without hardware: PyLink dummy mode works, the ioHub EyeLink device starts with `enable_interface_without_connection`, and `Eyelink('IsConnected')` returns 0 in Octave.

Datapixx: PTB has no Datapixx source. VPixx supplies prebuilt mex files for MATLAB and Octave. `with-datapixx.nix` always installs `Datapixx.mexa64` for MATLAB. With `withOctaveMex = true`, it also installs `Datapixx.mex` for Octave. The `-datapixx` and `-lab` variants set this option. The Octave file does not work on the nixpkgs Octave 11, for two reasons:

- VPixx built the file with Octave 5.2 and a 64-bit `mwSize`. The nixpkgs Octave uses 32-bit indexes (`use64BitIdx = false`). Thus calls that pass `mwSize` arrays, for example `mxCreateStructArray`, get wrong dimensions.
- Octave 10.2 and later refuse mex files without the `__octave_mex_soversion__` symbol. Octave 5.2 does not add this symbol.

The package solves these problems as follows:

- `octave-ilp64` is the nixpkgs Octave 11.1 with `use64BitIdx = true`. The `-datapixx` and `-lab` variants build PTB and the Octave environment with it. `psychtoolbox-3`, `psychtoolbox-3-eyelink`, and `octave-psychtoolbox` stay on the nixpkgs Octave. If the Octave has 32-bit indexes, a guard in `with-datapixx.nix` stops the build.
- `mkoctfile --mex` adds `__octave_mex_soversion__` to each file that it links. `with-datapixx.nix` uses it to compile the empty file `mex-soversion.c` into `libdatapixx-mex-soversion.so`. Then it adds this library as a `DT_NEEDED` entry of `Datapixx.mex`. Octave finds the symbol with `dlsym` on the mex handle, which also searches the dependencies.
- `octave-ilp64` also fixes a nixpkgs bug in `qrupdate`. `qrupdate` passes its ILP64 Fortran flags as one string with a space. Without `__structuredAttrs`, Nix splits the string and CMake fails on `-fdefault-integer-8`.

Tests without hardware: `Datapixx('Version')` returns a 1x1 struct, and the mex file lists 313 subfunctions. `Open`, `IsReady`, and `Close` run. Calls that need a device return usage errors. The install check tests `Version` and the subfunction list.

Costs:

- Hydra does not build `octave-ilp64`. A local build takes about 24 minutes. Then the Octave packages (`image`, `signal`, `statistics`, `optim`, `io`) build locally for it.
- The closure is about 0.1 GiB larger than with the nixpkgs Octave.
- Each `.oct` and `.mex` file in the environment must come from `octave-ilp64`. The `octave` override of `octave-psychtoolbox` does this for PTB and the Octave packages. Do not add Octave packages from the nixpkgs Octave.

Risk: the shim disables an Octave safety check. The package assumes that a mex file built with Octave 5.2 headers is ABI-compatible with the Octave 11 `liboctmex`. All `mx` and `mex` functions that the file imports exist in Octave 11. The file is not tested with a VPixx device.

`pypixxlib` in PsychoPy does not use the mex file, so it is not affected.

### MATLAB

MATLAB is outside the store, in the fleet FHS environment at `/opt/matlab/<release>`. MathWorks does not permit redistribution. Thus a derivation cannot run MATLAB's `mex`. `ptb-matlab-mex-builder` is an FHS environment that runs outside the Nix sandbox. It contains the libraries that MATLAB needs to start (a copy of the fleet's `fhsLibs`) and the headers and libraries of `psychtoolbox-3`. It applies the patches and the `postPatch` of `psychtoolbox-3`, then `matlab-nolm.patch`. Thus the MATLAB and Octave builds compile the same C code against the same libraries. `postPatch` deletes the prebuilt binaries, which include the upstream `.mexa64` files and `libLexActivator`.

License management: the upstream `.mexa64` files link `libLexActivator` and need a license key or a trial. The PTB source disables license management when `PSYCH_NOLM` is defined: `PsychLM.c` is inside `#ifndef PSYCH_NOLM`, and `MiniBox.c` has stub functions. Upstream defines `PSYCH_NOLM` for its Octave builds on Linux. Thus the C code does not change. `matlab-nolm.patch` changes only `linuxmakeit64.m`. It adds `-DPSYCH_NOLM` and removes `-lLexActivator` and the `PsychPlugins` library path and rpath. It also does what the Octave patches do: include paths from pkg-config, the system GLEW, no `-DPTB_USE_NVSTUSB`, and PsychCV without `libapriltag-utils`. It adds `-Wno-address` and `-Wno-int-conversion` to moglcore, because GCC 14 and later make `int-conversion` an error. It skips modes 7, 12, and 14 (libfreenect, Oculus SDK, OpenHMD). Self-built mex files do not get upstream support. For paid support, see `help PsychPaidSupportAndServices`.

Library search: MATLAB opens mex files with `dlopen`, and the MATLAB launcher puts its own library folders in `LD_LIBRARY_PATH`. The dynamic loader searches `DT_RPATH` before `LD_LIBRARY_PATH`, but `DT_RUNPATH` after it. Thus the builder sets `DT_RPATH` to the store library folders with `patchelf --force-rpath` after the build. A test with a fake library in `LD_LIBRARY_PATH` showed this: with `DT_RPATH`, the store library loaded; with `DT_RUNPATH`, the fake library loaded. Because of the rpath, the FHS environment that runs MATLAB does not need the PTB libraries. Thus `matlab-psychtoolbox` is a shell script around the fleet's `matlab` command, not a second FHS environment.

Limits of the rpath:

- If the MATLAB process already loaded a library with the same soname, the loader uses that library, whatever the rpath. MATLAB loads its own libstdc++ at start, but openal-soft needs `GLIBCXX_3.4.29`. Thus the wrapper sets `LD_PRELOAD` to the libstdc++ of the store GCC (`preloadLibstdcxx`, default `true`). nix-matlab does the same. The preload applies to all processes that the wrapper starts, so the store GCC must use the same glibc as the host. This is true only when the host and the overlay use the same nixpkgs, as in the fleet. Otherwise, set `preloadLibstdcxx = false`. Then a mex file that needs a newer libstdc++ can fail to load.
- The glibc of the FHS environment that runs MATLAB must not be older than the glibc of the store libraries. With one nixpkgs for the fleet and the overlay, they are the same.
- The rpath names exact store paths. The builder registers a GC root (`runtime`) next to the files. On machines that get a copy, the closure of `matlab-psychtoolbox` keeps the same libraries. Thus copy the files only to machines on the same flake revision.

Startup: `startup.m` adds PTB to the path, removes the Octave, macOS, Windows, ARM, and Wayland folders, and puts the mex folder first. The wrapper runs it with `run()` before the command of `-r` or `-batch`. The wrapper installs it as `ptb_startup.m` in a subfolder, because `run()` calls a script by its base name, which must be a valid MATLAB identifier. A store file name such as `<hash>-startup.m` is not valid. A `startup.m` on `MATLABPATH` would depend on the position of `userpath`. The package deletes the prebuilt `.class` files, but MATLAB releases before R2025a need the Java class `GetCharJava` for `GetChar` and `ListenChar`. Thus `matlab-psychtoolbox` compiles `GetCharJava.java` for Java 8 and adds it with `javaaddpath`.

### Known limits

- `Screen('OpenWindow')` causes a segmentation fault on Mesa llvmpipe. This is a Mesa bug: the drisw GLX screen leaves `getSwapInterval` as NULL, and `glXQueryDrawable(GLX_SWAP_INTERVAL_EXT)` calls it. Real GPUs are not affected. The `psychtoolbox-x11` test uses zink on lavapipe (`MESA_LOADER_DRIVER_OVERRIDE=zink`).
- Xvfb cannot run PTB windows.
- On the first Studio launch into an empty home directory, upstream starts the liaison bridge twice while it creates the venv. The second start fails with "Address already in use" and Studio shows "Python error" toasts. The first bridge stays connected. Later launches do not show this.
- wxGTK on X11 exports no window icon for a single 256 px icon (GDK request size limit). The app package sets the full icon bundle instead; this is an upstream wx/GDK behavior, not a Nix one.
- The Octave Datapixx mex file is not tested with a VPixx device. It loads only because a shim disables an Octave safety check. See [Vendor SDKs](#vendor-sdks).
- Hydra does not build `octave-ilp64`. The first build of a `-datapixx` or `-lab` Octave package takes about 24 minutes, plus the Octave packages.
- Upstream bug, not fixed here: the PsychHID keyboard thread in the PTB Python bindings tries to get realtime priority. If `pthread_setschedparam` fails, the thread prints a message with `PySys_WriteStdout` without the GIL, and the process stops with SIGSEGV. On lab machines, the realtime limits from the module prevent this. For a user without these limits (no `programs.psychtoolbox`), a PsychoPy `Keyboard` with the psychtoolbox backend crashes.
- `psychopy-glfw` 0.0.2 does not work with PsychoPy 2026: `winType='glfw'` fails. Thus the PsychoPy environments do not include it. Also, GLFW selects Wayland if `XDG_RUNTIME_DIR` contains a Wayland socket, even if `WAYLAND_DISPLAY` is not set.
- `sr-research-pylink` is built and tested only for Python 3.12 (cp312) and, in the 2024 packages, Python 3.10 (cp310).
- PsychoPy 2024.2.4 uses Mesa 24.2.8, which does not support RDNA4 GPUs (Radeon RX 9000). On these GPUs, the 2024 packages use software rendering. NVIDIA GLX is not affected.
- The 2024 packages come from nixos-24.11, which is end of life and gets no security fixes, for example for the WebKitGTK of the Pavlovia login. The Pavlovia login in 2024 is not tested.
- PsychoPy 2024 and 2026 share the preference folder `~/.psychopy3`.
- The GitHub Actions workflows have not run. See [Continuous integration](#continuous-integration).
- PTB tests that write into `PsychtoolboxRoot`, for example `UnitTestRunAll` and `Files_Test_FileFromFolder`, cannot run, because the store is read-only.
- Upstream bug, not fixed here: `PhotopigmentNomogramDemo` calls `sgtitle`, which Octave does not have.
- The MATLAB packages are not tested with a real MATLAB. Tested: the build of both builders and both wrappers, `--check-env`, `--dry-run`, Octave parses the patched `linuxmakeit64.m`, and the search order of `DT_RPATH`. Not tested: MATLAB's `mex` with these flags and its compiler check (MATLAB can warn that GCC 15 is not supported), conflicts between MATLAB's own libraries and the store libraries, loading the mex files, the libstdc++ preload, the GC root, the copy to other machines, and hardware (Eyelink, Datapixx).
