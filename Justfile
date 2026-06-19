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

iso:
    ./scripts/build-iso.sh
    sudo dd if=result/iso/$(ls result/iso/) of=/dev/sda bs=4M status=progress conv=fsync


#┌─── ✎ Edit: ⌘ den/aspects/hosts/jimi.nix 
#│disko.devices.disk.sda = {      
#│  device = "/dev/sda"; 
#│  type = "disk";        
qemu-verify-iso:
    #!/usr/bin/env bash

    cd ~/smallstepman.github.io && KEY=$(cat /tmp/qemu-test/id_ed25519.pub)     
    cat > /tmp/iso-expr-test4.nix << NIXEOF                                    
    let                                                                       
      f = builtins.getFlake "/home/m/smallstepman.github.io";                
      g = builtins.getFlake "/tmp/nix-generated";                           
      lib = f.inputs.nixpkgs.lib;                                          
      pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;                
      outputs = f.lib.mkOutputs { generated = g; };                      
      jimi = outputs.nixosConfigurations.jimi;                          
      installer = f.inputs.unattended-installer.lib.diskoInstallerWrapper jimi {  
        flake = "/tmp/qemu-test#test";                                 
        successAction = "poweroff";                                   
        showProgress = true;                                         
        waitForNetwork = false;                                     
        config = {                                                 
          users.users.root.openssh.authorizedKeys.keys = lib.mkForce [ "${KEY}" ];   
          services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
          systemd.services."unattended-installer-progress" = {
            wantedBy = [ "multi-user.target" ];              
            unitConfig.After = [ "getty.target" ];          
            unitConfig.Conflicts = [ "getty@tty8.service" ];
            serviceConfig.Type = "simple";                 
            path = [ pkgs.tmux pkgs.coreutils pkgs.kbd pkgs.nix-output-monitor ];
            script = ''                                                         
              set -xeufo pipefail                                              
              env -i ${pkgs.tmux}/bin/tmux start \; show -g                   
              ${pkgs.tmux}/bin/tmux new-session -d -s unattended-installer /bin/sh -lc "journalctl -fo cat -u unattended-installer.service 2>&1 | ${pkgs.nix-output-monitor}/bin/nom; /bin/sh" 
              ${pkgs.kbd}/bin/openvt -v --wait --login --console=8 --force --switch -- env -i TERM=linux ${pkgs.tmux}/bin/tmux attach-session -t unattended-installer                         
            '';                                                                                                                                                                              
          };                                                                                                                                                                                
        };                                                                                                                                                                                 
      };                                                                                                                                                                                  
    in                                                                                                                                                                                   
      installer.config.system.build.isoImage                                                                                                                                            
    NIXEOF                                                                                                                                                                             
    nix build --impure -f /tmp/iso-expr-test4.nix --out-link /tmp/qemu-test-iso13 2>&1 | tail -10                                                                                     
    sudo umount /mnt/iso 2>/dev/null                                                                                                                                                 
    sudo mount -o loop /tmp/qemu-test-iso13/iso/nixos-minimal-25.11.20260615.d6df351-x86_64-linux.iso /mnt/iso 2>&1                                                                 
    KERNEL=$(find /mnt/iso/boot -name 'bzImage' 2>/dev/null | head -1)                                                                                                             
    INITRD=$(find /mnt/iso/boot -name 'initrd' 2>/dev/null | head -1)                                                                                                             
    INIT=$(grep 'APPEND' /mnt/iso/isolinux/isolinux.cfg | head -1 | grep -oP 'init=\K[^ ]+')                                                                                     
    cp "$KERNEL" /tmp/qemu-test/bzImage13                                                                                                                                       
    cp "$INITRD" /tmp/qemu-test/initrd13                                                                                                                                      
    sudo umount /mnt/iso 2>/dev/null                                                                                                                                         
    echo "INIT=$INIT"                                                                                                                                                       
      qemu-system-x86_64 \                                                                                                                                                 
      -kernel /tmp/qemu-test/bzImage13 \                                                                                                                                  
      -initrd /tmp/qemu-test/initrd13 \                                                                                                                                  
      -append "init=/nix/store/30pgk6m250v8adk6ixy2316vfgy5h2js-nixos-system-nixos-25.11.20260615.d6df351/init boot.shell_on_fail root=LABEL=nixos-minimal-25.11-x86_64 quiet systemd.show_status=no nohibernate loglevel=4 lsm=landlock,yama,bpf console=ttyS0,115200n8" \                                                                              
      -cdrom /tmp/qemu-test-iso13/iso/nixos-minimal-25.11.20260615.d6df351-x86_64-linux.iso \                                                                                 
      -drive file=/tmp/nixos-test2.qcow2,format=qcow2 \                                                                                                                      
      -fsdev local,id=fsdev0,path=/tmp/qemu-test,security_model=mapped-xattr \                                                                                              
      -device virtio-9p-pci,fsdev=fsdev0,mount_tag=qemu-test \                                                                                                             
      -m 4G -smp 4 \                                                                                                                                                      
      -netdev user,id=net0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0 \                                                                                             
      -serial file:/tmp/qemu-serial23.log \                                                                                                                             
      -nographic -display none -vga none &                                                                                                                             
    QEMU_PID=$!                                                                                                                                                       
    sleep 300                                                                                                                                                        
    /tmp/sshpass-link/bin/sshpass -p "" ssh -i /tmp/qemu-test/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o PasswordAuthentication=no -p 2222 root@localhost 'echo "===STATUS==="; systemctl status unattended-installer 2>&1; systemctl status unattended-installer-progress 2>&1; echo "===JOURNAL==="; journalctl -u unattended-installer --no-pager -n 300 2>&1; echo "===MNT==="; ls -la /mnt 2>&1; echo "===DISKS==="; lsblk 2>&1; echo "===DONE==="' > /tmp/qemu-ssh-output13.log 2>&1                                             
    kill $QEMU_PID 2>/dev/null; wait $QEMU_PID 2>/dev/null                                                                                                                                      
    cat /tmp/qemu-ssh-output13.log                                                                                                                                                            
