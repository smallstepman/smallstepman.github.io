# Development tools: language runtimes, editors, language servers.
# Imported by development machines; headless servers may skip this.
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  home.packages = [
    pkgs.go
    pkgs.gopls

    # Rust toolchain (via rust-overlay)
    (pkgs.rust-bin.stable.latest.default.override {
      extensions = [ "rust-src" "rust-analyzer" ];
    })

    # Python + uv
    pkgs.python312
    pkgs.uv

    # Node.js with npx (included) + fnm for version management
    pkgs.nodejs_22
    pkgs.fnm
  ] ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.clang
    pkgs.valgrind
  ]);

  # Doom Emacs (via nix-doom-emacs-unstraightened)
  programs.doom-emacs = {
    enable = true;
    doomDir = ../doom;
    emacs = pkgs.emacs-pgtk;
    # :config literate has no effect in unstraightened; tangle config.org at build time
    # tangleArgs = "--all config.org";
  };

  # Emacs daemon as a systemd user service (Linux only; macOS has no systemd)
  services.emacs = lib.mkIf isLinux {
    enable = true;
    defaultEditor = false; # we set EDITOR to nvim elsewhere
  };

  programs.vscode = {
    enable = true;
    profiles = {
      default = {
        extensions = import ../vscode/extensions.nix { inherit pkgs; };
        keybindings = builtins.fromJSON (builtins.readFile ../vscode/keybindings.json);
        userSettings = builtins.fromJSON (builtins.readFile ../vscode/settings.json);
      };
    };
  };

  programs.go = {
    enable = true;
    env = { 
      GOPATH = "Documents/go";
      GOPRIVATE = [ "github.com/smallstepman" ];
    };
  };

  programs.lazyvim = {
    enable = true;
    configFiles = ../lazyvim;

    extras = {
      lang.nix.enable = true;
      lang.python = {
        enable = true;
        installDependencies = true;        # Install ruff
        installRuntimeDependencies = true; # Install python3
      };
      lang.go = {
        enable = true;
        installDependencies = true;        # Install gopls, gofumpt, etc.
        installRuntimeDependencies = true; # Install go compiler
      };
      lang.typescript = {
        enable = true;
        installDependencies = false;        # Skip typescript tools
        installRuntimeDependencies = true;  # But install nodejs
      };
      lang.rust.enable = true;
      ai.copilot.enable = true;

    };

    # Additional packages (optional)
    extraPackages = with pkgs; [
      nixd        # Nix LSP
      alejandra   # Nix formatter
      pyright     # Python LSP
    ];

    # Only needed for languages not covered by LazyVim extras
    treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
      templ     # Go templ files
    ];

  };
}
