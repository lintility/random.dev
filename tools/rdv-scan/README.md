# rdv-scan

Vulnerability scanner for rdv pipelines. Scans SBOMs for CVEs using [grype](https://github.com/anchore/grype) (Anchore) with configurable severity thresholds.

## Implements

rdv contract spec v0.1 · implementation variant `grype-v1`

## Inputs

| Variable | Required | Description |
|---|---|---|
| `TOOL_WORKSPACE` | yes | Read-only mount containing the SBOM to scan |
| `TOOL_OUTPUT` | yes | Read-write mount for scan results |
| `TOOL_CACHE` | no | Persistent cache for grype vulnerability DB |
| `TOOL_CONFIG` | no | Optional config mount — place `tool.json` here |

### `$TOOL_CONFIG/tool.json` options

```json
{
  "fail_on": ["critical", "high"],
  "sbom_file": "/workspace/custom-sbom.json"
}
```

| Field | Default | Description |
|---|---|---|
| `fail_on` | `["critical"]` | Severity levels that cause exit 1 |
| `sbom_file` | auto-detect | Explicit path to SBOM (otherwise auto-detected) |

**Severity levels:** `critical`, `high`, `medium`, `low`, `negligible`, `unknown`

## SBOM Auto-Detection

If `sbom_file` is not configured, the tool searches `$TOOL_WORKSPACE` for:
1. `sbom.json`
2. `*.cdx.json` (CycloneDX)
3. `*.bom.json`

Pairs naturally with `rdv-sbom` in a pipeline.

## Outputs

| File | Description |
|---|---|
| `$TOOL_OUTPUT/vulns.json` | Full grype JSON report |
| `$TOOL_OUTPUT/summary.txt` | Human-readable summary with counts by severity |

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Scan passed (no threshold violations) |
| 1 | Threshold violated (vulnerabilities found at configured severity) |
| 3 | Config error |

## Usage Example

```bash
# Scan an SBOM from rdv-sbom output
docker run --rm \
  -v /tmp/sbom-output:/workspace:ro \
  -v /tmp/scan-output:/output \
  -v /tmp/cache:/cache \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  -e TOOL_CACHE=/cache \
  rdv-scan:latest
```

With custom thresholds:

```bash
# Fail on critical or high
cat > /tmp/scan-config/tool.json << 'EOF'
{"fail_on": ["critical", "high"]}
EOF

docker run --rm \
  -v /tmp/sbom-output:/workspace:ro \
  -v /tmp/scan-output:/output \
  -v /tmp/scan-config:/config:ro \
  -v /tmp/cache:/cache \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  -e TOOL_CONFIG=/config \
  -e TOOL_CACHE=/cache \
  rdv-scan:latest
```
