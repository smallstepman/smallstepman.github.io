{ lib, ... }: {
  den.aspects.devtools = {
    homeManager = { pkgs, lib, config, ... }: {
      home.packages = [
        pkgs.devenv pkgs.just pkgs.gnumake pkgs.pixi

        pkgs.harlequin pkgs.btop pkgs.glowm pkgs.dust pkgs.tree
        pkgs.watch pkgs.websocat pkgs.yq pkgs.jq pkgs.d2 pkgs.adrs

        pkgs.dbeaver-bin

        pkgs.bws pkgs.fluxcd pkgs.kubernetes-helm pkgs.terragrunt pkgs.kubecm

        pkgs.parallel
        (pkgs.bats.withLibraries (libs: with libs; [ bats-assert bats-file ]))

        pkgs.go pkgs.gopls pkgs.protobuf pkgs.bun
        (pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        })
        (lib.hiPrio pkgs.python314)
        pkgs.uv pkgs.nodejs_22
        pkgs.llvmPackages_21.clang-tools
        pkgs.llvmPackages_21.lld pkgs.llvmPackages_21.lldb pkgs.llvmPackages_21.libcxx

        pkgs.s3fs pkgs.cmake pkgs.ninja

        pkgs.uniclip
      ];

      home.file.".gdbinit".source = ./gdbinit;

      home.file.".cargo/config.toml".text = "[build]\n" + "#target-dir = \"" + config.home.homeDirectory + "/.cargo/target\"\ntarget-dir = \"/Volumes/crucialP3/.cargo/target\"";

      programs.go = {
        enable = true;
        env = {
          GOPATH = "Documents/go";
          GOPRIVATE = [ "github.com/smallstepman" ];
        };
      };
    };
  };
}
