# Shell configuration: zsh, bash, aliases, tmux, direnv, prompt tools.
# Every machine imports this module for consistent shell experience.
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  shellAliases = {
          ".." = "cd ..";
         "..." = "cd ../..";
        "...." = "cd ../../..";
       "....." = "cd ../../../..";
      "......" = "cd ../../../../..";
     "......." = "cd ../../../../../..";
    "........" = "cd ../../../../../../..";

    
    g  = "git";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gl = "git prettylog";
    gp = "git push";
    gt = "git tag";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";

    l = "ls";
    lah = "eza -alh --color=auto --group-directories-first --icons";
    la = "eza -la";
    ll = "eza -lh --color=auto --group-directories-first --icons"; 
    magit = "emacsclient -c -a '' -e '(magit-status)'";
    "nix-gc" = "nix-collect-garbage -d";
    "nix-update-flakes" = "nix flake update";

    cc = "claude";
    oc = "opencode";
    ocd = "opencode-dev";
    openspec-in-progress = "openspec list --json | jq -r '.changes[] | select(.status == \"in-progress\").name'";

    rs = "cargo";
    kubectl = "kubecolor";

    nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";

  } // (if isLinux then {
    pbcopy = "wl-copy --type text/plain";
    pbpaste = "wl-paste --type text/plain";
    open = "xdg-open";
    noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
    nix-config = "nvim /nix-config";
    niks = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake '/nixos-config#vm-aarch64'";
    nikt = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --impure --flake '/nixos-config#vm-aarch64'";
  } else (if isDarwin then {
    nix-config = "nvim ~/.config/nix-config";
    niks = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake '.#macbook-pro-m1'";
    nikt = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --impure --flake '.#macbook-pro-m1'";
  } else {}));
in {
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = shellAliases;
    initContent = ''
      # vscode shell integration (if running inside vscode, which is true for vscode terminal and false for external terminal; this allows us to use the same shell config in both without bloating the external terminal with vscode-specific stuff)
      [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

      # fnm (Node version manager)
      eval "$(fnm env --use-on-cd)"
      bindkey -v

      # Doom-like leader key in zsh vi normal mode when running inside tmux.
      tmux-leader-menu() {
        if [[ -n "$TMUX" ]]; then
          tmux run-shell ~/.config/tmux/menus/doomux.sh
        else
          zle vi-forward-char
        fi
      }
      zle -N tmux-leader-menu
      bindkey -M vicmd " " tmux-leader-menu
    '' + (if isDarwin then ''

      # Homebrew
      eval "$(/opt/homebrew/bin/brew shellenv)"

      # NixOS VM management
      vm() { ~/.config/nix/docs/vm.sh "$@"; }
    '' else "") + (if isLinux then ''

      # gh: inject GITHUB_TOKEN per-invocation from rbw (no global env var)
      gh() { GITHUB_TOKEN=$(rbw get github-token) command gh "$@"; }

      # Ad-hoc API key injection (usage: with-openai some-command --flag)
      with-openai() { OPENAI_API_KEY=$(rbw get openai-api-key) "$@"; }
      with-amp() { AMP_API_KEY=$(rbw get amp-api-key) "$@"; }
    '' else "");
  };

  programs.bash = {
    enable = true;
    shellOptions = [];
    historyControl = [ "ignoredups" "ignorespace" ];
    initExtra = builtins.readFile ../bashrc;
    shellAliases = shellAliases;
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    extraConfig = ''
      set -g @menus_location_x 'C'
      set -g @menus_trigger 'Space'
      set -g @menus_main_menu '${config.home.homeDirectory}/.config/tmux/menus/doomux.sh'
      set -g @menus_display_commands 'No'
      run-shell ~/.local/share/tmux/plugins/tmux-menus/menus.tmux
      set -g status-keys vi
      setw -g mode-keys vi
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g set-clipboard on
    '';
  };

  programs.direnv= {
    enable = true;

    config = {
      whitelist = {
        prefix= [
          "$HOME/code/go/src/github.com/hashicorp"
          "$HOME/code/go/src/github.com/smallstepman"
        ];

        exact = ["$HOME/.envrc"];
      };
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = false;
    settings = builtins.fromTOML (builtins.readFile ../starship.toml);
  };

  programs.atuin = {
    enable = true;
  };

  programs.oh-my-posh = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ../oh-my-posh.json);
  };
}
