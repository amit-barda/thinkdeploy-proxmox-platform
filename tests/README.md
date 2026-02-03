# ThinkDeploy Proxmox Platform - Test Suite

מערכת בדיקות מקיפה לפרויקט ThinkDeploy Proxmox Platform.

## מבנה הבדיקות

```
tests/
├── test_helper.bash              # Helper functions for all tests
├── test_validation_functions.bats # Tests for validation functions
├── test_configuration_functions.bats # Tests for configuration functions
├── test_json_parsing.bats        # Tests for JSON parsing logic
├── test_terraform_validation.bats # Tests for Terraform validation
├── test_integration.bats          # Integration tests
├── fixtures/                      # Test fixtures and sample data
│   ├── sample_vm_config.json
│   ├── sample_lxc_config.json
│   └── sample_backup_config.json
├── tmp/                           # Temporary test artifacts (auto-generated)
└── run_tests.sh                   # Test runner script
```

## התקנה

### דרישות מוקדמות

1. **BATS** - Bash Automated Testing System
   ```bash
   # Ubuntu/Debian
   sudo apt-get install bats-core
   
   # macOS
   brew install bats-core
   
   # Manual installation
   git clone https://github.com/bats-core/bats-core.git
   cd bats-core
   ./install.sh /usr/local
   ```

2. **jq** - JSON processor (מומלץ)
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # macOS
   brew install jq
   ```

3. **Terraform** - Infrastructure as Code (לבדיקות Terraform)
   ```bash
   # See install.sh for installation instructions
   ```

### התקנה מהירה

```bash
# Install all dependencies
make install-deps

# Or manually
cd tests
./run_tests.sh all
```

## הרצת הבדיקות

### שימוש ב-Makefile (מומלץ)

```bash
# Run all tests
make test

# Run specific test categories
make test-unit          # Unit tests only
make test-integration   # Integration tests only
make test-terraform    # Terraform validation only

# Show test coverage
make test-coverage

# Lint code
make lint
make lint-fix
```

### שימוש ישיר ב-test runner

```bash
cd tests

# Run all tests
./run_tests.sh all

# Run specific test file
./run_tests.sh file test_validation_functions.bats

# Run tests by category
./run_tests.sh category validation
./run_tests.sh category configuration
./run_tests.sh category json
./run_tests.sh category terraform
./run_tests.sh category integration

# Show coverage
./run_tests.sh coverage
```

### הרצה ישירה עם BATS

```bash
# Run all tests
bats tests/*.bats

# Run specific test file
bats tests/test_validation_functions.bats

# Run with verbose output
bats --verbose tests/*.bats

# Run with tap output
bats --tap tests/*.bats
```

## קטגוריות הבדיקות

### 1. Validation Functions (`test_validation_functions.bats`)
בדיקות לפונקציות אימות:
- `validate_ip()` - אימות כתובות IP
- `log()` - פונקציית לוג
- `error_exit()` - טיפול בשגיאות
- `warning()` - אזהרות

### 2. Configuration Functions (`test_configuration_functions.bats`)
בדיקות לפונקציות תצורה:
- `configure_cluster()` - תצורת קלאסטר
- `configure_compute()` - תצורת VMs ו-LXC
- `configure_networking()` - תצורת רשת
- `configure_storage()` - תצורת אחסון
- `configure_backup()` - תצורת גיבויים
- `configure_security()` - תצורת אבטחה

### 3. JSON Parsing (`test_json_parsing.bats`)
בדיקות לפרסור ואימות JSON:
- אימות JSON תקין
- הפרדה בין VM ו-LXC
- פרסור תצורות קלאסטר
- פרסור תצורות snapshot ו-security

### 4. Terraform Validation (`test_terraform_validation.bats`)
בדיקות לתצורות Terraform:
- אימות syntax
- בדיקת טיפוסי משתנים
- בדיקת קיום מודולים
- בדיקת קבצים נדרשים

### 5. Integration Tests (`test_integration.bats`)
בדיקות אינטגרציה:
- בדיקת קיום וניתנות הרצה של סקריפטים
- בדיקת הגדרות שגיאה
- בדיקת פונקציות נדרשות
- בדיקת זרימת עבודה מלאה

## דוגמאות שימוש

### בדיקת פונקציית אימות IP

```bash
# Run specific test
bats tests/test_validation_functions.bats -f "validate_ip should accept valid IP addresses"
```

### בדיקת תצורת VM

```bash
# Run configuration tests
bats tests/test_configuration_functions.bats -f "configure_compute should output VM configuration"
```

### בדיקת Terraform

```bash
# Run Terraform validation
bats tests/test_terraform_validation.bats
```

## יצירת בדיקות חדשות

### תבנית לבדיקה חדשה

```bash
#!/usr/bin/env bats

load 'test_helper.bash'

setup() {
    test_helper_setup
    # Your setup code here
}

@test "description of what is being tested" {
    # Arrange
    local input="test input"
    
    # Act
    run your_function "$input"
    
    # Assert
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected output"* ]]
}
```

### כללי כתיבת בדיקות

1. **שמות בדיקות ברורים**: השתמש בשמות תיאוריים שמסבירים מה נבדק
2. **Arrange-Act-Assert**: ארגן את הבדיקה בשלושה שלבים
3. **בידוד**: כל בדיקה צריכה להיות עצמאית
4. **Mocking**: השתמש ב-mocks לפונקציות חיצוניות
5. **Cleanup**: נקה קבצים זמניים ב-teardown

## Debugging

### הרצה עם פלט מפורט

```bash
# Verbose output
bats --verbose tests/test_validation_functions.bats

# Show test output even on success
bats --show-output-of-passing-tests tests/*.bats
```

### בדיקת פונקציות בודדות

```bash
# Source the test helper
source tests/test_helper.bash

# Source setup.sh functions
source setup.sh

# Test function directly
validate_ip "192.168.1.1"
echo $?  # Should be 0
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install dependencies
        run: make install-deps
      - name: Run tests
        run: make test
```

### GitLab CI Example

```yaml
test:
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y bats-core jq
  script:
    - make test
```

## Troubleshooting

### BATS לא מותקן
```bash
# Check if BATS is installed
command -v bats

# Install BATS
make install-deps
```

### בדיקות נכשלות
```bash
# Run with verbose output to see details
bats --verbose tests/*.bats

# Check test helper
source tests/test_helper.bash
test_helper_setup
```

### בעיות עם mocks
```bash
# Check if mocks are created
ls -la tests/tmp/

# Clean and retry
make clean
make test
```

## תרומה

כשמוסיפים בדיקות חדשות:

1. הוסף בדיקה לקובץ המתאים או צור קובץ חדש
2. ודא שהבדיקה עוברת: `make test`
3. ודא שהקוד עובר linting: `make lint`
4. עדכן את ה-README אם נדרש

## רישיון

בהתאם לרישיון הפרויקט הראשי.
