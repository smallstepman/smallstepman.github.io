# AI agents and tools: LLM agents, OpenCode, Claude Code, wrapper scripts.
# Imported by development machines that need AI coding assistance.
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  opencodeAwesome = import ../opencode/awesome.nix { inherit pkgs lib; };
in {
  home.packages = [
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
    # pkgs.llm-agents.kilocode-cli
    # pkgs.llm-agents.letta-code
    # pkgs.llm-agents.mistral-vibe
    # pkgs.llm-agents.nanocoder
    # pkgs.llm-agents.pi
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
    # pkgs.llm-agents.claude-code-acp
    # pkgs.llm-agents.codex-acp

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
  ] ++ (lib.optionals (isLinux && !isWSL) [
    # Wrapper scripts: inject secrets from rbw per-process (not global env)
    # gh is provided by programs.gh (with gitCredentialHelper); auth via shell function below
    # Claude Code uses native apiKeyHelper instead (see home.file below)
    (pkgs.writeShellScriptBin "codex" ''
      OPENAI_API_KEY=$(${pkgs.rbw}/bin/rbw get "openai-api-key") \
        exec ${pkgs.codex}/bin/codex "$@"
    '')

    pkgs.claude-code
  ]);

  home.file = {} // (if isLinux then {
    # Claude Code apiKeyHelper: fetches token from rbw on demand (auto-refreshes every 5min)
    ".claude/settings.json".text = builtins.toJSON {
      apiKeyHelper = "${pkgs.rbw}/bin/rbw get claude-oauth-token";
    };
  } else {});

  xdg.configFile = {
    "opencode/plugins/superpowers.js".source = opencodeAwesome.superpowersPlugin;
    "opencode/skills/superpowers" = {
      source = opencodeAwesome.superpowersSkillsDir;
      recursive = true;
    };
  };

  programs.opencode = {
    enable = true;
    package = pkgs.llm-agents.opencode;
    settings = builtins.fromJSON (builtins.readFile ../opencode/settings.json);
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

  # Keep package.json writable so opencode can update/install plugin deps at runtime.
  home.activation.ensureOpencodePackageJsonWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/opencode"
    packageJson="$HOME/.config/opencode/package.json"
    if [ -L "$packageJson" ]; then
      run rm -f "$packageJson"
    fi
    run cp ${../opencode/package.json} "$packageJson"
    run chmod u+w "$packageJson"
  '';
}
