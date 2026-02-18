# Tool Container Spec v0.1

> The universal contract that every `rdv` tool container implements.

**Version:** 0.1.0  
**Status:** Draft

---

## Overview

A tool container is a self-describing OCI image that accepts work via mounted filesystem paths and produces artifacts + attestations. The interface is:

```
stdin / mounted workspace → tool container → stdout / mounted output + attestation
```

Everything in this spec is language-agnostic. Tools can be written in Go, Rust, Python, Node, shell — anything that runs in a container.

---

## Mounts

| Mount | Default Path | Description |
|-------|-------------|-------------|
| workspace | `/workspace` | Source input (read-only recommended) |
| output | `/output` | Artifacts destination (read-write) |
| cache | `/cache` | Persistent cache across runs (read-write) |
| config | `/config` | Config overlay directory (read-only) |
| sign socket | `/run/rdv-sign/sign.sock` | Signing sidecar API (Phase 3) |

All mounts are optional at the spec level; tools declare which they require in their manifest.

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TOOL_WORKSPACE` | Yes | Absolute path to workspace mount |
| `TOOL_OUTPUT` | Yes | Absolute path to output mount |
| `TOOL_CACHE` | No | Absolute path to cache mount |
| `TOOL_CONFIG` | No | Absolute path to config mount |
| `TOOL_TRUST_LEVEL` | Yes | `local`, `attested`, or `hardened` |
| `TOOL_LOG_SINK` | No | Log destination; default: `stderr` |
| `TOOL_INVOCATION_ID` | Yes | UUIDv4 unique to this run |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Tool error (the tool ran but failed — e.g., build error, test failures) |
| `2` | Contract violation (missing required mount, missing env var, bad manifest) |
| `3` | Config error (invalid or missing tool config) |

---

## Structured Logs

Tools emit structured logs to stderr as JSON lines. Required fields:

```json
{
  "timestamp": "2026-02-18T08:00:00.000Z",
  "level": "info",
  "tool": "rdv-build",
  "invocation_id": "550e8400-e29b-41d4-a716-446655440000",
  "message": "Build succeeded"
}
```

Valid `level` values: `debug`, `info`, `warn`, `error`.

---

## Tool Manifest (`tool-manifest.json`)

Every tool container ships a `tool-manifest.json` at the image root (`/tool-manifest.json`). This is the tool's self-description.

### Schema

See [`tool-manifest.schema.json`](tool-manifest.schema.json) for the full JSON Schema.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Tool identifier (e.g., `rdv-build`) |
| `version` | string | Yes | SemVer |
| `description` | string | Yes | Human-readable description |
| `spec_version` | string | Yes | Spec version this tool targets (e.g., `0.1`) |
| `inputs` | object | Yes | What this tool expects as input |
| `outputs` | object | Yes | What this tool produces |
| `config_schema` | object | No | JSON Schema for tool-specific config |
| `trust_requirements` | string | Yes | Minimum trust level: `local`, `attested`, `hardened` |
| `supported_platforms` | array | Yes | List of `{os, arch}` objects |
| `parallel_safe` | boolean | Yes | Whether multiple instances can run concurrently |
| `implementation_variant` | string | No | Variant identifier for A/B routing (e.g., `go-v1`) |

### `inputs` Object

```json
{
  "workspace": true,
  "config": false,
  "artifacts": []
}
```

- `workspace`: boolean — whether this tool reads from the workspace mount
- `config`: boolean — whether this tool reads from the config mount
- `artifacts`: array of strings — named artifact inputs from prior pipeline steps

### `outputs` Object

```json
{
  "artifacts": ["binary", "workspace"],
  "reports": ["sbom.json"],
  "attestation": true
}
```

- `artifacts`: named artifact outputs (available to subsequent pipeline steps)
- `reports`: named report files produced in `/output`
- `attestation`: boolean — whether this tool produces an attestation (always true for rdv-base images)

---

## Attestation

Every tool container produces an attestation file at `$TOOL_OUTPUT/.attestation.json` upon completion. The `rdv-base` entrypoint wrapper handles this automatically.

### Attestation Format

In-toto attestation with `rdv` predicates:

```json
{
  "spec_version": "0.1",
  "invocation_id": "550e8400-e29b-41d4-a716-446655440000",
  "tool": {
    "name": "rdv-build",
    "version": "0.1.0",
    "variant": "go-v1"
  },
  "builder": {
    "id": "rdv-local",
    "trust_level": "local"
  },
  "materials": {
    "workspace": "<sha256 of workspace tree hash>"
  },
  "products": {
    "binary": {
      "sha256": "<sha256>",
      "path": "/output/artifacts/binary"
    }
  },
  "exit_code": 0,
  "started_at": "2026-02-18T08:00:00.000Z",
  "finished_at": "2026-02-18T08:01:23.456Z",
  "signature": null
}
```

`signature` is populated by the signing sidecar (Phase 3). In Phase 0-2, it is `null`.

---

## Implementation Variants

A tool can ship multiple implementation variants. The manifest declares the variant via `implementation_variant`. The pipeline's `variant_selector` chooses which one to run:

| Selector | Behavior |
|----------|----------|
| `prefer-fastest` | Choose variant with lowest average runtime |
| `prefer-newest` | Choose latest version |
| `specific:<variant>` | Pin to a named variant |
| `random` | Random selection (useful for chaos testing) |

---

## Compliance Checklist

A tool container is spec-compliant if:

- [ ] Ships `/tool-manifest.json` that validates against `tool-manifest.schema.json`
- [ ] Exits with correct exit codes (0, 1, 2, 3)
- [ ] Emits structured JSON logs to stderr
- [ ] Produces `$TOOL_OUTPUT/.attestation.json` on completion
- [ ] Reads input only from declared mounts
- [ ] Writes output only to `$TOOL_OUTPUT`
- [ ] Does not write to `$TOOL_WORKSPACE` (treat as read-only)
- [ ] Respects `TOOL_TRUST_LEVEL` (fails if trust requirement not met)

---

## Changelog

| Version | Date | Notes |
|---------|------|-------|
| 0.1.0 | 2026-02-18 | Initial draft |
