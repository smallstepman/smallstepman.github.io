{ pkgs, ... }:

let
  opencode = import ./common.nix;
in {
  launchd.user.agents.opencode-web = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          ${pkgs.opencode}/bin/opencode models --refresh
          exec ${pkgs.opencode}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port 80 # ${toString opencode.webPort}
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/opencode-web.log";
      StandardErrorPath = "/tmp/opencode-web.log";
    };
  };
}
