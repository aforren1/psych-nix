{
  lib,
  octave,
  psychtoolbox-3,
  gst_all_1,
  gnuplot,
}:

let
  # Screen plays movies and captures video through GStreamer. The plugins
  # must come from the same gst_all_1 set that psychtoolbox-3 links against.
  gstPluginPath = lib.makeSearchPathOutput "out" "lib/gstreamer-1.0" (
    with gst_all_1;
    [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
    ]
  );
  gstPluginScanner = "${lib.getOutput "out" gst_all_1.gstreamer}/libexec/gstreamer-1.0/gst-plugin-scanner";

  env = octave.buildEnv.override {
    # The packages that the lab's Debian octaverc preloads. They are installed
    # but not loaded; use `pkg load`.
    extraLibs = with octave.pkgs; [
      image
      signal
      statistics
      optim
      io
    ];

    # buildEnv already wraps each program twice (OCTAVE_SITE_INITFILE, then
    # PATH). Add the GStreamer variables to the outer wrapper instead of a
    # third layer. gnuplot goes on PATH there too, not in extraLibs: a second
    # package with a bin directory stops buildEnv from wrapping the programs.
    # PTB demos that plot select graphics_toolkit('gnuplot').
    postBuild = ''
      echo 'source("${psychtoolbox-3.octaveStartup}");' \
        >> $out/share/octave/site/m/startup/octaverc

      for prog in octave octave-cli octave-${octave.version} octave-cli-${octave.version}; do
        substituteInPlace "$out/bin/$prog" --replace-fail 'exec -a "$0"' \
          "export PATH='${gnuplot}/bin'\''${PATH:+:\$PATH}
      export GST_PLUGIN_SYSTEM_PATH_1_0='${gstPluginPath}'\''${GST_PLUGIN_SYSTEM_PATH_1_0:+:\$GST_PLUGIN_SYSTEM_PATH_1_0}
      export GST_PLUGIN_SCANNER='${gstPluginScanner}'
      exec -a \"\$0\""
      done
    '';
  };
in
env.overrideAttrs (old: {
  name = "octave-psychtoolbox-${psychtoolbox-3.version}";
  passthru = old.passthru // {
    psychtoolbox = psychtoolbox-3;
    inherit octave;
  };
  meta = old.meta // {
    description = "GNU Octave with Psychtoolbox-3 on the path";
  };
})
