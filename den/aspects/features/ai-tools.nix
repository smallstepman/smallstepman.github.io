{ den, lib, inputs, ... }: {

  den.aspects.ai-tools = {
    homeManager = { pkgs, lib, ... }:
      let
        opencodeAwesome = import ../../../dotfiles/common/opencode/awesome.nix { inherit pkgs lib; };
        opencodeAuthRefresh = pkgs.writeShellScriptBin "opencode-auth-refresh" ''
          set -euo pipefail
          umask 077

          authDir="$HOME/.local/share/opencode"
          authJson="$authDir/auth.json"
          tmpJson="$(mktemp)"
          trap 'rm -f "$tmpJson"' EXIT

          mkdir -p "$authDir"
          export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
          export XDG_CONFIG_HOME="$HOME/.config"
          ${pkgs.rbw}/bin/rbw stop-agent || true
          export OPENCODE_AUTH_BAILIAN_CODING_PLAN="$(${pkgs.rbw}/bin/rbw get opencode-auth-bailian-coding-plan)"
          export OPENCODE_AUTH_GITHUB_COPILOT="$(${pkgs.rbw}/bin/rbw get opencode-auth-github-copilot)"
          export OPENCODE_AUTH_OPENCODE_GO="$(${pkgs.rbw}/bin/rbw get opencode-auth-opencode-go)"

          ${pkgs.python3}/bin/python - "$tmpJson" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])

github_copilot = json.loads(os.environ["OPENCODE_AUTH_GITHUB_COPILOT"])
if not isinstance(github_copilot, dict):
    raise SystemExit("opencode-auth-refresh: GitHub Copilot rbw item must contain a JSON object")

required_oauth_keys = {"type", "access", "refresh", "expires"}
if set(github_copilot.keys()) != required_oauth_keys:
    raise SystemExit(
        "opencode-auth-refresh: GitHub Copilot rbw item must contain exactly "
        f"{sorted(required_oauth_keys)}, got {sorted(github_copilot.keys())}"
    )
if github_copilot["type"] != "oauth":
    raise SystemExit("opencode-auth-refresh: GitHub Copilot rbw item must have type='oauth'")

data = {
    "bailian-coding-plan": {
        "type": "api",
        "key": os.environ["OPENCODE_AUTH_BAILIAN_CODING_PLAN"],
    },
    "github-copilot": github_copilot,
    "opencode-go": {
        "type": "api",
        "key": os.environ["OPENCODE_AUTH_OPENCODE_GO"],
    },
}

path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY

          mv "$tmpJson" "$authJson"
        '';
        agentShellCopilotAcp = pkgs.writeShellScriptBin "agent-shell-copilot-acp" ''
          export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
          export COPILOT_GITHUB_TOKEN="$(${pkgs.rbw}/bin/rbw get github-token)"
          exec ${pkgs.llm-agents.copilot-cli}/bin/copilot --acp "$@"
        '';
        agentShellClaudeCodeAcp = pkgs.writeShellScriptBin "agent-shell-claude-code-acp" ''
          export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
          export CLAUDE_CODE_OAUTH_TOKEN="$(${pkgs.rbw}/bin/rbw get claude-oauth-token)"
          exec ${pkgs.claude-code-acp}/bin/claude-code-acp "$@"
        '';
        agentShellOpencodeAcp = pkgs.writeShellScriptBin "agent-shell-opencode-acp" ''
          exec ${pkgs.opencode}/bin/opencode acp "$@"
        '';
      in {
        home.packages = [
          pkgs.agent-of-empires

          pkgs.llm-agents.amp
          pkgs.llm-agents.ccusage-amp
          pkgs.llm-agents.claude-code
          pkgs.claude-code-acp
          pkgs.llm-agents.ccusage
          pkgs.llm-agents.copilot-cli
          pkgs.llm-agents.pi
          pkgs.llm-agents.ccusage-pi
          pkgs.llm-agents.ccusage-opencode

          pkgs.llm-agents.beads
          pkgs.llm-agents.beads-rust
          pkgs.llm-agents.beads-viewer
          pkgs.llm-agents.openspec
          pkgs.llm-agents.workmux
          pkgs.gastown

          pkgs.dotagents
          pkgs.apm

          pkgs.llm-agents.copilot-language-server
          pkgs.llm-agents.openskills
          opencodeAuthRefresh
          agentShellCopilotAcp
          agentShellClaudeCodeAcp
          agentShellOpencodeAcp
        ];

        xdg.configFile."opencode/plugins/superpowers.js".source =
          opencodeAwesome.superpowersPlugin;
        xdg.configFile."opencode/skills/superpowers" = {
          source = opencodeAwesome.superpowersSkillsDir;
          recursive = true;
        };

        home.activation.ensureOpencodePackageJsonWritable =
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run mkdir -p "$HOME/.config/opencode"
            packageJson="$HOME/.config/opencode/package.json"
            if [ -L "$packageJson" ]; then
              run rm -f "$packageJson"
            fi
            run cp ${../../../dotfiles/common/opencode/package.json} "$packageJson"
            run chmod u+w "$packageJson"
          '';

        home.activation.ensureOpencodeAuthJson =
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${opencodeAuthRefresh}/bin/opencode-auth-refresh
          '';

        programs.opencode = {
          enable = true;
          package = pkgs.opencode;
          settings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/opencode/settings.json);
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
      };
  };

}
