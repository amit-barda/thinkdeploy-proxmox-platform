#!/bin/bash

# Test runner script for ThinkDeploy Proxmox Platform tests

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if BATS is installed
check_bats() {
    if ! command -v bats &> /dev/null; then
        print_error "BATS is not installed"
        echo ""
        echo "Install BATS using one of these methods:"
        echo "  Ubuntu/Debian: sudo apt-get install bats"
        echo "  macOS: brew install bats-core"
        echo "  Manual: https://github.com/bats-core/bats-core#installation"
        exit 1
    fi
    
    print_success "BATS is installed ($(bats --version))"
}

# Check if required tools are available
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    if ! command -v bash &> /dev/null; then
        missing_deps+=("bash")
    fi
    
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed (some tests may be skipped)"
    else
        print_success "jq is installed"
    fi
    
    if ! command -v terraform &> /dev/null; then
        print_warning "terraform is not installed (some tests may be skipped)"
    else
        print_success "terraform is installed ($(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo 'unknown'))"
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Run all tests
run_tests() {
    print_info "Running test suite..."
    echo ""
    
    cd "$SCRIPT_DIR"
    
    # Find all test files
    local test_files=($(find . -name "*.bats" -type f | sort))
    
    if [ ${#test_files[@]} -eq 0 ]; then
        print_error "No test files found"
        exit 1
    fi
    
    print_info "Found ${#test_files[@]} test file(s)"
    echo ""
    
    # Run tests with BATS
    if bats "${test_files[@]}"; then
        print_success "All tests passed!"
        return 0
    else
        print_error "Some tests failed"
        return 1
    fi
}

# Run specific test file
run_test_file() {
    local test_file=$1
    
    if [ ! -f "$test_file" ]; then
        print_error "Test file not found: $test_file"
        exit 1
    fi
    
    print_info "Running test file: $test_file"
    bats "$test_file"
}

# Run tests by category
run_category() {
    local category=$1
    local test_files=($(find . -name "test_${category}*.bats" -type f))
    
    if [ ${#test_files[@]} -eq 0 ]; then
        print_error "No test files found for category: $category"
        exit 1
    fi
    
    print_info "Running tests for category: $category"
    bats "${test_files[@]}"
}

# Show test coverage
show_coverage() {
    print_info "Test Coverage Summary"
    echo ""
    echo "Test Files:"
    find . -name "*.bats" -type f | while read -r file; do
        local count=$(grep -c "^@test" "$file" 2>/dev/null || echo "0")
        echo "  - $(basename "$file"): $count tests"
    done
    echo ""
}

# Main function
main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         ThinkDeploy Proxmox Platform - Test Suite         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Parse arguments
    case "${1:-all}" in
        all)
            check_bats
            check_dependencies
            echo ""
            run_tests
            ;;
        file)
            if [ -z "${2:-}" ]; then
                print_error "Please specify a test file"
                exit 1
            fi
            check_bats
            run_test_file "$2"
            ;;
        category)
            if [ -z "${2:-}" ]; then
                print_error "Please specify a category (validation, configuration, json, terraform, integration)"
                exit 1
            fi
            check_bats
            run_category "$2"
            ;;
        coverage)
            show_coverage
            ;;
        *)
            echo "Usage: $0 [all|file <file>|category <category>|coverage]"
            echo ""
            echo "Options:"
            echo "  all              Run all tests (default)"
            echo "  file <file>      Run a specific test file"
            echo "  category <cat>   Run tests for a specific category"
            echo "  coverage         Show test coverage summary"
            exit 1
            ;;
    esac
}

main "$@"
