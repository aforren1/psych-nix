# PsychoPy GUI (Builder, Coder, Runner). The launcher and bin/python share one
# interpreter that holds the library, the lab plugins and the app, because the
# Runner and Coder start experiments with sys.executable.
{
  lib,
  stdenv,
  python,
  adwaita-icon-theme,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  wrapGAppsHook3,
  # Function from the Python package set to extra packages, for example
  # import ./vendor-list.nix. Appended to the packages in ./packages-list.nix.
  extraPackages ? (ps: [ ]),
}:

let
  psychopy-app = python.pkgs.psychopy-app;

  pythonEnv =
    (python.buildEnv.override {
      extraLibs = import ./packages-list.nix python.pkgs ++ extraPackages python.pkgs ++ [ psychopy-app ];
    }).overrideAttrs
      { name = "psychopy-app-env"; };
in
stdenv.mkDerivation {
  pname = "psychopy-app";
  inherit (psychopy-app) version;

  dontUnpack = true;

  nativeBuildInputs = [ wrapGAppsHook3 ];

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

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share
    for prog in python python3 ${python.executable}; do
      ln -s ${pythonEnv}/bin/$prog $out/bin/$prog
    done
    for dir in applications icons mime; do
      ln -s ${psychopy-app}/share/$dir $out/share/$dir
    done

    runHook postInstall
  '';

  # The hook only exports schemas and GIO modules; GTK dialogs need a stock
  # icon theme when the desktop does not provide one. Suffix, so the
  # desktop theme still wins.
  postFixup = ''
    makeWrapper ${pythonEnv}/bin/psychopy $out/bin/psychopy \
      "''${gappsWrapperArgs[@]}" \
      --suffix XDG_DATA_DIRS : ${adwaita-icon-theme}/share
  '';

  passthru = {
    inherit python pythonEnv;
  };

  meta = psychopy-app.meta // {
    mainProgram = "psychopy";
  };
}
