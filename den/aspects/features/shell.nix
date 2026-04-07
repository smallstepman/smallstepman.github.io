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
          homeManager = { pkgs, lib, config, ... }:
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
                g        = "git";
                gs       = "git status";
                ga       = "git add";
                gc       = "git commit";
                gl       = "git prettylog";
                gp       = "git push";
                gco      = "git checkout";
                gcp      = "git cherry-pick";
                gdiff    = "git diff";

                j        = "just";
                y        = "yazi";
                l        = "ls";
                lah      = "eza -alh --color=auto --group-directories-first --icons";
                la       = "eza -la";
                ll       = "eza -lh --color=auto --group-directories-first --icons";
                magit    = "emacsclient -a \"\" -nw -e -q '(progn (magit-status))'";
                "nix-gc" = "nix-collect-garbage -d";

                rs       = "cargo";
                kubectl  = "kubecolor";

                nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";
              } // (lib.optionalAttrs isLinux {
                niks     = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
                nikt     = "${generatedDirSetup}; WRAPPER=$(NIX_CONFIG_DIR=/nixos-config GENERATED_INPUT_DIR=\"$generated_dir\" bash /nixos-config/scripts/external-input-flake.sh) && sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --flake \"path:$WRAPPER#vm-aarch64\" --no-write-lock-file";
                nikw     = "${niksWorktree}/bin/niks-worktree";
                open     = "xdg-open";
                pbcopy   = "wl-copy --type text/plain";
                pbpaste  = "wl-paste --type text/plain";
                noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
              }) // (lib.optionalAttrs isNonWSLLinux {
                nikw     = "${niksWorktree}/bin/niks-worktree";
              }) // (lib.optionalAttrs isDarwin {
                niks     = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                nikt     = "cd ~/.config/nix && ${generatedDirSetup} && WRAPPER=$(NIX_CONFIG_DIR=~/.config/nix GENERATED_INPUT_DIR=\"$generated_dir\" bash ~/.config/nix/scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' \"path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system\" --no-write-lock-file && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --flake \"path:$WRAPPER#macbook-pro-m1\" --no-write-lock-file";
                nikw     = "${niksWorktree}/bin/niks-worktree";
                pinentry = "pinentry-mac";
              });

              manpager = pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
                sh -c 'col -bx | bat -l man -p'
              '' else ''
                cat "$1" | col -bx | bat --language man --style plain
              '');

              yaziTheme = builtins.fromTOML ''
                "$schema" = "https://yazi-rs.github.io/schemas/theme.json"

                # vim:fileencoding=utf-8:foldmethod=marker

                # : Manager {{{

                [mgr]
                cwd = { fg = "#D87C4A", bold = true }

                # Hovered
                hovered = { reversed = true, bold = true }
                preview_hovered = { underline = true }

                # Find
                find_keyword = { fg = "#4A8B8B", bold = true, italic = true, underline = true }
                find_position = { fg = "#4A8B8B", bg = "reset", bold = true, italic = true }

                # Marker
                marker_copied = { fg = "#629C7D", bg = "#629C7D" }
                marker_cut = { fg = "#C53030", bg = "#C53030" }
                marker_marked = { fg = "#E5A72A", bg = "#E5A72A" }
                marker_selected = { fg = "#C4693D", bg = "#C4693D" }

                # Count
                count_copied = { fg = "#121212", bg = "#629C7D" }
                count_cut = { fg = "#121212", bg = "#C53030" }
                count_selected = { fg = "#121212", bg = "#C4693D" }

                # Border
                border_symbol = "│"
                border_style = { fg = "#a7a7a7" }

                # : }}}


                # : Tabs {{{

                [tabs]
                active = { fg = "#121212", bg = "#b4b4b4", bold = true }
                inactive = { fg = "#b4b4b4", bg = "#212121" }

                # Separator
                sep_inner = { open = "", close = "" }
                sep_outer = { open = "", close = "" }

                # : }}}


                # : Mode {{{

                [mode]
                normal_main = { fg = "#121212", bg = "#b4b4b4", bold = true }
                normal_alt = { fg = "#b4b4b4", bg = "#212121" }

                # Select mode
                select_main = { fg = "#121212", bg = "#BD4C4C", bold = true }
                select_alt = { fg = "#BD4C4C", bg = "#212121" }

                # Unset mode
                unset_main = { fg = "#121212", bg = "#D87C4A", bold = true }
                unset_alt = { fg = "#D87C4A", bg = "#212121" }

                # : }}}


                # : Status bar {{{

                [status]
                sep_left = { open = "", close = "" }
                sep_right = { open = "", close = "" }

                # Progress
                progress_label = { fg = "#121212", bold = true }
                progress_normal = { fg = "#C4693D", bg = "#323232" }
                progress_error = { fg = "#C53030", bg = "#323232" }

                # Permissions
                perm_sep = { fg = "#949494", bold = true }
                perm_type = { fg = "#B14242" }
                perm_read = { fg = "#d5d5d5", bold = true }
                perm_write = { fg = "#C4693D", bold = true }
                perm_exec = { fg = "#B14242", bold = true }

                # : }}}


                # : Pick {{{

                [pick]
                border = { fg = "#C4693D" }
                active = { fg = "#DF6464", bold = true }
                inactive = {}

                # : }}}


                # : Input {{{

                [input]
                border = { fg = "#B14242" }
                title = {}
                value = {}
                selected = { reversed = true }

                # : }}}


                # : Completion {{{

                [cmp]
                border = { fg = "#B14242" }

                # : }}}


                # : Tasks {{{

                [tasks]
                border = { fg = "#C4693D" }
                title = {}
                hovered = { fg = "#d5d5d5", underline = true }

                # : }}}


                # : Which {{{

                [which]
                mask = { bg = "#212121" }
                cand = { fg = "#E49A44" }
                rest = { fg = "#b4b4b4" }
                desc = { fg = "#DF6464" }
                separator = "  "
                separator_style = { fg = "#B14242" }

                # : }}}


                # : Help {{{

                [help]
                on = { fg = "#D87C4A" }
                run = { fg = "#DF6464" }
                desc = { fg = "#d5d5d5" }
                hovered = { reversed = true, bold = true }
                footer = { fg = "#e5e5e5", bg = "#121212" }

                # : }}}


                # : Notify {{{

                [notify]
                title_info = { fg = "#d5d5d5" }
                title_warn = { fg = "#E5A72A" }
                title_error = { fg = "#C53030" }

                # : }}}


                # : Spotter {{{

                [spot]
                border = { fg = "#C4693D" }
                title  = {}

                # Table
                tbl_cell = { fg = "#d5d5d5", reversed = true }
                tbl_col  = {}

                # : }}}


                # : Confirmation {{{

                [confirm]
                border     = { fg = "#C4693D" }
                title      = {}

                list       = {}
                btn_yes    = { reversed = true }
                btn_no     = {}
                btn_labels = [ " [Y]es  ", "  (N)o  " ]

                # : }}}


                # : File-specific styles {{{

                [filetype]

                rules = [
                  # Images
                  { mime = "image/*", fg = "#E49A44" },

                  # Media
                  { mime = "{audio,video}/*", fg = "#D87C4A" },

                  # Archives
                  { mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "#DF6464" },

                  # Documents
                  { mime = "application/{pdf,doc,rtf}", fg = "#C4693D" },

                  # Fallback
                  { name = "*", fg = "#d5d5d5" },
                  { name = "*/", fg = "#B14242" },
                ]

                # : }}}
              '';

              yaziKeymap = builtins.fromTOML ''
                [[mgr.prepend_keymap]]
                on = "l"
                run = "plugin dvces -- --enter-only"
                desc = "Enter directory or DuckDB database"

                [[mgr.prepend_keymap]]
                on = "<Right>"
                run = "plugin dvces -- --enter-only"
                desc = "Enter directory or DuckDB database"

                [[mgr.prepend_keymap]]
                on = "<Enter>"
                run = "plugin dvces"
                desc = "Open file or enter DuckDB database"

                [[mgr.prepend_keymap]]
                on = [ "g", "R" ]
                run = "plugin dvces -- --refresh"
                desc = "Refresh DuckDB virtual filesystem"

                [[mgr.prepend_keymap]]
                on = "H"
                run = "plugin dvces -- --preview-delta=-1"
                desc = "Scroll DuckDB preview columns left"

                [[mgr.prepend_keymap]]
                on = "L"
                run = "plugin dvces -- --preview-delta=1"
                desc = "Scroll DuckDB preview columns right"

                [[mgr.prepend_keymap]]
                on = "h"
                run = "plugin dvces -- --leave"
                desc = "Leave directory or DuckDB virtual filesystem"

                [[mgr.prepend_keymap]]
                on = "<Left>"
                run = "plugin dvces -- --leave"
                desc = "Leave directory or DuckDB virtual filesystem"

                [[mgr.prepend_keymap]]
                on = [ "R", "b" ]
                run = "plugin recycle-bin"
                desc = "Open Recycle Bin menu"
              '';

              yaziSettings = builtins.fromTOML ''
                [mgr]
                mouse_events = [ "click", "scroll", "touch" ]

                [opener]
                play = [
                  { run = 'mpv "$@"', orphan = true, for = "unix" },
                  { run = '"C:\Program Files\mpv.exe" %*', orphan = true, for = "windows" }
                ]
                edit = [
                  { run = 'nvim "$@"', block = true, for = "unix" },
                  #{ run = 'emacsclient -nw "$@"', block = true, for = "unix" },
                ]
                open = [
                  { run = 'open "$@"', desc = "Open" },
                ]

                [plugin]
                prepend_previewers = [
                  { url = "*.duckdbvfs", run = "dvces" },
                  { url = "*.csv", run = "ohlcv" },
                  { url = "*.parquet", run = "ohlcv" },
                  { url = "*.parq", run = "ohlcv" },
                  { url = "*.feather", run = "ohlcv" },
                  { url = "*.arrow", run = "ohlcv" },
                  { url = "*.ipc", run = "ohlcv" },
                ]
              '';

                yaziInitLua = ''
                require("recycle-bin"):setup()

                local orig_preview_touch = Preview.touch or function() end

                function Preview:touch(event, step)
                    local hovered = cx.active.current.hovered
                    if hovered and hovered.name == "rows.duckdbvfs" then
                      ya.emit("plugin", { "dvces", preview_delta = ya.clamp(-1, step, 1) })
                      return
                    end
                    ya.emit("seek", { step })
                    return orig_preview_touch(self, event, step)
                end
              '';

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

              home.sessionPath =
                lib.optionals (isDarwin || isNonWSLLinux) [
                  "${config.home.homeDirectory}/.cargo/target/release"
                ]
                ++ lib.optionals isDarwin [
                  "/Applications/VMware Fusion.app/Contents/Library"
                  "${config.home.homeDirectory}/.cargo/bin"
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
                pkgs.trash-cli
                manpager
              ] ++ lib.optionals (niksWorktree != null) [ niksWorktree ];

              programs.yazi = {
                enable = true;
                package = pkgs.yazi;
                plugins = {
                  ohlcv = ../../../dotfiles/common/yazi/ohlcv.yazi;
                  dvces = ../../../dotfiles/common/yazi/dvces.yazi;
                  "recycle-bin" = pkgs.fetchFromGitHub {
                    owner = "uhs-robert";
                    repo = "recycle-bin.yazi";
                    rev = "fa687116c46a784e664ef96619b32abf51f29b06";
                    hash = "sha256-lpxTGWA15szM5VJ+qvV2+GTg7HXiZaZfyWyjeNMsTSM=";
                  };
                };
                settings = yaziSettings;
                theme = yaziTheme;
                keymap = yaziKeymap;
                initLua = yaziInitLua;
                extraPackages = [
                  pkgs.duckdb
                  pkgs.python314
                  pkgs.trash-cli
                ];
              };

              programs.zsh = {
                enable = true;
                autocd = true;
                autosuggestion.enable = true;
                syntaxHighlighting.enable = true;
                shellAliases = shellAliases;
                initContent = /* bash */ ''
                  # VSCode shell integration
                  [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

                  # fnm (Node version manager)
                  eval "$(fnm env --use-on-cd)"
                  bindkey -v
                  source ${../../../dotfiles/common/zsh-manydot.sh}

                  # Add a `y` function to zsh that opens yazi either at the given directory or
                  # at the one zoxide's `z` command would pick.
                  unalias y 2>/dev/null || true
                  y() {
                    if [ "$#" -eq 0 ]; then
                      yazi
                    elif [ "$#" -eq 1 ] && [ -d "$1" ]; then
                      yazi "$1"
                    elif [ "$#" -eq 2 ] && [ "$1" = "--" ]; then
                      yazi "$2"
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
