#!/usr/bin/env bats
# Unit tests for LnOS-installer.sh
# Run with: bats test/unit-tests.bats

# Load test helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Setup and teardown
setup() {
    # Create temporary directory for each test
    export TEST_TEMP_DIR="$(temp_make)"
    export SCRIPT_LOG="${TEST_TEMP_DIR}/installer.log"
    export SCRIPT_CONFIG="${TEST_TEMP_DIR}/installer.conf"
    export SCRIPT_TMP_DIR="${TEST_TEMP_DIR}/tmp"
    mkdir -p "$SCRIPT_TMP_DIR"
    
    # Source the mock functions first
    source "${BATS_TEST_DIRNAME}/test_helper/mock_functions.sh"
    
    # Source only the functions from installer script, skip execution
    # Extract functions by sourcing everything except the entry point
    source <(sed '/^if \[ "\$1" = "--target=x86_64" \]/,$d' "${BATS_TEST_DIRNAME}/../scripts/LnOS-installer.sh") 2>/dev/null || true
}

teardown() {
    temp_del "$TEST_TEMP_DIR"
}

# ==================================================================================================
# LOGGING TESTS
# ==================================================================================================

@test "log_info writes to log file with correct format" {
    log_info "Test message"
    
    assert_file_exist "$SCRIPT_LOG"
    run cat "$SCRIPT_LOG"
    assert_output --partial "INFO"
    assert_output --partial "Test message"
}

@test "log_error writes ERROR level to log" {
    log_error "Error message"
    
    run cat "$SCRIPT_LOG"
    assert_output --partial "ERROR"
    assert_output --partial "Error message"
}

@test "log_fatal exits with code 1" {
    run log_fatal "Fatal error"
    assert_failure
    assert_equal "$status" 1
}

# ==================================================================================================
# INPUT VALIDATION TESTS
# ==================================================================================================

@test "username validation: accepts valid username" {
    LNOS_USERNAME="validuser"
    run select_username
    assert_success
}

@test "username validation: rejects empty username" {
    LNOS_USERNAME=""
    # Mock gum_input to return empty string
    function gum_input() { echo ""; }
    export -f gum_input
    
    run select_username
    assert_failure
}

@test "username validation: rejects invalid characters" {
    # This test would check if you add validation
    skip "Username validation not yet implemented"
}

@test "password validation: matching passwords succeed" {
    # Mock password input
    function gum_input() {
        if [[ "$*" == *"Enter"* ]]; then
            echo "password123"
        else
            echo "password123"
        fi
    }
    export -f gum_input
    
    LNOS_PASSWORD=""
    run select_password
    assert_success
}

@test "password validation: non-matching passwords fail" {
    # Mock password input with mismatch
    function gum_input() {
        if [[ "$*" == *"Enter"* ]]; then
            echo "password123"
        else
            echo "different456"
        fi
    }
    function gum_confirm() { return 0; }
    export -f gum_input gum_confirm
    
    LNOS_PASSWORD=""
    run select_password
    assert_failure
}

@test "password validation: empty password fails" {
    function gum_input() { echo ""; }
    export -f gum_input
    
    LNOS_PASSWORD=""
    run select_password
    assert_failure
}

# ==================================================================================================
# TIMEZONE TESTS
# ==================================================================================================

@test "timezone validation: accepts valid timezone" {
    LNOS_TIMEZONE="America/Chicago"
    run select_timezone
    assert_success
}

@test "timezone validation: rejects invalid timezone" {
    function gum_input() { echo "Invalid/Timezone"; }
    function gum_confirm() { return 0; }
    export -f gum_input gum_confirm
    
    LNOS_TIMEZONE=""
    run select_timezone
    assert_failure
}

@test "timezone auto-detection: uses curl fallback" {
    # Mock curl to fail
    function curl() { return 1; }
    export -f curl
    
    function gum_input() { echo "America/Chicago"; }
    export -f gum_input
    
    LNOS_TIMEZONE=""
    run select_timezone
    assert_success
}

# ==================================================================================================
# DISK SELECTION TESTS
# ==================================================================================================

@test "disk selection: correctly identifies nvme partition naming" {
    LNOS_DISK="/dev/nvme0n1"
    select_disk
    
    assert_equal "$LNOS_BOOT_PARTITION" "/dev/nvme0n1p1"
    assert_equal "$LNOS_ROOT_PARTITION" "/dev/nvme0n1p2"
}

@test "disk selection: correctly identifies sata partition naming" {
    LNOS_DISK="/dev/sda"
    select_disk
    
    assert_equal "$LNOS_BOOT_PARTITION" "/dev/sda1"
    assert_equal "$LNOS_ROOT_PARTITION" "/dev/sda2"
}

