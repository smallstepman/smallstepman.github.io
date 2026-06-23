{ generated, ... }: {
  den.aspects.touchid = {
    darwin = import ./_darwin.nix { inherit generated; };
    homeManager = { pkgs, ... }: let
      vmTouchIdKnownHosts = "/Users/m/.ssh/known_hosts_vm_touchid_bridge";
      vmTouchIdVmKnownHostsEntry = "192.168.130.3 ${builtins.readFile (generated.requireFile "vm-host-ssh-ed25519.pub")}";
    in {
      home.file.".ssh/${builtins.baseNameOf vmTouchIdKnownHosts}".text = vmTouchIdVmKnownHostsEntry;
    };
  };
}
