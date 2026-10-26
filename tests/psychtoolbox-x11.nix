# VM with a real X server on virtio-gpu (DRI3 and GLX through llvmpipe), the
# psychtoolbox NixOS module enabled for a normal user, and that user logged
# in. Exercises Screen('OpenWindow'), a sweep of PTB demos and tests
# (tests/ptb-sweep.m), a PsychoPy window and the wx app as that user, so the
# realtime limits and device access the module grants are tested the way the
# lab uses them. Xvfb cannot do this: Mesa segfaults in
# glXQueryDrawable there. PsychoPy 2024.2.4 (overlay-2024.nix) gets the same
# window and wx app checks, installed next to the 2026 app.
{ pkgs, lib, ... }:
let
  ptb = pkgs.psychtoolbox-3;
  ppy = pkgs.psychopy-env;
  # Lab variant: the base app shows the Tip of the Day and "Changes in"
  # dialogs on first run, as upstream does; the subtest asserts the kiosk
  # defaults that suppress them.
  app = pkgs.psychopy-app-lab;
  studio = pkgs.psychopy-studio;
  # PsychoPy 2024 from nixos-24.11 user space, with its own Mesa 24.2 for GLX
  # (the 24.11 glibc cannot load the Mesa of this system).
  ppy2024 = pkgs.psychopy-2024-env;
  app2024 = pkgs.psychopy-2024-app-lab;
  user = "alice";
  home = "/home/${user}";

  ptbScript = pkgs.writeText "ptb-x11-test.m" ''
    source('${ptb.octaveStartup}');
    AssertOpenGL;
    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'Verbosity', 4);
    w = Screen('OpenWindow', 0, [0 0 0]);
    Screen('FillRect', w, [200 0 0]);
    Screen('TextSize', w, 40);
    DrawFormattedText(w, 'Psychtoolbox on NixOS', 'center', 'center', [255 255 255]);
    Screen('Flip', w);
    fid = fopen('/tmp/ptb-flipped', 'w'); fclose(fid);
    WaitSecs(8);
    Screen('CloseAll');
    disp('PTB_WINDOW_OK');
  '';
  ppyScript = pkgs.writeText "psychopy-x11-test.py" ''
    from psychopy import visual, core, __version__
    print("psychopy", __version__)
    w = visual.Window(fullscr=True, color=[-1, -1, 1], units="pix")
    visual.TextStim(w, "PsychoPy on NixOS", height=40).draw()
    w.flip()
    open("/tmp/ppy-flipped", "w").close()
    core.wait(8)
    w.close()
    print("PPY_WINDOW_OK")
  '';

  # Run a GUI program as the logged-in user, detached from the test driver's
  # shell, through PAM so the login limits apply, logging to a file.
  run =
    unit: env: cmd:
    lib.concatStringsSep " " [
      "systemd-run --unit=${unit} --uid=${user} --gid=users -p PAMName=login"
      "--setenv=DISPLAY=:0 --setenv=HOME=${home} --setenv=XAUTHORITY=${home}/.Xauthority"
      "-p StandardOutput=file:/tmp/${unit}.log -p StandardError=file:/tmp/${unit}.log"
      env
      cmd
    ];
  # Mesa bug: the llvmpipe GLX screen leaves getSwapInterval NULL and
  # glXQueryDrawable(GLX_SWAP_INTERVAL_EXT) calls it. Real GPUs set it, and so
  # does zink on lavapipe, which is what the asserted PTB run uses.
  zink = "--setenv=MESA_LOADER_DRIVER_OVERRIDE=zink --setenv=LIBGL_ALWAYS_SOFTWARE=1 --setenv=LIBGL_KOPPER_DRI2=1";
  xdotool = "DISPLAY=:0 XAUTHORITY=${home}/.Xauthority ${pkgs.xdotool}/bin/xdotool search --onlyvisible --name . getwindowname %@";

  # Demo and test sweep, see tests/ptb-sweep.m. PAMName=login resets PATH,
  # so the sweep gets its PATH through env(1), not --setenv.
  sweepPath = lib.makeBinPath [
    pkgs.octave-psychtoolbox
    pkgs.xdotool
    pkgs.coreutils
  ];
  sweepCmd = lib.concatStringsSep " " [
    "${pkgs.coreutils}/bin/env PATH=${sweepPath}:/run/wrappers/bin:/run/current-system/sw/bin"
    "octave-cli --no-init-file --no-site-file -q ${./ptb-sweep.m} ${ptb.octaveStartup}"
  ];
  # The VM test runs 4 to 8 times slower on slow hosts (nested KVM, loaded CI
  # runners). The sweep multiplies all its time limits by this factor. A
  # normal sweep takes about 3 minutes, so sweepWait covers an 8 times slower
  # host with margin.
  sweepTimeScale = 3;
  sweepWait = 1800;
  # Sweep entries that must pass. The subtest fails only if one of these does
  # not pass; the other entries are logged for information. To update after a
  # PTB, Mesa or nixpkgs update, run the check, read the "SWEEP <name> ok"
  # lines in the log, and copy their names here. Before you remove a name,
  # find out why it fails.
  expectedPass = [
    "PsychtoolboxVersion"
    "WaitSecs"
    "PsychHIDDevices"
    "KbCheck"
    "PsychPortAudioGetDevices"
    "BasicSoundOutputDemo"
    "Oneliners_Test_Structs"
    "Files_Test_LineTerminators"
    "CIEXYZPhysTest"
    "DriftDemo"
    "FastNoiseDemo"
    "FastFilteredNoiseDemo"
    "AlphaAdditionTest"
    "AlphaBlendSettingTest"
    "TextInOffscreenWindowTest"
    "DrawTextFontSwitchSpeedTest"
    "DrawHighQualityUnicodeTextDemo"
    "HelloWorldDemo"
    "HelloGaborArrayDemo"
    "GratingDemo"
    "ExpandingRingsDemo"
    "ClutAnimDemo"
    "SimpleMovieDemo"
    "LosslessMovieWritingTest"
    "ProceduralGaborDemo"
  ];
