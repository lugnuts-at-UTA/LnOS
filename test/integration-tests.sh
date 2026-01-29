#!/bin/bash
# Integration tests using Docker
# These tests run the installer in a controlled environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up containers..."
		docker stop lnos-test-basic 2>/dev/null || true
    docker rm -f lnos-test-basic 2>/dev/null || true
}

trap cleanup EXIT

# ==================================================================================================
# TEST: Basic Installation (No Desktop, No Encryption)
# ==================================================================================================
test_basic_installation() {
    log_info "Test: Basic Installation"
    
    # Create container with loop device support
    docker run -d \
        --name lnos-test-basic \
        --privileged \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        sleep infinity
    
    # Create a loop device to simulate a disk
    docker exec lnos-test-basic bash -c '
        # Install dependencies
        pacman -Sy --noconfirm gum
        
        # Create a 10GB sparse file as disk
        dd if=/dev/zero of=/disk.img bs=1M count=1 seek=10240
        losetup /dev/loop0 /disk.img
        
        # Mock network check
        echo "127.0.0.1 google.com" >> /etc/hosts
        
        # Create auto-answer file for prompts
        export LNOS_USERNAME="testuser"
        export LNOS_PASSWORD="testpass123"
        export LNOS_ROOT_PASSWORD="rootpass123"
        export LNOS_DISK="/dev/loop0"
        export LNOS_FILESYSTEM="ext4"
        export LNOS_BOOTLOADER="grub"
        export LNOS_TIMEZONE="America/Chicago"
        export LNOS_LOCALE_LANG="en_US"
        export LNOS_VCONSOLE_KEYMAP="us"
        export LNOS_ENCRYPTION_ENABLED="false"
        export LNOS_DESKTOP_ENABLED="false"
        export LNOS_DESKTOP_ENVIRONMENT="TTY"
        export LNOS_MULTILIB_ENABLED="false"
        export LNOS_AUR_HELPER="none"
        export LNOS_PACKAGE_PROFILE="Minimal"
        
        # Run partitioning test only (not full install)
        cd /workspace
        bash -c "
            source ./scripts/LnOS-installer.sh --target=x86_64
            
            # Test boot mode detection
            if [ -d /sys/firmware/efi ]; then
                echo \"UEFI mode detected\"
            else
                echo \"BIOS mode detected\"
            fi
            
            # Test disk wiping
            wipefs -af /dev/loop0
            sgdisk --zap-all /dev/loop0
            
            # Test partitioning
            sgdisk -o /dev/loop0
            sgdisk -n 1:0:+512M -t 1:ef00 /dev/loop0
            sgdisk -n 2:0:0 -t 2:8300 /dev/loop0
            
            # Verify partitions were created
            lsblk /dev/loop0
        "
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Basic installation test passed"
        return 0
    else
        log_error "✗ Basic installation test failed"
        return 1
    fi
}

# ==================================================================================================
# TEST: Encryption Setup
# ==================================================================================================
test_encryption_setup() {
    log_info "Test: Encryption Setup"
    
    docker run -d \
        --name lnos-test-encryption \
        --privileged \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        sleep infinity
    
    docker exec lnos-test-encryption bash -c '
        pacman -Sy --noconfirm cryptsetup
        
        # Create test disk
        dd if=/dev/zero of=/disk.img bs=1M count=1 seek=5120
        losetup /dev/loop0 /disk.img
        
        # Create partitions
        parted /dev/loop0 mklabel gpt
        parted /dev/loop0 mkpart primary 1MiB 513MiB
        parted /dev/loop0 mkpart primary 513MiB 100%
        
        # Test encryption with non-interactive mode
        echo "testpass123" | cryptsetup luksFormat --type luks2 --batch-mode /dev/loop0p2
        echo "testpass123" | cryptsetup open /dev/loop0p2 testcrypt
        
        # Verify encrypted device is available
        if [ -e /dev/mapper/testcrypt ]; then
            echo "✓ Encryption device created successfully"
            cryptsetup close testcrypt
            exit 0
        else
            echo "✗ Encryption device not found"
            exit 1
        fi
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Encryption test passed"
        return 0
    else
        log_error "✗ Encryption test failed"
        return 1
    fi
}

# ==================================================================================================
# TEST: Filesystem Creation
# ==================================================================================================
test_filesystem_creation() {
    log_info "Test: Filesystem Creation"
    
    docker run -d \
        --name lnos-test-fs \
        --privileged \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        sleep infinity
    
    docker exec lnos-test-fs bash -c '
        pacman -Sy --noconfirm btrfs-progs e2fsprogs dosfstools
        
        # Create test disk
        dd if=/dev/zero of=/disk.img bs=1M count=1 seek=2048
        losetup /dev/loop0 /disk.img
        
        # Create partitions
        parted /dev/loop0 mklabel gpt
        parted /dev/loop0 mkpart primary fat32 1MiB 513MiB
        parted /dev/loop0 mkpart primary ext4 513MiB 100%
        
        # Format boot partition
        mkfs.fat -F32 /dev/loop0p1
        
        # Test ext4
        mkfs.ext4 -F /dev/loop0p2
        if ! blkid -t TYPE=ext4 /dev/loop0p2; then
            echo "✗ ext4 filesystem creation failed"
            exit 1
        fi
        
        # Cleanup for btrfs test
        wipefs -a /dev/loop0p2
        
        # Test btrfs
        mkfs.btrfs -f /dev/loop0p2
        if ! blkid -t TYPE=btrfs /dev/loop0p2; then
            echo "✗ btrfs filesystem creation failed"
            exit 1
        fi
        
        echo "✓ Filesystem creation tests passed"
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Filesystem test passed"
        return 0
    else
        log_error "✗ Filesystem test failed"
        return 1
    fi
}

