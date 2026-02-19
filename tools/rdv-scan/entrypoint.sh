#!/usr/bin/env bash
# rdv-scan entrypoint
# Scans an SBOM for vulnerabilities using grype, with configurable fail thresholds
set -euo pipefail

: "${TOOL_WORKSPACE:?TOOL_WORKSPACE must be set}"
: "${TOOL_OUTPUT:?TOOL_OUTPUT must be set}"
: "${TOOL_CACHE:=/tmp/rdv-cache}"

mkdir -p "$TOOL_OUTPUT" "$TOOL_CACHE/grype"

# Grype DB cache
export GRYPE_DB_CACHE_DIR="$TOOL_CACHE/grype"

echo "[rdv-scan] starting at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[rdv-scan] workspace: $TOOL_WORKSPACE"
echo "[rdv-scan] output:    $TOOL_OUTPUT"
echo "[rdv-scan] cache:     $GRYPE_DB_CACHE_DIR"

# ── Read config ───────────────────────────────────────────────────────────────
# fail_on: array of severity strings that cause exit 1
# Severities: critical, high, medium, low, negligible, unknown
FAIL_ON_JSON='["critical"]'
SBOM_FILE=""

CONFIG_FILE="${TOOL_CONFIG:-}/tool.json"
if [[ -n "${TOOL_CONFIG:-}" ]] && [[ -f "$CONFIG_FILE" ]]; then
    echo "[rdv-scan] reading config from $CONFIG_FILE"
    _fail=$(jq -r '.fail_on // empty' "$CONFIG_FILE" 2>/dev/null || true)
    _sbom=$(jq -r '.sbom_file // empty' "$CONFIG_FILE" 2>/dev/null || true)
    [[ -n "$_fail" ]] && FAIL_ON_JSON="$_fail"
    [[ -n "$_sbom" ]] && SBOM_FILE="$_sbom"
fi

echo "[rdv-scan] fail_on: $FAIL_ON_JSON"

# ── Locate SBOM ───────────────────────────────────────────────────────────────
if [[ -z "$SBOM_FILE" ]]; then
    echo "[rdv-scan] auto-detecting SBOM in $TOOL_WORKSPACE..."
    if [[ -f "$TOOL_WORKSPACE/sbom.json" ]]; then
        SBOM_FILE="$TOOL_WORKSPACE/sbom.json"
    else
        # Look for CycloneDX files
        SBOM_FILE=$(find "$TOOL_WORKSPACE" -maxdepth 2 \( -name "*.cdx.json" -o -name "*.bom.json" \) 2>/dev/null | head -1 || true)
    fi
fi

if [[ -z "$SBOM_FILE" ]] || [[ ! -f "$SBOM_FILE" ]]; then
    echo "[rdv-scan] ERROR: no SBOM file found in $TOOL_WORKSPACE"
    echo "[rdv-scan] expected: sbom.json, *.cdx.json, or specify sbom_file in tool.json"
    exit 1
fi

echo "[rdv-scan] using SBOM: $SBOM_FILE"

# ── Log tool versions ─────────────────────────────────────────────────────────
echo "[rdv-scan] grype version: $(grype version 2>&1 | head -1)"

# ── Run grype scan ────────────────────────────────────────────────────────────
echo "[rdv-scan] scanning SBOM for vulnerabilities..."
grype "sbom:${SBOM_FILE}" -o json > "$TOOL_OUTPUT/vulns.json" 2>&1 || {
    echo "[rdv-scan] ERROR: grype scan failed"
    exit 1
}

echo "[rdv-scan] scan complete, parsing results..."

# ── Parse results and write summary ──────────────────────────────────────────
SUMMARY_FILE="$TOOL_OUTPUT/summary.txt"

# Count vulnerabilities by severity
TOTAL=$(jq '.matches | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
CRITICAL=$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
HIGH=$(jq '[.matches[] | select(.vulnerability.severity == "High")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
MEDIUM=$(jq '[.matches[] | select(.vulnerability.severity == "Medium")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
LOW=$(jq '[.matches[] | select(.vulnerability.severity == "Low")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
NEGLIGIBLE=$(jq '[.matches[] | select(.vulnerability.severity == "Negligible")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)
UNKNOWN=$(jq '[.matches[] | select(.vulnerability.severity == "Unknown")] | length' "$TOOL_OUTPUT/vulns.json" 2>/dev/null || echo 0)

{
    echo "rdv-scan Vulnerability Summary"
    echo "=============================="
    echo "SBOM:       $SBOM_FILE"
    echo "Scanned at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "Vulnerability Counts:"
    echo "  Critical:   $CRITICAL"
    echo "  High:       $HIGH"
    echo "  Medium:     $MEDIUM"
    echo "  Low:        $LOW"
    echo "  Negligible: $NEGLIGIBLE"
    echo "  Unknown:    $UNKNOWN"
    echo "  Total:      $TOTAL"
    echo ""
} | tee "$SUMMARY_FILE"

# ── Check fail thresholds ─────────────────────────────────────────────────────
SHOULD_FAIL=false
FAIL_REASONS=()

# Normalize severities in fail_on to lowercase for comparison
while IFS= read -r severity; do
    severity_lower=$(echo "$severity" | tr '[:upper:]' '[:lower:]')
    case "$severity_lower" in
      critical)
        [[ "$CRITICAL" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$CRITICAL Critical vulnerability(ies)"); } ;;
      high)
        [[ "$HIGH" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$HIGH High vulnerability(ies)"); } ;;
      medium)
        [[ "$MEDIUM" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$MEDIUM Medium vulnerability(ies)"); } ;;
      low)
        [[ "$LOW" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$LOW Low vulnerability(ies)"); } ;;
      negligible)
        [[ "$NEGLIGIBLE" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$NEGLIGIBLE Negligible vulnerability(ies)"); } ;;
      unknown)
        [[ "$UNKNOWN" -gt 0 ]] && { SHOULD_FAIL=true; FAIL_REASONS+=("$UNKNOWN Unknown vulnerability(ies)"); } ;;
    esac
done < <(echo "$FAIL_ON_JSON" | jq -r '.[]' 2>/dev/null)

if [[ "$SHOULD_FAIL" == "true" ]]; then
    echo "SCAN FAILED — threshold exceeded:" | tee -a "$SUMMARY_FILE"
    for reason in "${FAIL_REASONS[@]}"; do
        echo "  ✗ $reason" | tee -a "$SUMMARY_FILE"
    done
    echo ""
    echo "[rdv-scan] threshold violations found — exiting 1"
    exit 1
else
    echo "SCAN PASSED — no threshold violations" | tee -a "$SUMMARY_FILE"
    echo "[rdv-scan] done at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
