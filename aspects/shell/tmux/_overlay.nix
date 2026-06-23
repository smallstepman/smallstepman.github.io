{ inputs }: final: prev: {
  tmuxPlugins = prev.tmuxPlugins // {
    "tmux-menus" = final.tmuxPlugins.mkTmuxPlugin {
      pluginName = "tmux-menus";
      version = "0-unstable-2026-02-21";
      src = inputs.tmux-menus-src;
      rtpFilePath = "menus.tmux";
    };
  };
}
