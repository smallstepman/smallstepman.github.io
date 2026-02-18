# Connectivity info for Linux VM
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= m
NIXINSTALLUSER ?= root

# Add VMware Fusion CLI to PATH
export PATH := /Applications/VMware Fusion.app/Contents/Library:$(PATH)

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The name of the nixosConfiguration in the flake
NIXNAME ?= vm-aarch64

# Block device for NixOS installation
NIXBLOCKDEVICE ?= nvme0n1

# SSH options that are used. These aren't meant to be overridden but are
# reused a lot so we just store them up here.
SSH_OPTIONS ?= -o StrictHostKeyChecking=accept-new

# Bootstrap uses password auth against a fresh VM (before keys/trust exist)
BOOTSTRAP_SSH_OPTIONS ?= -o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
INSTALL_SSH_OPTIONS ?= $(BOOTSTRAP_SSH_OPTIONS)
INSTALL_SSH_PASSWORD ?= root

# Host public key copied into nix config during bootstrap
HOST_SSH_PUBKEY_FILE ?= $(HOME)/.ssh/id_ed25519.pub
GENERATED_HOST_AUTH_KEYS_FILE ?= $(MAKEFILE_DIR)/machines/generated/host-authorized-keys
GENERATED_VM_AGE_PUBKEY_FILE ?= $(MAKEFILE_DIR)/machines/generated/vm-age-pubkey

# We need to do some OS switching below.
UNAME := $(shell uname)

switch:
ifeq ($(UNAME), Darwin)
	NIXPKGS_ALLOW_UNFREE=1 nix build --impure --extra-experimental-features nix-command --extra-experimental-features flakes ".#darwinConfigurations.${NIXNAME}.system" --max-jobs 8 --cores 0
	sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --impure --flake "$$(pwd)#${NIXNAME}"
else
	sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --impure --flake ".#${NIXNAME}"
endif

test:
ifeq ($(UNAME), Darwin)
	NIXPKGS_ALLOW_UNFREE=1 nix build --impure ".#darwinConfigurations.${NIXNAME}.system"
	sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild test --impure --flake "$$(pwd)#${NIXNAME}"
else
	sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild test --impure --flake ".#$(NIXNAME)"
endif

# This builds the given NixOS configuration and pushes the results to the
# cache. This does not alter the current running system. This requires
# cachix authentication to be configured out of band.
# cache:
# 	nix build '.#nixosConfigurations.$(NIXNAME).config.system.build.toplevel' --json \
# 		| jq -r '.[].outputs | to_entries[].value' \
# 		| cachix push <your-cachix-cache>


# Collect and encrypt secrets using sopsidy (requires rbw to be unlocked).
# secrets.yaml is gitignored (defense-in-depth) but Nix flakes only sees
# git-tracked files, so we stage it temporarily for the evaluation.
.PHONY: secrets/collect
secrets/collect:
	touch $(MAKEFILE_DIR)/machines/secrets.yaml
	git -C $(MAKEFILE_DIR) add -f machines/secrets.yaml
	nix --extra-experimental-features 'nix-command flakes' run .#collect-secrets
	git -C $(MAKEFILE_DIR) reset -q -- machines/secrets.yaml

# Get (or create) the VM's dedicated sops age public key
.PHONY: vm/age-key
vm/age-key:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo mkdir -p /var/lib/sops-nix && \
		sudo chmod 700 /var/lib/sops-nix && \
		if [ ! -f /var/lib/sops-nix/key.txt ]; then \
			sudo nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt'; \
			sudo chmod 600 /var/lib/sops-nix/key.txt; \
		fi && \
		sudo nix-shell -p age --run 'age-keygen -y /var/lib/sops-nix/key.txt' \
	"

.PHONY: vm/prepare-sops-host-pubkey
vm/prepare-sops-host-pubkey:
	sshpass -p "$(INSTALL_SSH_PASSWORD)" ssh $(INSTALL_SSH_OPTIONS) -p$(NIXPORT) $(NIXINSTALLUSER)@$(NIXADDR) " \
		sudo mkdir -p /var/lib/sops-nix && \
		sudo chmod 700 /var/lib/sops-nix && \
		if [ ! -f /var/lib/sops-nix/key.txt ]; then \
			sudo nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt'; \
			sudo chmod 600 /var/lib/sops-nix/key.txt; \
		fi && \
		sudo nix-shell -p age --run 'age-keygen -y /var/lib/sops-nix/key.txt' \
	" | tr -d '\r' > $(GENERATED_VM_AGE_PUBKEY_FILE)
	if ! grep -q '^age1' $(GENERATED_VM_AGE_PUBKEY_FILE); then \
		echo "Error: failed to fetch VM sops age public key"; \
		exit 1; \
	fi


