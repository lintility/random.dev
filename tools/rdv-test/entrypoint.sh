#!/usr/bin/env bash
# rdv-test entrypoint
# Auto-detects test framework and runs tests, producing JUnit XML + JSON output
set -euo pipefail

: "${TOOL_WORKSPACE:?TOOL_WORKSPACE must be set}"
: "${TOOL_OUTPUT:?TOOL_OUTPUT must be set}"
: "${TOOL_CACHE:=/tmp/rdv-cache}"

mkdir -p "$TOOL_OUTPUT" "$TOOL_CACHE"

echo "[rdv-test] starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[rdv-test] workspace: $TOOL_WORKSPACE"
echo "[rdv-test] output:    $TOOL_OUTPUT"

# ── Detect framework ──────────────────────────────────────────────────────────
FRAMEWORK=""

echo "[rdv-test] auto-detecting test framework..."

if [[ -f "$TOOL_WORKSPACE/go.mod" ]]; then
    FRAMEWORK="go"
elif [[ -f "$TOOL_WORKSPACE/Cargo.toml" ]]; then
    FRAMEWORK="rust"
elif [[ -f "$TOOL_WORKSPACE/package.json" ]]; then
    # Prefer vitest, then jest, based on devDependencies
    if jq -e '.devDependencies.vitest // .dependencies.vitest' "$TOOL_WORKSPACE/package.json" > /dev/null 2>&1; then
        FRAMEWORK="vitest"
    elif jq -e '.devDependencies.jest // .dependencies.jest' "$TOOL_WORKSPACE/package.json" > /dev/null 2>&1; then
        FRAMEWORK="jest"
    else
        # Default to jest if package.json present but neither explicit
        FRAMEWORK="jest"
    fi
elif [[ -f "$TOOL_WORKSPACE/pyproject.toml" ]] || [[ -f "$TOOL_WORKSPACE/pytest.ini" ]] || [[ -f "$TOOL_WORKSPACE/setup.cfg" ]]; then
    FRAMEWORK="pytest"
fi

if [[ -z "$FRAMEWORK" ]]; then
    echo "[rdv-test] ERROR: could not detect test framework"
    echo "[rdv-test] supported: go (go.mod), rust (Cargo.toml), jest/vitest (package.json), pytest (pyproject.toml/pytest.ini)"
    exit 3
fi

echo "[rdv-test] detected framework: $FRAMEWORK"

# ── Run tests ─────────────────────────────────────────────────────────────────
TEST_EXIT=0

case "$FRAMEWORK" in

  go)
    echo "[rdv-test] running Go tests..."
    export GOPATH="$TOOL_CACHE/go"
    export GOCACHE="$TOOL_CACHE/go/cache"
    mkdir -p "$GOPATH" "$GOCACHE"
    cd "$TOOL_WORKSPACE"

    go test -v ./... -json > "$TOOL_OUTPUT/test-results-raw.json" 2>&1 || TEST_EXIT=$?

    echo "[rdv-test] converting Go JSON output to JUnit XML..."
    # Convert go test -json output to JUnit XML using a self-contained awk script
    awk '
    BEGIN {
        print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        print "<testsuites>"
        tests = 0; failures = 0; errors = 0
    }
    {
        line = $0
        # Parse JSON fields we care about
        if (match(line, /"Action":"([^"]+)"/, arr)) action = arr[1]
        if (match(line, /"Test":"([^"]+)"/, arr)) test = arr[1]
        if (match(line, /"Package":"([^"]+)"/, arr)) pkg = arr[1]
        if (match(line, /"Elapsed":([0-9.]+)/, arr)) elapsed = arr[1]
        if (match(line, /"Output":"([^"]*)"/, arr)) output = arr[1]

        if (action == "pass" && test != "") {
            tests++
            printf "  <testsuite name=\"%s\"><testcase name=\"%s\" time=\"%s\"/></testsuite>\n", pkg, test, elapsed
        } else if (action == "fail" && test != "") {
            tests++; failures++
            printf "  <testsuite name=\"%s\"><testcase name=\"%s\" time=\"%s\"><failure>FAILED</failure></testcase></testsuite>\n", pkg, test, elapsed
        }
    }
    END {
        print "</testsuites>"
    }
    ' "$TOOL_OUTPUT/test-results-raw.json" > "$TOOL_OUTPUT/test-results.xml" 2>/dev/null || true

    # Create structured JSON summary
    jq -s '
      {
        "framework": "go",
        "passed": ([.[] | select(.Action=="pass" and .Test != null)] | length),
        "failed": ([.[] | select(.Action=="fail" and .Test != null)] | length),
        "skipped": ([.[] | select(.Action=="skip" and .Test != null)] | length),
        "raw": .
      }
    ' "$TOOL_OUTPUT/test-results-raw.json" > "$TOOL_OUTPUT/test-results.json" 2>/dev/null || \
        echo '{"framework":"go","error":"failed to parse results"}' > "$TOOL_OUTPUT/test-results.json"
    ;;

  rust)
    echo "[rdv-test] running Rust tests..."
    export CARGO_HOME="$TOOL_CACHE/cargo"
    mkdir -p "$CARGO_HOME"
    cd "$TOOL_WORKSPACE"

    # cargo test JSON output is unstable; try it first, fall back to text
    if cargo test -- --format json 2>/dev/null > "$TOOL_OUTPUT/test-results-raw.json"; then
        echo "[rdv-test] parsed structured Rust test output"
        # Write minimal JUnit XML
        cat > "$TOOL_OUTPUT/test-results.xml" << 'JUNITEOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="rust"><testcase name="cargo-test"/></testsuite></testsuites>
