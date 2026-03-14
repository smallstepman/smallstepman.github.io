let
  stablePort = 53721;
  webPort = 53723;
in {
  inherit stablePort webPort;
  stableUrl = "http://127.0.0.1:${toString stablePort}";
  stableMdnsDomain = "opencode-stable.local";
  webMdnsDomain = "opencode-web.local";
}
