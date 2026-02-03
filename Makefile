# Makefile for ThinkDeploy Proxmox Platform

.PHONY: help lint lint-fix validate fmt clean test test-bash test-terraform test-integration

# Default target
help:
	@echo "ThinkDeploy Proxmox Platform - Available Targets"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint             - Run shellcheck and terraform fmt"
	@echo "  make lint-fix         - Auto-fix linting issues"
	@echo ""
	@echo "Terraform:"
	@echo "  make validate        - Validate Terraform configuration"
	@echo "  make fmt             - Format Terraform files"
	@echo ""
	@echo "Testing:"
	@echo "  make test             - Run all tests (bash + terraform)"
	@echo "  make test-bash        - Run bash unit tests only"
	@echo "  make test-terraform   - Run terraform tests only"
	@echo "  make test-integration - Run integration tests (requires PROXMOX_INTEGRATION_TESTS=true)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean           - Clean temporary files"

# Linting
lint:
	@echo "Running linters..."
	@if command -v shellcheck &> /dev/null; then \
		echo "Running shellcheck..."; \
		shellcheck setup.sh install.sh || true; \
	else \
		echo "⚠️  shellcheck not installed (skipping)"; \
	fi
	@if command -v terraform &> /dev/null; then \
		echo "Running terraform fmt -check..."; \
		terraform fmt -check || true; \
	else \
		echo "⚠️  terraform not installed (skipping)"; \
	fi

# Auto-fix linting issues
lint-fix:
	@echo "Fixing linting issues..."
	@if command -v shellcheck &> /dev/null; then \
		echo "Note: shellcheck doesn't auto-fix, please fix manually"; \
	fi
	@if command -v terraform &> /dev/null; then \
		terraform fmt -recursive; \
		echo "✓ Terraform files formatted"; \
	fi

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	@rm -rf .terraform/
	@rm -f *.tfstate *.tfstate.*
	@rm -f .terraform.lock.hcl
	@rm -f /tmp/thinkdeploy-setup-*.log
	@echo "✓ Cleaned temporary files"

# Validate Terraform configuration
validate:
	@echo "Validating Terraform configuration..."
	@if command -v terraform &> /dev/null; then \
		terraform init -backend=false > /dev/null 2>&1 || true; \
		terraform validate || echo "⚠️  Validation failed (may need variables)"; \
	else \
		echo "⚠️  terraform not installed"; \
	fi

# Format Terraform files
fmt:
	@echo "Formatting Terraform files..."
	@if command -v terraform &> /dev/null; then \
		terraform fmt -recursive; \
		echo "✓ Terraform files formatted"; \
	else \
		echo "⚠️  terraform not installed"; \
	fi

# Testing targets
TEST_DIR=tests
BASH_TEST_DIR=$(TEST_DIR)/bash
TERRAFORM_TEST_DIR=$(TEST_DIR)/terraform
MOCKS_DIR=$(TEST_DIR)/mocks

# Run all tests
test: test-bash test-terraform
	@echo ""
	@echo "✓ All tests completed"

# Run bash unit tests
test-bash:
	@echo "Running bash unit tests..."
	@if command -v bats &> /dev/null; then \
		bats $(BASH_TEST_DIR)/*.bats || exit 1; \
	else \
		echo "⚠️  bats not installed. Install: https://github.com/bats-core/bats-core"; \
		echo "   On Ubuntu/Debian: apt-get install bats"; \
		echo "   On macOS: brew install bats-core"; \
		exit 1; \
	fi

# Run terraform tests
test-terraform: test-terraform-static test-terraform-behavior
	@echo ""
	@echo "✓ Terraform tests completed"

# Terraform static tests (fmt, validate, plan)
test-terraform-static:
	@echo "Running Terraform static tests..."
	@bash $(TERRAFORM_TEST_DIR)/static_test.sh

# Terraform behavior tests (null_resource triggers, enabled flag)
test-terraform-behavior:
	@echo "Running Terraform behavior tests..."
	@export PATH="$$(pwd)/$(MOCKS_DIR):$$PATH"; \
	bash $(TERRAFORM_TEST_DIR)/behavior_test.sh

# Integration tests (mocked SSH/pvesh)
test-integration:
	@if [ "$$PROXMOX_INTEGRATION_TESTS" != "true" ]; then \
		echo "⚠️  Integration tests require PROXMOX_INTEGRATION_TESTS=true"; \
		echo "   Set flag to enable real Proxmox tests"; \
		exit 1; \
	fi
	@echo "Running integration tests..."
	@export PATH="$(abspath $(MOCKS_DIR)):$$PATH"; \
	bats $(TEST_DIR)/test_integration.bats || exit 1
