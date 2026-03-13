{ isWSL, inputs, currentSystemName, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
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

  # Per-project flakes sourced with direnv and nix-shell handle most packages.
  home.packages = [] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.ghostty-bin

    pkgs.skhd
    pkgs.cachix
    pkgs.gettext
    pkgs.sentry-cli
    pkgs.rsync         # newer rsync than macOS ships
    pkgs.sshpass       # non-interactive ssh password auth
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.file =
    (if isDarwin then {
    # not gonna manage plists, but keep them here to remember
    # "Library/Preferences/com.MrKai77.Loop.plist".source = ./com.MrKai77.Loop.plist;
    # "Library/Preferences/com.brnbw.Leader-Key.plist".source = ./com.brnbw.Leader-Key.plist;
    # not ready yet to freeze it
    # "Library/Application Support/Leader Key/config.json".source = ./leader-key-config.json;
  } else {}) // (if isLinux then {
    # Claude Code apiKeyHelper: fetches token from rbw on demand (auto-refreshes every 5min)
    # ".claude/settings.json".text = builtins.toJSON {
    #   apiKeyHelper = "${pkgs.rbw}/bin/rbw get claude-oauth-token";
    # };
  } else {});


  xdg.configFile = {
    "grm/repos.yaml".source = ./grm-repos.yaml;
  } // (if isDarwin then {
    "wezterm/wezterm.lua".text = builtins.readFile ./wezterm.darwin.lua;
    "activitywatch/scripts" = {
      source = ./activitywatch;
      recursive = true;
    };
    "kanata-tray" = {
      source = ./kanata/tray;
      recursive = true;
    };
    "kanata" = {
      source = ./kanata/config-macbook-iso;
      recursive = true;
    };
  } else {});

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  # rbw (Bitwarden) configuration.
  # macOS: brew-managed, manual setup (`brew install rbw && rbw register`).
  # Linux/VM: Nix-managed package. Config file is written by the rbw-config
  #           systemd service (reads email from sops), NOT by home-manager.
  programs.rbw = lib.mkIf isLinux {
    enable = true;
    settings = {
      base_url = "https://api.bitwarden.eu";
      email = "overwritten-by-systemd";
      lock_timeout = 86400; # 24 hours
      pinentry = if isWSL then pkgs.pinentry-tty else pkgs.wayprompt;
    };
  };

}
