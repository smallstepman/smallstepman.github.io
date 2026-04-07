# dvces.yazi

DuckDB virtual-filesystem and row-preview plugin for Yazi.

It turns `.duckdb` files into browsable trees and renders `rows.duckdbvfs` previews with horizontal column scrolling.

Use it from `keymap.toml` and `yazi.toml` with the `dvces` plugin name:

```toml
[[mgr.prepend_keymap]]
on = [ "l" ]
run = "plugin dvces -- --enter-only"

[plugin]
prepend_previewers = [
  { url = "*.duckdbvfs", run = "dvces" },
]
```
