# Run the test suite.
# bats comes from den.aspects.devtools (home.packages). On a fresh macOS host
# before switching, prefix with: nix shell <bats-store-path> <parallel-store-path>
#
# Targets: vm, darwin, wsl (default: full suite)
test target='':
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      vm)     exec bats --jobs 4 --filter-tags vm-desktop,linux-core,gpg tests.bats ;;
      darwin) exec bats --jobs 4 --filter-tags darwin tests.bats ;;
      wsl)    exec bats --jobs 4 --filter-tags wsl tests.bats ;;
      '')     exec bats --jobs 4 tests.bats ;;
      *)      echo "Unknown target: {{target}}. Use: vm, darwin, or wsl" >&2; exit 1 ;;
    esac
