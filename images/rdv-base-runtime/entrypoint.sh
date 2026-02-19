#!/usr/bin/env bash
# rdv entrypoint wrapper for rdv-base:runtime
# Validates the rdv contract, sets up structured logging, runs the tool,
# and produces an attestation on exit.
set -euo pipefail

SPEC_VERSION="0.1"
TOOL_NAME="${RDV_TOOL_NAME:-unknown}"
INVOCATION_ID="${TOOL_INVOCATION_ID:-unknown}"

# ── Structured logging ────────────────────────────────────────────────────────
log_json() {
  local level="$1" msg="$2"
  printf '{"timestamp":"%s","level":"%s","tool":"%s","invocation_id":"%s","message":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$TOOL_NAME" "$INVOCATION_ID" "$msg" >&2
}

# ── Read manifest ─────────────────────────────────────────────────────────────
if [[ -f /tool-manifest.json ]]; then
  TOOL_NAME=$(jq -r '.name // "unknown"' /tool-manifest.json)
  TOOL_VERSION=$(jq -r '.version // "unknown"' /tool-manifest.json)
else
  TOOL_VERSION="unknown"
fi

log_json "info" "rdv entrypoint starting (spec ${SPEC_VERSION})"

# ── Contract validation ───────────────────────────────────────────────────────
validate_contract() {
  local ok=0

  for var in TOOL_WORKSPACE TOOL_OUTPUT TOOL_TRUST_LEVEL TOOL_INVOCATION_ID; do
    if [[ -z "${!var:-}" ]]; then
      log_json "error" "Contract violation: ${var} is not set"
      ok=1
    fi
  done

  for mount_var in TOOL_WORKSPACE TOOL_OUTPUT; do
    local path="${!mount_var:-}"
    if [[ -n "$path" && ! -d "$path" ]]; then
      log_json "error" "Contract violation: ${mount_var} mount not found at ${path}"
      ok=1
    fi
  done

  if [[ -n "${TOOL_OUTPUT:-}" ]] && ! touch "${TOOL_OUTPUT}/.rdv-write-test" 2>/dev/null; then
    log_json "error" "Contract violation: TOOL_OUTPUT ${TOOL_OUTPUT} is not writable"
    ok=1
  fi
  rm -f "${TOOL_OUTPUT}/.rdv-write-test" 2>/dev/null || true

  return $ok
}

if ! validate_contract; then
  exit 2
fi
log_json "info" "Contract validated"

# ── Hash workspace (materials) ────────────────────────────────────────────────
workspace_hash() {
  # Sort by path first to ensure a deterministic hash regardless of filesystem order.
  find "${TOOL_WORKSPACE}" -type f -print0 2>/dev/null \
    | sort -z | xargs -0 sha256sum 2>/dev/null \
    | sha256sum | awk '{print $1}'
}
WORKSPACE_HASH=$(workspace_hash)
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Run the tool ──────────────────────────────────────────────────────────────
TOOL_BIN=""
for candidate in /tool /tool.sh /tool.py /tool.js; do
  if [[ -f "$candidate" ]]; then
    TOOL_BIN="$candidate"
    break
  fi
done

if [[ -z "$TOOL_BIN" ]]; then
  log_json "error" "Tool binary not found. Expected /tool, /tool.sh, /tool.py, or /tool.js"
  exit 2
fi

[[ -x "$TOOL_BIN" ]] || chmod +x "$TOOL_BIN"

EXIT_CODE=0
"$TOOL_BIN" "$@" || EXIT_CODE=$?

FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Collect output products ───────────────────────────────────────────────────
products_json() {
  # Use jq for proper JSON encoding — handles filenames with special characters.
  find "${TOOL_OUTPUT}" -type f -print0 2>/dev/null \
    | sort -z \
    | while IFS= read -r -d '' file; do
        local rel="${file#"${TOOL_OUTPUT}/"}"
        [[ "$rel" == ".attestation.json" ]] && continue
        local hash; hash=$(sha256sum "$file" | awk '{print $1}')
        jq -n --arg k "$rel" --arg h "$hash" --arg p "$file" \
               '{($k): {sha256: $h, path: $p}}'
      done \
    | jq -s 'add // {}'
}

# ── Write attestation ─────────────────────────────────────────────────────────
PRODUCTS=$(products_json)
TRUST_LEVEL="${TOOL_TRUST_LEVEL:-local}"

if ! jq -n \
  --arg spec_version    "$SPEC_VERSION" \
  --arg invocation_id   "$INVOCATION_ID" \
  --arg tool_name       "$TOOL_NAME" \
  --arg tool_version    "$TOOL_VERSION" \
  --arg builder_id      "rdv-${TRUST_LEVEL}" \
  --arg trust_level     "$TRUST_LEVEL" \
  --arg workspace_hash  "$WORKSPACE_HASH" \
  --argjson products    "$PRODUCTS" \
  --argjson exit_code   "$EXIT_CODE" \
  --arg started_at      "$STARTED_AT" \
  --arg finished_at     "$FINISHED_AT" \
  '{
    spec_version:  $spec_version,
    invocation_id: $invocation_id,
    tool:     { name: $tool_name,    version: $tool_version },
    builder:  { id:   $builder_id,   trust_level: $trust_level },
    materials: { workspace: $workspace_hash },
    products:  $products,
    exit_code: $exit_code,
    started_at:  $started_at,
    finished_at: $finished_at,
    signature:   null
  }' > "${TOOL_OUTPUT}/.attestation.json"; then
  log_json "error" "Contract violation: failed to write attestation to ${TOOL_OUTPUT}/.attestation.json"
  exit 2
fi

log_json "info" "Attestation written to ${TOOL_OUTPUT}/.attestation.json"
log_json "info" "Finished with exit code ${EXIT_CODE}"

exit $EXIT_CODE