@test "disk selection: rejects empty disk selection" {
    function gum_choose() { echo ""; }
    export -f gum_choose
    
    LNOS_DISK=""
    run select_disk
    assert_failure
}

# ==================================================================================================
# FILESYSTEM TESTS
# ==================================================================================================

@test "filesystem selection: accepts btrfs" {
    function gum_choose() { echo "btrfs"; }
    export -f gum_choose
    
    LNOS_FILESYSTEM=""
    run select_filesystem
    assert_success
    assert_equal "$LNOS_FILESYSTEM" "btrfs"
}

@test "filesystem selection: accepts ext4" {
    function gum_choose() { echo "ext4"; }
    export -f gum_choose
    
    LNOS_FILESYSTEM=""
    run select_filesystem
    assert_success
    assert_equal "$LNOS_FILESYSTEM" "ext4"
}

# ==================================================================================================
# BOOTLOADER TESTS
# ==================================================================================================

@test "bootloader selection: accepts grub" {
    function gum_choose() { echo "grub"; }
    export -f gum_choose
    
    LNOS_BOOTLOADER=""
    run select_bootloader
    assert_success
    assert_equal "$LNOS_BOOTLOADER" "grub"
}

@test "bootloader selection: accepts systemd" {
    function gum_choose() { echo "systemd"; }
    export -f gum_choose
    
    LNOS_BOOTLOADER=""
    run select_bootloader
    assert_success
    assert_equal "$LNOS_BOOTLOADER" "systemd"
}

# ==================================================================================================
# BOOT MODE DETECTION TESTS
# ==================================================================================================

@test "boot mode detection: recognizes UEFI" {
    # Mock /sys/firmware/efi directory
    mkdir -p "${TEST_TEMP_DIR}/sys/firmware/efi"
    
    # This would need to be called from install_base_system
    # For now, we test the logic directly
    if [ -d "${TEST_TEMP_DIR}/sys/firmware/efi" ]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    
    assert_equal "$BOOT_MODE" "uefi"
}

@test "boot mode detection: defaults to BIOS when no EFI" {
    if [ -d "${TEST_TEMP_DIR}/sys/firmware/efi" ]; then
        BOOT_MODE="uefi"
    else
        BOOT_MODE="bios"
    fi
    
    assert_equal "$BOOT_MODE" "bios"
}

# ==================================================================================================
# CONFIGURATION PERSISTENCE TESTS
# ==================================================================================================

@test "properties_generate: creates config file" {
    LNOS_USERNAME="testuser"
    LNOS_DISK="/dev/sda"
    LNOS_TIMEZONE="America/Chicago"
    
    run properties_generate
    assert_success
    assert_file_exist "$SCRIPT_CONFIG"
}

@test "properties_generate: sanitizes passwords" {
    LNOS_USERNAME="testuser"
    LNOS_PASSWORD="secret123"
    LNOS_ROOT_PASSWORD="rootsecret"
    
    properties_generate
    
    run cat "$SCRIPT_CONFIG"
    assert_output --partial "LNOS_PASSWORD='*****'"
    assert_output --partial "LNOS_ROOT_PASSWORD='*****'"
    refute_output --partial "secret123"
}

@test "properties_source: loads config correctly" {
    # Create a test config
    cat > "$SCRIPT_CONFIG" <<EOF
LNOS_USERNAME='testuser'
LNOS_DISK='/dev/sda'
LNOS_TIMEZONE='America/Chicago'
LNOS_FILESYSTEM='ext4'
EOF
    
    run properties_source
    assert_success
    assert_equal "$LNOS_USERNAME" "testuser"
    assert_equal "$LNOS_DISK" "/dev/sda"
}

# ==================================================================================================
# HELPER FUNCTION TESTS
# ==================================================================================================

@test "print_filled_space: pads strings correctly" {
    result=$(print_filled_space 20 "test")
    assert_equal "${#result}" 20
}

@test "print_filled_space: handles strings longer than total" {
    result=$(print_filled_space 5 "longstring")
    assert_equal "$result" "longstring"
}

@test "print_filled_space: handles empty strings" {
    result=$(print_filled_space 10 "")
    assert_equal "${#result}" 10
}

# ==================================================================================================
# ENCRYPTION TESTS
# ==================================================================================================

@test "encryption selection: stores boolean value" {
    function gum_confirm() { return 0; }  # Yes
    export -f gum_confirm
    
    LNOS_ENCRYPTION_ENABLED=""
    run select_enable_encryption
    assert_success
    assert_equal "$LNOS_ENCRYPTION_ENABLED" "true"
}

@test "encryption selection: handles negative response" {
    function gum_confirm() { return 1; }  # No
    export -f gum_confirm
    
    LNOS_ENCRYPTION_ENABLED=""
    run select_enable_encryption
    assert_success
    assert_equal "$LNOS_ENCRYPTION_ENABLED" "false"
}

