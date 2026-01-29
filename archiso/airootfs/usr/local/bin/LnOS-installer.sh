#!/bin/bash
# /*
# Copyright 2025 UTA-LugNuts Authors.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# */
#
# @file LnOS-installer.sh
# @brief Installs Arch Linux with LnOS customizations
# @author Betim-Hodza, Ric3y, rcghpge
# @date 2025

set -e

# ==================================================================================================
# GLOBALS
# ==================================================================================================

VERSION='1.0.0'
SCRIPT_LOG="./installer.log"
SCRIPT_CONFIG="./installer.conf"
SCRIPT_TMP_DIR="$(mktemp -d "./.tmp.XXXXX")"
ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"

[ "$*" = "--version" ] && echo "$VERSION" && exit 0

# Colors (for gum styling)
COLOR_BLACK=0
COLOR_RED=9
COLOR_GREEN=10
COLOR_YELLOW=11
COLOR_BLUE=12
COLOR_PURPLE=13
COLOR_CYAN=14
COLOR_WHITE=15
COLOR_FOREGROUND="${COLOR_BLUE}"
COLOR_BACKGROUND="${COLOR_WHITE}"

# Configuration variables
LNOS_USERNAME=""
LNOS_PASSWORD=""
LNOS_ROOT_PASSWORD=""           # Separate root password (recommended)
LNOS_TIMEZONE=""
LNOS_LOCALE_LANG=""
LNOS_LOCALE_GEN_LIST=()
LNOS_VCONSOLE_KEYMAP=""
LNOS_DISK=""
LNOS_BOOT_PARTITION=""
LNOS_ROOT_PARTITION=""
LNOS_FILESYSTEM=""         # Default, user can change
LNOS_BOOTLOADER=""
LNOS_ENCRYPTION_ENABLED=""
LNOS_DESKTOP_ENABLED=""
LNOS_DESKTOP_ENVIRONMENT=""
LNOS_DESKTOP_GRAPHICS_DRIVER=""
LNOS_MULTILIB_ENABLED=""
LNOS_AUR_HELPER=""
LNOS_PACKAGE_PROFILE=""


# ==================================================================================================
# BETTER LOGGING 
# ==================================================================================================
log() {
	local level="$1"
	shift 
	local msg="$*"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local func="${FUNCNAME[2]:-main}"
	local line="${BASH_LINENO[1]:-?}"
	echo -e "$timestamp | $level | $func:$line | $msg" >> "$SCRIPT_LOG"
  echo -e "$msg"
}

log_debug() { log "DEBUG" "$@"; }
log_info()  { log "INFO " "$@"; }
log_warn()  { log "WARN " "$@"; }
log_error() { log "ERROR" "$@"; }
log_fatal() { log "FATAL" "$@"; exit 1; }


run_logged() {
	log_debug "Running: $*"
	"$@" 2>&1 | while IFS= read -r line; do log_debug "$line"; done
	return ${PIPESTATUS[0]}
}

# ==================================================================================================
# TRAP FUNCTIONS
# ==================================================================================================

trap_error() {
	local cmd="$BASH_COMMAND"
	local code=$?
	echo "Command '$cmd' failed with code $code in ${FUNCNAME[1]:-unknown} (line ${BASH_LINENO[0]})" > "$ERROR_MSG"
}

trap_exit() {
	local code=$?
	local error_msg=""
	[ -f "$ERROR_MSG" ] && error_msg=$(<"$ERROR_MSG") && rm -f "$ERROR_MSG"

	unset LNOS_PASSWORD LNOS_ROOT_PASSWORD
	rm -rf "$SCRIPT_TMP_DIR"

	if [ $code -eq 130 ]; then
			gum_warn "Installation cancelled by user" || log_warn "Installation cancelled"
			exit 1
	fi

	if [ $code -ne 0 ]; then
			if [ -n "$error_msg" ]; then
					gum_fail "$error_msg" || log_error "$error_msg"
			else
					gum_fail "Installation failed with code $code" || log_error "Installation failed with code $code"
			fi
			gum_warn "Full log: $SCRIPT_LOG" || log_warn "Full log: $SCRIPT_LOG"
	fi
	exit $code
}

trap 'trap_exit' EXIT
trap 'trap_error ${FUNCNAME} ${LINENO}' ERR

# ==================================================================================================
# GUM WRAPPER FUNCTIONS
# ==================================================================================================

