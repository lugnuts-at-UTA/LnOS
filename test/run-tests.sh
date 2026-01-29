#!/bin/bash
# Master test runner for LnOS installer
# Runs all test suites in appropriate order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_section() { echo -e "${BLUE}[====]${NC} $*"; }

# Test results tracking
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

record_result() {
    local test_name="$1"
    local result="$2"  # pass, fail, skip
    
    TEST_RESULTS["$test_name"]="$result"
    ((TOTAL_TESTS++))
    
    case "$result" in
        pass) ((PASSED_TESTS++)) ;;
        fail) ((FAILED_TESTS++)) ;;
        skip) ((SKIPPED_TESTS++)) ;;
    esac
}

# ==================================================================================================
# TEST SUITE RUNNERS
# ==================================================================================================

run_static_analysis() {
    log_section "Running Static Analysis"
    
    # Shellcheck
    log_info "Running shellcheck..."
    if shellcheck "$PROJECT_ROOT/scripts/LnOS-installer.sh" 2>&1 | tee /tmp/shellcheck.log; then
        log_info "✓ Shellcheck passed"
        record_result "shellcheck" "pass"
    else
        log_error "✗ Shellcheck failed"
        record_result "shellcheck" "fail"
    fi
    
    # Syntax check
    log_info "Running bash syntax check..."
    if bash -n "$PROJECT_ROOT/scripts/LnOS-installer.sh"; then
        log_info "✓ Syntax check passed"
        record_result "syntax_check" "pass"
    else
        log_error "✗ Syntax check failed"
        record_result "syntax_check" "fail"
    fi
    
		# psshh i dont care about line length
}

run_unit_tests() {
    log_section "Running Unit Tests"
    
    if ! command -v bats &>/dev/null; then
        log_warn "bats not installed, skipping unit tests"
        log_info "Install with: git clone https://github.com/bats-core/bats-core && cd bats-core && sudo ./install.sh /usr/local"
        record_result "unit_tests" "skip"
        return 0
    fi
    
    # Install test helpers if not present
    if [ ! -d "$PROJECT_ROOT/test/test_helper/bats-support" ]; then
        log_info "Installing bats test helpers..."
        mkdir -p "$PROJECT_ROOT/test/test_helper"
        git clone --depth 1 https://github.com/bats-core/bats-support.git "$PROJECT_ROOT/test/test_helper/bats-support"
        git clone --depth 1 https://github.com/bats-core/bats-assert.git "$PROJECT_ROOT/test/test_helper/bats-assert"
        git clone --depth 1 https://github.com/bats-core/bats-file.git "$PROJECT_ROOT/test/test_helper/bats-file"
    fi
    
    if bats "$PROJECT_ROOT/test/unit-tests.bats"; then
        log_info "✓ Unit tests passed"
        record_result "unit_tests" "pass"
    else
        log_error "✗ Unit tests failed"
        record_result "unit_tests" "fail"
    fi
}

run_integration_tests() {
    log_section "Running Integration Tests"
    
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not installed, skipping integration tests"
        record_result "integration_tests" "skip"
        return 0
    fi
    
    if bash "$PROJECT_ROOT/test/integration-tests.sh"; then
        log_info "✓ Integration tests passed"
        record_result "integration_tests" "pass"
    else
        log_error "✗ Integration tests failed"
        record_result "integration_tests" "fail"
    fi
}

run_e2e_tests() {
    log_section "Running End-to-End Tests"
    
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        log_warn "QEMU not installed, skipping E2E tests"
        record_result "e2e_tests" "skip"
        return 0
    fi
    
    log_warn "E2E tests take 30+ minutes. Run manually with: ./test/e2e-tests.sh"
    record_result "e2e_tests" "skip"
}

# ==================================================================================================
# COVERAGE REPORTING
# ==================================================================================================

