# dvces.yazi

DuckDB virtual-filesystem and row-preview plugin for Yazi.

It turns `.duckdb` files into browsable trees and renders `rows.duckdbvfs` previews with horizontal column scrolling.

Use it from `keymap.toml` and `yazi.toml` with the `dvces` plugin name:

```toml
[[mgr.prepend_keymap]]
on = [ "l" ]
run = "plugin dvces -- --enter-only"

[[mgr.prepend_keymap]]
on = "H"
run = "plugin dvces -- --preview-delta=-1"

[[mgr.prepend_keymap]]
on = "L"
run = "plugin dvces -- --preview-delta=1"

[plugin]
prepend_previewers = [
  { url = "*.duckdbvfs", run = "dvces" },
]
```
