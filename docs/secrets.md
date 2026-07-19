# Secrets Management

The repository uses SOPS and sops-nix for secrets needed during NixOS
activation, with sopsidy collecting their values from Bitwarden.

The age-encrypted file is tracked at
`aspects/authentication/secrets.yaml`. Keeping encrypted data in Git is the
normal SOPS workflow and lets the flake evaluate directly without a generated
input or wrapper flake.

## Files and ownership

| Path | Contents |
|------|----------|
| `aspects/authentication/secrets.yaml` | Age-encrypted boot-time secrets, tracked in Git |
| `aspects/authentication/vm-age.pub` | Public age recipient used by sopsidy, tracked beside the SOPS configuration |
| `aspects/network/ssh/m.pub` | General user SSH public key, tracked beside the SSH configuration |
| `aspects/authorization/touchid/*.pub` | Host pins and bridge public keys, tracked beside the Touch ID bridge configuration |
| `/var/lib/sops-nix/key.txt` | VM age private key, never stored in Git |
| `/var/lib/grafana-secret/secret_key` | Jimi-local Grafana encryption key, generated once as `root:grafana` with mode `0440` |
| `~/.local/share/nix-config-generated/kubeconfig` | Private runtime OrbStack kubeconfig, never used as a flake input |
| `/nixos-generated/kubeconfig` | VMware shared-folder view of that runtime kubeconfig |

## Boot-time secrets

The VM currently decrypts:

| Secret | Consumer |
|--------|----------|
| `tailscale/auth-key` | `services.tailscale.authKeyFile` |
| `rbw/email` | Generated Linux rbw configuration |
| `uniclip/password` | VM Uniclip client (`UNICLIP_PASSWORD`) |
| `user/hashed-password` | `users.users.m.hashedPasswordFile` |

Runtime API tokens remain in Bitwarden and are fetched by their individual
shell helpers or services.

## Jimi unattended installer

The Jimi installer is parameterized at build time rather than carrying Wi-Fi
credentials in tracked Nix:

```bash
# .env is ignored by Git; only the Bitwarden item name is stored here.
WIFI_SSID=...
WIFI_PSK_RBW_ITEM=...

scripts/build-iso.sh
```

The build script fetches the PSK with `rbw` immediately before evaluation. It
also accepts `WIFI_PSK_FILE` (for a mounted secret) or `WIFI_PSK` (for an
already-populated environment). `scripts/jimi-installer.nix` reads the resolved
variables during impure evaluation and adds the Wi-Fi profile only to the
installer configuration. After installation, the installer copies
NetworkManager's mode-`0600` runtime keyfile into the installed system. The
regular Jimi NixOS configuration contains no Wi-Fi PSK.

An unattended ISO that can join the network necessarily contains the Wi-Fi
credential. Treat `.env`, the builder's Nix store/derivation, the resulting ISO,
and the installed NetworkManager keyfile as secret-bearing artifacts. Do not
publish the ISO; use a dedicated installer network or rotate the PSK if that
exposure is unacceptable.

## Grafana encryption key

Jimi generates Grafana's `security.secret_key` once at
`/var/lib/grafana-secret/secret_key`. The root-owned value is not present in Git
or a Nix store path and survives rebuilds. Back it up with Grafana's database:
replacing or losing it can make credentials already encrypted in that database
unreadable.

## Collecting secrets

From the repository root:

```bash
nix run .#collect-secrets --no-write-lock-file
```

sopsidy reads the declarations in `aspects/authentication/secrets.nix`, fetches
the corresponding Bitwarden items, and rewrites the tracked encrypted YAML for
the recipient in `aspects/authentication/vm-age.pub`.

To rotate a value, update the Bitwarden item, run the command above, review the
encrypted YAML diff, and deploy normally.

## Provisioning or rotating the VM key

`docs/vm.sh refresh-secrets` ensures the VM private age key exists, writes its
public recipient beside the authentication aspect, refreshes the SSH and Touch
ID aspects' public inputs, and runs `collect-secrets`.

On installation, `docs/vm.sh` creates the private age key in the installer,
copies it to the installed system, refreshes the tracked recipient and
encrypted YAML, and then builds the target configuration directly from the
repository.

## Runtime kubeconfig

The OrbStack kubeconfig can contain private key material, so it remains outside
Git. The macOS launch agent and `docs/vm.sh refresh-kubeconfig` fetch it from
Bitwarden into `~/.local/share/nix-config-generated/kubeconfig`. The VM reads it
through the `/nixos-generated` VMware shared folder. This directory is runtime
state only and is not part of Nix evaluation.

## Security boundary

- The repository contains encrypted secret values and public keys.
- The VM age private key remains only at `/var/lib/sops-nix/key.txt`.
- That is a deployment identity, not a rule against recovery: another consumer
  or an offline recovery location should use its own age identity/recipient
  rather than receive a copy of the VM's private key.
- Anyone with both the repository and that private key can decrypt the tracked
  YAML.
- Runtime Bitwarden tokens, the kubeconfig, and Jimi's Grafana key remain
  outside the repository.
