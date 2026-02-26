# Git, GitHub CLI, GPG, and secrets configuration.
# Every machine imports this module for version control and auth.
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  programs.gpg.enable = !isDarwin;

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  # gh with credential helper: replaces credential.helper = "store"
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

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

  programs.git = {
    enable = true;
    signing = {
      key = "247AE5FC6A838272";
      signByDefault = true;
    };
    settings = {
      user.name = "Marcin Nowak Liebiediew";
      user.email = "m.liebiediew@gmail.com";
      gpg.program = if isDarwin then "/opt/homebrew/bin/gpg" else "${pkgs.gnupg}/bin/gpg";
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      # Git credentials handled by programs.gh.gitCredentialHelper
      github.user = "smallstepman";
      push.default = "tracking";
      init.defaultBranch = "main";
      aliases = {
        cleanup = "!git branch --merged | grep  -v '\\*\\|master\\|develop' | xargs -n 1 -r git branch -d";
        prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        root = "rev-parse --show-toplevel";
        ce = "git commit --amend --no-edit";
      };
    };
  };
}