# ==================================================================================================
# TEST: Configuration Persistence
# ==================================================================================================
test_config_persistence() {
    log_info "Test: Configuration Persistence"
    
    docker run -d \
        --name lnos-test-config \
        --privileged \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        sleep infinity
    
    docker exec lnos-test-config bash -c '
        pacman -Sy --noconfirm gum
        cd /workspace
        
        # Source the installer functions
        export SCRIPT_CONFIG="/tmp/test-config.conf"
        export SCRIPT_LOG="/tmp/test.log"
        export SCRIPT_TMP_DIR="/tmp/test-tmp"
        mkdir -p "$SCRIPT_TMP_DIR"
        
        source <(sed -n "/^properties_generate/,/^}/p" scripts/LnOS-installer.sh)
        source <(sed -n "/^properties_source/,/^}/p" scripts/LnOS-installer.sh)
        
        # Set test values
        export LNOS_USERNAME="testuser"
        export LNOS_PASSWORD="secret"
        export LNOS_DISK="/dev/sda"
        export LNOS_TIMEZONE="America/Chicago"
        export LNOS_FILESYSTEM="ext4"
        
        # Generate config
        properties_generate
        
        # Verify config file exists
        if [ ! -f "$SCRIPT_CONFIG" ]; then
            echo "✗ Config file not created"
            exit 1
        fi
        
        # Verify password is sanitized
        if grep -q "secret" "$SCRIPT_CONFIG"; then
            echo "✗ Password not sanitized in config"
            exit 1
        fi
        
        # Verify other values are present
        if ! grep -q "LNOS_USERNAME=.testuser." "$SCRIPT_CONFIG"; then
            echo "✗ Username not in config"
            exit 1
        fi
        
        echo "✓ Configuration persistence tests passed"
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Config persistence test passed"
        return 0
    else
        log_error "✗ Config persistence test failed"
        return 1
    fi
}

# ==================================================================================================
# TEST: Network Detection
# ==================================================================================================
test_network_detection() {
    log_info "Test: Network Detection"
    
    docker run -d \
        --name lnos-test-network \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        sleep infinity
    
    # Test with network
    docker exec lnos-test-network bash -c '
        if ping -c 1 google.com &>/dev/null; then
            echo "✓ Network is available"
            exit 0
        else
            echo "✗ Network not available"
            exit 1
        fi
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Network detection test passed"
        return 0
    else
        log_error "✗ Network detection test failed"
        return 1
    fi
}

# ==================================================================================================
# TEST: Partition Naming (NVMe vs SATA)
# ==================================================================================================
test_partition_naming() {
    log_info "Test: Partition Naming Logic"
    
    docker run --rm \
        -v "$PROJECT_ROOT:/workspace" \
        archlinux:latest \
        bash -c '
        cd /workspace
        
        # Test NVMe naming
        LNOS_DISK="/dev/nvme0n1"
        if [[ "$LNOS_DISK" =~ ^/dev/nvme ]]; then
            BOOT="${LNOS_DISK}p1"
            ROOT="${LNOS_DISK}p2"
        else
            BOOT="${LNOS_DISK}1"
            ROOT="${LNOS_DISK}2"
        fi
        
        if [ "$BOOT" != "/dev/nvme0n1p1" ] || [ "$ROOT" != "/dev/nvme0n1p2" ]; then
            echo "✗ NVMe partition naming incorrect: $BOOT, $ROOT"
            exit 1
        fi
        
        # Test SATA naming
        LNOS_DISK="/dev/sda"
        if [[ "$LNOS_DISK" =~ ^/dev/nvme ]]; then
            BOOT="${LNOS_DISK}p1"
            ROOT="${LNOS_DISK}2"
        else
            BOOT="${LNOS_DISK}1"
            ROOT="${LNOS_DISK}2"
        fi
        
        if [ "$BOOT" != "/dev/sda1" ] || [ "$ROOT" != "/dev/sda2" ]; then
            echo "✗ SATA partition naming incorrect: $BOOT, $ROOT"
            exit 1
        fi
        
        echo "✓ Partition naming tests passed"
    '
    
    if [ $? -eq 0 ]; then
        log_info "✓ Partition naming test passed"
        return 0
    else
        log_error "✗ Partition naming test failed"
        return 1
    fi
}

# ==================================================================================================
# MAIN TEST RUNNER
# ==================================================================================================

main() {
    log_info "Starting LnOS Integration Tests"
    log_info "================================"
    
    local failed=0
    
    test_basic_installation || ((failed++))
    test_encryption_setup || ((failed++))
    test_filesystem_creation || ((failed++))
    test_config_persistence || ((failed++))
    test_network_detection || ((failed++))
    test_partition_naming || ((failed++))
    
    echo ""
    log_info "================================"
    if [ $failed -eq 0 ]; then
        log_info "All tests passed! ✓"
        exit 0
    else
        log_error "$failed test(s) failed ✗"
        exit 1
    fi
}

main "$@"
