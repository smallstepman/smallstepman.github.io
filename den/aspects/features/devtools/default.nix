{ den, lib, inputs, ... }: {
  den.aspects.devtools = {
    homeManager = { pkgs, lib, config, ... }: {
      home.packages = [
        pkgs.llm-agents.omp
        pkgs.llm-agents.pi
        pkgs.llm-agents.codex
        pkgs.llm-agents.apm
        pkgs.llm-agents.skills

        pkgs.devenv
        pkgs.just
        pkgs.gnumake

        pkgs.harlequin
        pkgs.btop
        pkgs.glowm
        pkgs.dust
        pkgs.tree
        pkgs.watch
        pkgs.websocat
        pkgs.yq
        pkgs.jq
        pkgs.d2
        pkgs.adrs

        pkgs.dbeaver-bin

        pkgs.bws
        pkgs.fluxcd
        pkgs.kubernetes-helm
        pkgs.terragrunt
        pkgs.kubecm


        pkgs.cachix
        pkgs.gettext
        pkgs.sentry-cli
        pkgs.parallel
        (pkgs.bats.withLibraries (libs: [
          libs.bats-support
          libs.bats-assert
          libs.bats-file
          libs.bats-detik
        ]))

        pkgs.pixi
        pkgs.uv
        pkgs.go
        pkgs.gopls
        pkgs.protobuf
        pkgs.bun
        (pkgs.rust-bin.nightly.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ "wasm32-wasip1" "wasm32-unknown-unknown" "wasm32-wasip2" ];
        })
        (lib.hiPrio pkgs.python314)
        pkgs.nodejs_22
        pkgs.cmake
        pkgs.llvmPackages_21.clang-tools
        pkgs.llvmPackages_21.lld
        pkgs.llvmPackages_21.lldb
        pkgs.llvmPackages_21.libcxx

        pkgs.s3fs
        pkgs.ninja

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
