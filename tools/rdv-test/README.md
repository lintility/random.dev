# rdv-test

Multi-language test runner for rdv pipelines. Auto-detects Go, Rust, Node/TypeScript (Jest/Vitest), and Python (pytest) test suites. Outputs JUnit XML and JSON for CI integration.

## Implements

rdv contract spec v0.1 · implementation variant `polyglot-v1`

## Inputs

| Variable | Required | Description |
|---|---|---|
| `TOOL_WORKSPACE` | yes | Read-only mount of the source tree to test |
| `TOOL_OUTPUT` | yes | Read-write mount for test results |
| `TOOL_CACHE` | no | Persistent cache for build/install caches |
| `TOOL_CONFIG` | no | Optional config mount |

## Outputs

| File | Description |
|---|---|
| `$TOOL_OUTPUT/test-results.json` | Structured JSON test results |
| `$TOOL_OUTPUT/test-results.xml` | JUnit XML (compatible with CI systems) |

## Framework Detection

| File detected | Framework used |
|---|---|
| `go.mod` | `go test -v ./... -json` |
| `Cargo.toml` | `cargo test` |
| `package.json` + vitest in deps | `vitest run` |
| `package.json` + jest in deps (or default) | `jest --ci` |
| `pyproject.toml` or `pytest.ini` | `pytest` |

## Language Details

### Go

```bash
GOPATH=$TOOL_CACHE/go GOCACHE=$TOOL_CACHE/go/cache \
  go test -v ./... -json > test-results-raw.json
# Converted to JUnit XML via awk
```

### Rust

```bash
cargo test -- --format json   # unstable, falls back to text
```

Note: Rust structured JSON output is a nightly feature. The tool falls back to text output if unavailable, still capturing pass/fail for exit code.

### Jest

```bash
npx jest --ci --json --outputFile=test-results.json
```

### Vitest

```bash
npx vitest run --reporter=json --reporter=junit
```

### Python

```bash
pytest --json-report --json-report-file=test-results.json --junit-xml=test-results.xml
```

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | All tests passed |
| 1 | One or more tests failed |
| 3 | Could not detect test framework |

## Usage Example

```bash
docker run --rm \
  -v /my/project:/workspace:ro \
  -v /tmp/test-output:/output \
  -v /tmp/cache:/cache \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  -e TOOL_CACHE=/cache \
  rdv-test:latest
```