JUNITEOF
        echo '{"framework":"rust","note":"structured output (unstable)"}' > "$TOOL_OUTPUT/test-results.json"
    else
        echo "[rdv-test] falling back to text output..."
        cargo test 2>&1 | tee "$TOOL_OUTPUT/test-output.txt" || TEST_EXIT=$?
        # Write placeholder structured output
        cat > "$TOOL_OUTPUT/test-results.xml" << 'JUNITEOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="rust"><testcase name="cargo-test"/></testsuite></testsuites>
JUNITEOF
        echo '{"framework":"rust","note":"text output only (structured output unavailable)"}' > "$TOOL_OUTPUT/test-results.json"
    fi
    ;;

  jest)
    echo "[rdv-test] running Jest tests..."
    mkdir -p "$TOOL_CACHE/npm"
    cd "$TOOL_WORKSPACE"

    # Install deps if node_modules absent
    if [[ ! -d "node_modules" ]]; then
        npm ci --cache "$TOOL_CACHE/npm" 2>&1
    fi

    npx jest \
        --ci \
        --json \
        --outputFile="$TOOL_OUTPUT/test-results.json" \
        --testResultsProcessor="" \
        2>&1 | tee "$TOOL_OUTPUT/jest.log" || TEST_EXIT=$?

    # Generate JUnit XML via jest-junit if available, else minimal placeholder
    npx jest \
        --ci \
        --reporters=jest-junit \
        --env=node \
        2>/dev/null || true
    JUNIT_PATH="${JUNIT_REPORT_PATH:-junit.xml}"
    if [[ -f "$JUNIT_PATH" ]]; then
        mv "$JUNIT_PATH" "$TOOL_OUTPUT/test-results.xml"
    else
        cat > "$TOOL_OUTPUT/test-results.xml" << 'JUNITEOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites><testsuite name="jest"><testcase name="see-test-results.json"/></testsuite></testsuites>
JUNITEOF
    fi
    ;;

  vitest)
    echo "[rdv-test] running Vitest tests..."
    mkdir -p "$TOOL_CACHE/npm"
    cd "$TOOL_WORKSPACE"

    if [[ ! -d "node_modules" ]]; then
        npm ci --cache "$TOOL_CACHE/npm" 2>&1
    fi

    npx vitest run \
        --reporter=json \
        --outputFile="$TOOL_OUTPUT/test-results.json" \
        --reporter=junit \
        --outputFile.junit="$TOOL_OUTPUT/test-results.xml" \
        2>&1 | tee "$TOOL_OUTPUT/vitest.log" || TEST_EXIT=$?
    ;;

  pytest)
    echo "[rdv-test] running pytest..."
    cd "$TOOL_WORKSPACE"

    python -m pytest \
        --json-report \
        --json-report-file="$TOOL_OUTPUT/test-results.json" \
        --junit-xml="$TOOL_OUTPUT/test-results.xml" \
        -v \
        2>&1 | tee "$TOOL_OUTPUT/pytest.log" || TEST_EXIT=$?
    ;;

esac

# ── Report ────────────────────────────────────────────────────────────────────
echo "[rdv-test] done at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$TEST_EXIT" -ne 0 ]]; then
    echo "[rdv-test] tests FAILED (exit $TEST_EXIT)"
    exit 1
fi

echo "[rdv-test] tests PASSED"
exit 0
