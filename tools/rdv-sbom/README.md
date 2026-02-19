# rdv-sbom

SBOM generator for rdv pipelines. Generates CycloneDX or SPDX SBOMs from any workspace using [syft](https://github.com/anchore/syft) (Anchore).

## Implements

rdv contract spec v0.1 · implementation variant `syft-v1`

## Inputs

| Variable | Required | Description |
|---|---|---|
| `TOOL_WORKSPACE` | yes | Read-only mount of source/artifact tree to scan |
| `TOOL_OUTPUT` | yes | Read-write mount for SBOM output |
| `TOOL_CACHE` | no | Persistent cache directory |
| `TOOL_CONFIG` | no | Optional config mount — place `tool.json` here |

### `$TOOL_CONFIG/tool.json` options

```json
{
  "format": "cyclonedx-json",
  "output_name": "sbom.json"
}
```

| Field | Default | Options |
|---|---|---|
| `format` | `cyclonedx-json` | `cyclonedx-json`, `spdx-json` |
| `output_name` | `sbom.json` | Any filename |

## Outputs

| File | Description |
|---|---|
| `$TOOL_OUTPUT/sbom.json` | SBOM in the configured format |

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | SBOM generated successfully |
| 1 | syft scan failed |
| 3 | Invalid format specified in config |

## Usage Example

```bash
docker run --rm \
  -v /my/project:/workspace:ro \
  -v /tmp/output:/output \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  rdv-sbom:latest
```

With custom format:

```bash
docker run --rm \
  -v /my/project:/workspace:ro \
  -v /tmp/output:/output \
  -v /tmp/sbom-config:/config:ro \
  -e TOOL_WORKSPACE=/workspace \
  -e TOOL_OUTPUT=/output \
  -e TOOL_CONFIG=/config \
  rdv-sbom:latest
```

Where `/tmp/sbom-config/tool.json` contains:

```json
{
  "format": "spdx-json",
  "output_name": "spdx-sbom.json"
}
```
