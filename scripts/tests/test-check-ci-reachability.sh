#!/bin/bash
#
# Tests for check-ci-reachability.sh.
#
# Each test builds a throwaway fake-repo under a fresh mktemp -d, runs the
# script against it, and asserts on its stdout and exit code. Every test
# gets its own temp directory (created and destroyed inside the test
# function) so no test can leak state into another.
#
# Usage: bash test-check-ci-reachability.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/../check-ci-reachability.sh"

FAILURES=0
TESTS_RUN=0

pass() {
    echo "  [PASS] $1"
}

fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

# assert_contains <haystack> <needle> <description>
assert_contains() {
    local haystack="$1" needle="$2" description="$3"
    if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
        pass "$description"
    else
        fail "$description (expected output to contain: $needle)"
        echo "    --- actual output ---"
        printf '%s\n' "$haystack" | sed 's/^/    /'
    fi
}

# assert_not_contains <haystack> <needle> <description>
assert_not_contains() {
    local haystack="$1" needle="$2" description="$3"
    if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
        fail "$description (did not expect output to contain: $needle)"
        echo "    --- actual output ---"
        printf '%s\n' "$haystack" | sed 's/^/    /'
    else
        pass "$description"
    fi
}

# assert_eq <actual> <expected> <description>
assert_eq() {
    local actual="$1" expected="$2" description="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$description"
    else
        fail "$description (expected: $expected, got: $actual)"
    fi
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "=== $test_name ==="
    "$test_name"
    echo
}

mkworkflow() {
    # mkworkflow <repo> <filename> <<< 'yaml content'
    local repo="$1" name="$2"
    mkdir -p "$repo/.github/workflows"
    cat > "$repo/.github/workflows/$name"
}

init_fixture_repo() {
    # init_fixture_repo <repo>
    #
    # Turns a plain fixture directory into a real git repo so that
    # check-ci-reachability.sh's `git -C "$REPO" ls-files` call actually
    # sees the fixture's files. Uses a repo-local git identity (never the
    # user's global config) and silences all git output so it does not
    # pollute the test report.
    local repo="$1"
    git -C "$repo" init -q >/dev/null 2>&1
    git -C "$repo" config user.email "fixture@example.com" >/dev/null 2>&1
    git -C "$repo" config user.name "Fixture" >/dev/null 2>&1
    git -C "$repo" add -A >/dev/null 2>&1
    git -C "$repo" commit -q -m "fixture" --allow-empty >/dev/null 2>&1
}

# ---------------------------------------------------------------------------

test_check_ci_reachability_pytest_workflow_is_reachable() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"

    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: pytest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 when pytest runs in CI"
    assert_contains "$output" "[REACHABLE]" "reports tests dir as REACHABLE"
    assert_contains "$output" "tests" "mentions the tests directory"
    assert_contains "$output" "ci.yml" "attributes reachability to ci.yml"
    assert_contains "$output" "test" "attributes reachability to the job named test"

    rm -rf "$repo"
}

test_check_ci_reachability_docker_build_only_is_unreachable() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"

    mkworkflow "$repo" "deploy.yml" <<'EOF'
name: Deploy
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install test tool for local dev only
        run: pip install pytest
      - name: build image
        run: docker build -t myimage:latest .
      - name: push image
        run: docker push myimage:latest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "1" "exit code is 1 when CI only builds docker image"
    assert_contains "$output" "[UNREACHABLE]" "reports tests dir as UNREACHABLE"
    assert_contains "$output" "No test-running command found" "notes that no test command exists in the workflow"

    rm -rf "$repo"
}

test_check_ci_reachability_no_workflows_dir_is_unreachable_without_crash() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"
    # deliberately no .github/workflows at all

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "1" "exit code is 1 when there is no CI at all"
    assert_contains "$output" "No .github/workflows directory found" "explains that no workflows directory exists"
    assert_contains "$output" "[UNREACHABLE]" "reports the tests dir as UNREACHABLE"
    assert_not_contains "$output" "Traceback" "does not crash with a traceback"
    assert_not_contains "$output" "syntax error" "does not crash with a shell syntax error"

    rm -rf "$repo"
}

test_check_ci_reachability_excludes_venv_test_files_from_count() {
    local repo
    repo="$(mktemp -d)"

    # Fake a large third-party test suite living inside .venv, which must
    # never be counted as this project's own tests.
    mkdir -p "$repo/.venv/lib/python3.12/site-packages/somepkg/tests"
    for i in 1 2 3 4 5 6 7 8 9 10; do
        echo "def test_vendor_$i(): pass" > "$repo/.venv/lib/python3.12/site-packages/somepkg/tests/test_vendor_$i.py"
    done

    # The project's own, much smaller, real test suite.
    mkdir -p "$repo/tests"
    echo "def test_real_one(): pass" > "$repo/tests/test_real_one.py"
    echo "def test_real_two(): pass" > "$repo/tests/test_real_two.py"

    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pytest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 (only the real tests/ dir counts, and it is reachable)"
    assert_not_contains "$output" ".venv" "never mentions any path inside .venv"
    assert_contains "$output" "tests (2 files)" "counts only the 2 real test files, not the 10 vendored ones"

    rm -rf "$repo"
}