.PHONY: vm/prepare-host-authorized-keys
vm/prepare-host-authorized-keys:
	if [ ! -f $(HOST_SSH_PUBKEY_FILE) ]; then \
		echo "Error: host SSH public key not found at $(HOST_SSH_PUBKEY_FILE)"; \
		exit 1; \
	fi
	cp $(HOST_SSH_PUBKEY_FILE) $(GENERATED_HOST_AUTH_KEYS_FILE)

# Create a fresh NixOS VM in VMware Fusion
.PHONY: vm/create
vm/create:
	@$(MAKEFILE_DIR)/scripts/vm-create.sh


# Partition disk using disko and install NixOS
vm/install:
	$(MAKE) vm/prepare-host-authorized-keys
	$(MAKE) vm/prepare-sops-host-pubkey
	git -C $(MAKEFILE_DIR) add machines/generated/vm-age-pubkey machines/generated/host-authorized-keys
	$(MAKE) secrets/collect
	rsync -av -e 'sshpass -p "$(INSTALL_SSH_PASSWORD)" ssh $(INSTALL_SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='iso/' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXINSTALLUSER)@$(NIXADDR):/nix-config
	sshpass -p "$(INSTALL_SSH_PASSWORD)" ssh $(INSTALL_SSH_OPTIONS) -p$(NIXPORT) $(NIXINSTALLUSER)@$(NIXADDR) " \
		if [ ! -d /nix-config ]; then \
			echo 'Error: /nix-config missing. Run vm/copy first (for first install: NIXUSER=root make vm/copy).'; \
			exit 1; \
		fi && \
		cd /nix-config && \
		git config --global --add safe.directory /nix-config && \
		git config --global user.email 'bootstrap@localhost' && \
		git config --global user.name 'Bootstrap' && \
		git init -q && \
		git add -A && \
		git add -f machines/secrets.yaml && \
		(git diff --cached --quiet || git commit -q -m 'bootstrap') && \
		sudo nix --experimental-features 'nix-command flakes' run \
			github:nix-community/disko -- \
			--mode disko \
			/nix-config/machines/hardware/disko-vm.nix && \
		sudo mkdir -p /mnt/var/lib/sops-nix && \
		sudo cp /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt && \
		sudo chmod 700 /mnt/var/lib/sops-nix && \
		sudo chmod 600 /mnt/var/lib/sops-nix/key.txt && \
		sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-install \
			--flake /nix-config#$(NIXNAME) \
			--no-root-passwd && \
		reboot \
	"


# copy the Nix configurations into the VM.
# Two-step: rsync to user-writable staging dir, then sudo move into
# root-owned /nix-config. This keeps /nix-config root-owned while
# requiring a password for every write (ssh -t gives sudo a TTY).
vm/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='vendor/' \
		--exclude='iso/' \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):~/.nix-config-staging
	ssh -t $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) \
		"sudo rsync -a ~/.nix-config-staging/ /nix-config/"

# run the nixos-rebuild switch command. This does NOT copy files so you
# have to run vm/copy before.
vm/switch:
	ssh -t $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo rsync -a ~/.nix-config-staging/ /nix-config/ && \
		sudo git config --global --add safe.directory /nix-config && \
		sudo git -C /nix-config add -f machines/secrets.yaml && \
		sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

vm/update:
	export NIXADDR=$$(vmrun -T fusion getGuestIPAddress "/Users/m/Virtual Machines.localized/NixOS 25.11 aarch64.vmwarevm/NixOS 25.11 aarch64.vmx") && \
	$(MAKE) vm/copy NIXADDR=$$NIXADDR && \
	$(MAKE) vm/switch NIXADDR=$$NIXADDR

# Build a WSL installer
.PHONY: wsl
wsl:
	nix build ".#nixosConfigurations.wsl.config.system.build.installer"


# One-command bootstrap using nixos-anywhere (experimental on aarch64)
.PHONY: vm/anywhere
vm/anywhere:
	nix run github:nix-community/nixos-anywhere -- \
		--flake ".#$(NIXNAME)" \
		--kexec "https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-aarch64-linux.tar.gz" \
		root@$(NIXADDR)
