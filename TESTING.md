# מדריך בדיקות - ThinkDeploy Proxmox Platform

## סקירה כללית

פרויקט זה כולל מערכת בדיקות מקיפה המשתמשת ב-BATS (Bash Automated Testing System) לבדיקת כל הפונקציות והתצורות.

## התחלה מהירה

### 1. התקנת תלויות

```bash
# התקן את כל התלויות הנדרשות
make install-deps

# או באופן ידני:
# Ubuntu/Debian
sudo apt-get install bats-core jq shellcheck

# macOS
brew install bats-core jq shellcheck
```

### 2. הרצת כל הבדיקות

```bash
# דרך Makefile (מומלץ)
make test

# או ישירות
cd tests
./run_tests.sh all
```

### 3. הרצת קטגוריות ספציפיות

```bash
# בדיקות יחידה
make test-unit

# בדיקות אינטגרציה
make test-integration

# בדיקות Terraform
make test-terraform
```

## מבנה הבדיקות

```
tests/
├── test_helper.bash                    # Helper functions
├── test_validation_functions.bats      # בדיקות פונקציות אימות
├── test_configuration_functions.bats   # בדיקות פונקציות תצורה
├── test_json_parsing.bats              # בדיקות פרסור JSON
├── test_terraform_validation.bats      # בדיקות Terraform
├── test_integration.bats               # בדיקות אינטגרציה
├── fixtures/                           # קבצי בדיקה לדוגמה
└── run_tests.sh                        # Test runner
```

## סוגי הבדיקות

### בדיקות יחידה (Unit Tests)

בודקות פונקציות בודדות:

- **Validation Functions**: `validate_ip()`, `log()`, `error_exit()`, `warning()`
- **Configuration Functions**: כל פונקציות ה-`configure_*()`

**דוגמה:**
```bash
bats tests/test_validation_functions.bats
```

### בדיקות אינטגרציה (Integration Tests)

בודקות את הזרימה המלאה:

- קיום וניתנות הרצה של סקריפטים
- הגדרות שגיאה
- זרימת עבודה מלאה

**דוגמה:**
```bash
bats tests/test_integration.bats
```

### בדיקות Terraform

בודקות תצורות Terraform:

- אימות syntax
- בדיקת טיפוסי משתנים
- בדיקת מודולים

**דוגמה:**
```bash
bats tests/test_terraform_validation.bats
```

## דוגמאות שימוש

### בדיקת פונקציה ספציפית

```bash
# בדיקת אימות IP
bats tests/test_validation_functions.bats -f "validate_ip should accept valid IP addresses"
```

### בדיקה עם פלט מפורט

```bash
# פלט מפורט
bats --verbose tests/*.bats

# הצגת פלט גם בבדיקות שעברו
bats --show-output-of-passing-tests tests/*.bats
```

### בדיקת קובץ ספציפי

```bash
cd tests
./run_tests.sh file test_validation_functions.bats
```

## כתיבת בדיקות חדשות

### תבנית בסיסית

```bash
#!/usr/bin/env bats

load 'test_helper.bash'

setup() {
    test_helper_setup
    # קוד setup נוסף
}

@test "תיאור הבדיקה" {
    # Arrange - הכנה
    local input="קלט לבדיקה"
    
    # Act - ביצוע
    run your_function "$input"
    
    # Assert - אימות
    [ "$status" -eq 0 ]
    [[ "$output" == *"פלט צפוי"* ]]
}
```

### כללי כתיבה

1. **שמות ברורים**: שמות תיאוריים שמסבירים מה נבדק
2. **בידוד**: כל בדיקה עצמאית
3. **Arrange-Act-Assert**: מבנה ברור
4. **Mocking**: שימוש ב-mocks לפונקציות חיצוניות

## CI/CD Integration

### GitHub Actions

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: make install-deps
      - run: make test
```

### GitLab CI

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
# בדוק אם BATS מותקן
command -v bats

# התקן
make install-deps
```

### בדיקות נכשלות

```bash
# הרץ עם פלט מפורט
bats --verbose tests/*.bats

# נקה קבצים זמניים
make clean
make test
```

### בעיות עם mocks

```bash
# בדוק אם mocks נוצרו
ls -la tests/tmp/

# נקה ונסה שוב
make clean && make test
```

## סטטיסטיקות

לאחר הרצת הבדיקות, תוכל לראות:

- מספר הבדיקות שבוצעו
- מספר הבדיקות שעברו
- מספר הבדיקות שנכשלו
- מספר הבדיקות שדולגו

```bash
# הצגת כיסוי בדיקות
make test-coverage
```

## תרומה

כשמוסיפים בדיקות:

1. הוסף בדיקה לקובץ המתאים
2. ודא שהבדיקה עוברת: `make test`
3. ודא linting: `make lint`
4. עדכן תיעוד אם נדרש

## משאבים נוספים

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS Assertions](https://github.com/bats-core/bats-assert)
- [BATS Support](https://github.com/bats-core/bats-support)

---

**סטטוס**: ✅ מערכת בדיקות מלאה ופועלת  
**גרסה**: 1.0.0  
**תאימות**: BATS 1.0+, Bash 4.0+
