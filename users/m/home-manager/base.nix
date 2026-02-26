{ lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  shellAliases = {
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";
    "....." = "cd ../../../..";
    "......" = "cd ../../../../..";
    "......." = "cd ../../../../../..";
    "........" = "cd ../../../../../../..";

    g  = "git";
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gl = "git prettylog";
    gp = "git push";
    gt = "git tag";
    gco = "git checkout";
    gcp = "git cherry-pick";
    gdiff = "git diff";

    l = "ls";
    lah = "eza -alh --color=auto --group-directories-first --icons";
    la = "eza -la";
    ll = "eza -lh --color=auto --group-directories-first --icons";
    magit = "emacsclient -c -a '' -e '(magit-status)'";
    "nix-gc" = "nix-collect-garbage -d";
    "nix-update-flakes" = "nix flake update";

    cc = "claude";
    oc = "opencode";
    ocd = "opencode-dev";
    openspec-in-progress = "openspec list --json | jq -r '.changes[] | select(.status == \"in-progress\").name'";

    rs = "cargo";
    kubectl = "kubecolor";

    nvim-hrr = "nvim --headless -c 'Lazy! sync' +qa";

  } // (if isLinux then {
    pbcopy = "wl-copy --type text/plain";
    pbpaste = "wl-paste --type text/plain";
    open = "xdg-open";
    noctalia-diff = "nix shell nixpkgs#jq nixpkgs#colordiff -c bash -c \"colordiff -u --nobanner <(jq -S . ~/.config/noctalia/settings.json) <(noctalia-shell ipc call state all | jq -S .settings)\"";
    nix-config = "nvim /nix-config";
    niks = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake '/nixos-config#vm-aarch64'";
    nikt = "sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --impure --flake '/nixos-config#vm-aarch64'";
  } else (if isDarwin then {
    nix-config = "nvim ~/.config/nix-config";
    niks = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake '.#macbook-pro-m1'";
    nikt = "cd ~/.config/nix && NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features 'nix-command flakes' '.#darwinConfigurations.macbook-pro-m1.system' && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --impure --flake '.#macbook-pro-m1'";
  } else {}));

  # For our MANPAGER env var
  # https://github.com/sharkdp/bat/issues/1145
  manpager = (pkgs.writeShellScriptBin "manpager" (if isDarwin then ''
    sh -c 'col -bx | bat -l man -p'
    '' else ''
    cat "$1" | col -bx | bat --language man --style plain
  ''));
in {
  home.sessionVariables.MANPAGER = "${manpager}/bin/manpager";
  programs.zsh.shellAliases = shellAliases;
  programs.bash.shellAliases = shellAliases;
}
