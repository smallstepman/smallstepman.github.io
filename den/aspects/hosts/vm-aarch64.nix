# den/aspects/hosts/vm-aarch64.nix
#
# Host aspect for the vm-aarch64 (vm-macbook) NixOS machine.
#
# Owns host-only behavior that should not live in shared feature aspects:
# hostname wiring, VMware host bridge config, aarch64 VM allowances, disk and
# boot config, DHCP pinning, Open WebUI proxying, and user-specific settings.
{ den, generated, inputs, yeetAndYoink, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      # Core Linux system behavior (non-desktop, non-WSL-specific).
      den.aspects.linux-core

      # Secret-backed system settings (sops, Tailscale, user password, rbw).
      den.aspects.secrets

      # Linux graphical desktop stack (niri, greetd, keyd, kitty, etc.).
      den.aspects.linux-desktop

      # Generic VMware guest integration.
      den.aspects.vmware

      # Hostname battery: sets networking.hostName from den.hosts config.
      den.provides.hostname

      # Host-specific NixOS configuration that does not belong in a shared aspect.
        ({ host, ... }: {
          nixos = { config, pkgs, lib, ... }: {
            imports = [
              inputs.disko.nixosModules.disko
            ];

            nixpkgs.config.allowUnfree = true;
            nixpkgs.config.allowUnsupportedSystem = true;

            # Copied from the old nixos-generate-config output so the VM keeps the
            # same initrd driver set after the legacy hardware file removal.
            boot.initrd.availableKernelModules = [ "uhci_hcd" "ahci" "xhci_pci" "nvme" "usbhid" "sr_mod" ];
            boot.initrd.kernelModules = [ ];
            boot.kernelModules = [ ];
            boot.extraModulePackages = [ ];
            swapDevices = [ ];

            # Copied from the former disko file so the VM disk layout remains
            # den-owned while still producing the same /boot and / filesystem setup.
            disko.devices = {
              disk.main = {
                device = lib.mkDefault "/dev/nvme0n1";
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    ESP = {
                      size = "500M";
                      type = "EF00";
                      content = {
                        type = "filesystem";
                        format = "vfat";
                        mountpoint = "/boot";
                        mountOptions = [ "umask=0077" ];
                      };
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/";
                      };
                    };
                  };
                };
              };
            };

            # Setup qemu so this aarch64 VM can run x86_64 binaries.
            boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

            fileSystems."/nixos-config" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/nixos-config";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };

            fileSystems."/nixos-generated" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/nixos-generated";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };

            fileSystems."/Users/m/Projects" = {
              fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
              device = ".host:/Projects";
              options = [
                "umask=22"
                "uid=1000"
                "gid=1000"
                "allow_other"
                "auto_unmount"
                "defaults"
              ];
            };

            # Let NetworkManager use DHCP on VMware NAT; VMware's DHCP reservation
            # keeps this guest pinned to 192.168.130.3.
            networking.interfaces.enp2s0.useDHCP = true;

            # Host-specific sops age public key used by secret collection.
            sops.hostPubKey = lib.removeSuffix "\n"
              (generated.readFile "vm-age-pubkey");

            # Ensure vm-macbook resolves locally regardless of DNS state.
            networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];

            # Expose a tunneled Open WebUI instance on localhost:80.
            systemd.services.openwebui-local-proxy = {
              description = "Expose tunneled Open WebUI on localhost:80";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
                Restart = "always";
                RestartSec = 1;
              };
            };

            # User m: host-specific group membership and SSH authorized keys.
            # Note: wheel and networkmanager are already added by den.provides.primary-user;
            # only add the vm-aarch64-specific lxd group here to avoid duplicates.
            users.users.m = {
              extraGroups = [ "lxd" ];
              openssh.authorizedKeys.keyFiles = [
                (generated.requireFile "host-authorized-keys")
              ];
            };
          };

          homeManager =
            { pkgs, lib, ... }:
            let
              projectsRoot =
                if builtins.pathExists /Users/m/Projects
                then /Users/m/Projects
                else /home/m/Projects;

              niriDeepDevBinary = "${toString projectsRoot}/yeet-and-yoink/target/release/yny";

              niriDeepZellijBreak =
                let
                  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
                    targets = [ "wasm32-wasip1" ];
                  };
                  rustPlatform = pkgs.makeRustPlatform {
                    cargo = rustToolchain;
                    rustc = rustToolchain;
                  };
                in
                rustPlatform.buildRustPackage {
                  pname = "yeet-and-yoink-zellij-break";
                  version = "0.1.0";
                  src = lib.cleanSourceWith {
                    src = yeetAndYoink.root;
                    filter = path: type:
                      let
                        baseName = builtins.baseNameOf path;
                      in
                      baseName != "target" && baseName != ".git";
                  };
                  cargoLock.lockFile = yeetAndYoink.requirePath "Cargo.lock";
                  buildPhase = ''
                    runHook preBuild
                    cargo build --frozen --release --target wasm32-wasip1
                    runHook postBuild
                  '';
                  doCheck = false;
                  installPhase = ''
                    runHook preInstall
                    mkdir -p $out
                    if [ -f target/wasm32-wasip1/release/yeet-and-yoink-zellij-break.wasm ]; then
                      install -m0644 target/wasm32-wasip1/release/yeet-and-yoink-zellij-break.wasm $out/yeet-and-yoink-zellij-break.wasm
                    else
                      echo "yeet-and-yoink-zellij-break.wasm not found after build" >&2
                      exit 1
                    fi
                    runHook postInstall
                  '';
                };

              niriDeepZellijBreakPlugin = "${niriDeepZellijBreak}/yeet-and-yoink-zellij-break.wasm";
            in {
              home.packages = [
                pkgs.docker-client
              ];

              home.sessionVariables = {
                NIRI_DEEP_ZELLIJ_BREAK_PLUGIN = niriDeepZellijBreakPlugin;
                DOCKER_CONTEXT = "host-mac";
              };

              programs.zellij.settings.load_plugins = [
                "file:${niriDeepZellijBreakPlugin}"
              ];

              programs.ssh = {
                enable = true;
                enableDefaultConfig = false;
                matchBlocks."mac-host-docker" = {
                  hostname = "192.168.130.1";
                  user = "m";
                  identityFile = "~/.ssh/id_ed25519";
                  controlMaster = "auto";
                  controlPersist = "10m";
                  controlPath = "~/.ssh/control-%h-%p-%r";
                  serverAliveInterval = 30;
                };
              };

              programs.niri.settings = {
                hotkey-overlay = {
                  skip-at-startup = true;
                };
                prefer-no-csd = true;
                input = {
                  mod-key = "Alt";
                  keyboard.xkb.layout = "us";
                  keyboard.repeat-delay = 150;
                  keyboard.repeat-rate = 50;
                  touchpad = {
                    tap = true;
                    natural-scroll = true;
                  };
                };

                window-rules = [
                  {
                    geometry-corner-radius = {
                      top-left = 12.0;
                      top-right = 12.0;
                      bottom-right = 12.0;
                      bottom-left = 12.0;
                    };
                  }
                  {
                    clip-to-geometry = true;
                  }
                ];

                outputs."Virtual-1".scale = 2.0;

                layout = {
                  always-center-single-column = true;
                  gaps = 16;
                  center-focused-column = "never";
                  preset-column-widths = [
                    { proportion = 1.0 / 3.0; }
                    { proportion = 1.0 / 2.0; }
                    { proportion = 2.0 / 3.0; }
                  ];
                  default-column-width.proportion = 0.5;
                  focus-ring = {
                    width = 2;
                    active.color = "#7fc8ff";
                    inactive.color = "#505050";
                  };
                };

                spawn-at-startup = [
                  { command = [ "mako" ]; }
                ];

                workspaces = {
                  "stash" = { };
                };

                environment = {
                  NIXOS_OZONE_WL = "1";
                  NIRI_DEEP_ZELLIJ_BREAK_PLUGIN = niriDeepZellijBreakPlugin;
                };

                binds = {
                  "Mod+T".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "org.wezfurlong.wezterm"
                    "--spawn" "wezterm"
                  ];
                  "Mod+Shift+T".action.spawn = "wezterm";

                  "Mod+S".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "librewolf"
                    "--spawn" "librewolf"
                  ];
                  "Mod+Shift+S".action.spawn = "librewolf";

                  "Mod+P".action.spawn = [
                    niriDeepDevBinary "focus-or-cycle"
                    "--app-id" "spotify"
                    "--spawn" "spotify"
                    "--summon"
                  ];

                  "Mod+Space".action.spawn = "wlr-which-key";
                  "Mod+Q".action.close-window = {};

                  "Mod+R".action.switch-preset-column-width = {};
                  "Mod+F".action.maximize-column = {};
                  "Mod+Shift+F".action.fullscreen-window = {};
                  "Mod+Minus".action.set-column-width = "-10%";
                  "Mod+Equal".action.set-column-width = "+10%";
                  "Mod+W".action.toggle-column-tabbed-display = {};
                  "Mod+Slash".action.toggle-overview = {};

                  "Mod+N".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "west" ];
                  "Mod+E".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "south" ];
                  "Mod+I".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "north" ];
                  "Mod+O".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "focus" "east" ];

                  "Mod+H".action.consume-or-expel-window-left = {};
                  "Mod+L".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "west" ];
                  "Mod+U".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "south" ];
                  "Mod+Y".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "north" ];
                  "Mod+Semicolon".action.spawn = [ niriDeepDevBinary "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" "move" "east" ];
                  "Mod+Return".action.consume-or-expel-window-right = {};

                  "Mod+f1".action.focus-workspace = 1;
                  "Mod+f2".action.focus-workspace = 2;
                  "Mod+f3".action.focus-workspace = 3;
                  "Mod+f4".action.focus-workspace = 4;
                  "Mod+f5".action.focus-workspace = 5;
                  "Mod+f6".action.focus-workspace = 6;
                  "Mod+f7".action.focus-workspace = 7;
                  "Mod+f8".action.focus-workspace = 8;
                  "Mod+f9".action.focus-workspace = 9;

                  "Shift+f1".action.move-column-to-workspace = 1;
                  "Shift+f2".action.move-column-to-workspace = 2;
                  "Shift+f3".action.move-column-to-workspace = 3;
                  "Shift+f4".action.move-column-to-workspace = 4;
                  "Shift+f5".action.move-column-to-workspace = 5;
                  "Shift+f6".action.move-column-to-workspace = 6;
                  "Shift+f7".action.move-column-to-workspace = 7;
                  "Shift+f8".action.move-column-to-workspace = 8;
                  "Shift+f9".action.move-column-to-workspace = 9;
                };
              };

              home.activation.ensureHostDockerContext =
                lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
                    run ${pkgs.docker-client}/bin/docker context create host-mac \
                      --docker "host=ssh://m@mac-host-docker"
                  fi
                '';

              systemd.user.services.uniclip = {
                Unit = {
                  Description = "Uniclip clipboard client (direct connection to macOS server)";
                  After = [ "graphical-session.target" ];
                };
                Service = {
                  Type = "simple";
                  ExecStart = "${pkgs.writeShellScript "uniclip-client" ''
                    set -euo pipefail
                    export XDG_RUNTIME_DIR=/run/user/$(id -u)
                    export PATH=${lib.makeBinPath [ pkgs.wl-clipboard ]}:$PATH
                    if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
                      export WAYLAND_DISPLAY=wayland-1
                    elif [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
                      export WAYLAND_DISPLAY=wayland-0
                    else
                      echo "uniclip: no wayland socket found in $XDG_RUNTIME_DIR" >&2
                      exit 1
                    fi
                    if [ ! -r /run/secrets/uniclip/password ]; then
                      echo "uniclip: /run/secrets/uniclip/password is missing" >&2
                      exit 1
                    fi
                    UNICLIP_PASSWORD="$(cat /run/secrets/uniclip/password)"
                    if [ -z "$UNICLIP_PASSWORD" ]; then
                      echo "uniclip: empty password from /run/secrets/uniclip/password" >&2
                      exit 1
                    fi
                    export UNICLIP_PASSWORD
                    exec ${pkgs.uniclip}/bin/uniclip --secure 192.168.130.1:53701
                  ''}";
                  Restart = "on-failure";
                  RestartSec = 5;
                };
                Install.WantedBy = [ "graphical-session.target" ];
              };
            };
        })
    ];
  };
}
