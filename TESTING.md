# Testing Guide for LnOS Installer

## Overview
The LnOS installer includes a comprehensive test suite to ensure reliability and compatibility across different configurations. The testing framework uses multiple approaches to validate the installer functionality, from unit tests to full end-to-end system testing.

## Test Structure

The testing suite consists of four main components:

### 🔧 Static Analysis Tests
- **Shellcheck**: Validates shell script syntax and best practices
- **Syntax Check**: Ensures bash script parsing works correctly
- **Location**: `scripts/run-tests.sh`

### 🧪 Unit Tests  
- **Framework**: BATS (Bash Automated Testing System)
- **File**: `test/unit-tests.bats` is run from `scripts/run-test.sh --unit-only` 
- **Coverage**: Tests individual functions in isolation
- **Test Helpers**: Uses bats-support, bats-assert, and bats-file for enhanced testing capabilities

There are other testing tools but they're in development, current the two above are the recommended workflow so that we don't need to check w/ a vm all the time to make sure the script will install.

## Prerequisites

### Required Tools
```bash
# Static analysis
sudo pacman -S shellcheck

# Unit testing
git clone https://github.com/bats-core/bats-core && cd bats-core && sudo ./install.sh /usr/local

# Integration testing  
sudo pacman -S docker

# E2E testing
sudo pacman -S qemu-desktop expect
```

### Test Dependencies
The unit tests automatically install these helpers if not present:
- [bats-support](https://github.com/bats-core/bats-support) - Enhanced test assertions
- [bats-assert](https://github.com/bats-core/bats-assert) - Assertion helpers  
- [bats-file](https://github.com/bats-core/bats-file) - File system test utilities

## Running Tests

### Quick Test Suite
```bash
# Run only static analysis
./scripts/run-tests.sh 
```

### Individual Test Types
```bash
# Static analysis only
./scripts/run-tests.sh --static-only
```
# Unit tests only  
```bash
./scripts/run-tests.sh --unit-only
```
### Manual Test Execution
# Run unit tests directly
```bash 
bats test/unit-tests.bats
```

## Test Coverage

### Shellcheck
Shell linter, prevents common syntax errors

### Unit Test Coverage
The unit tests cover these installer components:

**🔍 Input Validation**
- Username validation (format and constraints)
- Password validation (matching, strength)
- Timezone validation (valid timezone detection)
- Disk selection validation

**📁 Configuration Management**
- Configuration file generation
- Password sanitization in logs
- Configuration persistence and loading

**💾 System Detection**  
- Boot mode detection (UEFI vs BIOS)
- Disk partition naming (NVMe vs SATA)
- Filesystem type validation

**🛠️ Component Selection**
- Desktop environment selection
- Bootloader selection (GRUB vs systemd-boot)
- Package profile selection
- AUR helper configuration

### Integration Test Coverage (Future planning not done yet)
Docker-based tests validate:

**💽 Disk Operations**
- Partition table creation
- Loop device handling  
- Filesystem formatting (ext4, btrfs)

**🔐 Encryption Setup**
- LUKS2 encryption container creation
- Encrypted device mapping
- Password-based unlocking

**🌐 Network Detection**
- Internet connectivity validation
- Package mirror accessibility

**📊 Configuration Persistence**
- Config file creation and validation
- Sensitive data sanitization

### E2E Test Coverage (Future planning not done yet)
Virtual machine testing includes:

**🖥️ Full Installation Flow**
- Automated installer execution
- Interactive prompt handling
- Complete system installation

**🔄 Boot Testing**  
- Post-installation boot verification
- System startup validation
- Installed system accessibility

### Test Result Symbols
- ✓ **Passed**: Test completed successfully
- ✗ **Failed**: Test encountered an error
- ⊝ **Skipped**: Test was skipped (missing dependencies)

## Development Testing

### Adding New Tests
When adding new installer functionality:

1. **Add unit tests** in `test/unit-tests.bats`
2. **Mock external dependencies** in `test/test_helper/mock_functions.sh`
3. **Add integration tests** if testing system operations
4. **Update this documentation** for new test categories

### Test Structure Guidelines
```bash
@test "component: specific behavior description" {
    # Setup test environment
    setup_test_vars
    
    # Execute function under test
    run function_name
    
    # Assert expected results
    assert_success
    assert_equal "$variable" "expected_value"
}
```

### Mock Functions
For unit testing, external commands are mocked:
```bash
# Mock interactive input
function gum_input() { echo "mocked_response"; }
export -f gum_input

# Mock system commands  
function curl() { return 0; }
export -f curl
```

## Continuous Integration (planned)

### Test Automation
The test suite is designed for automated execution in CI/CD environments:

**GitHub Actions Ready** - Configurations available for:
- Static analysis pipeline
- Unit test execution  
- Integration test validation

**Development Tools**
- **Packer** templates for automated VM testing
- **Vagrant** setup for development testing
- **Docker** containers for isolated testing

## Troubleshooting Tests

### Common Issues

**BATS Not Found**
```bash
# Install BATS testing framework
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local
```

**Docker Permission Denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

**QEMU Not Available**
```bash
# Install QEMU for E2E testing
sudo pacman -S qemu-desktop
```

**Slow E2E Tests**
- E2E tests require 30+ minutes for full completion
- Use `--quick` flag for faster development testing
- Run E2E tests only before releases

### Test Environment Cleanup
```bash
# Clean up test containers
docker system prune -f

# Remove test virtual machines
rm -f lnos-test-vm.qcow2

# Clean test temporary files
rm -rf /tmp/lnos-test-*
```

## Testing Best Practices

### Before Submitting Changes
1. Run quick test suite: `./scripts/run-tests.sh --quick`
2. Verify new functionality has corresponding tests
3. Check test coverage report for gaps
4. Run full test suite for major changes

### Test-Driven Development
1. Write failing tests first
2. Implement minimum code to pass tests  
3. Refactor while maintaining test coverage
4. Update documentation for new features

---

For more information about contributing to LnOS development, see our [Development Guide](https://github.com/lugnuts-at-uta/LnOS/wiki/testing).
