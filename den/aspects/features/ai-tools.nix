{ den, lib, inputs, ... }: {

  den.aspects.ai-tools = {
    homeManager = { pkgs, lib, ... }:
      let
        opencodeAwesome = import ../../../dotfiles/common/opencode/awesome.nix { inherit pkgs lib; };
      in {
        home.packages = [
          pkgs.agent-of-empires
          pkgs.gastown

          pkgs.llm-agents.amp
          pkgs.llm-agents.ccusage-amp
          pkgs.llm-agents.eca
          pkgs.llm-agents.claude-code
          pkgs.llm-agents.ccusage
          pkgs.llm-agents.copilot-cli
          pkgs.llm-agents.pi
          pkgs.llm-agents.ccusage-pi
          pkgs.llm-agents.qwen-code
          pkgs.llm-agents.ccusage-opencode

          pkgs.llm-agents.beads
          pkgs.llm-agents.beads-rust
          pkgs.llm-agents.beads-viewer
          pkgs.llm-agents.openspec
          pkgs.llm-agents.workmux

          pkgs.dotagents
          pkgs.apm

          pkgs.llm-agents.copilot-language-server
          pkgs.llm-agents.openskills
        ];

        programs.zsh.shellAliases.opencode-dev = "${pkgs.opencode-dev}/bin/opencode";
        programs.bash.shellAliases.opencode-dev = "${pkgs.opencode-dev}/bin/opencode";

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

        programs.opencode = {
          enable = true;
          package = pkgs.llm-agents.opencode;
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