generate_coverage_report() {
    log_section "Generating Coverage Report"
    
    # Count functions in installer
    local total_functions=$(grep -c "^[a-z_]*() {" "$PROJECT_ROOT/scripts/LnOS-installer.sh" || echo 0)
    
    # Count tested functions (rough estimate from test file)
    local tested_functions=$(grep -c "@test" "$PROJECT_ROOT/test/unit-tests.bats" || echo 0)
    
    local coverage=0
    if [ "$total_functions" -gt 0 ]; then
        coverage=$((tested_functions * 100 / total_functions))
    fi
    
    cat > "$PROJECT_ROOT/test/coverage-report.txt" <<EOF
LnOS Installer Test Coverage Report
Generated: $(date)

Code Coverage:
--------------
Total Functions: $total_functions
Tested Functions: ~$tested_functions
Estimated Coverage: ~${coverage}%

Test Results:
-------------
Total Tests: $TOTAL_TESTS
Passed: $PASSED_TESTS
Failed: $FAILED_TESTS
Skipped: $SKIPPED_TESTS

Detailed Results:
-----------------
EOF
    
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local symbol="?"
        case "$result" in
            pass) symbol="✓" ;;
            fail) symbol="✗" ;;
            skip) symbol="⊝" ;;
        esac
        echo "$symbol $test_name: $result" >> "$PROJECT_ROOT/test/coverage-report.txt"
    done
    
    log_info "Coverage report saved to: test/coverage-report.txt"
}

# ==================================================================================================
# REPORT GENERATION
# ==================================================================================================

print_summary() {
    echo ""
    log_section "Test Summary"
    echo ""
    
    echo "┌────────────────────────────────────┐"
    echo "│       Test Results Summary         │"
    echo "├────────────────────────────────────┤"
    printf "│ Total Tests:  %-20s │\n" "$TOTAL_TESTS"
    printf "│ ${GREEN}Passed:${NC}       %-20s │\n" "$PASSED_TESTS"
    printf "│ ${RED}Failed:${NC}       %-20s │\n" "$FAILED_TESTS"
    printf "│ ${YELLOW}Skipped:${NC}      %-20s │\n" "$SKIPPED_TESTS"
    echo "└────────────────────────────────────┘"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
        log_info "${GREEN}All tests passed! ✓${NC}"
        return 0
    elif [ $FAILED_TESTS -gt 0 ]; then
        log_error "${RED}Some tests failed ✗${NC}"
        return 1
    else
        log_warn "${YELLOW}No tests were run${NC}"
        return 1
    fi
}

# ==================================================================================================
# CI/CD HELPERS
# ==================================================================================================

# i dont trust ci/cd yet
#generate_ci_config() {
#    log_section "Generating CI/CD Configurations"
#    
#    # GitHub Actions
#    mkdir -p "$PROJECT_ROOT/.github/workflows"
#    cat > "$PROJECT_ROOT/.github/workflows/test.yml" <<'EOF'
#name: LnOS Installer Tests
#
#on:
#  push:
#    branches: [ main, develop ]
#  pull_request:
#    branches: [ main ]
#
#jobs:
#  static-analysis:
#    runs-on: ubuntu-latest
#    steps:
#      - uses: actions/checkout@v3
#      - name: Install shellcheck
#        run: sudo apt-get install -y shellcheck
#      - name: Run shellcheck
#        run: shellcheck LnOS-installer.sh
#
#  unit-tests:
#    runs-on: ubuntu-latest
#    steps:
#      - uses: actions/checkout@v3
#      - name: Install bats
#        run: |
#          git clone https://github.com/bats-core/bats-core.git
#          cd bats-core
#          sudo ./install.sh /usr/local
#      - name: Install test helpers
#        run: |
#          mkdir -p test/test_helper
#          git clone https://github.com/bats-core/bats-support.git test/test_helper/bats-support
#          git clone https://github.com/bats-core/bats-assert.git test/test_helper/bats-assert
#          git clone https://github.com/bats-core/bats-file.git test/test_helper/bats-file
#      - name: Run unit tests
#        run: bats test/unit-tests.bats
#
#  integration-tests:
#    runs-on: ubuntu-latest
#    steps:
#      - uses: actions/checkout@v3
#      - name: Run integration tests
#        run: |
#          chmod +x test/integration-tests.sh
#          ./test/integration-tests.sh
#EOF
#    
#    log_info "GitHub Actions config created: .github/workflows/test.yml"
#    
#    # GitLab CI
#    cat > "$PROJECT_ROOT/.gitlab-ci.yml" <<'EOF'
#stages:
#  - test
#
#static-analysis:
#  stage: test
#  image: koalaman/shellcheck-alpine:latest
#  script:
#    - shellcheck LnOS-installer.sh
#
#unit-tests:
#  stage: test
#  image: archlinux:latest
#  script:
#    - pacman -Sy --noconfirm git
#    - git clone https://github.com/bats-core/bats-core.git
#    - cd bats-core && ./install.sh /usr/local && cd ..
#    - bats test/unit-tests.bats
#
#integration-tests:
#  stage: test
#  image: docker:latest
#  services:
#    - docker:dind
#  script:
#    - chmod +x test/integration-tests.sh
#    - ./test/integration-tests.sh
#EOF
#    
#    log_info "GitLab CI config created: .gitlab-ci.yml"
#}

