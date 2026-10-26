# VM test for nixosModules.psychtoolbox. Takes the module so that the flake
# can pass its own output.
module: {
  name = "psychtoolbox-module";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ module ];

      programs.psychtoolbox = {
        enable = true;
        users = [ "tester" ];
      };
      users.users.tester.isNormalUser = true;

      environment.systemPackages = [ pkgs.xvfb-run ];
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
    '';
}
