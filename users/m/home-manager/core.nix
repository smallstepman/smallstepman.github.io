# Core home-manager configuration: base packages, env vars, dotfiles.
# Every machine (VM, macOS, WSL, rpi, vps, GPU server) imports this module.
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));
in {
  # Home-manager 22.11 requires this be set. We never set it so we have
  # to use the old state version.
  home.stateVersion = "18.09";

  # Disabled for now since we mismatch our versions. See flake.nix for details.
  home.enableNixpkgsReleaseCheck = false;

  xdg.enable = true;

  #---------------------------------------------------------------------
  # Packages
  #---------------------------------------------------------------------

  # Packages I always want installed. Most packages I install using
  # per-project flakes sourced with direnv and nix-shell, so this is
  # not a huge list.
  home.packages = [
    pkgs.bat
    pkgs.eza
    pkgs.fd
    pkgs.bws
    pkgs.fzf
    pkgs.jq
    pkgs.fluxcd
    pkgs.kubecolor
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.rbw
    pkgs.ripgrep
    pkgs.tree
    pkgs.watch
    pkgs.nerd-fonts.symbols-only  # icon font for Doom Emacs (+icons) and terminal apps
    pkgs.emacs-all-the-icons-fonts  # all-the-icons font family for Emacs

    # CLI tools
    pkgs.yazi          # terminal file manager
    pkgs.btop          # system monitor
    pkgs.gnumake       # make
    pkgs.just          # command runner
    pkgs.tig           # git TUI
    pkgs.difi          # terminal git diff reviewer
    pkgs.agent-of-empires  # terminal session manager for AI agents
    pkgs.dust          # disk usage analyzer (du alternative)
    pkgs.zoxide

    # Clipboard sharing (macOS <-> VM via SSH tunnel)
    pkgs.uniclip

  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.skhd
    pkgs.cachix
    pkgs.gettext
    pkgs.sentry-cli
    pkgs.rsync         # newer rsync than macOS ships
    pkgs.sshpass       # non-interactive ssh password auth
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    (pkgs.writeShellScriptBin "sentry-cli" ''
      SENTRY_AUTH_TOKEN=$(${pkgs.rbw}/bin/rbw get "sentry-auth-token") \
        exec ${pkgs.sentry-cli}/bin/sentry-cli "$@"
    '')
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionPath = lib.optionals isDarwin [
    "/Applications/VMware Fusion.app/Contents/Library"
  ];

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";

  } // (if isDarwin then {
    # See: https://github.com/NixOS/nixpkgs/issues/390751
    DISPLAY = "nixpkgs-390751";
  } else {});

  home.file = {
    ".gdbinit".source = ../gdbinit;
    ".inputrc".source = ../inputrc;
  } // (if isDarwin then {
    # not gonna manage plists, but keep them here to remember
    # "Library/Preferences/com.MrKai77.Loop.plist".source = ../com.MrKai77.Loop.plist;
    # "Library/Preferences/com.brnbw.Leader-Key.plist".source = ../com.brnbw.Leader-Key.plist;
    # "Library/Preferences/com.knollsoft.Rectangle.plist".source = ../com.knollsoft.Rectangle.plist;
    # not ready yet to freeze it
    # "Library/Application Support/Leader Key/config.json".source = ../leader-key-config.json;
  } else {});

  xdg.configFile = {
    "rofi/config.rasi".text = builtins.readFile ../rofi;
    "grm/repos.yaml".source = ../grm-repos.yaml;
    "tmux/menus/doomux.sh" = {
      source = ../tmux/doomux.sh;
      executable = true;
    };
  } // (if isDarwin then {
    "ghostty/config".text = builtins.readFile ../ghostty.darwin.cfg;
    "kanata-tray" = {
      source = ../kanata/tray;
      recursive = true;
    };
    "kanata" = {
      source = ../kanata/config-macbook-iso;
      recursive = true;
    };
    "rectangle/RectangleConfig.json".text = builtins.readFile ../RectangleConfig.json;
    # "karabiner/karabiner.json".source = ../kanata/karabiner.json; # keeping it in kanata/ since i dont use it directly with karabiner, but via kanata
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ../ghostty.linux.cfg;
    # Prevent home-manager from managing rbw config as a read-only store symlink;
    # the rbw-config systemd service writes the real config with sops email.
    "rbw/config.json".enable = lib.mkForce false;

    # wlr-which-key configuration
    "wlr-which-key/config.yaml".text = builtins.readFile ../wlr-which-key-config.yaml;
  } else {});

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

  # tmux-menus needs a writable plugin directory for cache files.
  home.activation.installWritableTmuxMenus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    src=${pkgs.tmuxPlugins."tmux-menus"}/share/tmux-plugins/tmux-menus
    dst="$HOME/.local/share/tmux/plugins/tmux-menus"
    run mkdir -p "$HOME/.local/share/tmux/plugins"
    run rm -rf "$dst"
    run cp -R "$src" "$dst"
    run chmod -R u+w "$dst"
  '';
}
