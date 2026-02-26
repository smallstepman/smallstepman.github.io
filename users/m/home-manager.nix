# Home-manager orchestrator: imports composable sub-modules.
#
# This is the "full workstation" profile used by vm-aarch64 and macbook-pro-m1.
# For headless machines (rpi, vps, GPU servers), create a slimmer orchestrator
# that imports only the modules it needs (e.g. core + shell + git).
#
# Sub-modules:
#   home-manager/core.nix       — base packages, env vars, dotfiles (every machine)
#   home-manager/shell.nix      — zsh, bash, aliases, tmux, prompt (every machine)
#   home-manager/git.nix        — git, gh, GPG, rbw (every machine)
#   home-manager/dev.nix        — language runtimes, editors (dev machines)
#   home-manager/desktop.nix    — Wayland, browsers, screenshots (GUI machines)
#   home-manager/ai-agents.nix  — LLM agents, OpenCode (dev machines)
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

{
  imports = [
    (import ./home-manager/core.nix { inherit isWSL inputs; })
    (import ./home-manager/shell.nix { inherit isWSL inputs; })
    (import ./home-manager/git.nix { inherit isWSL inputs; })
    (import ./home-manager/dev.nix { inherit isWSL inputs; })
    (import ./home-manager/desktop.nix { inherit isWSL inputs; })
    (import ./home-manager/ai-agents.nix { inherit isWSL inputs; })
    (import ./opencode/modules/home-manager.nix { inherit isWSL; })
  ];
}
