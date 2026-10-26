# Declarative equivalent of Psychtoolbox's PsychLinuxConfiguration.m. That
# script copies files into /etc, runs groupadd and usermod, and rebuilds the
# initramfs, none of which works on NixOS. The configuration files come from
# the installed Psychtoolbox, so they follow the selected `package` version.
#
# Requires this flake's overlay (or a `pkgs` that has `psychtoolbox-3` and
# `octave-psychtoolbox`) for the option defaults.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.psychtoolbox;
  ptb = "${cfg.package}/share/psychtoolbox-3";

  # psychtoolbox.rules keeps its unnumbered name so that it sorts after the
  # numbered rule files, as it does on other distributions. The VPixx and CRS
  # vendor rules duplicate parts of it, but can diverge in later releases.
  udevRules = pkgs.runCommand "psychtoolbox-udev-rules" { } ''
    mkdir -p $out/lib/udev/rules.d
    substitute ${ptb}/PsychBasic/psychtoolbox.rules \
      $out/lib/udev/rules.d/psychtoolbox.rules \
      --replace-fail '"/bin/chmod ' '"${pkgs.coreutils}/bin/chmod ' \
      --replace-fail '"/bin/chgrp psychtoolbox ' '"${pkgs.coreutils}/bin/chgrp ${cfg.group} '
    cp ${ptb}/PsychHardware/DatapixxToolbox/60-vpixx-permissions.rules \
      ${ptb}/PsychHardware/ColorCal2/60-cambridgeresearch-permissions.rules \
      $out/lib/udev/rules.d/

    if grep -n '"/\(usr/\)\?s\?bin/' $out/lib/udev/rules.d/*; then
      echo "error: unpatched absolute path in Psychtoolbox udev rules" >&2
      exit 1
    fi
  '';
in
{
  options.programs.psychtoolbox = {
    enable = lib.mkEnableOption "Psychtoolbox-3 with the system configuration it expects";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.psychtoolbox-3;
      defaultText = lib.literalExpression "pkgs.psychtoolbox-3";
      description = ''
        Psychtoolbox-3 package that supplies the udev rules, drirc and
        modprobe files. The default needs this flake's overlay. For VPixx
        devices, use `pkgs.psychtoolbox-3-datapixx` or
        `pkgs.psychtoolbox-3-lab`, which contain the Datapixx mex.
      '';
    };

    octavePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.octave-psychtoolbox;
      defaultText = lib.literalExpression "pkgs.octave-psychtoolbox";
      description = ''
        Octave environment with Psychtoolbox on the path, added to
        {option}`environment.systemPackages`. It should contain
        {option}`programs.psychtoolbox.package`. For VPixx devices, use
        `pkgs.octave-psychtoolbox-datapixx` or `pkgs.octave-psychtoolbox-lab`,
        which use an Octave with 64-bit indexing.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "psychtoolbox";
      description = ''
        Group that gets realtime scheduling limits and access to GPU
        registers. Psychtoolbox does not check the group name itself.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users to add to {option}`programs.psychtoolbox.group` and to the
        dialout, lp, video and (with GameMode) gamemode groups. The users
        must be defined elsewhere.
      '';
    };

    enableGamemode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable GameMode with Psychtoolbox's gamemode.ini. Psychtoolbox
        requests GameMode while `Priority` is above 0.
      '';
    };

    enableOpenXR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        PsychOpenXRCore needs an OpenXR runtime. This enables Monado as the
        system default runtime.
      '';
    };

    vpixx = {
      enable = lib.mkEnableOption ''
        the VPixx software tools: `vputil`, libdpx and VPixx's udev rules.
        The udev rules also cover the X-Rite i1Display and i1Pro colorimeters.
        This option does not need {option}`programs.psychtoolbox.enable`
      '';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.vpixx-software-tools;
        defaultText = lib.literalExpression "pkgs.vpixx-software-tools";
        description = "VPixx software tools package. The default needs this flake's overlay.";
      };

      deviceServer.enable = lib.mkEnableOption ''
        the VPixx Device Server, which the Debian package enables. libdpx,
        `vputil` and LabMaestro connect to it on TCP port 9827 if it runs, and
        print "Unable to connect to server!" if it does not
      '';
    };

    enableDeepColor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable more than 8 bits per color channel on AMD GPUs (amdgpu and
        radeon `deep_color=1`) and install Psychtoolbox's /etc/drirc. The
        drirc also enables 10-bit OpenGL framebuffers in Mesa and forces
        double buffering for Vulkan stimulus presentation.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      warnings =
        lib.optional (cfg.users == [ ])
          "programs.psychtoolbox.enable is set but programs.psychtoolbox.users is empty: no user gets realtime limits or device access.";

      environment.systemPackages = [ cfg.octavePackage ];

      services.udev.packages = [ udevRules ];

      users.groups.${cfg.group} = { };
      users.users = lib.genAttrs cfg.users (_: {
        extraGroups = [
          cfg.group
          "dialout"
          "lp"
          "video"
        ]
        ++ lib.optional cfg.enableGamemode "gamemode";
      });

      # PsychBasic/99-psychtoolboxlimits.conf
      security.pam.loginLimits = [
        {
          domain = "@${cfg.group}";
          type = "-";
          item = "nice";
          value = "-20";
        }
        {
          domain = "@${cfg.group}";
          type = "-";
          item = "rtprio";
          value = "50";
        }
        {
          domain = "@${cfg.group}";
          type = "-";
          item = "memlock";
          value = "unlimited";
        }
      ];

      # PsychHardware/blacklist-psychtoolbox.conf: lp would claim the parallel
      # port that Psychtoolbox drives through ppdev.
      boot.blacklistedKernelModules = [ "lp" ];
      boot.extraModprobeConfig = ''
        install lp ${pkgs.coreutils}/bin/false
      ''
      # PsychHardware/amddeepcolor-psychtoolbox.conf. NixOS copies this file
      # into the initrd, so it also applies when amdgpu loads early.
      + lib.optionalString cfg.enableDeepColor ''
        options radeon deep_color=1
        options amdgpu deep_color=1
        options amdgpu freesync_video=1
      '';

      # PTB installs this file as /usr/share/drirc.d/90-psychtoolbox-deepcolor.conf.
      # Mesa on NixOS reads drirc.d only from its own store path, but it also
      # reads /etc/drirc.
      environment.etc.drirc = lib.mkIf cfg.enableDeepColor {
        source = "${ptb}/PsychHardware/90-psychtoolbox-deepcolor.conf";
      };

      # The Monado module also installs the xr-hardware udev rules and its
      # Vulkan layers, so no extra groups or packages are needed.
      services.monado = lib.mkIf cfg.enableOpenXR {
        enable = true;
        defaultRuntime = true;
      };

      # PsychBasic/gamemode.ini, without its commented-out entries.
      programs.gamemode = lib.mkIf cfg.enableGamemode {
        enable = true;
        settings = {
          general = {
            reaper_freq = 5;
            desiredgov = "performance";
            igpu_desiredgov = "powersave";
            igpu_power_threshold = 0.3;
            softrealtime = "off";
            renice = 20;
            ioprio = 0;
            inhibit_screensaver = 1;
          };
          gpu = {
            apply_gpu_optimisations = "accept-responsibility";
            gpu_device = 0;
            nv_powermizer_mode = 1;
          };
          custom.script_timeout = 10;
        };
      };
    })

    (lib.mkIf cfg.vpixx.enable {
      environment.systemPackages = [ cfg.vpixx.package ];
      # 70-vpixx.rules. It has no absolute paths to rewrite.
      services.udev.packages = [ cfg.vpixx.package ];
    })

    # The Debian postinst creates this user and enables the upstream unit,
    # which runs as vpixxds. The server listens on 0.0.0.0:9827; the NixOS
    # firewall blocks that port unless it is opened.
    (lib.mkIf (cfg.vpixx.enable && cfg.vpixx.deviceServer.enable) {
      systemd.packages = [ cfg.vpixx.package ];
      systemd.services.vpixx-device-server.wantedBy = [ "multi-user.target" ];

      users.users.vpixxds = {
        isSystemUser = true;
        group = "vpixxds";
        description = "VPixx Device Server";
      };
      users.groups.vpixxds = { };
    })
  ];
}