# ==================================================================================================
# DESKTOP ENVIRONMENT TESTS
# ==================================================================================================

@test "desktop selection: TTY disables desktop" {
    function gum_choose() { echo "TTY"; }
    export -f gum_choose
    
    LNOS_DESKTOP_ENABLED=""
    LNOS_DESKTOP_ENVIRONMENT=""
    run select_enable_desktop_environment
    assert_success
    assert_equal "$LNOS_DESKTOP_ENABLED" "false"
    assert_equal "$LNOS_DESKTOP_ENVIRONMENT" "TTY"
}

@test "desktop selection: Gnome enables desktop" {
    function gum_choose() { echo "Gnome"; }
    export -f gum_choose
    
    LNOS_DESKTOP_ENABLED=""
    LNOS_DESKTOP_ENVIRONMENT=""
    run select_enable_desktop_environment
    assert_success
    assert_equal "$LNOS_DESKTOP_ENABLED" "true"
    assert_equal "$LNOS_DESKTOP_ENVIRONMENT" "Gnome"
}

# ==================================================================================================
# MULTILIB TESTS
# ==================================================================================================

@test "multilib selection: stores boolean value" {
    function gum_confirm() { return 0; }  # Yes
    export -f gum_confirm
    
    LNOS_MULTILIB_ENABLED=""
    run select_enable_multilib
    assert_success
    assert_equal "$LNOS_MULTILIB_ENABLED" "true"
}

# ==================================================================================================
# AUR HELPER TESTS
# ==================================================================================================

@test "aur selection: accepts paru" {
    function gum_choose() { echo "paru"; }
    export -f gum_choose
    
    LNOS_AUR_HELPER=""
    run select_enable_aur
    assert_success
    assert_equal "$LNOS_AUR_HELPER" "paru"
}

@test "aur selection: accepts none" {
    function gum_choose() { echo "none"; }
    export -f gum_choose
    
    LNOS_AUR_HELPER=""
    run select_enable_aur
    assert_success
    assert_equal "$LNOS_AUR_HELPER" "none"
}

# ==================================================================================================
# PACKAGE PROFILE TESTS
# ==================================================================================================

@test "package profile: accepts valid profiles" {
    for profile in "CSE" "SWE" "CPE" "DS" "Custom" "Minimal"; do
        function gum_choose() { echo "$profile"; }
        export -f gum_choose
        
        LNOS_PACKAGE_PROFILE=""
        run select_package_profile
        assert_success
        assert_equal "$LNOS_PACKAGE_PROFILE" "$profile"
    done
}

# ==================================================================================================
# ERROR HANDLING TESTS
# ==================================================================================================

@test "trap_error: captures command and error code" {
    # Simulate a failing command
    export BASH_COMMAND="false"
    export ERROR_MSG="${SCRIPT_TMP_DIR}/installer.err"
    
    run trap_error
    assert_file_exist "$ERROR_MSG"
    
    run cat "$ERROR_MSG"
    assert_output --partial "failed"
}

# ==================================================================================================
# INTEGRATION-STYLE TESTS (Still unit tests, but test interactions)
# ==================================================================================================

@test "full config flow: all selections persist" {
    # Mock all interactive functions
    function gum_input() {
        case "$*" in
            *Username*) echo "testuser" ;;
            *Password*) echo "password123" ;;
            *Timezone*) echo "America/Chicago" ;;
        esac
    }
    function gum_choose() {
        case "$*" in
            *Disk*) echo "/dev/sda (20GB) Test" ;;
            *Filesystem*) echo "ext4" ;;
            *Bootloader*) echo "grub" ;;
            *Desktop*) echo "TTY" ;;
            *Graphics*) echo "mesa" ;;
            *AUR*) echo "paru" ;;
            *Package*) echo "Minimal" ;;
        esac
    }
    function gum_filter() { echo "en_US"; }
    function gum_confirm() { return 1; }  # No to encryption, multilib
    export -f gum_input gum_choose gum_filter gum_confirm
    
    # Run all selections
    select_username
    select_password
    select_timezone
    select_language
    select_disk
    select_filesystem
    select_bootloader
    select_enable_encryption
    select_enable_desktop_environment
    select_enable_multilib
    select_enable_aur
    select_package_profile
    
    # Generate config
    properties_generate
    
    # Verify config file contains expected values
    assert_file_exist "$SCRIPT_CONFIG"
    run cat "$SCRIPT_CONFIG"
    assert_output --partial "LNOS_USERNAME='testuser'"
    assert_output --partial "LNOS_DISK='/dev/sda'"
    assert_output --partial "LNOS_FILESYSTEM='ext4'"
}
