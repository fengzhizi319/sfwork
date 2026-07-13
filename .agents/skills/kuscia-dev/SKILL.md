---
name: kuscia-dev
description: Develop Kuscia, the Go-based privacy-preserving computing orchestration engine. Use when the user asks about Kuscia code, CRDs, controllers, DataMesh, Gateway, DomainRoute, DomainData, task scheduling, deployment scripts, or local Kuscia setup.
---

# Kuscia Development

Kuscia is the Go orchestration engine that schedules privacy computing jobs across domains.

## Stack

- Go 1.24.7
- Kubernetes CRDs (k8s.io/* v0.33.5)
- gRPC / Protocol Buffers
- Gin (internal HTTP), Envoy (gateway), CoreDNS
- containerd / runc / K3s (embedded control plane)
- Apache Arrow Flight (DataMesh I/O)

## Key Directories

```
kuscia/
├── cmd/kuscia/             # CLI entry point
├── pkg/agent/              # Pod lifecycle, CRI
├── pkg/controllers/        # CRD controllers
├── pkg/kusciaapi/          # External HTTP/gRPC API
├── pkg/datamesh/           # DataMesh HTTP/gRPC + Arrow Flight
├── pkg/gateway/            # Envoy xDS control plane
├── pkg/confmanager/        # Certificate & config management
├── pkg/transport/          # Standalone transport service
├── pkg/scheduler/          # Scheduler plugins
├── pkg/web/                # Internal Gin + gRPC framework
├── pkg/utils/              # Shared utilities, nlog, TLS helpers
├── pkg/crd/                # Generated Go types, clientset
├── crds/v1alpha1/          # CRD YAML manifests
├── proto/api/v1alpha1/     # Protobuf definitions
├── scripts/deploy/         # Docker deployment scripts
└── docs/                   # Documentation (also in docs/doc-center)
```

## Key Commands

```bash
cd kuscia

# Build kuscia binary
make build
# or
bash hack/build.sh -t kuscia

# Build transport binary
bash hack/build.sh -t transport

# Unit tests
make test

# Lint
make lint-golang
make check

# Generate code (CRDs, clientset, proto)
make generate

# Docker image
make image
```

## Local Non-Docker Master

```bash
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
sudo bash scripts/run_local_kuscia.sh master
```

Needs root for CoreDNS port 53 and Envoy port 80.

## Key Ports

| Service | Port |
|---|---|
| KusciaAPI gRPC | 8083 (non-Docker: 18083 on host) |
| Gateway public | 1080 |
| Gateway internal | 80 (non-Docker: 13081 on host) |
| DataMesh HTTP | 8070 |
| DataMesh gRPC | 8071 |
| ConfManager HTTP | 8060 |
| Reporter HTTP | 8050 |
| Transport gRPC | 9090 |

## Conventions

- Run `make fmt` before committing.
- Imports grouped with `local-prefixes: github.com/secretflow/kuscia`
- Apache-2.0 license header required.
- Use `pkg/errors` style wrapping.
- Table-driven tests with testify and gomock.

## Critical Concepts

- **Domain**: A participating party (e.g., alice, bob, master)
- **DomainData**: Data asset registered in a domain
- **DomainRoute**: Network route between domains
- **KusciaJob / KusciaTask**: Job/task CRDs
- **DataMesh**: Data access layer using gRPC + Arrow Flight

## Important References

- Architecture: `docs/doc-center/04-Kuscia/kuscia-architecture_cn.md`
- Deployment: `docs/doc-center/04-Kuscia/kuscia-kuscia_deployment_instructions.md`
- Design docs: `docs/doc-center/04-Kuscia/kuscia-设计文档.md`
- DomainData spec: `docs/doc-center/04-Kuscia/kuscia-domaindata_specification.md`
