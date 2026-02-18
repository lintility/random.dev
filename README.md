# random.dev (`rdv`)

> Universal composable tool container runtime. Secure, auditable, agent-native.

`rdv` is a framework for building and running tools as containers with a standardized interface, composable pipelines, and security baked in from the ground up.

## Core Idea

Every tool is a container. Every container speaks the same contract:

```
stdin / mounted workspace → tool container → stdout / mounted output + attestation
```

Tools are composed into pipelines via declarative YAML. Pipelines are auditable — every run produces signed attestations tracing inputs to outputs.

## Architecture

```
rdv CLI (orchestrator)
├── Tool Containers (rdv-build, rdv-sbom, rdv-scan, rdv-test, ...)
│   └── built on rdv-base:minimal or rdv-base:runtime
├── Pipeline Engine (declarative YAML, DAG execution)
├── Signing Layer (local keychain → KMS → multi-party WebAuthn)
└── Agent Composition API (machine-readable task graph)
```

## Phases

| Phase | Focus | Key Deliverables |
|-------|-------|-----------------|
| P0 Bootstrap | Spec + shim | Tool contract spec, base images, `rdv run` |
| P1 Foundation | Core tools | build, sbom, scan, test |
| P2 Composition | Pipelines | Pipeline YAML, DAG engine, real `rdv` CLI |
| P3 Trust | Signing | Attestation format, three-tier signing |
| P4 Ecosystem | Polish | Caching, observability, config UI |

## Quick Start

```bash
# Run a tool container
rdv run rdv-build:latest --workspace .

# Run with config
rdv run rdv-build:latest --workspace . --config ./rdv.yaml

# Clean cache
rdv clean
```

## Spec

See [`spec/tool-container-spec.md`](spec/tool-container-spec.md) for the full tool container contract.

## Status

🚧 **Bootstrap phase** — spec and shim in progress.

## License

MIT
