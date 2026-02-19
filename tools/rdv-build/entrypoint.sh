#!/usr/bin/env bash
# rdv-build entrypoint
# Detects language and runs the appropriate build, outputting artifacts to $TOOL_OUTPUT
set -euo pipefail

: "${TOOL_WORKSPACE:?TOOL_WORKSPACE must be set}"
: "${TOOL_OUTPUT:?TOOL_OUTPUT must be set}"
: "${TOOL_CACHE:=/tmp/rdv-cache}"

mkdir -p "$TOOL_OUTPUT" "$TOOL_CACHE"

LOG="$TOOL_OUTPUT/build.log"
exec > >(tee -a "$LOG") 2>&1

echo "[rdv-build] starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[rdv-build] workspace: $TOOL_WORKSPACE"
echo "[rdv-build] output:    $TOOL_OUTPUT"
echo "[rdv-build] cache:     $TOOL_CACHE"

# ── Step 1: Check for explicit config ────────────────────────────────────────
LANGUAGE=""
CONFIG_FILE="$TOOL_WORKSPACE/build.rdv.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
    echo "[rdv-build] found build.rdv.yaml, reading language config..."
    # Parse language: field from YAML (simple grep — no yq dependency)
    LANGUAGE=$(grep -E '^language:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' || true)
    echo "[rdv-build] explicit language: ${LANGUAGE:-<none>}"
fi

# ── Step 2: Auto-detect language if not explicit ──────────────────────────────
if [[ -z "$LANGUAGE" ]]; then
    echo "[rdv-build] auto-detecting language..."
    if [[ -f "$TOOL_WORKSPACE/go.mod" ]]; then
        LANGUAGE="go"
    elif [[ -f "$TOOL_WORKSPACE/Cargo.toml" ]]; then
        LANGUAGE="rust"
    elif [[ -f "$TOOL_WORKSPACE/package.json" ]]; then
        LANGUAGE="node"
    elif [[ -f "$TOOL_WORKSPACE/pyproject.toml" ]] || [[ -f "$TOOL_WORKSPACE/setup.py" ]]; then
        LANGUAGE="python"
    fi
    echo "[rdv-build] detected language: ${LANGUAGE:-<unknown>}"
fi

# ── Step 3: Build ─────────────────────────────────────────────────────────────
case "$LANGUAGE" in

  go)
    echo "[rdv-build] building Go project..."
    export GOPATH="$TOOL_CACHE/go"
    export GOCACHE="$TOOL_CACHE/go/cache"
    mkdir -p "$GOPATH" "$GOCACHE"
    cd "$TOOL_WORKSPACE"
    go build -v ./... -o "$TOOL_OUTPUT/" || {
        echo "[rdv-build] ERROR: go build failed"
        exit 1
    }
    echo "[rdv-build] Go build complete"
    ;;

  rust)
    echo "[rdv-build] building Rust project..."
    export CARGO_HOME="$TOOL_CACHE/cargo"
    mkdir -p "$CARGO_HOME"
    cd "$TOOL_WORKSPACE"
    cargo build --release 2>&1 || {
        echo "[rdv-build] ERROR: cargo build failed"
        exit 1
    }
    echo "[rdv-build] copying release binaries to output..."
    find target/release -maxdepth 1 -type f -executable -exec cp -v {} "$TOOL_OUTPUT/" \;
    echo "[rdv-build] Rust build complete"
    ;;

  node)
    echo "[rdv-build] building Node/TypeScript project..."
    mkdir -p "$TOOL_CACHE/npm"
    cd "$TOOL_WORKSPACE"
    npm ci --cache "$TOOL_CACHE/npm" || {
        echo "[rdv-build] ERROR: npm ci failed"
        exit 1
    }
    npm run build 2>&1 || {
        echo "[rdv-build] ERROR: npm run build failed"
        exit 1
    }
    # Copy common build output directories
    for dir in dist build out; do
        if [[ -d "$TOOL_WORKSPACE/$dir" ]]; then
            echo "[rdv-build] copying $dir/ to output..."
            cp -r "$TOOL_WORKSPACE/$dir" "$TOOL_OUTPUT/"
        fi
    done
    echo "[rdv-build] Node/TypeScript build complete"
    ;;

  python)
    echo "[rdv-build] building Python project..."
    cd "$TOOL_WORKSPACE"
    if [[ -f "pyproject.toml" ]]; then
        # Detect build backend
        if grep -q 'poetry' pyproject.toml 2>/dev/null; then
            echo "[rdv-build] detected poetry..."
            pip install --no-cache-dir poetry 2>&1
            poetry build --no-interaction -o "$TOOL_OUTPUT/" 2>&1 || {
                echo "[rdv-build] ERROR: poetry build failed"
                exit 1
            }
        elif grep -q 'hatch' pyproject.toml 2>/dev/null; then
            echo "[rdv-build] detected hatch..."
            pip install --no-cache-dir hatch 2>&1
            hatch build -t wheel 2>&1 || {
                echo "[rdv-build] ERROR: hatch build failed"
                exit 1
            }
            find dist -name '*.whl' -exec cp -v {} "$TOOL_OUTPUT/" \;
        else
            echo "[rdv-build] using build (PEP 517)..."
            pip install --no-cache-dir build 2>&1
            python -m build --wheel --outdir "$TOOL_OUTPUT/" 2>&1 || {
                echo "[rdv-build] ERROR: python -m build failed"
                exit 1
            }
        fi
    elif [[ -f "setup.py" ]]; then
        echo "[rdv-build] using setuptools (setup.py)..."
        pip install --no-cache-dir wheel 2>&1
        python setup.py bdist_wheel --dist-dir "$TOOL_OUTPUT/" 2>&1 || {
            echo "[rdv-build] ERROR: setup.py bdist_wheel failed"
            exit 1
        }
    fi
    echo "[rdv-build] Python build complete"
    ;;

  *)
    echo "[rdv-build] ERROR: unknown or undetected language: '${LANGUAGE}'"
    echo "[rdv-build] supported languages: go, rust, node, python"
    echo "[rdv-build] to specify explicitly, create build.rdv.yaml with 'language: <lang>'"
    exit 3
    ;;
esac

echo "[rdv-build] done at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
