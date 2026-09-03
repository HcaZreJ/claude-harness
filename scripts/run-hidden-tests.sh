#!/bin/bash
#
# run-hidden-tests.sh — Run hidden tests and report ONLY pass/fail counts.
# The implementing agent must NOT see test details, only aggregate results.
#
# Usage:
#   bash ~/.claude/scripts/run-hidden-tests.sh <repo-root> [function-name]
#
# Arguments:
#   repo-root      Path to the repo root (required)
#   function-name  If provided, only run tests matching this name (-k filter)
#
# The script auto-detects the test framework from the repo's config files.
# Supported: pytest (Python), jest/vitest (Node), node --test (Node built-in),
#            go test (Go), cargo test (Rust)
#
# Exit codes:
#   0 = all tests passed
#   1 = some tests failed
#   2 = no hidden tests found or setup error

set -euo pipefail

REPO_ROOT="${1:?Usage: run-hidden-tests.sh <repo-root> [function-name]}"
FUNC_NAME="${2:-}"
HIDDEN_DIR="$REPO_ROOT/tests/hidden"

if [ ! -d "$HIDDEN_DIR" ]; then
    echo "ERROR: No hidden test directory found at $HIDDEN_DIR"
    exit 2
fi

# Count test files
TEST_FILE_COUNT=$(find "$HIDDEN_DIR" -type f \( -name "*.py" -o -name "*.test.*" -o -name "*_test.*" -o -name "*.spec.*" \) | wc -l | tr -d ' ')
if [ "$TEST_FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No test files found in $HIDDEN_DIR"
    exit 2
fi

# --- Detect test framework ---

detect_framework() {
    # Python: pytest
    if [ -f "$REPO_ROOT/pyproject.toml" ] || [ -f "$REPO_ROOT/pytest.ini" ] || [ -f "$REPO_ROOT/setup.cfg" ] || [ -f "$REPO_ROOT/requirements.txt" ]; then
        if find "$HIDDEN_DIR" -name "*.py" -type f | head -1 | grep -q .; then
            echo "pytest"
            return
        fi
    fi
    # Node: jest or vitest
    if [ -f "$REPO_ROOT/package.json" ]; then
        if grep -q '"vitest"' "$REPO_ROOT/package.json" 2>/dev/null; then
            echo "vitest"
            return
        fi
        if grep -q '"jest"' "$REPO_ROOT/package.json" 2>/dev/null; then
            echo "jest"
            return
        fi
    fi
    # Go
    if [ -f "$REPO_ROOT/go.mod" ]; then
        echo "gotest"
        return
    fi
    # Rust
    if [ -f "$REPO_ROOT/Cargo.toml" ]; then
        echo "cargo"
        return
    fi
    # Node built-in test runner: no package.json (or one without jest/vitest),
    # but hidden dir has .mjs / .mts / .test.js files that Node's test runner
    # auto-discovers. This handles zero-dependency ESM repos like this one.
    if find "$HIDDEN_DIR" -type f \( -name "*.test.mjs" -o -name "*.test.mts" -o -name "*.test.js" \) | head -1 | grep -q .; then
        echo "nodetest"
        return
    fi
    # Fallback: try pytest if .py files exist
    if find "$HIDDEN_DIR" -name "*.py" -type f | head -1 | grep -q .; then
        echo "pytest"
        return
    fi
    echo "unknown"
}

FRAMEWORK=$(detect_framework)

# --- Run tests and capture output ---

TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

run_pytest() {
    local k_filter=""
    if [ -n "$FUNC_NAME" ]; then
        k_filter="-k $FUNC_NAME"
    fi
    cd "$REPO_ROOT"
    # --color=no: pytest keeps emitting ANSI codes even when stdout is a file
    # (uv run, FORCE_COLOR, or a repo-level color setting all trigger it), which
    # would leave the summary line starting with an escape sequence instead of a
    # digit and defeat the parser below.
    # Try uv run first, fall back to plain pytest
    if command -v uv &>/dev/null && [ -f "pyproject.toml" ]; then
        uv run pytest "$HIDDEN_DIR" $k_filter --tb=no --no-header --color=no -q 2>&1 > "$TMPFILE" || true
    else
        python -m pytest "$HIDDEN_DIR" $k_filter --tb=no --no-header --color=no -q 2>&1 > "$TMPFILE" || true
    fi
}

run_jest() {
    local filter=""
    if [ -n "$FUNC_NAME" ]; then
        filter="--testNamePattern=$FUNC_NAME"
    fi
    cd "$REPO_ROOT"
    npx jest "$HIDDEN_DIR" $filter --silent --no-verbose 2>&1 > "$TMPFILE" || true
}

run_vitest() {
    local filter=""
    if [ -n "$FUNC_NAME" ]; then
        filter="--testNamePattern=$FUNC_NAME"
    fi
    cd "$REPO_ROOT"
    npx vitest run "$HIDDEN_DIR" $filter --silent > "$TMPFILE" 2>&1 || true
}

run_gotest() {
    local filter=""
    if [ -n "$FUNC_NAME" ]; then
        filter="-run $FUNC_NAME"
    fi
    cd "$REPO_ROOT"
    go test ./tests/hidden/... -count=1 -v $filter 2>&1 > "$TMPFILE" || true
}

run_cargo() {
    cd "$REPO_ROOT"
    cargo test --test hidden 2>&1 > "$TMPFILE" || true
}

run_nodetest() {
    local filter=""
    if [ -n "$FUNC_NAME" ]; then
        filter="--test-name-pattern=$FUNC_NAME"
    fi
    cd "$REPO_ROOT"
    # node --test does not auto-discover directory args; expand test files by glob.
    # Use nullglob to gracefully handle empty match sets.
    shopt -s nullglob 2>/dev/null || true
    local files=(tests/hidden/*.test.mjs tests/hidden/*.test.mts tests/hidden/*.test.js)
    if [ ${#files[@]} -eq 0 ]; then
        echo "ERROR: No node test files matched under tests/hidden/" > "$TMPFILE"
        return
    fi
    node --test $filter "${files[@]}" 2>&1 > "$TMPFILE" || true
}

case "$FRAMEWORK" in
    pytest)   run_pytest ;;
    jest)     run_jest ;;
    vitest)   run_vitest ;;
    gotest)   run_gotest ;;
    cargo)    run_cargo ;;
    nodetest) run_nodetest ;;
    *)
        echo "ERROR: Could not detect test framework for $REPO_ROOT"
        exit 2
        ;;
esac

# --- Parse output and report only counts ---

parse_pytest() {
    # pytest -q output looks like: "3 passed, 2 failed" or "5 passed"
    # Strip any ANSI escape sequences first, so a colourised summary line still
    # anchors correctly against the digit-leading patterns below.
    local summary
    summary=$(sed $'s/\033\\[[0-9;]*m//g' "$TMPFILE" \
        | grep -E "^[0-9]+ passed|^[0-9]+ failed|^FAILED|^==" | tail -1)

    local passed=0
    local failed=0

    if echo "$summary" | grep -qoE "[0-9]+ passed"; then
        passed=$(echo "$summary" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
    fi
    if echo "$summary" | grep -qoE "[0-9]+ failed"; then
        failed=$(echo "$summary" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")
    fi
    if echo "$summary" | grep -qoE "[0-9]+ error"; then
        local errors
        errors=$(echo "$summary" | grep -oE "[0-9]+ error" | grep -oE "[0-9]+")
        failed=$((failed + errors))
    fi

    local total=$((passed + failed))
    if [ "$total" -eq 0 ]; then
        echo "ERROR: Could not parse test results"
        exit 2
    fi

    echo "PASSED: $passed/$total test cases"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

parse_jest_vitest() {
    local passed=0
    local failed=0

    # Strip ANSI color codes; accept both jest ("Tests: ...") and
    # vitest (" Tests  3 failed | 33 passed (36)") summary formats.
    local clean
    clean=$(sed -E $'s/\x1b\\[[0-9;]*m//g' "$TMPFILE" | grep -E "Tests:?[[:space:]]" | tail -1)

    if echo "$clean" | grep -qoE "[0-9]+ passed"; then
        passed=$(echo "$clean" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
    fi
    if echo "$clean" | grep -qoE "[0-9]+ failed"; then
        failed=$(echo "$clean" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")
    fi

    local total=$((passed + failed))
    if [ "$total" -eq 0 ]; then
        echo "ERROR: Could not parse test results"
        exit 2
    fi

    echo "PASSED: $passed/$total test cases"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

parse_gotest() {
    local passed
    local failed
    # grep -c 在计数为 0 时既打印 0 又返回退出码 1，用 || true 吞掉退出码，
    # 保持输出为单行数字；参数展开兜住文件缺失导致的空串。
    passed=$(grep -c "^--- PASS:" "$TMPFILE" 2>/dev/null || true)
    failed=$(grep -c "^--- FAIL:" "$TMPFILE" 2>/dev/null || true)
    passed=${passed:-0}
    failed=${failed:-0}

    local total=$((passed + failed))
    if [ "$total" -eq 0 ]; then
        echo "ERROR: Could not parse test results"
        exit 2
    fi

    echo "PASSED: $passed/$total test cases"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

parse_cargo() {
    # cargo test output: "test result: ok. 5 passed; 0 failed;"
    local summary
    summary=$(grep "^test result:" "$TMPFILE" | tail -1)
    local passed=0
    local failed=0

    if echo "$summary" | grep -qoE "[0-9]+ passed"; then
        passed=$(echo "$summary" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
    fi
    if echo "$summary" | grep -qoE "[0-9]+ failed"; then
        failed=$(echo "$summary" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")
    fi

    local total=$((passed + failed))
    if [ "$total" -eq 0 ]; then
        echo "ERROR: Could not parse test results"
        exit 2
    fi

    echo "PASSED: $passed/$total test cases"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

parse_nodetest() {
    # node --test TAP output ends with:
    #   # tests N
    #   # pass P
    #   # fail F
    local passed=0
    local failed=0

    if grep -qE "^# pass [0-9]+" "$TMPFILE"; then
        passed=$(grep -E "^# pass [0-9]+" "$TMPFILE" | tail -1 | grep -oE "[0-9]+")
    fi
    if grep -qE "^# fail [0-9]+" "$TMPFILE"; then
        failed=$(grep -E "^# fail [0-9]+" "$TMPFILE" | tail -1 | grep -oE "[0-9]+")
    fi

    local total=$((passed + failed))
    if [ "$total" -eq 0 ]; then
        echo "ERROR: Could not parse test results"
        exit 2
    fi

    echo "PASSED: $passed/$total test cases"
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

case "$FRAMEWORK" in
    pytest)       parse_pytest ;;
    jest|vitest)  parse_jest_vitest ;;
    gotest)       parse_gotest ;;
    cargo)        parse_cargo ;;
    nodetest)     parse_nodetest ;;
esac
