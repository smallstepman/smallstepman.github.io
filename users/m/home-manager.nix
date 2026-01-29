{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  sources = import ../../nix/sources.nix;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  shellAliases = {
    ga = "git add";
    gc = "git commit";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";
    gl = "git prettylog";
    gp = "git push";
    gs = "git status";
    gt = "git tag";

    jd = "jj desc";
    jf = "jj git fetch";
    jn = "jj new";
    jp = "jj git push";
    js = "jj st";
  } // (if isLinux then {
    # Two decades of using a Mac has made this such a strong memory
    # that I'm just going to keep it consistent.
    pbcopy = "xclip";
    pbpaste = "xclip -o";
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
    pkgs._1password-cli
    pkgs.asciinema
    pkgs.bat
    pkgs.chezmoi
    pkgs.eza
    pkgs.fd
    pkgs.fzf
    pkgs.gh
    pkgs.htop
    pkgs.jq
    pkgs.ripgrep
    pkgs.sentry-cli
    pkgs.starship
    pkgs.tree
    pkgs.watch

    pkgs.gopls
    pkgs.zigpkgs."0.15.2"

    pkgs.claude-code
    pkgs.codex

    # Node is required for Copilot.vim
    pkgs.nodejs

    # Emacs + Doom Emacs dependencies
    pkgs.emacs30
    pkgs.cmake       # for vterm
    pkgs.libtool     # for vterm
    pkgs.shellcheck  # for shell script linting
  ] ++ (lib.optionals isDarwin [
    # This is automatically setup on Linux
    pkgs.cachix
    pkgs.gettext
  ]) ++ (lib.optionals (isLinux && !isWSL) [
    pkgs.chromium
    pkgs.clang
    pkgs.firefox
    pkgs.fuzzel       # app launcher for Wayland
    pkgs.valgrind
    pkgs.zathura
    pkgs.xfce.xfce4-terminal
    pkgs.mako         # notifications
    pkgs.swaylock     # screen locker
    pkgs.grim         # screenshots
    pkgs.slurp        # region selection
  ]);

  #---------------------------------------------------------------------
  # Env vars and dotfiles
  #---------------------------------------------------------------------

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "nvim";
    PAGER = "less -FirSwX";
    MANPAGER = "${manpager}/bin/manpager";

    AMP_API_KEY = "op://Private/Amp_API/credential";
    OPENAI_API_KEY = "op://Private/OpenAPI_Personal/credential";
  } // (if isDarwin then {
    # See: https://github.com/NixOS/nixpkgs/issues/390751
    DISPLAY = "nixpkgs-390751";
  } else {});

  home.file = {
    ".gdbinit".source = ./gdbinit;
    ".inputrc".source = ./inputrc;
  };

  xdg.configFile = {
    "rofi/config.rasi".text = builtins.readFile ./rofi;
  } // (if isDarwin then {
    # Rectangle.app. This has to be imported manually using the app.
    "rectangle/RectangleConfig.json".text = builtins.readFile ./RectangleConfig.json;
  } else {}) // (if isLinux then {
    "ghostty/config".text = builtins.readFile ./ghostty.linux;
  } else {});

  #---------------------------------------------------------------------
  # Programs
  #---------------------------------------------------------------------

  programs.gpg.enable = !isDarwin;

  # Niri Wayland compositor configuration (Linux only)
  programs.niri.settings = lib.mkIf isLinux {
    input = {
      keyboard.xkb.layout = "us";
      keyboard.repeat-delay = 200;
      keyboard.repeat-rate = 40;
      touchpad = {
        tap = true;
        natural-scroll = true;
      };
    };

    outputs."eDP-1".scale = 2.0;

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
      "Mod+Return".action.spawn = "xfce4-terminal";
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

  programs.waybar = lib.mkIf isLinux {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 30;
      modules-left = [ "niri/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [ "cpu" "memory" "network" "pulseaudio" "tray" ];
    };
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

  programs.fish = {
    enable = true;
    shellAliases = shellAliases;
    interactiveShellInit = lib.strings.concatStrings (lib.strings.intersperse "\n" ([
      "source ${inputs.theme-bobthefish}/functions/fish_prompt.fish"
      "source ${inputs.theme-bobthefish}/functions/fish_right_prompt.fish"
      "source ${inputs.theme-bobthefish}/functions/fish_title.fish"
      (builtins.readFile ./config.fish)
      "set -g SHELL ${pkgs.fish}/bin/fish"
    ]));

    plugins = map (n: {
      name = n;
      src  = inputs.${n};
    }) [
      "fish-fzf"
      "fish-foreign-env"
      "theme-bobthefish"
    ];
  };

  programs.git = {
    enable = true;
    signing = {
      key = "7D9B7E8B2C83D94F";
      signByDefault = true;
    };
    settings = {
      user.name = "Marcin Nowak Liebiediew";
      user.email = "m.liebiediew@gmail.com";
      branch.autosetuprebase = "always";
      color.ui = true;
      core.askPass = ""; # needs to be empty to use terminal for ask pass
      credential.helper = "store"; # want to make this more secure
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

  programs.go = {
    enable = true;
    env = { 
      GOPATH = "Documents/go";
      GOPRIVATE = [ "github.com/smallstepman" ];
    };
  };

  programs.jujutsu = {
    enable = true;

    # I don't use "settings" because the path is wrong on macOS at
    # the time of writing this.
  };

  programs.alacritty = {
    enable = !isWSL;

    settings = {
      env.TERM = "xterm-256color";

      key_bindings = [
        { key = "K"; mods = "Command"; chars = "ClearHistory"; }
        { key = "V"; mods = "Command"; action = "Paste"; }
        { key = "C"; mods = "Command"; action = "Copy"; }
        { key = "Key0"; mods = "Command"; action = "ResetFontSize"; }
        { key = "Equals"; mods = "Command"; action = "IncreaseFontSize"; }
        { key = "Subtract"; mods = "Command"; action = "DecreaseFontSize"; }
      ];
    };
  };

  programs.kitty = {
    enable = !isWSL;
    extraConfig = builtins.readFile ./kitty;
  };

  programs.i3status = {
    enable = isLinux && !isWSL;

    general = {
      colors = true;
      color_good = "#8C9440";
      color_bad = "#A54242";
      color_degraded = "#DE935F";
    };

    modules = {
      ipv6.enable = false;
      "wireless _first_".enable = false;
      "battery all".enable = false;
    };
  };

  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
  };

  programs.npm = {
    enable = isLinux;
  };

  programs.atuin = {
    enable = true;
  };

  programs.nushell = {
    enable = true;
  };

  programs.oh-my-posh = {
    enable = true;
  };

  services.gpg-agent = {
    enable = isLinux;
    pinentry.package = pkgs.pinentry-tty;

    # cache the keys forever so we don't get asked for a password
    defaultCacheTtl = 31536000;
    maxCacheTtl = 31536000;
  };

  xresources.extraConfig = builtins.readFile ./Xresources;

  # Make cursor not tiny on HiDPI screens
  home.pointerCursor = lib.mkIf (isLinux && !isWSL) {
    name = "Vanilla-DMZ";
    package = pkgs.vanilla-dmz;
    size = 128;
    x11.enable = true;
  };
}