in
{
  name = "psychtoolbox-x11";

  nodes.machine = {
    imports = [
      "${pkgs.path}/nixos/tests/common/x11.nix"
      "${pkgs.path}/nixos/tests/common/user-account.nix"
      ../psychtoolbox/nixos-module.nix
    ];
    test-support.displayManager.auto.user = user;
    programs.psychtoolbox = {
      enable = true;
      users = [ user ];
    };
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
    hardware.graphics.enable = true;
    # Both GUIs installed, to check that their file names do not collide.
    environment.systemPackages = [
      pkgs.psychopy-app
      app2024
    ];
  };

  testScript = ''
    def gui_check(unit, cmd, marker, ok, must=True):
        machine.succeed(cmd)
        machine.wait_until_succeeds(f"test -e {marker} || ! systemctl is-active --quiet {unit}", timeout=300)
        machine.sleep(2)
        machine.screenshot(unit)
        machine.wait_until_succeeds(f"! systemctl is-active --quiet {unit}", timeout=120)
        out = machine.succeed(f"cat /tmp/{unit}.log")
        print(f"===== {unit} log =====\n{out}\n===== end {unit} =====")
        machine.succeed(f"rm -f {marker}")
        if must:
            assert ok in out, f"{unit}: window test did not finish cleanly"
        return ok in out

    machine.wait_for_x()
    machine.wait_for_file("${home}/.Xauthority")

    with subtest("module grants the user realtime limits"):
        assert machine.succeed("su - ${user} -c 'ulimit -r'").strip() == "50"

    with subtest("PTB survives the x86 device tree of the NixOS kernel"):
        # Unpatched PTB calls _exit(123) when /sys/firmware/devicetree exists.
        machine.succeed("test -e /sys/firmware/devicetree")
        machine.succeed("su - ${user} -c '${ppy}/bin/python -c \"from psychtoolbox import GetSecs; print(GetSecs())\"' >&2")
        machine.succeed("su - ${user} -c '${ppy2024}/bin/python -c \"from psychtoolbox import GetSecs; print(GetSecs())\"' >&2")
        machine.succeed("su - ${user} -c \"${pkgs.octave}/bin/octave-cli --no-init-file -q --eval \\\"source('${ptb.octaveStartup}'); GetSecs\\\"\" >&2")

    machine.succeed("DISPLAY=:0 XAUTHORITY=${home}/.Xauthority ${pkgs.mesa-demos}/bin/glxinfo -B >&2")

    with subtest("PsychoPy window"):
        gui_check("ppytest", "${
          run "ppytest" "" "${ppy}/bin/python ${ppyScript}"
        }", "/tmp/ppy-flipped", "PPY_WINDOW_OK")

    with subtest("PsychoPy 2024 window"):
        gui_check("ppy2024", "${
          run "ppy2024" "" "${ppy2024}/bin/python ${ppyScript}"
        }", "/tmp/ppy-flipped", "PPY_WINDOW_OK")
        machine.succeed("grep -q 'psychopy 2024.2.4' /tmp/ppy2024.log")

    with subtest("Psychtoolbox window"):
        dri3 = gui_check("ptbdri3", "${
          run "ptbdri3" "" "${pkgs.octave}/bin/octave-cli --no-init-file -q ${ptbScript}"
        }", "/tmp/ptb-flipped", "PTB_WINDOW_OK", must=False)
        print(f"PTB on plain llvmpipe (expected to fail in this VM): {'ok' if dri3 else 'FAILED'}")
        gui_check("ptbtest", "${
          run "ptbtest" zink "${pkgs.octave}/bin/octave-cli --no-init-file -q ${ptbScript}"
        }", "/tmp/ptb-flipped", "PTB_WINDOW_OK")

    with subtest("Psychtoolbox demo sweep"):
        machine.succeed("${
          run "ptbsweep" "${zink} --setenv=PTB_SWEEP_TIME_SCALE=${toString sweepTimeScale}" sweepCmd
        }")
        machine.wait_until_succeeds("! systemctl is-active --quiet ptbsweep", timeout=${toString sweepWait})
        out = machine.succeed("cat /tmp/ptbsweep.log")
        print(f"===== ptbsweep log =====\n{out}\n===== end ptbsweep =====")
        results = {}
        for line in out.splitlines():
            f = line.split(" ", 4)
            if len(f) >= 4 and f[0] == "SWEEP":
                results[f[1]] = f[2]
        assert "SWEEP-DONE" in out, "the sweep did not finish"
        broken = [n for n in ${builtins.toJSON expectedPass} if results.get(n) != "ok"]
        assert not broken, f"sweep entries in expectedPass that did not pass: {broken}"

    with subtest("wx app starts without first-run or realtime dialogs"):
        machine.succeed("${run "ppyapp" "--setenv=GDK_BACKEND=x11" "${app}/bin/psychopy"}")
        machine.wait_until_succeeds("${xdotool} | grep -q Builder", timeout=180)
        machine.sleep(15)
        windows = machine.succeed("${xdotool}")
        print(windows)
        machine.screenshot("ppyapp")
        machine.succeed("systemctl stop ppyapp || true")
        print(machine.succeed("cat /tmp/ppyapp.log"))
        for frame in ["Runner", "Coder", "Builder"]:
            assert frame in windows, f"{frame} frame missing"
        for bad in ["Tip of the Day", "Changes in", "Additional configuration"]:
            assert bad not in windows, f"unexpected startup dialog: {bad}"
        assert "Traceback" not in machine.succeed("cat /tmp/ppyapp.log; cat ${home}/.psychopy3/last_app_load.log || true")

    with subtest("wx app 2024 starts without first-run or realtime dialogs"):
        # Both versions use ~/.psychopy3. Move the 2026 files aside so that
        # this is a first run of 2024, as on a kiosk with a wiped home.
        machine.succeed("mv ${home}/.psychopy3 ${home}/.psychopy3-2026")
        machine.succeed("${run "ppyapp2024" "--setenv=GDK_BACKEND=x11" "${app2024}/bin/psychopy-2024"}")
        machine.wait_until_succeeds("${xdotool} | grep -q 'Builder (v2024.2.4)'", timeout=180)
        machine.sleep(15)
        windows = machine.succeed("${xdotool}")
        print(windows)
        machine.screenshot("ppyapp2024")
        machine.succeed("systemctl stop ppyapp2024 || true")
        print(machine.succeed("cat /tmp/ppyapp2024.log"))
        for frame in ["Runner (v2024.2.4)", "Coder (IDE) (v2024.2.4)", "Builder (v2024.2.4)"]:
            assert frame in windows, f"{frame} frame missing"
        for bad in ["Tip of the Day", "Changes in", "Additional configuration"]:
            assert bad not in windows, f"unexpected startup dialog: {bad}"
        assert "Traceback" not in machine.succeed("cat /tmp/ppyapp2024.log; cat ${home}/.psychopy3/last_app_load.log || true")
        machine.succeed("rm -rf ${home}/.psychopy3 && mv ${home}/.psychopy3-2026 ${home}/.psychopy3")

    with subtest("2024 and 2026 GUIs install side by side"):
        # system-path ignores collisions, so a shared file name would let one
        # package hide the other's file without an error.
        sw = "/run/current-system/sw"

        def owner(f):
            return machine.succeed(f"readlink -f {sw}/{f}")

        assert "-psychopy-app-2026.2.4/" in machine.succeed(f"readlink {sw}/bin/psychopy")
        assert "-psychopy-2024-app-2024.2.4/" in machine.succeed(f"readlink {sw}/bin/psychopy-2024")
        assert "-psychopy-2024-app-2024.2.4/" in machine.succeed(f"readlink {sw}/bin/python3.10")
        for f in ["bin/python", "bin/python3"]:
            assert "2024" not in machine.succeed(f"readlink {sw}/{f}"), f"{f} comes from the 2024 app"
        assert "-psychopy-app-2026.2.4/" in owner("share/applications/psychopy.desktop")
        assert "-psychopy-2024-app-2024.2.4/" in owner("share/applications/psychopy-2024.desktop")
        assert "-psychopy-2024-app-2024.2.4/" in owner("share/icons/hicolor/256x256/apps/psychopy-2024.png")
        machine.succeed(f"grep -q '^Exec=psychopy-2024 %F' {sw}/share/applications/psychopy-2024.desktop")

    with subtest("Studio starts offline against the Nix Python"):
        machine.succeed("${
          run "studio" "--setenv=XDG_RUNTIME_DIR=/run/user/1000" "${studio}/bin/psychopy-studio --disable-gpu"
        }")
        machine.wait_until_succeeds("${xdotool} | grep -q 'PsychoPy Builder'", timeout=240)
        machine.sleep(10)
        machine.screenshot("studio")
        machine.succeed("systemctl stop studio || true")
        print(machine.succeed("tail -n 40 /tmp/studio.log"))
        machine.succeed("grep -q 'include-system-site-packages = true' ${home}/.config/psychopy4/.python/*/pyvenv.cfg")
        machine.fail("test -e ${home}/.config/psychopy4/.uv")
        machine.succeed("grep -q 'LIAISON:CONNECTED' ${home}/.config/psychopy4/last_app_load.log")
        machine.fail("grep -qi 'pip install\\|releases/download' ${home}/.config/psychopy4/last_app_load.log")
  '';
}
