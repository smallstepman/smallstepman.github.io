{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  opencodeAwesome = import ./opencode/awesome.nix { inherit pkgs lib; };

  shellAliases = {
    ".."   = "cd ..";
    "..."  = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";
    "......" = "cd ../../../../..";
    "......." = "cd ../../../../../..";
    "........" = "cd ../../../../../../..";

    
    ga = "git add";
    gc = "git commit";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";
    gl = "git prettylog";
    gp = "git push";
    gs = "git status";
    gt = "git tag";

    ll = "ls -lh";
    la = "ls -a";
    ls = "eza --group-directories-first";
    magit = "emacsclient -c -a '' -e '(magit-status)'";
    "nix-gc" = "nix-collect-garbage -d";
    "nix-update-flakes" = "nix flake update";

    cc = "claude";
    oc = "opencode";
    
    rs = "cargo";

    nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";
  } // (if isLinux then {
    # Two decades of using a Mac has made this such a strong memory
    # that I'm just going to keep it consistent.
    pbcopy = "xclip";
    pbpaste = "xclip -o";
    noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";

    # NOTE: with-amp / with-openai are shell functions (see zsh initContent below).
    # Shell aliases can't wrap commands; these placeholders exist only for discoverability.
    # Actual definitions: with-openai() { OPENAI_API_KEY=$(rbw get openai-api-key) "$@"; }
  } else {});

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

  # We manage our own Nushell config via Chezmoi
  home.shell.enableNushellIntegration = false;

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
    pkgs.fzf
    pkgs.jq
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
    pkgs.tmux          # terminal multiplexer
    pkgs.tig           # git TUI
    pkgs.difi          # terminal git diff reviewer
    pkgs.agent-of-empires  # terminal session manager for AI agents
    pkgs.dust          # disk usage analyzer (du alternative)
    pkgs.zoxide

    # llm-agents.nix — AI coding agents
    pkgs.llm-agents.amp
    # pkgs.llm-agents.code
    pkgs.llm-agents.copilot-cli
    pkgs.llm-agents.crush
    pkgs.llm-agents.cursor-agent
    # pkgs.llm-agents.droid
    pkgs.llm-agents.eca
    pkgs.llm-agents.forge
    # pkgs.llm-agents.gemini-cli
    # pkgs.llm-agents.goose-cli
    # pkgs.llm-agents.jules
    pkgs.llm-agents.kilocode-cli
    pkgs.llm-agents.letta-code
    pkgs.llm-agents.mistral-vibe
    pkgs.llm-agents.nanocoder
    pkgs.llm-agents.pi
    pkgs.llm-agents.qoder-cli
    pkgs.llm-agents.qwen-code

    # llm-agents.nix — Claude Code ecosystem
    # pkgs.llm-agents.auto-claude
    pkgs.llm-agents.catnip
    pkgs.llm-agents.ccstatusline
    pkgs.llm-agents.claude-code-router
    pkgs.llm-agents.claude-plugins
    pkgs.llm-agents.claudebox
    pkgs.llm-agents.sandbox-runtime
    pkgs.llm-agents.skills-installer

    # llm-agents.nix — ACP ecosystem
    pkgs.llm-agents.claude-code-acp
    pkgs.llm-agents.codex-acp

    # llm-agents.nix — usage analytics
    pkgs.llm-agents.ccusage
    pkgs.llm-agents.ccusage-amp
    pkgs.llm-agents.ccusage-codex
    pkgs.llm-agents.ccusage-opencode
    pkgs.llm-agents.ccusage-pi

    # llm-agents.nix — workflow & project management
    pkgs.llm-agents.agent-deck
    pkgs.llm-agents.backlog-md
    pkgs.llm-agents.beads # bd — Beads CLI
    pkgs.bv               # beads_viewer — graph-aware TUI for Beads issue tracker
    pkgs.llm-agents.beads-rust
    # pkgs.llm-agents.cc-sdd
    # pkgs.llm-agents.chainlink
    pkgs.llm-agents.openspec
    pkgs.llm-agents.spec-kit
    pkgs.llm-agents.vibe-kanban
    pkgs.llm-agents.workmux

    # llm-agents.nix — code review
    pkgs.llm-agents.coderabbit-cli
    pkgs.llm-agents.tuicr

    # llm-agents.nix — utilities
    pkgs.llm-agents.ck
    pkgs.llm-agents.copilot-language-server
    pkgs.llm-agents.happy-coder
    pkgs.llm-agents.openskills
    # pkgs.llm-agents.agent-browser
    # pkgs.llm-agents.coding-agent-search
    # pkgs.llm-agents.handy
    # pkgs.llm-agents.localgpt
    # pkgs.llm-agents.mcporter
    # pkgs.llm-agents.openclaw
    # pkgs.llm-agents.qmd

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
    # Wrapper scripts: inject secrets from rbw per-process (not global env)
    # gh is provided by programs.gh (with gitCredentialHelper); auth via shell function below
    # Claude Code uses native apiKeyHelper instead (see home.file below)
    (pkgs.writeShellScriptBin "codex" ''
      OPENAI_API_KEY=$(${pkgs.rbw}/bin/rbw get "openai-api-key") \
        exec ${pkgs.codex}/bin/codex "$@"
    '')
    (pkgs.writeShellScriptBin "sentry-cli" ''
      SENTRY_AUTH_TOKEN=$(${pkgs.rbw}/bin/rbw get "sentry-auth-token") \
        exec ${pkgs.sentry-cli}/bin/sentry-cli "$@"
    '')

    # Called by Noctalia hooks/user-templates on wallpaper/dark-mode changes
    (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
      # Reload Noctalia theme in running Emacs daemon
      ${pkgs.emacs-pgtk}/bin/emacsclient -e \
        '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
        2>/dev/null || true
    '')

    pkgs.claude-code
    pkgs.chromium
    pkgs.clang
    pkgs.firefox
    pkgs.activitywatch # automated time tracker (Linux only; Darwin via homebrew cask)
    pkgs.fuzzel       # app launcher for Wayland
    pkgs.valgrind
    pkgs.foot         # lightweight Wayland terminal
    pkgs.grim         # screenshots
    pkgs.slurp        # region selection

    # Wayland utilities
    inputs.mangowc.packages.${pkgs.system}.default  # window control
    pkgs.wlr-which-key                              # which-key for wlroots

    # Wallpaper
    pkgs.git-repo-manager                           # declarative git repo sync

    # Bootstrap script - run once after fresh install
    (pkgs.writeShellScriptBin "setup-my-tools" ''
      set -e

      echo "==> Syncing git repositories..."
      ${pkgs.git-repo-manager}/bin/grm repos sync config --config ~/.config/grm/repos.yaml

      echo "==> Setting up Neovim (Lazy sync)..."
      ${pkgs.neovim}/bin/nvim --headless "+Lazy! sync" +qa || true

      echo "==> Regenerating Noctalia color templates..."
      noctalia-shell ipc call colorscheme regenerate || true

      echo "==> Bootstrap complete!"
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
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
  } // (if isDarwin then {
    # not gonna manage plists, but keep them here to remember
    # "Library/Preferences/com.MrKai77.Loop.plist".source = ./com.MrKai77.Loop.plist;
    # "Library/Preferences/com.brnbw.Leader-Key.plist".source = ./com.brnbw.Leader-Key.plist;
    # "Library/Preferences/com.knollsoft.Rectangle.plist".source = ./com.knollsoft.Rectangle.plist;
    # not ready yet to freeze it
    # "Library/Application Support/Leader Key/config.json".source = ./leader-key-config.json;
  } else {}) // (if isLinux then {
    # Claude Code apiKeyHelper: fetches token from rbw on demand (auto-refreshes every 5min)
    ".claude/settings.json".text = builtins.toJSON {
      apiKeyHelper = "${pkgs.rbw}/bin/rbw get claude-oauth-token";
    };
  } else {});


  xdg.configFile = {
    "rofi/config.rasi".text = builtins.readFile ./rofi;
    "grm/repos.yaml".source = ./grm-repos.yaml;
    "opencode/plugins/superpowers.js".source = opencodeAwesome.superpowersPlugin;
    "opencode/skills/superpowers" = {
      source = opencodeAwesome.superpowersSkillsDir;
      recursive = true;
    };
    "ghostty/config".text = builtins.readFile ./ghostty.cfg;
  } // (if isDarwin then {
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
    "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
    "karabiner/karabiner.json".source = ./kanata/karabiner.json; # keeping it in kanata/ since i dont use it directly with karabiner, but via kanata
  } else {}) // (if isLinux then {
    # Prevent home-manager from managing rbw config as a read-only store symlink;
    # the rbw-config systemd service writes the real config with sops email.
    "rbw/config.json".enable = lib.mkForce false;

    # wlr-which-key configuration
    "wlr-which-key/config.yaml".text = builtins.readFile ./wlr-which-key-config.yaml;

    # Noctalia user templates and theme template inputs
    "noctalia/user-templates.toml".source = ./noctalia-user-templates.toml;
    "noctalia/emacs-template.el".source = ./doom/themes/noctalia-template.el;

    # Neovim matugen template (input for Noctalia user template → nvim base16 theme)
    "nvim/lua/matugen-template.lua".source = ./lazyvim/lua/matugen-template.lua;
  } else {});

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  # Doom Emacs (via nix-doom-emacs-unstraightened)
  programs.doom-emacs = {
    enable = true;
    doomDir = ./doom;
    emacs = pkgs.emacs-pgtk;
    # :config literate has no effect in unstraightened; tangle config.org at build time
    tangleArgs = "--all config.org";
  };

  # Emacs daemon as a systemd user service (Linux only; macOS has no systemd)
  services.emacs = lib.mkIf isLinux {
    enable = true;
    defaultEditor = false; # we set EDITOR to nvim elsewhere
  };

  programs.gpg.enable = !isDarwin;

  # Niri Wayland compositor configuration (Linux only)
  programs.niri.settings = lib.mkIf (isLinux && !isWSL) {
    hotkey-overlay = {
      skip-at-startup = true;
    };
    prefer-no-csd = true; # Client Side Decorations (title bars etc)
    input = {
      mod-key = "Control";  # or "Super", "Control", etc.
      keyboard.xkb.layout = "us";
      keyboard.repeat-delay = 150;
      keyboard.repeat-rate = 50;
      touchpad = {
        tap = true;
        natural-scroll = true;
      };
    };

    window-rules = [
      {
        geometry-corner-radius = {
          top-left = 12.0;
          top-right = 12.0;
          bottom-right = 12.0;
          bottom-left = 12.0;
        };
      }
      {
        clip-to-geometry = true;
      }
    ];

    outputs."Virtual-1".scale = 2.0;

    layout = {
      gaps = 16;
      center-focused-column = "never";
      preset-column-widths = [
        { proportion = 1.0 / 3.0; }
        { proportion = 1.0 / 2.0; }
        { proportion = 2.0 / 3.0; }
      ];
      default-column-width.proportion = 0.5;
      focus-ring = {
        width = 2;
        active.color = "#7fc8ff";
        inactive.color = "#505050";
      };
    };

    spawn-at-startup = [
      { command = [ "mako" ]; }
    ];

    environment = {
      NIXOS_OZONE_WL = "1";
    };

    binds = {
      # Launch
      "Mod+Return".action.spawn = "foot";
      "Mod+D".action.spawn = "fuzzel";
      "Mod+Q".action.close-window = {};

      # Session
      # "Mod+Shift+E".action.quit = {};

      # Focus
      "Mod+N".action.focus-column-left = {};
      "Mod+E".action.focus-window-down = {};
      "Mod+I".action.focus-window-up = {};
      "Mod+O".action.focus-column-right = {};

      # Move
      "Mod+Shift+N".action.move-column-left = {};
      "Mod+Shift+E".action.move-window-down = {};
      "Mod+Shift+I".action.move-window-up = {};
      "Mod+Shift+O".action.move-column-right = {};

      # Workspaces
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+6".action.focus-workspace = 6;
      "Mod+7".action.focus-workspace = 7;
      "Mod+8".action.focus-workspace = 8;
      "Mod+9".action.focus-workspace = 9;

      "Mod+Shift+1".action.move-column-to-workspace = 1;
      "Mod+Shift+2".action.move-column-to-workspace = 2;
      "Mod+Shift+3".action.move-column-to-workspace = 3;
      "Mod+Shift+4".action.move-column-to-workspace = 4;
      "Mod+Shift+5".action.move-column-to-workspace = 5;
      "Mod+Shift+6".action.move-column-to-workspace = 6;
      "Mod+Shift+7".action.move-column-to-workspace = 7;
      "Mod+Shift+8".action.move-column-to-workspace = 8;
      "Mod+Shift+9".action.move-column-to-workspace = 9;

      # Layout
      "Mod+R".action.switch-preset-column-width = {};
      "Mod+F".action.maximize-column = {};
      "Mod+Shift+F".action.fullscreen-window = {};
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";

      # Screenshots
      "Print".action.screenshot = {};
      "Mod+Print".action.screenshot-window = {};

      # Lock
      "Mod+Escape".action.spawn = "swaylock";
    };
  };

  # Mango Wayland compositor configuration (Linux only)
  wayland.windowManager.mango = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = ''
      # Mango config - keybindings matching niri (Colemak: n/e/i/o = left/down/up/right)
      monitorrule=name:Virtual-1,scale:2.0

      # Launch applications
      bind=SUPER,Return,spawn,foot
      bind=SUPER,d,spawn,fuzzel
      bind=SUPER,q,killclient

      # Focus navigation (Colemak layout)
      bind=SUPER,n,focusdir,left
      bind=SUPER,e,focusdir,down
      bind=SUPER,i,focusdir,up
      bind=SUPER,o,focusdir,right

      # Move windows (Colemak layout)
      bind=SUPER+SHIFT,n,movetodir,left
      bind=SUPER+SHIFT,e,movetodir,down
      bind=SUPER+SHIFT,i,movetodir,up
      bind=SUPER+SHIFT,o,movetodir,right

      # Workspaces (view = focus, tag = move window)
      bind=SUPER,1,view,1
      bind=SUPER,2,view,2
      bind=SUPER,3,view,3
      bind=SUPER,4,view,4
      bind=SUPER,5,view,5
      bind=SUPER,6,view,6
      bind=SUPER,7,view,7
      bind=SUPER,8,view,8
      bind=SUPER,9,view,9

      bind=SUPER+SHIFT,1,tag,1
      bind=SUPER+SHIFT,2,tag,2
      bind=SUPER+SHIFT,3,tag,3
      bind=SUPER+SHIFT,4,tag,4
      bind=SUPER+SHIFT,5,tag,5
      bind=SUPER+SHIFT,6,tag,6
      bind=SUPER+SHIFT,7,tag,7
      bind=SUPER+SHIFT,8,tag,8
      bind=SUPER+SHIFT,9,tag,9

      # Layout
      bind=SUPER,f,togglefullscreen
      bind=SUPER+SHIFT,f,togglefloating

      # Screenshots (using grim + slurp)
      bind=NONE,Print,spawn_shell,grim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png
      bind=SUPER,Print,spawn_shell,grim -g "$(slurp)" ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png

      # Lock screen
      bind=SUPER,Escape,spawn,swaylock

      # Which-key menu
      bind=SUPER,space,spawn,wlr-which-key

      # Quit mango
      bind=SUPER+SHIFT,q,quit
    '';
    autostart_sh = ''
      # Start notification daemon
      mako &
    '';
  };

  # Noctalia shell configuration (Linux VM only)
  programs.noctalia-shell = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = ./noctalia.json;
  };

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
    '' + (if isDarwin then ''

      # Homebrew
      eval "$(/opt/homebrew/bin/brew shellenv)"
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
    initExtra = builtins.readFile ./bashrc;
    shellAliases = shellAliases;
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
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.atuin = {
    enable = true;
  };

  programs.oh-my-posh = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ./oh-my-posh.json);
  };

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
      pinentry = pkgs.pinentry-tty;
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
      };
    };
  };
  
  programs.opencode = {
    enable = true;
    package = pkgs.llm-agents.opencode;
    settings = builtins.fromJSON (builtins.readFile ./opencode/settings.json);
    agents = opencodeAwesome.agents;
    commands = opencodeAwesome.commands;
    themes = opencodeAwesome.themes;
    rules = ''
      You are an intelligent and observant agent.
      
      You are on NixOS. Prefer `nix run nixpkgs#<tool>` over installing tools globally.
      If instructed to commit, do not use gpg signing.

      ## Agents
      Delegate tasks to subagents frequently.

      ## Think deeply about everything.
      Break problems down, abstract them out, understand the fundamentals.
    '';


  };

  programs.vscode = {
    enable = true;
    profiles = {
      default = {
        extensions = import ./vscode/extensions.nix { inherit pkgs; };
        keybindings = builtins.fromJSON (builtins.readFile ./vscode/keybindings.json);
        userSettings = builtins.fromJSON (builtins.readFile ./vscode/settings.json);
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
    configFiles = ./lazyvim;

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

    };

    # Additional packages (optional)
    extraPackages = with pkgs; [
      nixd       # Nix LSP
      alejandra  # Nix formatter
      pyright    # Python LSP
    ];

    # Only needed for languages not covered by LazyVim extras
    treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
      templ     # Go templ files
    ];

  };

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
  };

  # Keep package.json writable so opencode can update/install plugin deps at runtime.
  home.activation.ensureOpencodePackageJsonWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/opencode"
    packageJson="$HOME/.config/opencode/package.json"
    if [ -L "$packageJson" ]; then
      run rm -f "$packageJson"
    fi
    run cp ${./opencode/package.json} "$packageJson"
    run chmod u+w "$packageJson"
  '';

  # Ensure writable output directories for Noctalia user templates
  home.activation.createNoctaliaThemeDirs = lib.mkIf (isLinux && !isWSL) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
  '');

  # Uniclip clipboard client: connects to macOS server via SSH reverse tunnel
  systemd.user.services.uniclip = lib.mkIf (isLinux && !isWSL) {
    Unit = {
      Description = "Uniclip clipboard client (connects to macOS server via SSH tunnel)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScript "uniclip-client" ''
        export UNICLIP_PASSWORD=$(${pkgs.rbw}/bin/rbw get uniclip-password)
        export WAYLAND_DISPLAY=wayland-1
        export XDG_RUNTIME_DIR=/run/user/$(id -u)
        export PATH=${lib.makeBinPath [ pkgs.wl-clipboard ]}:$PATH
        exec ${pkgs.uniclip}/bin/uniclip --secure 127.0.0.1:53701
      ''}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
