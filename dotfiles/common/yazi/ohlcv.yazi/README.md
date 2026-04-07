# ohlcv.yazi

Yazi preview plugin for OHLCV-style charts on CSV, Parquet, Feather, Arrow, and IPC files.

It prefers `ohlcv-ascii` when available and falls back to a readable raw preview when it is not.

Use it from `yazi.toml` with:

```toml
[plugin]
prepend_previewers = [
  { url = "*.csv", run = "ohlcv" },
  { url = "*.parquet", run = "ohlcv" },
  { url = "*.parq", run = "ohlcv" },
  { url = "*.feather", run = "ohlcv" },
  { url = "*.arrow", run = "ohlcv" },
  { url = "*.ipc", run = "ohlcv" },
]
```
