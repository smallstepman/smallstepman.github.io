{ den, lib, ... }: {

  den.aspects.shell = {
    includes = [
      ({ host, ... }:
        let
          isDarwin      = host.class == "darwin";
          isLinux       = host.class == "nixos";
          isWSL         = host.wsl.enable or false;
          isNonWSLLinux = isLinux && !isWSL;
          generatedDirSetup = lib.removeSuffix "\n" ''
            generated_dir="''${GENERATED_INPUT_DIR:-''${HOME}/.local/share/nix-config-generated}"
          '';
        in {
          homeManager = { pkgs, lib, ... }:
            let
              niksWorktree = if isDarwin || isNonWSLLinux then pkgs.writeShellApplication {
                name = "niks-worktree";
                runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.fzf ];
                text =
                  let
                    repoRoot = if isDarwin then "~/.config/nix" else "/nixos-config";
                    applyCommand =
                      if isDarwin then ''
                        cd "$selected"
                        NIXPKGS_ALLOW_UNFREE=1 nix build \
                          --extra-experimental-features 'nix-command flakes' \
                          "path:$wrapper#darwinConfigurations.macbook-pro-m1.system" \
                          --no-write-lock-file \
                          --max-jobs 8 \
                          --cores 0
                        sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch \
                          --flake "path:$wrapper#macbook-pro-m1" \
                          --no-write-lock-file
                      '' else ''
                        sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch \
                          --flake "path:$wrapper#vm-aarch64" \
                          --no-write-lock-file
                      '';
                  in ''
                    set -euo pipefail

                    repo_root=${repoRoot}

                    generated_dir="''${GENERATED_INPUT_DIR:-}"
                    if [ -z "$generated_dir" ]; then
                      if [ -d "$HOME/.local/share/nix-config-generated" ]; then
                        generated_dir="$HOME/.local/share/nix-config-generated"
                      elif [ -d /nixos-generated ]; then
                        generated_dir=/nixos-generated
                      else
                        echo "niks-worktree: generated dataset missing; set GENERATED_INPUT_DIR" >&2
                        exit 1
                      fi
                    fi

                    if ! { [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; }; then
                      if [ -r /dev/tty ] && [ -w /dev/tty ]; then
                        exec </dev/tty >/dev/tty 2>/dev/tty
                      else
                        echo "niks-worktree: interactive terminal required" >&2
                        exit 1
                      fi
                    fi

                    list_repos() {
                      printf '%s\n' "$repo_root"
                      if [ -d "$repo_root/.worktrees" ]; then
                        find "$repo_root/.worktrees" -mindepth 1 -maxdepth 1 -type d | sort
                      fi
                    }

                    choose_repo() {
                      local selected
                      mapfile -t repos < <(list_repos)
                      if [ "''${#repos[@]}" -eq 0 ]; then
                        echo "niks-worktree: no repo roots found under $repo_root" >&2
                        return 1
                      fi

                      if command -v fzf >/dev/null 2>&1; then
                        selected=$(printf '%s\n' "''${repos[@]}" | fzf --prompt='niks-worktree> ')
                        [ -n "$selected" ] || return 1
                        printf '%s\n' "$selected"
                        return 0
                      fi

                      PS3='Select nix worktree: '
                      select selected in "''${repos[@]}"; do
                        [ -n "$selected" ] || continue
                        printf '%s\n' "$selected"
                        return 0
                      done
                    }

                    selected=$(choose_repo)
                    wrapper=$(NIX_CONFIG_DIR="$selected" GENERATED_INPUT_DIR="$generated_dir" bash "$selected/scripts/external-input-flake.sh")

                    ${applyCommand}
                  '';
              } else null;

              shellAliases = {
                g     = "git";
                gs    = "git status";
                ga    = "git add";
                gc    = "git commit";
                gl    = "git prettylog";
                gp    = "git push";
                gco   = "git checkout";
                gcp   = "git cherry-pick";
                gdiff = "git diff";

                l   = "ls";
                lah = "eza -alh --color=auto --group-directories-first --icons";
                la  = "eza -la";
                ll  = "eza -lh --color=auto --group-directories-first --icons";
                magit        = "emacsclient -a \"\" -nw -e -q '(progn (magit-status))'";
                "nix-gc"           = "nix-collect-garbage -d";
                "nix-update-flakes" = "nix flake update";

                # cc = "claude";
                oc  = "opencode";
                ocd = "opencode";
                openspec-in-progress = "openspec list --json | jq -r '.changes[] | select(.status == \"in-progress\").name'";

                rs      = "cargo";
                kubectl = "kubecolor";

                nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";
              } // (lib.optionalAttrs isLinux {
                pbcopy  = "wl-copy --type text/plain";
                pbpaste = "wl-paste --type text/plain";
                open    = "xdg-open";
                noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
                nix-config = "nvim /nix-config";
                niks = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
                nikt = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
              }) // (lib.optionalAttrs isNonWSLLinux {
                "niks-worktree" = "${niksWorktree}/bin/niks-worktree";
              }) // (lib.optionalAttrs isDarwin {
                nix-config = "nvim ~/.config/nix-config";
                niks = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                nikt = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                "niks-worktree" = "${niksWorktree}/bin/niks-worktree";
                pinentry = "pinentry-mac";
              });

              manpager = pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
                sh -c 'col -bx | bat -l man -p'
              '' else ''
                cat "$1" | col -bx | bat --language man --style plain
              '');

            in {
              home.stateVersion = "18.09";
              home.enableNixpkgsReleaseCheck = false;
              xdg.enable = true;

              home.file.".inputrc".source = ../../../dotfiles/common/inputrc;

              home.sessionVariables = {
                LANG     = "en_US.UTF-8";
                LC_CTYPE = "en_US.UTF-8";
                LC_ALL   = "en_US.UTF-8";
                EDITOR   = "nvim";
                PAGER    = "less -FirSwX";
                MANPAGER = "${manpager}/bin/manpager";
              } // (lib.optionalAttrs isDarwin {
                DISPLAY = "nixpkgs-390751";
              });

              home.sessionPath = lib.optionals isDarwin [
                "/Applications/VMware Fusion.app/Contents/Library"
                "/Users/m/.cargo/bin"
              ];

              home.packages = [
                pkgs.bat
                pkgs.dua
                pkgs.dust
                pkgs.eza
                pkgs.fd
                pkgs.fnm
                pkgs.fzf
                pkgs.jq
                pkgs.kubecolor
                pkgs.kubectl
                pkgs.rbw
                pkgs.ripgrep
                pkgs.basalt
                manpager
              ] ++ lib.optionals (niksWorktree != null) [ niksWorktree ];

              programs.zsh = {
                enable = true;
                autocd = true;
                autosuggestion.enable = true;
                syntaxHighlighting.enable = true;
                shellAliases = shellAliases;
                initContent = ''
                  # VSCode shell integration
                  [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

                  # fnm (Node version manager)
                  eval "$(fnm env --use-on-cd)"
                  bindkey -v
                  source ${../../../dotfiles/common/zsh-manydot.sh}

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
                '' + (lib.optionalString isDarwin ''

                  # Homebrew
                  eval "$(/opt/homebrew/bin/brew shellenv)"

                  # NixOS VM management
                  vm() { ~/.config/nix/docs/vm.sh "$@"; }
                '') + (lib.optionalString isLinux ''

                  # gh: inject GITHUB_TOKEN per-invocation from rbw (no global env var)
                  gh() { GITHUB_TOKEN=$(rbw get github-token) command gh "$@"; }

                  # Ad-hoc API key injection (usage: with-openai some-command --flag)
                  with-openai() { OPENAI_API_KEY=$(rbw get openai-api-key) "$@"; }
                  with-amp() { AMP_API_KEY=$(rbw get amp-api-key) "$@"; }
                  copilot() { COPILOT_GITHUB_TOKEN=$(rbw get github-token) command copilot "$@"; }
                  claude() { CLAUDE_CODE_OAUTH_TOKEN=$(rbw get claude-oauth-token) command claude "$@"; }
                  codex() { OPENAI_API_KEY=$(rbw get openai-api-key) command codex "$@"; }
                '');
              };

              programs.bash = {
                enable = true;
                shellOptions = [];
                historyControl = [ "ignoredups" "ignorespace" ];
                initExtra = builtins.readFile ../../../dotfiles/common/bashrc;
                shellAliases = shellAliases;
              };

              programs.direnv = {
                enable = true;
                config = {
                  whitelist = {
                    prefix = [
                      "$HOME/code/go/src/github.com/hashicorp"
                      "$HOME/code/go/src/github.com/smallstepman"
                    ];
                    exact = [ "$HOME/.envrc" ];
                  };
                };
              };

              programs.zoxide = {
                enable = true;
                enableBashIntegration = true;
                enableZshIntegration = true;
              };

              programs.atuin = {
                enable = true;
              };

              programs.oh-my-posh = {
                enable = true;
                settings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/oh-my-posh.json);
              };
            };
        })
    ];
  };

}
