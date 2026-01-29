#!/bin/bash
# Mock functions for testing LnOS-installer.sh
# This file provides mock implementations of external commands

# Mock gum functions (always return success unless overridden)
gum_style() { echo "$@"; }
gum_confirm() { return 0; }
gum_input() { echo "test_input"; }
gum_choose() { echo "test_choice"; }
gum_filter() { echo "test_filter"; }
gum_write() { echo "test_write"; }
gum_spin() { "$@"; }

gum_foreground() { echo "$@"; }
gum_white() { echo "$@"; }
gum_green() { echo "$@"; }
gum_yellow() { echo "$@"; }
gum_red() { echo "$@"; }

gum_title() { echo "$@"; }
gum_info() { echo "$@"; }
gum_warn() { echo "$@"; }
gum_fail() { echo "$@"; exit 1; }
gum_proc() { echo "$@"; }
gum_property() { echo "$@"; }

# Mock system commands
pacman() { echo "mock: pacman $@"; return 0; }
arch-chroot() { echo "mock: arch-chroot $@"; return 0; }
wipefs() { echo "mock: wipefs $@"; return 0; }
sgdisk() { echo "mock: sgdisk $@"; return 0; }
parted() { echo "mock: parted $@"; return 0; }
partprobe() { echo "mock: partprobe $@"; return 0; }
cryptsetup() { echo "mock: cryptsetup $@"; return 0; }
mkfs.fat() { echo "mock: mkfs.fat $@"; return 0; }
mkfs.ext4() { echo "mock: mkfs.ext4 $@"; return 0; }
mkfs.btrfs() { echo "mock: mkfs.btrfs $@"; return 0; }
mount() { echo "mock: mount $@"; return 0; }
pacstrap() { echo "mock: pacstrap $@"; return 0; }
genfstab() { echo "mock: genfstab $@"; return 0; }
bootctl() { echo "mock: bootctl $@"; return 0; }
lsblk() { echo "sda 20G TestDisk"; return 0; }
localectl() { echo "us"; return 0; }
blkid() { echo "12345-67890"; return 0; }
timedatectl() { echo "mock: timedatectl $@"; return 0; }
curl() { echo "America/Chicago"; return 0; }
ping() { return 0; }

# Export all functions
export -f gum_style gum_confirm gum_input gum_choose gum_filter gum_write gum_spin
export -f gum_foreground gum_white gum_green gum_yellow gum_red
export -f gum_title gum_info gum_warn gum_fail gum_proc gum_property
export -f pacman arch-chroot wipefs sgdisk parted partprobe cryptsetup
export -f mkfs.fat mkfs.ext4 mkfs.btrfs mount pacstrap genfstab bootctl
export -f lsblk localectl blkid timedatectl curl ping

# Mock file system
export TEST_MODE=1
