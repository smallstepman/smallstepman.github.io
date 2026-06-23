{ pkgs, lib, config, ... }: let
  librewolfProfile = "default-release";
in {
  den.aspects.desktop.browsers = {
    homeManager = { pkgs, lib, config, ... }: {
      home.packages = [
        pkgs.brave
        pkgs.chromium
        (pkgs.librewolf.override {
          extraPolicies = config.programs.librewolf.policies;
        })
        pkgs.pywalfox-native
      ];

      programs.librewolf = {
        enable = true;
        package = null;
        profiles.${librewolfProfile} = {
          id = 0;
          isDefault = true;
          settings = {
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "sidebar.verticalTabs" = false;
            "sidebar.revamp" = false;
          };
          userChrome = builtins.readFile ./librewolf/userChrome.css;
        };
        policies = {
          AppAutoUpdate = false;
          BackgroundAppUpdate = false;
          DisableBuiltinPDFViewer = true;
          DisableFirefoxStudies = true;
          DisableFirefoxAccounts = true;
          DisableFirefoxScreenshots = true;
          DisableForgetButton = true;
          DisableMasterPasswordCreation = true;
          DisableProfileImport = true;
          DisableProfileRefresh = true;
          DisableSetDesktopBackground = true;
          DisablePocket = true;
          DisableTelemetry = true;
          DisableFormHistory = true;
          DisablePasswordReveal = true;
          BlockAboutConfig = false;
          BlockAboutProfiles = true;
          BlockAboutSupport = true;
          DisplayMenuBar = "never";
          DontCheckDefaultBrowser = true;
          HardwareAcceleration = false;
          OfferToSaveLogins = false;
          DefaultDownloadDirectory = "/home/m/Downloads";
          Cookies = {
            "Allow" = [
              "https://addy.io" "https://element.io" "https://discord.com"
              "https://github.com" "https://lemmy.cafe" "https://proton.me"
            ];
            "Locked" = true;
          };
          ExtensionSettings = {
            "pywalfox@frewacom.org" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"; installation_mode = "force_installed"; };
            "{3c078156-979c-498b-8990-85f7987dd929}" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/sidebery/latest.xpi"; installation_mode = "force_installed"; };
            "uBlock0@raymondhill.net" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"; installation_mode = "force_installed"; };
            "addon@darkreader.org" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi"; installation_mode = "force_installed"; };
            "vimium-c@gdh1995.cn" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-c/latest.xpi"; installation_mode = "force_installed"; };
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"; installation_mode = "force_installed"; };
            "browser-bridge@yeetnyoink" = { install_url = "https://addons.mozilla.org/firefox/downloads/latest/yeetnyoink-browser-bridge/latest.xpi"; installation_mode = "force_installed"; };
          };
          FirefoxHome = { "Search" = false; };
          Preferences = {
            "browser.preferences.defaultPerformanceSettings.enabled" = false;
            "browser.startup.homepage" = "about:home";
            "browser.toolbar.bookmarks.visibility" = "newtab";
            "browser.toolbars.bookmarks.visibility" = "newtab";
            "browser.urlbar.suggest.bookmark" = false;
            "browser.urlbar.suggest.engines" = false;
            "browser.urlbar.suggest.history" = false;
            "browser.urlbar.suggest.openpage" = false;
            "browser.urlbar.suggest.recentsearches" = false;
            "browser.urlbar.suggest.topsites" = false;
            "browser.warnOnQuit" = false;
            "browser.warnOnQuitShortcut" = false;
            "places.history.enabled" = "false";
            "privacy.resistFingerprinting" = true;
            "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;
          };
        };
      };

      home.file.".librewolf/${librewolfProfile}/chrome/autohide.css".source =
        ./librewolf/autohide.css;

      mozilla.librewolfNativeMessagingHosts = [ pkgs.pywalfox-native ];

      systemd.user.services.pywalfox-boot = {
        Unit = { Description = "Install and update Pywalfox for LibreWolf on boot"; After = [ "graphical-session.target" ]; };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "pywalfox-boot" ''
            set -euo pipefail
            ${pkgs.pywalfox-native}/bin/pywalfox install --browser librewolf
            ${pkgs.pywalfox-native}/bin/pywalfox update
          ''}";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
