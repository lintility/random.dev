# rdv-build

Multi-language build tool for rdv pipelines. Auto-detects Go, Rust, TypeScript/Node, and Python projects.

## Implements

rdv contract spec v0.1 · implementation variant `polyglot-v1`

## Inputs

| Variable | Required | Description |
|---|---|---|
| `TOOL_WORKSPACE` | yes | Read-only mount of the source tree to build |
| `TOOL_OUTPUT` | yes | Read-write mount for build artifacts |
| `TOOL_CACHE` | no | Persistent cache directory (speeds up repeated builds) |
| `TOOL_CONFIG` | no | Optional config mount — place `build.rdv.yaml` here or in workspace root |

## Outputs

| File | Description |
|---|---|
| `$TOOL_OUTPUT/<binaries/wheels/dist>` | Build artifacts (language-specific) |
| `$TOOL_OUTPUT/build.log` | Full build log |

## Language Detection

The tool auto-detects the project language in order:

1. `build.rdv.yaml` in workspace root (explicit override)
2. `go.mod` → Go
3. `Cargo.toml` → Rust
4. `package.json` → Node/TypeScript
5. `pyproject.toml` or `setup.py` → Python

### `build.rdv.yaml` format

```yaml
language: go  # go | rust | node | python
```

## Language Build Commands

### Go

```bash
GOPATH=$TOOL_CACHE/go GOCACHE=$TOOL_CACHE/go/cache go build -v ./... -o $TOOL_OUTPUT/
```

### Rust

```bash
CARGO_HOME=$TOOL_CACHE/cargo cargo build --release
# Copies target/release/ executables to $TOOL_OUTPUT/
```

### Node/TypeScript

```bash
npm ci --cache $TOOL_CACHE/npm
npm run build
# Copies dist/, build/, or out/ to $TOOL_OUTPUT/
```

### Python

Auto-detects build backend from `pyproject.toml` (poetry → hatch → build PEP 517) or `setup.py` (setuptools). Outputs wheels to `$TOOL_OUTPUT/`.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Build succeeded |
| 1 | Build failed |
| 3 | Unknown/undetected language (config error) |

## Usage Example

```bash
docker run --rm \
  -v /my/project:/workspace:ro \
  -v /tmp/output:/output \
  -v /tmp/cache:/cache \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  -e TOOL_CACHE=/cache \
  rdv-build:latest
```
