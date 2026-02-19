#!/usr/bin/env bash
# rdv-sbom entrypoint
# Generates a CycloneDX or SPDX SBOM from $TOOL_WORKSPACE using syft
set -euo pipefail

: "${TOOL_WORKSPACE:?TOOL_WORKSPACE must be set}"
: "${TOOL_OUTPUT:?TOOL_OUTPUT must be set}"
: "${TOOL_CACHE:=/tmp/rdv-cache}"

mkdir -p "$TOOL_OUTPUT" "$TOOL_CACHE"

echo "[rdv-sbom] starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[rdv-sbom] workspace: $TOOL_WORKSPACE"
echo "[rdv-sbom] output:    $TOOL_OUTPUT"

# ── Read config ───────────────────────────────────────────────────────────────
FORMAT="cyclonedx-json"
OUTPUT_NAME="sbom.json"

CONFIG_FILE="${TOOL_CONFIG:-}/tool.json"
if [[ -n "${TOOL_CONFIG:-}" ]] && [[ -f "$CONFIG_FILE" ]]; then
    echo "[rdv-sbom] reading config from $CONFIG_FILE"
    _fmt=$(jq -r '.format // empty' "$CONFIG_FILE" 2>/dev/null || true)
    _name=$(jq -r '.output_name // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$_fmt" ]] && FORMAT="$_fmt"
    [[ -n "$_name" ]] && OUTPUT_NAME="$_name"
fi

echo "[rdv-sbom] format:      $FORMAT"
echo "[rdv-sbom] output name: $OUTPUT_NAME"

# ── Validate format ───────────────────────────────────────────────────────────
case "$FORMAT" in
  cyclonedx-json|spdx-json) ;;
  *)
    echo "[rdv-sbom] ERROR: unsupported format '$FORMAT'. Valid: cyclonedx-json, spdx-json"
    exit 3
    ;;
esac

# ── Log tool versions ─────────────────────────────────────────────────────────
echo "[rdv-sbom] syft version: $(syft version 2>&1 | head -1)"

# ── Run syft scan ─────────────────────────────────────────────────────────────
echo "[rdv-sbom] scanning $TOOL_WORKSPACE..."
syft scan "dir:${TOOL_WORKSPACE}" -o "${FORMAT}=${TOOL_OUTPUT}/${OUTPUT_NAME}" 2>&1 || {
    echo "[rdv-sbom] ERROR: syft scan failed"
    exit 1
}

# ── Verify output ─────────────────────────────────────────────────────────────
if [[ ! -f "$TOOL_OUTPUT/$OUTPUT_NAME" ]]; then
    echo "[rdv-sbom] ERROR: expected output file not found: $TOOL_OUTPUT/$OUTPUT_NAME"
    exit 1
fi

OUTPUT_SIZE=$(wc -c < "$TOOL_OUTPUT/$OUTPUT_NAME")
echo "[rdv-sbom] SBOM written: $TOOL_OUTPUT/$OUTPUT_NAME ($OUTPUT_SIZE bytes)"
echo "[rdv-sbom] done at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
