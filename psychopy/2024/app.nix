# PsychoPy 2024.2.4 GUI (Builder, Coder, Runner). Installs side by side with
# the 2026 psychopy-app: NixOS merges systemPackages with collisions
# ignored, so every file name here differs from the 2026 package
# (bin/psychopy-2024, psychopy-2024.desktop, icon psychopy-2024), and the
# package has no bin/python or bin/python3 and no MIME definition, which stay
# with the 2026 package.
# The launcher and bin/python3.10 share one interpreter that holds the library,
# the lab plugins and the GUI, because the Runner and Coder start experiments
# with sys.executable.
{
  lib,
  stdenv,
  python,
  adwaita-icon-theme,
  copyDesktopItems,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  imagemagick,
  makeDesktopItem,
  mesa,
  wrapGAppsHook3,
  # Function from the Python package set to extra packages, for example
  # import ../vendor-list.nix. Appended to the packages in ./packages-list.nix.
  extraPackages ? (ps: [ ]),
}:

let
  inherit (python.pkgs) psychopy;

  pythonEnv =
    (python.buildEnv.override {
      extraLibs = import ./packages-list.nix python.pkgs ++ extraPackages python.pkgs;
      # Experiments run with sys.executable, so the interpreter needs the
      # Mesa wrapper too, not only the launcher.
      makeWrapperArgs = import ./gl-wrapper-args.nix { inherit mesa; };
    }).overrideAttrs
      { name = "psychopy-2024-app-env"; };
in
stdenv.mkDerivation {
  pname = "psychopy-2024-app";
  inherit (psychopy) version;

  dontUnpack = true;

  nativeBuildInputs = [
    copyDesktopItems
    imagemagick
    wrapGAppsHook3
  ];

  # gsettings-desktop-schemas: GTK file dialogs abort without them.
  # glib-networking: TLS for the Pavlovia login page in wx.html2 (WebKitGTK).
  buildInputs = [
    glib-networking
    gsettings-desktop-schemas
    gtk3
  ];

  # Only the launcher needs the GTK environment; wrap it explicitly instead of
  # letting the hook wrap every file in bin/.
  dontWrapGApps = true;

  # Upstream's Resources/psychopy.desktop is stale (Exec=psychopyApp.py).
  # text/x-psyexp lists this version under "Open with"; the 2026 package
  # owns the MIME definition and stays the default handler.
  desktopItems = [
    (makeDesktopItem {
      name = "psychopy-2024";
      desktopName = "PsychoPy 2024.2.4";
      genericName = "Experiment Builder";
      comment = "Create and run psychology and neuroscience experiments with PsychoPy 2024.2.4";
      exec = "psychopy-2024 %F";
      icon = "psychopy-2024";
      categories = [
        "Science"
        "Education"
      ];
      mimeTypes = [ "text/x-psyexp" ];
      startupNotify = true;
    })
  ];

  # The upstream PNG is 567 pixels square; hicolor lookups only match the
  # size directory, so scale it to standard sizes.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    ln -s ${pythonEnv}/bin/${python.executable} $out/bin/${python.executable}

    res=${psychopy}/${python.sitePackages}/psychopy/app/Resources
    for size in 256 512; do
      mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
      magick $res/psychopy@2x.png -resize ''${size}x''${size} \
        $out/share/icons/hicolor/''${size}x''${size}/apps/psychopy-2024.png
    done

    runHook postInstall
  '';

  # The hook only exports schemas and GIO modules; GTK dialogs need a stock
  # icon theme when the desktop does not provide one. Suffix, so the
  # desktop theme still wins.
  postFixup = ''
    makeWrapper ${pythonEnv}/bin/psychopy $out/bin/psychopy-2024 \
      "''${gappsWrapperArgs[@]}" \
      --suffix XDG_DATA_DIRS : ${adwaita-icon-theme}/share
  '';

  passthru = {
    inherit python pythonEnv;
  };

  meta = psychopy.meta // {
    description = "PsychoPy 2024.2.4 wx GUI (Builder, Coder, Runner)";
    mainProgram = "psychopy-2024";
  };
}
