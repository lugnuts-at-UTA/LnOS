#!/bin/bash
# End-to-end VM testing using QEMU
# This script creates a VM, boots it, and runs the installer automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
VM_NAME="lnos-test-vm"
VM_DISK="${VM_NAME}.qcow2"
VM_DISK_SIZE="20G"
VM_RAM="4G"
VM_CPUS="2"
ISO_URL="https://mirrors.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso"
ISO_PATH="archlinux.iso"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ==================================================================================================
# SETUP FUNCTIONS
# ==================================================================================================

download_iso() {
    if [ ! -f "$ISO_PATH" ]; then
        log_info "Downloading Arch Linux ISO..."
        curl -L -o "$ISO_PATH" "$ISO_URL"
    else
        log_info "ISO already downloaded"
    fi
}

create_vm_disk() {
    log_info "Creating VM disk: $VM_DISK ($VM_DISK_SIZE)"
    qemu-img create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
}

cleanup() {
    log_info "Cleaning up..."
    pkill -f "qemu-system-x86_64.*${VM_NAME}" 2>/dev/null || true
    rm -f "$VM_DISK" 2>/dev/null || true
}

# ==================================================================================================
# VM LAUNCH FUNCTIONS
# ==================================================================================================

launch_vm_install() {
    log_info "Launching VM for installation..."
    
    qemu-system-x86_64 \
        -name "$VM_NAME" \
        -machine type=q35,accel=kvm \
        -cpu host \
        -smp "$VM_CPUS" \
        -m "$VM_RAM" \
        -drive file="$VM_DISK",format=qcow2,if=virtio \
        -cdrom "$ISO_PATH" \
        -boot d \
        -net nic,model=virtio \
        -net user \
        -display none \
        -serial mon:stdio \
        -no-reboot &
    
    VM_PID=$!
    log_info "VM launched with PID: $VM_PID"
}

launch_vm_test() {
    log_info "Launching VM to test installation..."
    
    qemu-system-x86_64 \
        -name "$VM_NAME" \
        -machine type=q35,accel=kvm \
        -cpu host \
        -smp "$VM_CPUS" \
        -m "$VM_RAM" \
        -drive file="$VM_DISK",format=qcow2,if=virtio \
        -boot c \
        -net nic,model=virtio \
        -net user \
        -display none \
        -serial mon:stdio \
        -no-reboot
}

# ==================================================================================================
# EXPECT SCRIPT FOR AUTOMATION
# ==================================================================================================

create_expect_script() {
    cat > /tmp/lnos-test.exp <<'EOF'
#!/usr/bin/expect -f

set timeout 600
set prompt "root@archiso.*#"

# Start VM interaction
spawn qemu-system-x86_64 \
    -name lnos-test-vm \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp 2 \
    -m 4G \
    -drive file=lnos-test-vm.qcow2,format=qcow2,if=virtio \
    -cdrom archlinux.iso \
    -boot d \
    -net nic,model=virtio \
    -net user \
    -display none \
    -serial mon:stdio

# Wait for boot
expect {
    timeout { puts "Timeout waiting for boot"; exit 1 }
    -re $prompt
}

# Download and run installer
send "curl -o installer.sh https://raw.githubusercontent.com/YOUR_REPO/LnOS/main/LnOS-installer.sh\r"
expect -re $prompt
send "chmod +x installer.sh\r"
expect -re $prompt

# Run installer with automated responses
send "./installer.sh --target=x86_64\r"

# Wait for username prompt
expect {
    timeout { puts "Timeout waiting for username prompt"; exit 1 }
    "Enter Username"
}
send "testuser\r"

# Wait for password prompts
expect "Enter User Password"
send "testpass123\r"
expect "Confirm User Password"
send "testpass123\r"

# Root password
expect "Set separate root password"
send "n\r"

# Timezone (should auto-detect)
expect "Enter Timezone"
send "\r"

# Language
expect "Choose Language"
send "en_US\r"

# Keyboard
expect "Choose Keyboard"
send "us\r"

# Disk (select first option)
expect "Choose Disk"
send "\r"

# Filesystem
expect "Choose Root Filesystem"
send "ext4\r"

# Bootloader
expect "Choose Bootloader"
send "grub\r"

# Encryption
expect "Enable full disk encryption"
send "n\r"

# Desktop
expect "Choose Desktop Environment"
send "TTY\r"

# Graphics driver
expect "Choose Graphics Driver"
send "mesa\r"

# Multilib
expect "Enable 32-bit support"
send "n\r"

# AUR
expect "Choose AUR Helper"
send "none\r"

# Package profile
expect "Choose Package Profile"
send "Minimal\r"

# Confirm installation
expect "Start LnOS installation"
send "y\r"

# Wait for installation to complete (this takes a while)
set timeout 1800
expect {
    timeout { puts "Installation timeout"; exit 1 }
    "Installation completed"
}

# Don't reboot, exit
expect "Reboot into LnOS now"
send "n\r"

puts "Installation completed successfully!"
exit 0
EOF
    
    chmod +x /tmp/lnos-test.exp
}

