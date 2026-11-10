# VM test for nixosModules.psychtoolbox. Takes the module so that the flake
# can pass its own output.
module:
{ pkgs, ... }:
let
  # Stand-in for a LabHackers MilliKey: uinput devices with its USB ID and
  # the two endpoints that matter, a joystick and a keyboard.
  fakeMilliKey = pkgs.writers.writePython3 "fake-millikey" { libraries = ps: [ ps.evdev ]; } ''
    import sys
    import time

    import evdev
    from evdev import AbsInfo
    from evdev import ecodes as e

    if sys.argv[1] == "joystick":
        axis = AbsInfo(0, 0, 255, 0, 0, 0)
        cap = {
            e.EV_KEY: [e.BTN_TRIGGER, e.BTN_THUMB, e.BTN_THUMB2],
            e.EV_ABS: [(e.ABS_X, axis), (e.ABS_Y, axis)],
        }
    else:
        # udev marks a device as a keyboard if it has the first 31 keys.
        cap = {e.EV_KEY: list(range(e.KEY_ESC, e.KEY_SPACE + 1))}
    dev = evdev.UInput(
        cap,
        name="LabHackers MilliKey",
        vendor=0x16C0,
        product=0x048A,
        bustype=e.BUS_USB,
    )
    time.sleep(3600)
  '';
in
{
  name = "psychtoolbox-module";

  nodes.machine =
    { modulesPath, ... }:
    {
      imports = [
        module
        # A real X server, for the MilliKey rule.
        "${modulesPath}/../tests/common/x11.nix"
      ];
      boot.kernelModules = [ "uinput" ];

      programs.psychtoolbox = {
        enable = true;
        users = [ "tester" ];
      };
      users.users.tester.isNormalUser = true;

      environment.systemPackages = [
        pkgs.xvfb-run
        pkgs.xinput
      ];
      virtualisation.memorySize = 2048;
    };

  testScript =
    { nodes, ... }:
    let
      ptbWarnings = builtins.filter (
        w: builtins.match "programs\\.psychtoolbox.*" w != null
      ) nodes.machine.warnings;
    in
    assert ptbWarnings == [ ];
    ''
      machine.wait_for_unit("multi-user.target")

      def as_tester(cmd):
          rc, out = machine.execute(f"su - tester -c '{cmd}' 2>&1")
          assert rc == 0, f"{cmd} exited with {rc}:\n{out}"
          return out.strip()

      with subtest("groups"):
          groups = as_tester("id -nG").split()
          for g in ["psychtoolbox", "dialout", "lp", "video", "gamemode"]:
              assert g in groups, f"{g} missing from {groups}"

      with subtest("udev rules"):
          machine.succeed("grep -q 'bin/chgrp psychtoolbox %S%p/resource2' /etc/udev/rules.d/psychtoolbox.rules")
          machine.fail("grep -q '\"/bin/' /etc/udev/rules.d/psychtoolbox.rules")
          machine.succeed("test -e /etc/udev/rules.d/60-vpixx-permissions.rules")
          machine.succeed("test -e /etc/udev/rules.d/60-cambridgeresearch-permissions.rules")

      with subtest("PAM limits"):
          assert as_tester("ulimit -r") == "50"
          assert as_tester("ulimit -e") == "40"  # nice -20
          assert as_tester("ulimit -l") == "unlimited"
          as_tester("chrt -f 50 true")
          as_tester("nice -n -20 true")

      with subtest("modprobe, drirc, gamemode"):
          machine.succeed("grep -qx 'blacklist lp' /etc/modprobe.d/nixos.conf")
          machine.succeed("grep -q '^install lp .*/bin/false' /etc/modprobe.d/nixos.conf")
          machine.succeed("grep -qx 'options amdgpu deep_color=1' /etc/modprobe.d/nixos.conf")
          machine.succeed("grep -q allow_rgb10_configs /etc/drirc")
          machine.succeed("grep -qx 'renice=20' /etc/gamemode.ini")

      with subtest("Octave"):
          as_tester("octave-cli --eval GetSecs")
          # Priority needs an X display. It sets SCHED_FIFO, so this checks
          # that the limits reach Psychtoolbox.
          as_tester("xvfb-run -a octave-cli --eval \"Priority(1); assert(Priority() == 1)\"")

      with subtest("X ignores the MilliKey joystick endpoint"):
          machine.succeed("grep -q 'MatchUSBID \"16c0:048a\"' /etc/X11/xorg.conf.d/52-millikey.conf")
          machine.wait_for_x()
          machine.wait_for_file("/root/.Xauthority")
          for kind in ["joystick", "keyboard"]:
              machine.succeed(f"systemd-run --unit=millikey-{kind} ${fakeMilliKey} {kind}")
          machine.wait_until_succeeds(
              "(cat /var/log/X.0.log; journalctl -b) | grep -q 'LabHackers MilliKey: Ignoring device from InputClass \"MilliKey joystick endpoint\"'",
              timeout=60,
          )
          xinput = "DISPLAY=:0 XAUTHORITY=/root/.Xauthority xinput list --name-only"
          machine.wait_until_succeeds(f"{xinput} | grep -qx 'LabHackers MilliKey'", timeout=60)
          names = machine.succeed(xinput).splitlines()
          print(names)
          # The keyboard endpoint, which PsychHID needs, is still there.
          assert names.count("LabHackers MilliKey") == 1, names
    '';
}