gum_style() { gum style "${@}"; }
gum_confirm() { gum confirm --prompt.foreground "$COLOR_FOREGROUND" --selected.background "$COLOR_FOREGROUND" --selected.foreground "$COLOR_BACKGROUND" --unselected.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_input() { gum input --placeholder "..." --prompt "> " --cursor.foreground "$COLOR_FOREGROUND" --prompt.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_choose() { gum choose --cursor "> " --header.foreground "$COLOR_FOREGROUND" --cursor.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_filter() { gum filter --prompt "> " --indicator ">" --placeholder "Type to filter..." --height 8 --header.foreground "$COLOR_FOREGROUND" --indicator.foreground "$COLOR_FOREGROUND" --match.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_write() { gum write --prompt "> " --show-cursor-line --char-limit 0 --cursor.foreground "$COLOR_FOREGROUND" --header.foreground "$COLOR_FOREGROUND" "${@}"; }
gum_spin() { gum spin --spinner line --title.foreground "$COLOR_FOREGROUND" --spinner.foreground "$COLOR_FOREGROUND" "${@}"; }

gum_foreground() { gum_style --foreground "$COLOR_FOREGROUND" "${@}"; }
gum_white() { gum_style --foreground "$COLOR_WHITE" "${@}"; }
gum_green() { gum_style --foreground "$COLOR_GREEN" "${@}"; }
gum_yellow() { gum_style --foreground "$COLOR_YELLOW" "${@}"; }
gum_red() { gum_style --foreground "$COLOR_RED" "${@}"; }

gum_title() { log_info "${*}" && gum join "$(gum_foreground --bold "+ ")" "$(gum_foreground --bold "${*}")"; }
gum_info() { log_info "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "${*}")"; }
gum_warn() { log_warn "$*" && gum join "$(gum_yellow --bold "• ")" "$(gum_white "${*}")"; }
gum_fail() { log_fatal "$*" && gum join "$(gum_red --bold "• ")" "$(gum_white "${*}")"; }
gum_proc() { log_debug "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white --bold "$(print_filled_space 24 "${1}")")" "$(gum_white " > ")" "$(gum_green "${2}")"; }
gum_property() { log_debug "$*" && gum join "$(gum_green --bold "• ")" "$(gum_white "$(print_filled_space 24 "${1}")")" "$(gum_green --bold " > ")" "$(gum_white --bold "${2}")"; }

# ==================================================================================================
# HELPER FUNCTIONS
# ==================================================================================================

print_header() {
    local title="$1"
    clear
    gum_foreground '
 █████                     ███████     █████████ 
░░███                    ███░░░░░███  ███░░░░░███
 ░███        ████████   ███     ░░███░███    ░░░ 
 ░███       ░░███░░███ ░███      ░███░░█████████ 
 ░███        ░███ ░███ ░███      ░███ ░░░░░░░░███
 ░███      █ ░███ ░███ ░░███     ███  ███    ░███
 ███████████ ████ █████ ░░░███████░  ░░█████████ 
░░░░░░░░░░░ ░░░░ ░░░░░    ░░░░░░░     ░░░░░░░░░  
'
    gum_white --margin "1 0" --align left --bold "Welcome to ${title} v.${VERSION}"
}

print_filled_space() {
    local total="$1" text="$2" length="${#text}"
    [ "$length" -ge "$total" ] && echo "$text" && return 0
    printf '%s%*s\n' "$text" "$((total - length))" ""
}

trap_gum_exit() { exit 130; }
trap_gum_exit_confirm() { gum_confirm "Exit Installation?" && trap_gum_exit; }

# ==================================================================================================
# CONFIGURATION PERSISTENCE
# ==================================================================================================

properties_source() {
    [ ! -f "$SCRIPT_CONFIG" ] && return 1
    set -a
    source "$SCRIPT_CONFIG"
    set +a
}

properties_generate() {
    {
        echo "LNOS_USERNAME='${LNOS_USERNAME}'"
        echo "LNOS_PASSWORD='*****'"  # Never store real password
        echo "LNOS_ROOT_PASSWORD='*****'"
        echo "LNOS_DISK='${LNOS_DISK}'"
        echo "LNOS_BOOT_PARTITION='${LNOS_BOOT_PARTITION}'"
        echo "LNOS_ROOT_PARTITION='${LNOS_ROOT_PARTITION}'"
        echo "LNOS_FILESYSTEM='${LNOS_FILESYSTEM}'"
        echo "LNOS_BOOTLOADER='${LNOS_BOOTLOADER}'"
        echo "LNOS_ENCRYPTION_ENABLED='${LNOS_ENCRYPTION_ENABLED}'"
        echo "LNOS_TIMEZONE='${LNOS_TIMEZONE}'"
        echo "LNOS_LOCALE_LANG='${LNOS_LOCALE_LANG}'"
        echo "LNOS_LOCALE_GEN_LIST=(${LNOS_LOCALE_GEN_LIST[*]@Q})"
        echo "LNOS_VCONSOLE_KEYMAP='${LNOS_VCONSOLE_KEYMAP}'"
        echo "LNOS_DESKTOP_ENABLED='${LNOS_DESKTOP_ENABLED}'"
        echo "LNOS_DESKTOP_ENVIRONMENT='${LNOS_DESKTOP_ENVIRONMENT}'"
        echo "LNOS_DESKTOP_GRAPHICS_DRIVER='${LNOS_DESKTOP_GRAPHICS_DRIVER}'"
        echo "LNOS_MULTILIB_ENABLED='${LNOS_MULTILIB_ENABLED}'"
        echo "LNOS_AUR_HELPER='${LNOS_AUR_HELPER}'"
        echo "LNOS_PACKAGE_PROFILE='${LNOS_PACKAGE_PROFILE}'"
    } > "$SCRIPT_CONFIG"
}

# ==================================================================================================
# SELECTION FUNCTIONS
# ==================================================================================================

select_username() {
    if [ -z "$LNOS_USERNAME" ]; then
        local input
        input=$(gum_input --header "+ Enter Username") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_USERNAME="$input"
        properties_generate
    fi
    gum_property "Username" "$LNOS_USERNAME"
}

select_password() {
    if [ "$1" = "--change" ] || [ -z "$LNOS_PASSWORD" ]; then
        local pass1 pass2
        pass1=$(gum_input --password --header "+ Enter User Password") || trap_gum_exit_confirm
        [ -z "$pass1" ] && return 1
        pass2=$(gum_input --password --header "+ Confirm User Password") || trap_gum_exit_confirm
        [ "$pass1" != "$pass2" ] && { gum_confirm --affirmative="Ok" --negative="" "Passwords do not match"; return 1; }
        LNOS_PASSWORD="$pass1"
        properties_generate
    fi
    [ "$1" = "--change" ] && gum_info "User password changed"
    [ "$1" != "--change" ] && gum_property "User Password" "*******"
}

select_root_password() {
    if [ -z "$LNOS_ROOT_PASSWORD" ]; then
        if gum_confirm "Set separate root password? (Recommended)"; then
            local pass1 pass2
            pass1=$(gum_input --password --header "+ Enter Root Password") || trap_gum_exit_confirm
            [ -z "$pass1" ] && return 1
            pass2=$(gum_input --password --header "+ Confirm Root Password") || trap_gum_exit_confirm
            [ "$pass1" != "$pass2" ] && { gum_confirm --affirmative="Ok" --negative="" "Root passwords do not match"; return 1; }
            LNOS_ROOT_PASSWORD="$pass1"
        else
            LNOS_ROOT_PASSWORD="$LNOS_PASSWORD"
        fi
        properties_generate
    fi
    [ "$LNOS_ROOT_PASSWORD" = "$LNOS_PASSWORD" ] && gum_property "Root Password" "Same as user" || gum_property "Root Password" "Separate"
}

select_timezone() {
    if [ -z "$LNOS_TIMEZONE" ]; then
        local auto_tz input
        auto_tz="$(curl -s http://ip-api.com/line?fields=timezone 2>/dev/null || echo "America/Chicago")"
        input=$(gum_input --header "+ Enter Timezone (auto-detected)" --value "$auto_tz") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        [ ! -f "/usr/share/zoneinfo/$input" ] && { gum_confirm --affirmative="Ok" --negative="" "Invalid timezone"; return 1; }
        LNOS_TIMEZONE="$input"
        properties_generate
    fi
    gum_property "Timezone" "$LNOS_TIMEZONE"
}

select_language() {
    if [ -z "$LNOS_LOCALE_LANG" ] || [ ${#LNOS_LOCALE_GEN_LIST[@]} -eq 0 ]; then
        local input items options
        mapfile -t items < <(basename -a /usr/share/i18n/locales/* | grep -v "@")
        options=()
        for item in "${items[@]}"; do
            grep -q -e "^$item" -e "^#$item" /etc/locale.gen && options+=("$item")
        done
        input=$(gum_filter --header "+ Choose Language" "${options[@]}") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_LOCALE_LANG="$input"
        LNOS_LOCALE_GEN_LIST=()
        while read -r line; do
            LNOS_LOCALE_GEN_LIST+=("$line")
        done < <(sed "/^#$LNOS_LOCALE_LANG/s/^#//" /etc/locale.gen | grep "$LNOS_LOCALE_LANG")
        [[ " ${LNOS_LOCALE_GEN_LIST[*]} " != *" en_US.UTF-8 UTF-8 "* ]] && LNOS_LOCALE_GEN_LIST+=("en_US.UTF-8 UTF-8")
        properties_generate
    fi
    gum_property "Language" "$LNOS_LOCALE_LANG"
}

select_keyboard() {
    if [ -z "$LNOS_VCONSOLE_KEYMAP" ]; then
        local input items
        mapfile -t items < <(localectl list-keymaps)
        input=$(gum_filter --header "+ Choose Keyboard Layout" "${items[@]}") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_VCONSOLE_KEYMAP="$input"
        properties_generate
    fi
    gum_property "Keyboard" "$LNOS_VCONSOLE_KEYMAP"
}

select_disk() {
    if [ -z "$LNOS_DISK" ]; then
        local input items
        mapfile -t items < <(lsblk -d -n -o NAME,SIZE,MODEL | awk '{print "/dev/"$1" ("$2") "$3}')
        input=$(gum_choose --header "+ Choose Disk (WILL BE WIPED!)" "${items[@]}") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_DISK=$(echo "$input" | awk '{print $1}')
        [[ "$LNOS_DISK" =~ ^/dev/nvme ]] && LNOS_BOOT_PARTITION="${LNOS_DISK}p1" || LNOS_BOOT_PARTITION="${LNOS_DISK}1"
        [[ "$LNOS_DISK" =~ ^/dev/nvme ]] && LNOS_ROOT_PARTITION="${LNOS_DISK}p2" || LNOS_ROOT_PARTITION="${LNOS_DISK}2"
        properties_generate
    fi
    gum_property "Disk" "$LNOS_DISK"
    gum_property "Boot Partition" "$LNOS_BOOT_PARTITION"
    gum_property "Root Partition" "$LNOS_ROOT_PARTITION"
}

select_filesystem() {
    if [ -z "$LNOS_FILESYSTEM" ]; then
        local input
        input=$(gum_choose --header "+ Choose Root Filesystem" "btrfs" "ext4") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_FILESYSTEM="$input"
        properties_generate
    fi
    gum_property "Filesystem" "$LNOS_FILESYSTEM"
}

select_bootloader() {
    if [ -z "$LNOS_BOOTLOADER" ]; then
        local input
        input=$(gum_choose --header "+ Choose Bootloader (systemd = Secure Boot support)" "grub" "systemd") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_BOOTLOADER="$input"
        properties_generate
    fi
    gum_property "Bootloader" "$LNOS_BOOTLOADER"
}

select_enable_encryption() {
    if [ -z "$LNOS_ENCRYPTION_ENABLED" ]; then
        gum_confirm "Enable full disk encryption?" && LNOS_ENCRYPTION_ENABLED="true" || LNOS_ENCRYPTION_ENABLED="false"
        properties_generate
    fi
    gum_property "Disk Encryption" "$LNOS_ENCRYPTION_ENABLED"
}

select_enable_desktop_environment() {
    if [ -z "$LNOS_DESKTOP_ENABLED" ] || [ -z "$LNOS_DESKTOP_ENVIRONMENT" ]; then
        local input
        input=$(gum_choose --header "+ Choose Desktop Environment" "Gnome" "KDE" "Hyprland" "DWM" "TTY") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_DESKTOP_ENVIRONMENT="$input"
        [ "$input" = "TTY" ] && LNOS_DESKTOP_ENABLED="false" || LNOS_DESKTOP_ENABLED="true"
        properties_generate
    fi
    gum_property "Desktop Environment" "$LNOS_DESKTOP_ENVIRONMENT"
}

select_enable_desktop_driver() {
    if [ "$LNOS_DESKTOP_ENABLED" = "true" ] && [ "$LNOS_DESKTOP_GRAPHICS_DRIVER" = "none" ]; then
        local input
        input=$(gum_choose --header "+ Choose Graphics Driver (default: mesa)" mesa intel_i915 nvidia amd ati) || trap_gum_exit_confirm
        [ -z "$input" ] && input="mesa"
        LNOS_DESKTOP_GRAPHICS_DRIVER="$input"
        properties_generate
    fi
    gum_property "Graphics Driver" "${LNOS_DESKTOP_GRAPHICS_DRIVER:-mesa}"
}

select_enable_multilib() {
    if [ -z "$LNOS_MULTILIB_ENABLED" ]; then
        gum_confirm "Enable 32-bit support (multilib)?" && LNOS_MULTILIB_ENABLED="true" || LNOS_MULTILIB_ENABLED="false"
        properties_generate
    fi
    gum_property "32-bit Support" "$LNOS_MULTILIB_ENABLED"
}

select_enable_aur() {
    if [ -z "$LNOS_AUR_HELPER" ]; then
        local input
        input=$(gum_choose --header "+ Choose AUR Helper" "paru" "paru-git" "none") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_AUR_HELPER="$input"
        properties_generate
    fi
    gum_property "AUR Helper" "$LNOS_AUR_HELPER"
}

select_package_profile() {
    if [ -z "$LNOS_PACKAGE_PROFILE" ]; then
        local input
        input=$(gum_choose --header "+ Choose Package Profile" "CSE" "SWE" "CPE" "DS" "Custom" "Minimal") || trap_gum_exit_confirm
        [ -z "$input" ] && return 1
        LNOS_PACKAGE_PROFILE="$input"
        properties_generate
    fi
    gum_property "Package Profile" "$LNOS_PACKAGE_PROFILE"
}

# ==================================================================================================
# INSTALLATION FUNCTIONS
# ==================================================================================================

install_base_system() {
    gum_info "Installing base system..."
		log_info "Starting base system installation"

    # Detect boot mode
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    log_info "Boot mode: $BOOT_MODE"

    timedatectl set-ntp true

    # Final warning before wiping disk
    gum_confirm "This will COMPLETELY WIPE $LNOS_DISK. Continue?" || exit 1

    run_logged wipefs -af "$LNOS_DISK"
    run_logged sgdisk --zap-all "$LNOS_DISK"

    if [ "$BOOT_MODE" = "uefi" ]; then
			run_logged sgdisk -o "$LNOS_DISK"
			run_logged sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$LNOS_DISK"
			run_logged sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$LNOS_DISK"
    else
			run_logged parted "$LNOS_DISK" mklabel msdos
			run_logged parted "$LNOS_DISK" mkpart primary fat32 1MiB 513MiB
			run_logged parted "$LNOS_DISK" mkpart primary ext2 513MiB 100%
			run_logged parted "$LNOS_DISK" set 1 boot on
    fi

    run_logged partprobe "$LNOS_DISK"

    # Encryption handling
    if [ "$LNOS_ENCRYPTION_ENABLED" = "true" ]; then
			
			log_info "formatting encrypted root partition"

			echo -n "$LNOS_PASSWORD" | cryptsetup luksFormat --type luks2 "$LNOS_ROOT_PARTITION"
			echo -n "$LNOS_PASSWORD" | cryptsetup open "$LNOS_ROOT_PARTITION" cryptroot
			ROOT_DEV="/dev/mapper/cryptroot"
    else
			ROOT_DEV="$LNOS_ROOT_PARTITION"
    fi

    # Format boot partition
    run_logged mkfs.fat -F32 -n BOOT "$LNOS_BOOT_PARTITION"

    # Format root
    if [ "$LNOS_FILESYSTEM" = "ext4" ]; then
			run_logged mkfs.ext4 -F -L ROOT "$ROOT_DEV"
    else
			run_logged mkfs.btrfs -f -L ROOT "$ROOT_DEV"
    fi

		log_debug "mounting drives"

    # Mount
    mount "$ROOT_DEV" /mnt
    mount --mkdir "$LNOS_BOOT_PARTITION" /mnt/boot

    # Base packages
    local packages=(base linux-hardened linux-firmware base-devel git networkmanager)
    [ "$LNOS_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs)
    [ "$LNOS_BOOTLOADER" = "grub" ] && packages+=(grub) && [ "$BOOT_MODE" = "uefi" ] && packages+=(efibootmgr)

    run_logged pacstrap -K /mnt "${packages[@]}"
    run_logged genfstab -U /mnt >> /mnt/etc/fstab

    gum_info "Base system installed"
}

configure_system() {
    gum_info "Configuring system..."

    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$LNOS_TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locale
    for locale in "${LNOS_LOCALE_GEN_LIST[@]}"; do
        sed -i "s/^#$locale/$locale/" /mnt/etc/locale.gen
    done
    arch-chroot /mnt locale-gen
    echo "LANG=${LNOS_LOCALE_LANG}.UTF-8" > /mnt/etc/locale.conf

    # Keyboard
    echo "KEYMAP=$LNOS_VCONSOLE_KEYMAP" > /mnt/etc/vconsole.conf

    # Hostname
    echo "LnOS" > /mnt/etc/hostname
    cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
EOF

    # mkinitcpio hooks for encryption
    if [ "$LNOS_ENCRYPTION_ENABLED" = "true" ]; then
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)/' /mnt/etc/mkinitcpio.conf
    fi
    arch-chroot /mnt mkinitcpio -P

    # Users and passwords
    arch-chroot /mnt useradd -m -G wheel,audio,video,optical,storage -s /bin/bash "$LNOS_USERNAME"
    printf "%s\n%s" "$LNOS_PASSWORD" "$LNOS_PASSWORD" | arch-chroot /mnt passwd "$LNOS_USERNAME"
    printf "%s\n%s" "$LNOS_ROOT_PASSWORD" "$LNOS_ROOT_PASSWORD" | arch-chroot /mnt passwd root

    # Sudo
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers

    # Services
    arch-chroot /mnt systemctl enable NetworkManager

    gum_info "System configured"
}

install_bootloader() {
	gum_info "Installing bootloader..."
	log_info "Installing bootloader: $LNOS_BOOTLOADER ($BOOT_MODE)"

	local kernel_args=('rw')

	if [ "$LNOS_ENCRYPTION_ENABLED" = "true" ]; then
		local uuid=$(blkid -s UUID -o value "$LNOS_ROOT_PARTITION")
		kernel_args+=("rd.luks.uuid=$uuid" "root=/dev/mapper/cryptroot")
	else
		kernel_args+=("root=PARTUUID=$(blkid -s PARTUUID -o value "$LNOS_ROOT_PARTITION")")
	fi

	if [ "$BOOT_MODE" = "uefi" ]; then
		if [ "$LNOS_BOOTLOADER" = "systemd" ]; then
			arch-chroot /mnt bootctl --esp-path=/boot install
			mkdir -p /mnt/boot/loader/entries
			cat > /mnt/boot/loader/loader.conf <<EOF
default main.conf
timeout 0
editor no
EOF
			cat > /mnt/boot/loader/entries/main.conf <<EOF
title   LnOS
linux   /vmlinuz-linux-hardened
initrd  /initramfs-linux-hardened.img
options ${kernel_args[*]}
EOF
			# Secure Boot (best effort)
			arch-chroot /mnt pacman -S --noconfirm sbctl
			arch-chroot /mnt sbctl create-keys || true
			arch-chroot /mnt sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine || true
			for f in /boot/vmlinuz-linux-hardened /boot/initramfs-linux-hardened.img /boot/loader/loader.conf /boot/loader/entries/main.conf; do
				arch-chroot /mnt sbctl sign -s "$f" || true
			done
		else  # GRUB on UEFI
			run_logged arch-chroot /mnt pacman -S --noconfirm grub efibootmgr
			run_logged arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
			sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ ${kernel_args[*]} \"/" /mnt/etc/default/grub
			run_logged arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
			gum_warn "GRUB installed on UEFI (Secure Boot not supported)"
		fi
	else  # BIOS
		run_logged arch-chroot /mnt pacman -S --noconfirm grub
		sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/s/\"$/ ${kernel_args[*]} \"/" /mnt/etc/default/grub
		run_logged arch-chroot /mnt grub-install --target=i386-pc "$LNOS_DISK"
		run_logged arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
	fi

	gum_info "Bootloader installed"
}

install_desktop_environment() {
    [ "$LNOS_DESKTOP_ENABLED" != "true" ] && return

    gum_info "Installing desktop: $LNOS_DESKTOP_ENVIRONMENT"

    case "$LNOS_DESKTOP_ENVIRONMENT" in
        Gnome)
            arch-chroot /mnt pacman -S --noconfirm xorg gnome gdm
            arch-chroot /mnt systemctl enable gdm
            ;;
        KDE)
            arch-chroot /mnt pacman -S --noconfirm xorg plasma kde-applications sddm
            arch-chroot /mnt systemctl enable sddm
            ;;
        Hyprland)
            arch-chroot /mnt pacman -S --noconfirm hyprland kitty waybar wofi dunst xdg-desktop-portal-hyprland
            mkdir -p "/mnt/home/$LNOS_USERNAME/.config/hypr"
            cat > "/mnt/home/$LNOS_USERNAME/.config/hypr/hyprland.conf" <<'EOF'
exec-once = waybar & dunst & kitty
input { kb_layout = us }
EOF
            echo '[[ $(tty) = /dev/tty1 ]] && exec Hyprland' >> "/mnt/home/$LNOS_USERNAME/.bash_profile"
            arch-chroot /mnt chown -R "$LNOS_USERNAME:$LNOS_USERNAME" "/home/$LNOS_USERNAME"
            ;;
        DWM)
            if [ "$LNOS_AUR_HELPER" != "none" ]; then
                arch-chroot /mnt /usr/bin/runuser -u "$LNOS_USERNAME" -- "$LNOS_AUR_HELPER" -S --noconfirm dwm dmenu st
            else
                gum_warn "AUR helper not selected – installing minimal X11"
                arch-chroot /mnt pacman -S --noconfirm xorg xterm
            fi
            ;;
    esac

    gum_info "Desktop installed"
}

install_graphics_driver() {
    [ -z "$LNOS_DESKTOP_GRAPHICS_DRIVER" ] || [ "$LNOS_DESKTOP_GRAPHICS_DRIVER" = "none" ] && return

    gum_info "Installing graphics driver: $LNOS_DESKTOP_GRAPHICS_DRIVER"

    case "$LNOS_DESKTOP_GRAPHICS_DRIVER" in
        mesa)           arch-chroot /mnt pacman -S --noconfirm mesa lib32-mesa ;;
        intel_i915)     arch-chroot /mnt pacman -S --noconfirm mesa intel-media-driver vulkan-intel lib32-mesa lib32-vulkan-intel ;;
        nvidia)         arch-chroot /mnt pacman -S --noconfirm nvidia nvidia-utils lib32-nvidia-utils ;;
        amd)            arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-amdgpu vulkan-radeon lib32-mesa lib32-vulkan-radeon ;;
        ati)            arch-chroot /mnt pacman -S --noconfirm mesa xf86-video-ati lib32-mesa ;;
    esac

    gum_info "Graphics driver installed"
}

enable_multilib() {
    [ "$LNOS_MULTILIB_ENABLED" != "true" ] && return

    gum_info "Enabling multilib repository..."
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
    arch-chroot /mnt pacman -Syyu --noconfirm
    gum_info "Multilib enabled"
}

install_aur_helper() {
    [ "$LNOS_AUR_HELPER" = "none" ] && return

    gum_info "Installing AUR helper: $LNOS_AUR_HELPER"

    echo "$LNOS_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /mnt/etc/sudoers.d/aur-temp

    arch-chroot /mnt /usr/bin/runuser -u "$LNOS_USERNAME" -- bash -c "
        cd /tmp
        git clone https://aur.archlinux.org/$LNOS_AUR_HELPER.git
        cd $LNOS_AUR_HELPER
        makepkg -si --noconfirm
    "

    rm /mnt/etc/sudoers.d/aur-temp
    gum_info "AUR helper installed"
}

install_packages() {
    gum_info "Installing packages for profile: $LNOS_PACKAGE_PROFILE"

    local base_packages=(
        vim nano git wget curl base-devel
        dolphin btop htop tree unzip zip jq cowsay
        cava bat man man-pages tldr strace fzf
        openssh mpv signal-desktop
    )

    case "$LNOS_PACKAGE_PROFILE" in
        CSE|SWE|CPE|DS)
            local file="./pacman-packages/${LNOS_PACKAGE_PROFILE}_packages.txt"
            if [[ -f "$file" ]]; then
                mapfile -t extra < "$file"
                base_packages+=("${extra[@]}")
            fi
            arch-chroot /mnt pacman -S --noconfirm "${base_packages[@]}"

            [ "$LNOS_AUR_HELPER" != "none" ] && arch-chroot /mnt /usr/bin/runuser -u "$LNOS_USERNAME" -- "$LNOS_AUR_HELPER" -S --noconfirm brave-bin
            ;;
        Custom)
            local custom=$(gum_input --header "+ Enter additional packages (space-separated, or blank)")
            [ -n "$custom" ] && arch-chroot /mnt pacman -S --noconfirm $custom
            ;;
        Minimal)
            arch-chroot /mnt pacman -S --noconfirm vim git wget curl openssh
            ;;
    esac

    gum_info "Packages installed"
}

copy_lnos_files() {
    gum_info "Copying LnOS custom files..."
    local repo="/root/LnOS"
    if [ -d "$repo" ]; then
        mkdir -p /mnt/root/LnOS
        cp -r "$repo"/* /mnt/root/LnOS/ 2>/dev/null || true
        [ -f /mnt/root/LnOS/files/os-release ] && cp /mnt/root/LnOS/files/os-release /mnt/etc/os-release
        gum_info "LnOS files copied"
    else
        gum_warn "LnOS repo not found at $repo"
    fi
}

finalize_installation() {
    gum_info "Finalizing..."

    cp -f "$SCRIPT_CONFIG" "/mnt/home/$LNOS_USERNAME/installer.conf" 2>/dev/null || true
    cp -f "$SCRIPT_LOG" "/mnt/home/$LNOS_USERNAME/installer.log" 2>/dev/null || true
    arch-chroot /mnt chown -R "$LNOS_USERNAME:$LNOS_USERNAME" "/home/$LNOS_USERNAME" 2>/dev/null || true

    arch-chroot /mnt pacman -Rns --noconfirm $(pacman -Qtdq) 2>/dev/null || true

    gum_info "Installation finalized"
}

# ==================================================================================================
# MAIN
# ==================================================================================================

main() {
    [ -f "$SCRIPT_LOG" ] && rm "$SCRIPT_LOG"
    command -v gum >/dev/null || pacman -Sy --noconfirm gum

    log_info "LnOS Installer $VERSION started"

    while true; do
        print_header "LnOS Installer"

        gum_white "Please ensure:"
        gum_white "• Data backed up"
        gum_white "• Stable internet"
        gum_white "• UEFI mode recommended"
        echo

        # Internet check
        if ! ping -c1 google.com &>/dev/null; then
            gum_warn "No internet detected. Opening nmtui..."
            nmtui
            sleep 3
            ping -c1 google.com &>/dev/null || { gum_fail "Still no internet connection"; exit 1; }
        fi

        gum_title "Core Setup"
        until select_username; do :; done
        until select_password; do :; done
        until select_root_password; do :; done
        until select_timezone; do :; done
        until select_language; do :; done
        until select_keyboard; do :; done
        until select_disk; do :; done
        until select_filesystem; do :; done
        until select_bootloader; do :; done

        gum_title "Desktop & Features"
        until select_enable_desktop_environment; do :; done
        until select_enable_desktop_driver; do :; done
        until select_enable_encryption; do :; done
        until select_enable_multilib; do :; done
        until select_enable_aur; do :; done
        until select_package_profile; do :; done

        gum_title "Summary"
        if gum_confirm "Start LnOS installation?"; then
            break
        fi
    done

    local start=$SECONDS
    gum_title "Installing LnOS"

    install_base_system
    configure_system
    install_bootloader
    enable_multilib
    install_desktop_environment
    install_graphics_driver
    install_aur_helper
    install_packages
    copy_lnos_files
    finalize_installation

    local duration=$((SECONDS - start))
    gum_green --bold "Installation completed in $((duration / 60))m $((duration % 60))s"

    if gum_confirm "Reboot into LnOS now?"; then
        umount -R /mnt
        [ "$LNOS_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot
        reboot
    else
        gum_warn "System is ready at /mnt. Reboot manually when ready."
    fi
}

# ==================================================================================================
# ENTRY POINT
# ==================================================================================================

if [ "$1" = "--target=x86_64" ]; then
    main
elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    gum_style --foreground 255 --border double --width 80 --padding "2 4" \
        "LnOS Installer" \
        "Usage: ./LnOS-installer.sh --target=x86_64"
else
    gum_fail "Invalid arguments. Use --target=x86_64"
    exit 1
fi