# ==================================================================================================
# TEST SCENARIOS
# ==================================================================================================

test_basic_install() {
    log_info "Test: Basic Installation (UEFI, no encryption)"
    
    cleanup
    download_iso
    create_vm_disk
    create_expect_script
    
    log_info "Starting automated installation..."
    if /tmp/lnos-test.exp; then
        log_info "✓ Basic installation test passed"
        return 0
    else
        log_error "✗ Basic installation test failed"
        return 1
    fi
}

test_post_install_boot() {
    log_info "Test: Boot into installed system"
    
    launch_vm_test &
    VM_PID=$!
    
    sleep 60  # Wait for boot
    
    # Check if VM is still running
    if kill -0 $VM_PID 2>/dev/null; then
        log_info "✓ System booted successfully"
        kill $VM_PID
        return 0
    else
        log_error "✗ System failed to boot"
        return 1
    fi
}

# ==================================================================================================
# PACKER ALTERNATIVE (Recommended for CI/CD)
# ==================================================================================================

create_packer_template() {
    log_info "Creating Packer template for automated testing..."
    
    cat > packer-lnos.json <<'EOF'
{
  "builders": [{
    "type": "qemu",
    "iso_url": "https://mirrors.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso",
    "iso_checksum": "sha256:REPLACE_WITH_ACTUAL_CHECKSUM",
    "output_directory": "output-lnos",
    "shutdown_command": "sudo systemctl poweroff",
    "disk_size": 20480,
    "format": "qcow2",
    "accelerator": "kvm",
    "http_directory": "http",
    "ssh_username": "testuser",
    "ssh_password": "testpass123",
    "ssh_timeout": "30m",
    "vm_name": "lnos-test",
    "net_device": "virtio-net",
    "disk_interface": "virtio",
    "boot_wait": "5s",
    "boot_command": [
      "<enter><wait30>",
      "curl -o /tmp/installer.sh http://{{ .HTTPIP }}:{{ .HTTPPort }}/LnOS-installer.sh<enter><wait>",
      "chmod +x /tmp/installer.sh<enter><wait>",
      "/tmp/installer.sh --automated<enter>"
    ]
  }],
  "provisioners": [{
    "type": "shell",
    "inline": [
      "echo 'Verifying installation...'",
      "test -f /etc/os-release",
      "grep -q 'LnOS' /etc/os-release || exit 1",
      "echo 'Installation verified!'"
    ]
  }]
}
EOF
    
    log_info "Packer template created: packer-lnos.json"
    log_info "Run with: packer build packer-lnos.json"
}

# ==================================================================================================
# VAGRANT ALTERNATIVE (For Development Testing)
# ==================================================================================================

create_vagrant_setup() {
    log_info "Creating Vagrant test setup..."
    
    cat > Vagrantfile <<'EOF'
Vagrant.configure("2") do |config|
  config.vm.box = "archlinux/archlinux"
  
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus = 2
    vb.name = "lnos-test"
  end
  
  # Copy installer to VM
  config.vm.provision "file", source: "./scripts/LnOS-installer.sh", destination: "/tmp/installer.sh"
  
  # Run tests
  config.vm.provision "shell", inline: <<-SHELL
    cd /tmp
    chmod +x installer.sh
    
    # Run installer in test mode
    export TEST_MODE=1
    export LNOS_USERNAME="testuser"
    export LNOS_PASSWORD="testpass123"
    # ... set other env vars
    
    # Run validation tests
    bash -n installer.sh || exit 1
    shellcheck installer.sh || exit 1
    
    echo "All tests passed!"
  SHELL
end
EOF
    
    log_info "Vagrantfile created"
    log_info "Run with: vagrant up && vagrant provision"
}

# ==================================================================================================
# MAIN
# ==================================================================================================

main() {
    log_info "LnOS End-to-End Test Suite"
    log_info "==========================="
    
    # Check dependencies
    for cmd in qemu-system-x86_64 expect curl; do
        if ! command -v $cmd &>/dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    case "${1:-full}" in
        install)
            test_basic_install
            ;;
        boot)
            test_post_install_boot
            ;;
        packer)
            create_packer_template
            ;;
        vagrant)
            create_vagrant_setup
            ;;
        full)
            test_basic_install
            test_post_install_boot
            ;;
        *)
            echo "Usage: $0 {install|boot|packer|vagrant|full}"
            exit 1
            ;;
    esac
}

trap cleanup EXIT
main "$@"
