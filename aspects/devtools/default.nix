{ den, lib, ... }: {
  den.aspects.devtools.homeManager = { pkgs, lib, config, ... }: {
    home.packages = with pkgs; [
      # LLM 
      llm-agents.omp llm-agents.pi llm-agents.codex llm-agents.skills herdr
      # Dev Tools
      devenv just gnumake pixi cmake 
      harlequin dbeaver-bin d2 adrs bws parallel uniclip wezterm ninja 
      # DevOps & Cloud
      fluxcd kubecm kubecolor kubectl kubernetes-helm terragrunt s3fs k9s lazydocker
      # Testing
      (bats.withLibraries (libs: with libs; [ bats-support bats-assert bats-file bats-detik ]))
      # Languages & Runtimes
      go gopls protobuf bun uv nodejs_22 (lib.hiPrio python314) ty
      # LLVM
      llvmPackages_21.clang-tools llvmPackages_21.lld llvmPackages_21.lldb llvmPackages_21.libcxx
      # Rust Nightly
      (rust-bin.nightly.latest.default.override {
        extensions = [ "rust-src" "rust-analyzer" ];
        targets = [ "wasm32-wasip1" "wasm32-unknown-unknown" "wasm32-wasip2" ];
      })
    ];

    home.file = {
      ".gdbinit".source = ./gdbinit;
      ".cargo/config.toml".text = ''
        [build]
        target-dir = "/Volumes/crucialP3/.cargo/target"
      '';
    };
  };
}
