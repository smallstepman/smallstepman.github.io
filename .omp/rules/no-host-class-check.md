---
name: no-host-class-check
description: "Never guard feature aspects with host.class == N — use class keys directly"
condition: "host\\.class\\s*=="
scope: ["tool:write(*/den/aspects/features/*/default.nix)", "tool:edit(*/den/aspects/features/*/default.nix)"]
---

`host.class` checks inside feature aspects are an antipattern. den already dispatches class keys (`darwin = ...`, `nixos = ...`) based on the host context. If an aspect only has a `darwin = ...` key, it automatically only applies on darwin hosts. Drop the `{ host, ... }: lib.optionalAttrs (host.class == ...)` wrapper entirely.