test_check_ci_reachability_multiple_workflows_only_one_runs_tests() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"

    mkworkflow "$repo" "lint.yml" <<'EOF'
name: Lint
on: [push]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: ruff check .
EOF

    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: docker build -t app .
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pytest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 since one job does run pytest"
    assert_contains "$output" "[REACHABLE]" "reports tests dir as REACHABLE"
    assert_contains "$output" "ci.yml" "attributes to ci.yml, not lint.yml"
    # The attribution line should name the "test" job specifically, not "build".
    assert_contains "$output" 'job "test"' "attributes to the test job specifically"

    rm -rf "$repo"
}

test_check_ci_reachability_empty_repo_exits_cleanly() {
    local repo
    repo="$(mktemp -d)"
    # Completely empty repo: no test files, no workflows, nothing.

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 for an empty repo (vacuously all reachable)"
    assert_contains "$output" "No test directories found" "reports that no test directories exist"
    assert_not_contains "$output" "Traceback" "does not crash"

    rm -rf "$repo"
}

test_check_ci_reachability_dockerfile_missing_test_copy_is_flagged() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests" "$repo/src"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"
    echo "print('hi')" > "$repo/src/main.py"

    cat > "$repo/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY src ./src
CMD ["python", "src/main.py"]
EOF

    mkworkflow "$repo" "deploy.yml" <<'EOF'
name: Deploy
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: docker build -t app .
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "1" "exit code is 1 (tests still unreachable regardless of Dockerfile)"
    assert_contains "$output" "Dockerfile warning" "flags a Dockerfile warning"
    assert_contains "$output" "tests" "the Dockerfile warning names the tests directory"

    rm -rf "$repo"
}

test_check_ci_reachability_defaults_to_current_directory() {
    local repo
    repo="$(mktemp -d)"
    mkdir -p "$repo/tests"
    echo "def test_ok(): pass" > "$repo/tests/test_thing.py"
    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: pytest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$(cd "$repo" && "$SCRIPT_UNDER_TEST" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 when run with no argument from inside the repo"
    assert_contains "$output" "[REACHABLE]" "still detects reachability using cwd as the repo path"

    rm -rf "$repo"
}

test_check_ci_reachability_node_modules_excluded_from_js_test_count() {
    local repo
    repo="$(mktemp -d)"

    mkdir -p "$repo/node_modules/somelib/tests"
    for i in 1 2 3 4 5; do
        echo "test('vendor $i', () => {});" > "$repo/node_modules/somelib/tests/vendor$i.test.js"
    done

    mkdir -p "$repo/src"
    echo "test('real', () => {});" > "$repo/src/app.test.js"

    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npx vitest run
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "0" "exit code is 0 (real test file is reachable)"
    assert_not_contains "$output" "node_modules" "never mentions any path inside node_modules"
    assert_contains "$output" "src (1 files)" "counts only the 1 real scattered test file under src"

    rm -rf "$repo"
}

test_check_ci_reachability_scoped_working_directory_leaves_other_service_unreachable() {
    local repo
    repo="$(mktemp -d)"

    mkdir -p "$repo/services/api/tests"
    echo "def test_ok(): pass" > "$repo/services/api/tests/test_api.py"

    mkdir -p "$repo/services/legacy/tests"
    echo "def test_old(): pass" > "$repo/services/legacy/tests/test_old.py"

    mkworkflow "$repo" "ci.yml" <<'EOF'
name: CI
on: [push]
jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - name: run api tests
        working-directory: services/api
        run: pytest
EOF

    init_fixture_repo "$repo"

    local output exit_code
    output="$("$SCRIPT_UNDER_TEST" "$repo" 2>&1)"
    exit_code=$?

    assert_eq "$exit_code" "1" "exit code is 1 because the legacy service's tests are never run"
    assert_contains "$output" "[REACHABLE]   services/api/tests" "services/api/tests is reachable via the scoped job"
    assert_contains "$output" "[UNREACHABLE] services/legacy/tests" "services/legacy/tests is unreachable since no job scopes to it"

    rm -rf "$repo"
}

# ---------------------------------------------------------------------------

run_test test_check_ci_reachability_pytest_workflow_is_reachable
run_test test_check_ci_reachability_docker_build_only_is_unreachable
run_test test_check_ci_reachability_no_workflows_dir_is_unreachable_without_crash
run_test test_check_ci_reachability_excludes_venv_test_files_from_count
run_test test_check_ci_reachability_multiple_workflows_only_one_runs_tests
run_test test_check_ci_reachability_empty_repo_exits_cleanly
run_test test_check_ci_reachability_dockerfile_missing_test_copy_is_flagged
run_test test_check_ci_reachability_defaults_to_current_directory
run_test test_check_ci_reachability_node_modules_excluded_from_js_test_count
run_test test_check_ci_reachability_scoped_working_directory_leaves_other_service_unreachable

echo "============================================"
echo "Ran $TESTS_RUN test functions, $FAILURES assertion failure(s)."
if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
exit 0