# ==================================================================================================
# PRE-COMMIT HOOKS
# ==================================================================================================

# not sure about git hooks yet either
#setup_git_hooks() {
#    log_section "Setting up Git Hooks"
#    
#    cat > "$PROJECT_ROOT/.git/hooks/pre-commit" <<'EOF'
##!/bin/bash
## Pre-commit hook for LnOS installer
#
#echo "Running pre-commit checks..."
#
## Run shellcheck
#if ! shellcheck LnOS-installer.sh; then
#    echo "❌ Shellcheck failed. Commit aborted."
#    exit 1
#fi
#
## Run syntax check
#if ! bash -n LnOS-installer.sh; then
#    echo "❌ Syntax check failed. Commit aborted."
#    exit 1
#fi
#
## Run quick unit tests if bats is available
#if command -v bats &>/dev/null; then
#    if ! bats test/unit-tests.bats; then
#        echo "❌ Unit tests failed. Commit aborted."
#        exit 1
#    fi
#fi
#
#echo "✅ All pre-commit checks passed!"
#exit 0
#EOF
#    
#    chmod +x "$PROJECT_ROOT/.git/hooks/pre-commit"
#    log_info "Pre-commit hook installed"
#}

# ==================================================================================================
# MAIN
# ==================================================================================================

main() {
    cd "$PROJECT_ROOT"
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   LnOS Installer Test Suite v0.0.1     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # Parse arguments
    local run_static=true
    local run_unit=true
    local run_integration=true
    local run_e2e=false
    local setup_ci=false
    local setup_hooks=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                run_integration=false
                run_e2e=false
                ;;
            --full)
                run_e2e=true
                ;;
            --ci)
                setup_ci=true
                run_static=false
                run_unit=false
                run_integration=false
                ;;
            --hooks)
                setup_hooks=true
                run_static=false
                run_unit=false
                run_integration=false
                ;;
            --static-only)
                run_unit=false
                run_integration=false
                ;;
            --unit-only)
                run_static=false
                run_integration=false
                ;;
            --integration-only)
                run_static=false
                run_unit=false
                ;;
            *)
                echo "Usage: $0 [--quick|--full|--ci|--hooks|--static-only|--unit-only|--integration-only]"
                echo ""
                echo "Options:"
                echo "  --quick            Run only static analysis and unit tests"
                echo "  --full             Run all tests including E2E"
                echo "  --ci               Generate CI/CD configurations"
                echo "  --hooks            Setup git hooks"
                echo "  --static-only      Run only static analysis"
                echo "  --unit-only        Run only unit tests"
                echo "  --integration-only Run only integration tests"
                exit 1
                ;;
        esac
        shift
    done
    
    # Run selected test suites
    #[ "$setup_ci" = true ] && generate_ci_config
    [ "$setup_hooks" = true ] && setup_git_hooks
    [ "$run_static" = true ] && run_static_analysis
    [ "$run_unit" = true ] && run_unit_tests
    [ "$run_integration" = true ] && run_integration_tests
    [ "$run_e2e" = true ] && run_e2e_tests
    
    # Generate reports
    if [ "$setup_ci" = false ] && [ "$setup_hooks" = false ]; then
        generate_coverage_report
        print_summary
    fi
}

main "$@"
