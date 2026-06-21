{ den, lib, inputs, ... }: {
  den.aspects.ai-tools = {
    homemanager = { pkgs, lib, ... }: {
      home.packages = [
        pkgs.llm-agents.omp
        pkgs.llm-agents.pi
        pkgs.llm-agents.codex
        pkgs.llm-agents.apm
        pkgs.llm-agents.skills
      ];
    };
  };
}

