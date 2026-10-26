{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  replaceVars,
  asar,
  copyDesktopItems,
  electron_42,
  makeDesktopItem,
  makeWrapper,
  uv,
  python,
  # Function from the Python package set to extra packages, for example
  # import ../vendor-list.nix. Appended to the packages in ../packages-list.nix.
  extraPackages ? (ps: [ ]),
}:

let
  electron = electron_42;

  # Studio runs experiments and its liaison bridge in a venv. Seeding that
  # venv with system site packages from this environment replaces upstream's
  # runtime `uv pip install` of the same packages.
  pythonEnv = python.buildEnv.override {
    extraLibs =
      import ../packages-list.nix python.pkgs
      ++ extraPackages python.pkgs
      ++ (with python.pkgs; [
        liaison-py
        websockets
        esprima
        dukpy
        javascripthon
      ]);
  };
in
buildNpmPackage (finalAttrs: {
  pname = "psychopy-studio";
  version = "2026.2.3";

  src = fetchFromGitHub {
    owner = "psychopy";
    repo = "psychopy-studio";
    tag = finalAttrs.version;
    hash = "sha256-XlXH4fBV03wD7OD/8cYNnSoT9yjZkDS5wX09JdJFDjU=";
  };

  patches = [
    (replaceVars ./nix-offline.patch {
      uv = lib.getExe uv;
      python = pythonEnv;
      psychopyVersion = python.pkgs.psychopy.version;
    })
  ];

  # index.cjs has CRLF line endings, so it is edited here, not in the patch:
  # - The Nix wrapper passes the app path as argv[1], so the view flag
  #   (--builder etc.) is at argv[2], which upstream expects only in dev mode.
  # - Upstream creates ~/.config/psychopy4 non-recursively and crashes when
  #   ~/.config does not exist yet, as on a fresh home directory.
  # package.json lists the macOS-only dmg-builder, which the lockfile lacks,
  # so `npm ci` would refuse to install.
  postPatch = ''
    substituteInPlace electron/src/index.cjs \
      --replace-fail "process.argv[isDev ? 2 : 1]" "process.argv[process.defaultApp ? 2 : 1]" \
      --replace-fail 'if (!fs.existsSync(path.join(app.getPath("appData"), "psychopy4"))) {' \
        'fs.mkdirSync(app.getPath("appData"), { recursive: true }); if (!fs.existsSync(path.join(app.getPath("appData"), "psychopy4"))) {'
    substituteInPlace package.json \
      --replace-fail '"@rollup/rollup-linux-x64-gnu": "*",' '"@rollup/rollup-linux-x64-gnu": "*"' \
      --replace-fail '"dmg-builder": "^0.5.1"' ""
  '';

  npmDepsHash = "sha256-AZvRat8/5wOOmzOd1S7Ehg94CKQD5tbR79LJJWv+Z84=";

  env.ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  # electron-builder would download Electron; the app is assembled below and
  # run with the nixpkgs Electron instead.
  npmBuildScript = "svelte:build";

  nativeBuildInputs = [
    asar
    copyDesktopItems
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    # The patched code editor loads Monaco from the app's own web server.
    # Only the renderer uses it, so the main process does not need the copy
    # in node_modules.
    mkdir dist/monaco-editor
    cp -r node_modules/monaco-editor/min dist/monaco-editor/
    npm prune --omit=dev --no-save
    rm -r node_modules/monaco-editor

    mkdir app
    cp -r package.json electron dist node_modules app/
    mkdir -p $out/share/psychopy-studio
    # dlopen needs real files; electron-builder unpacks native modules too.
    asar pack app $out/share/psychopy-studio/app.asar --unpack "*.node"

    makeWrapper ${lib.getExe electron} $out/bin/psychopy-studio \
      --add-flags $out/share/psychopy-studio/app.asar \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --set UV_PYTHON_DOWNLOADS never \
      --set UV_OFFLINE 1 \
      --set UV_NO_CACHE 1 \
      --set UV_NO_CONFIG 1 \
      --inherit-argv0

    install -Dm644 static/branding/favicon.svg \
      $out/share/icons/hicolor/scalable/apps/psychopy-studio.svg
    install -Dm644 static/branding/favicon@1024x1024.png \
      $out/share/icons/hicolor/1024x1024/apps/psychopy-studio.png

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "psychopy-studio";
      desktopName = "PsychoPy Studio";
      genericName = "Experiment builder";
      comment = finalAttrs.meta.description;
      exec = "psychopy-studio";
      icon = "psychopy-studio";
      startupWMClass = "psychopy-studio";
      categories = [
        "Science"
        "Education"
      ];
    })
  ];

  passthru = {
    inherit electron pythonEnv;
  };

  meta = {
    description = "Builder, Coder and Runner for PsychoPy experiments";
    homepage = "https://github.com/psychopy/psychopy-studio";
    license = lib.licenses.mit;
    mainProgram = "psychopy-studio";
    platforms = lib.platforms.linux;
  };
})
