{ lib, ... }: {
  den.aspects.shell = {
    darwin = { pkgs, ... }: {
      programs.zsh.enable = true;
      programs.zsh.shellInit = ''
        # Nix
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
        # End Nix
      '';
      programs.fish.enable = true;
      programs.fish.shellInit = ''
        # Nix
        if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
          source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
        end
        # End Nix
      '';
      environment.shells = with pkgs; [ bashInteractive zsh fish ];
      environment.systemPackages = with pkgs; [ cachix ];
    };

    homeManager = { pkgs, lib, config, ... }:
      let
        isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
        isLinux = !isDarwin;
        isWSL = false;
        isNonWSLLinux = isLinux;

        generatedDirSetup = lib.removeSuffix "\n" ''
          generated_dir="''${GENERATED_INPUT_DIR:-''${HOME}/.local/share/nix-config-generated}"
        '';

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
      in {
        home.stateVersion = "18.09";
        home.enableNixpkgsReleaseCheck = false;
        xdg.enable = true;

        home.file.".inputrc".source = ./inputrc;

        home.sessionVariables = {
          LANG     = "en_US.UTF-8";
          LC_CTYPE = "en_US.UTF-8";
          LC_ALL   = "en_US.UTF-8";
          EDITOR   = "nvim";
          PAGER    = "less -FirSwX";
          MANPAGER = "${
            pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
              sh -c 'col -bx | bat -l man -p'
            '' else ''
              cat "$1" | col -bx | bat --language man --style plain
            '')
          }/bin/manpager";
        } // (lib.optionalAttrs isDarwin {
          DISPLAY = "nixpkgs-390751";
        });

        home.sessionPath =
          lib.optionals (isDarwin || isNonWSLLinux) [
            "${config.home.homeDirectory}/.local/bin"
            "${config.home.homeDirectory}/.cargo/target/release"
          ]
          ++ lib.optionals isDarwin [
            "/Applications/VMware Fusion.app/Contents/Library"
          ];

        home.packages = [
          pkgs.bat pkgs.dua pkgs.dust pkgs.eza pkgs.fd pkgs.fnm pkgs.fzf
          pkgs.jq pkgs.kubecolor pkgs.kubectl pkgs.mdfried pkgs.rbw pkgs.ripgrep
          pkgs.basalt pkgs.trash-cli pkgs.zellij pkgs.kitty pkgs.alacritty pkgs.wezterm
        ] ++ lib.optionals (niksWorktree != null) [ niksWorktree ];

        programs.yazi = {
          enable = true;
          shellWrapperName = "y";
          package = pkgs.yazi;
          plugins = {
            ohlcv = ./yazi/ohlcv.yazi;
            overlap = ./yazi/overlap.yazi;
            dvces = ./yazi/dvces.yazi;
            duckdb = pkgs.fetchFromGitHub {
              owner = "wylie102";
              repo = "duckdb.yazi";
              rev = "3f8c8633d4b02d3099cddf9e892ca5469694ba22";
              hash = "sha256-XQM459V3HbPgXKgd9LnAIKRQOAaJPdZA/Tp91TSGHqY=";
            };
            "recycle-bin" = pkgs.fetchFromGitHub {
              owner = "uhs-robert";
              repo = "recycle-bin.yazi";
              rev = "fa687116c46a784e664ef96619b32abf51f29b06";
              hash = "sha256-lpxTGWA15szM5VJ+qvV2+GTg7HXiZaZfyWyjeNMsTSM=";
            };
          };
          settings = builtins.fromTOML (builtins.readFile ./yazi/settings.toml);
          theme = builtins.fromTOML (builtins.readFile ./yazi/theme.toml);
          keymap = builtins.fromTOML (builtins.readFile ./yazi/keymap.toml);
          initLua = builtins.readFile ./yazi/init.lua;
          extraPackages = [
            pkgs.duckdb pkgs.python314 pkgs.trash-cli
          ];
        };

        xdg.configFile."tmux/menus/doomux.sh" = {
          source = ./tmux/doomux.sh;
          executable = true;
        };

        home.activation.installWritableTmuxMenus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          src=${pkgs.tmuxPlugins."tmux-menus"}/share/tmux-plugins/tmux-menus
          dst="$HOME/.local/share/tmux/plugins/tmux-menus"
          run mkdir -p "$HOME/.local/share/tmux/plugins"
          run rm -rf "$dst"
          run cp -R "$src" "$dst"
          run chmod -R u+w "$dst"
        '';

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

        programs.starship = {
          enable = false;
          settings = builtins.fromTOML (builtins.readFile ./starship.toml);
        };

        programs.zsh = {
          enable = true;
          autocd = true;
          dotDir = "${config.xdg.configHome}/zsh";
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          shellAliases = {
            g = "git"; gs = "git status"; ga = "git add"; gaa = "git add .";
            gc = "git commit"; gcc = "git commit -m"; gaacc = "git add . && git commit -m";
            gl = "git log --oneline"; gll = "git log"; gp = "git push";
            gco = "git checkout"; gcp = "git cherry-pick"; gd = "git diff";
            j = "just"; jj = "just -g"; jjfo = "just -g focusedride";
            l = "ls"; lah = "eza -alh --color=auto --group-directories-first --icons";
            la = "eza -la"; ll = "eza -lh --color=auto --group-directories-first --icons";
            magit = "emacsclient -a \"\" -nw -e -q '(progn (magit-status))'";
            "nix-gc" = "nix-collect-garbage -d";
            rs = "cargo"; kubectl = "kubecolor";
            nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";
          } // (lib.optionalAttrs isLinux {
            niks = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
            nikt = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
            nikw = "${niksWorktree}/bin/niks-worktree";
            open = "xdg-open";
            pbcopy = "wl-copy --type text/plain";
            pbpaste = "wl-paste --type text/plain";
            noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
          }) // (lib.optionalAttrs isNonWSLLinux {
            nikw = "${niksWorktree}/bin/niks-worktree";
          }) // (lib.optionalAttrs isDarwin {
            niks = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
            nikt = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
            nikw = "${niksWorktree}/bin/niks-worktree";
            pinentry = "pinentry-mac";
          });
          initContent = ''
            # VSCode shell integration
            [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

            # fnm (Node version manager)
            eval "$(fnm env --use-on-cd)"
            bindkey -v
            source ${./zsh-manydot.sh}

            # Add a `y` function to zsh that opens yazi either at the given directory or
            # at the one zoxide's `z` command would pick.
            unalias y 2>/dev/null || true
            y() {
              if [ "$#" -eq 0 ]; then yazi
              elif [ "$#" -eq 1 ] && [ -d "$1" ]; then yazi "$1"
              elif [ "$#" -eq 2 ] && [ "$1" = "--" ]; then yazi "$2"
              else
                local result
                result="$(zoxide query --exclude "$(\builtin pwd -L)" -- "$@")" && yazi "$result"
              fi
              return $?
            }

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
          '') + ''

            # Zummoner - AI CLI command helper (bound to Ctrl+L)
            zummoner() {
              local question="$BUFFER"
              local prompt=$(cat ${./zummoner-prompt.txt})
              BUFFER="$question ... thinking"
              zle -R
              local response
              response=$(curl -sf http://localhost:1234/api/v1/chat \
                -H "Content-Type: application/json" \
                -d "$(jq -n \
                  --arg model "google/gemma-4-e4b" \
                  --arg system_prompt "$prompt" \
                  --arg input "$question" \
                  '{model: $model, system_prompt: $system_prompt, input: $input}')")
              local command
              command=$(printf '%s' "$response" | jq -r '.output[0].content // empty' | sed 's/```//g' | tr -d '\n')
              if [[ -n "$command" ]]; then
                QUESTION="$(echo $question | cut -d '#' -f 2)"
                BUFFER="$command # $QUESTION"
                CURSOR=''${#BUFFER}
              else
                BUFFER="$question ... no results"
              fi
            }
            zle -N zummoner
            bindkey '\C-e' zummoner
          '';
        };

        programs.bash = {
          enable = true;
          shellOptions = [];
          historyControl = [ "ignoredups" "ignorespace" ];
          initExtra = builtins.readFile ./bashrc;
          shellAliases = {
            g = "git"; gs = "git status"; ga = "git add"; gaa = "git add .";
            gc = "git commit"; gcc = "git commit -m"; gaacc = "git add . && git commit -m";
            gl = "git log --oneline"; gll = "git log"; gp = "git push";
            gco = "git checkout"; gcp = "git cherry-pick"; gd = "git diff";
            j = "just"; l = "ls"; lah = "eza -alh"; la = "eza -la"; ll = "eza -lh";
            "nix-gc" = "nix-collect-garbage -d";
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
          settings = builtins.fromJSON (builtins.readFile ./oh-my-posh.json);
        };
      };
  };
}
