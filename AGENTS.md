# SFWork — Agent Guide

This guide describes the `sfwork` workspace for AI coding agents. The workspace is a mono-repo-like directory that bundles the four main repositories of the SecretFlow privacy-preserving computing ecosystem. Read this first before touching any code.

> **Documentation language note**: The projects maintain both English and Chinese documentation. The most detailed operation guides (e.g. `无docker运行说明.md`, `运行说明.md`) are in Chinese, while architecture summaries such as `PROJECT_SUMMARY.md` are in English. Code comments are often bilingual.
>
> **Centralized docs**: All project documentation is organized and copied to `docs/doc-center/`. Start with `docs/doc-center/README.md` to find the right document by category.  
> **Agent skills**: Project-level Kimi skills live in `.agents/skills/`. Use them for doc lookup, frontend/backend/Kuscia workflows, and workspace orientation.

---

## 1. Project Overview

`sfwork` is the local development workspace for the SecretFlow stack. It contains four independent but integrated projects:

| Project | Language | Role | Directory |
|---|---|---|---|
| **Kuscia** | Go | Kubernetes-based orchestration engine for federated learning jobs | `kuscia/` |
| **SecretFlow** | Python | Privacy-preserving computation framework (MPC, HEU, SPU, TEE, FL) | `secretflow/` |
| **SecretPad** | Java (Spring Boot) | Web management console backend | `secretpad/` |
| **SecretPad Frontend** | TypeScript / React | Web management console UI | `secretpad/frontend-src/` |

There is also a legacy copy of the frontend at `secretpad-frontend/`, but active development happens in `secretpad/frontend-src/`.

### 1.1 Local Privacy SDKs / Agent

In addition to the four main projects, `sfwork` is accompanied by three standalone local-privacy repositories. They provide masking, K-anonymity, differential privacy, and query obfuscation without requiring a full SecretFlow job:

| Project | Language | Role | Repository |
|---|---|---|---|
| **privacy-java-sdk** | Java 17 | Local SDK for Java/SecretPad backends | [github.com/fengzhizi319/privacy-java-sdk](https://github.com/fengzhizi319/privacy-java-sdk) |
| **privacy-go-sdk** | Go 1.21 | Local SDK for Go microservices | [github.com/fengzhizi319/privacy-go-sdk](https://github.com/fengzhizi319/privacy-go-sdk) |
| **privacy-local-agent** | Python 3.10+ | REST + gRPC Sidecar for multi-language access | [github.com/fengzhizi319/privacy-local-agent](https://github.com/fengzhizi319/privacy-local-agent) |

Clone them next to the `sfwork` root directory when needed; they are ignored by the `sfwork` root repository. Use the Java/Go SDKs when the consuming service is written in the same language and can embed a library. Use the Agent when you need a language-agnostic Sidecar or cannot embed an SDK. See `docs/dp/README.md` for a selection guide.

### How the pieces fit together

```text
SecretPad Frontend (React/Umi, port 8000 dev)
        │  REST /api/v1alpha1/*
        ▼
SecretPad Backend (Spring Boot, ports 8080/8443/9001)
        │  gRPC
        ▼
Kuscia Master/Lite (Go, gRPC port 8083, Envoy ports 80/1080)
        │  schedules pods / DomainData / DomainRoute
        ▼
SecretFlow (Python)  ← executes privacy-preserving algorithms inside containers
```

Data access is mediated by **DataMesh** (part of Kuscia) using gRPC and Apache Arrow Flight.

### 1.2 c-life Privacy Computing Platform

The platform is positioned as a full-stack privacy computing system with three capability layers:

```
Data Ingest → Classification (L1~L5) → Local Privacy Processing → FL / MPC → Audit & Budget
```

- **Classification**: Rule Engine → Small-NER → local VLM/LLM for multimodal medical data.
- **Local Privacy**: Masking, K-anonymity, Differential Privacy, Query Obfuscation.
- **FL / MPC**: Cross-domain collaborative computing with data available but invisible.

The detailed whitepaper and presentation are in `docs/doc-center/00-项目总览/`.

### 1.3 Documentation Center & Agent Skills

| Resource | Path | Purpose |
|---|---|---|
| Centralized docs | `docs/doc-center/README.md` | Categorized archive of all sfwork / frontend / backend / Kuscia docs |
| Project whitepaper | `docs/doc-center/00-项目总览/数据分类分级与本地隐私原语-团队汇报与落地白皮书.md` | Full-stack privacy computing overview |
| Presentation | `docs/doc-center/00-项目总览/数据分类分级与本地隐私原语-汇报PPT.html` | HTML slide deck |
| Workspace skill | `.agents/skills/sfwork-workspace/SKILL.md` | Workspace orientation and cross-project commands |
| Doc reader skill | `.agents/skills/doc-center-reader/SKILL.md` | How to navigate docs/doc-center |
| Frontend skill | `.agents/skills/secretpad-frontend-dev/SKILL.md` | Frontend development workflow |
| Backend skill | `.agents/skills/secretpad-backend-dev/SKILL.md` | Backend development workflow |
| Kuscia skill | `.agents/skills/kuscia-dev/SKILL.md` | Kuscia development workflow |

---

## 2. Repository Layout

```text
/home/charles/code/sfwork/
├── AGENTS.md                     # this file
├── PROJECT_SUMMARY.md            # high-level English architecture summary
├── 项目总结.md                    # high-level Chinese architecture summary
├── 无docker运行说明.md            # Chinese non-Docker runbook
├── scripts/run-all-no-docker.sh  # one-script launcher for local dev
├── .local-kuscia/                # Kuscia runtime home (created at runtime)
├── logs/                         # aggregated logs from run-all-no-docker.sh
├── kuscia/                       # Go orchestration engine
├── secretflow/                   # Python privacy-preserving ML framework
├── secretpad/                    # Java backend + frontend-src
├── secretpad-frontend/           # legacy frontend copy (inactive)
├── privacy-java-sdk/             # Java local privacy SDK
├── privacy-go-sdk/               # Go local privacy SDK
└── privacy-local-agent/          # Python REST/gRPC privacy agent
```

---

## 3. Technology Stack

### Kuscia (`kuscia/`)
- **Go 1.24.7**
- Kubernetes CRDs (`k8s.io/* v0.33.5`)
- gRPC / Protocol Buffers
- Gin (internal HTTP), Envoy (gateway), CoreDNS (service discovery)
- containerd / runc / K3s (embedded control plane)
- Apache Arrow Flight (DataMesh I/O)
- Zap / custom `nlog` logger, Viper for config

### SecretFlow (`secretflow/`)
- **Python 3.10 / 3.11**
- JAX, NumPy, pandas, scikit-learn
- SPU, HEU, sf-sml, secretflow-spec, secretflow-dataproxy (ecosystem packages)
- PyArrow, DuckDB, gRPC
- Build: `pdm-backend`, PEP 517 wheel

### SecretPad (`secretpad/`)
- **Java 17**
- **Spring Boot 3.3.5**
- Spring Data JPA + Hibernate, SQLite default, MySQL optional
- Flyway migrations
- gRPC 1.62.2 + Protobuf 3.25.5
- Quartz scheduling, Ehcache 3
- Maven multi-module project

### SecretPad Frontend (`secretpad/frontend-src/`)
- **Node.js >= 16.14.0**, **pnpm 8.8.0**
- **React 18**, **Umi 4**, **Ant Design 5**
- **TypeScript 4.9**
- **Valtio** for state management
- Nx monorepo, tsup for shared packages
- Jest + React Testing Library

---

## 4. Build & Test Commands

### 4.1 Kuscia

```bash
cd /home/charles/code/sfwork/kuscia

# Build the kuscia binary
make build
# or
bash hack/build.sh -t kuscia

# Build the standalone transport binary
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

### 4.2 SecretFlow

```bash
cd /home/charles/code/sfwork/secretflow

# Editable install
pip install -e .

# Install dev extras
pdm install -G dev

# Build wheel
python -m build --wheel
# or
pdm build

# Compile extended protobufs (protoc 3.19.6)
~/protoc-3.19.6/bin/protoc \
  --proto_path secretflow/protos/ \
  --python_out . \
  secretflow/protos/secretflow/spec/extend/*.proto

# Run tests
python -m pytest tests/ -v                    # simulation mode
python -m pytest tests/ --env=prod -v         # MPC/prod mode
```

### 4.3 SecretPad Backend

```bash
cd /home/charles/code/sfwork/secretpad

# Run tests
mvn clean test

# Build backend jar (skip tests)
mvn clean package -DskipTests -Dfile.encoding=UTF-8
# fat jar is produced at target/secretpad.jar

# Full build with frontend assets
./scripts/build/build.sh true

# Docker image
make image

# Package all-in-one tar.gz
make pack platform="linux/amd64"
```

### 4.4 SecretPad Frontend

```bash
cd /home/charles/code/sfwork/secretpad/frontend-src

# Install dependencies and build shared packages
pnpm bootstrap

# Dev server (http://localhost:8000)
pnpm --filter secretpad dev

# Build
pnpm --filter secretpad build

# Test
pnpm --filter secretpad test

# Lint / format
pnpm --filter secretpad lint:js
pnpm --filter secretpad lint:css
pnpm --filter secretpad lint:typing
pnpm fix
pnpm format-all
```

---

## 5. Code Organization

### Kuscia
| Directory | Purpose |
|---|---|
| `cmd/kuscia/` | CLI entry point and module initializers |
| `pkg/agent/` | Kubelet-like agent, pod lifecycle, CRI |
| `pkg/controllers/` | CRD controllers (job, task, domain, route, domaindata, GC, ...) |
| `pkg/kusciaapi/` | External HTTP/gRPC API server |
| `pkg/datamesh/` | DataMesh HTTP/gRPC + Arrow Flight |
| `pkg/gateway/` | Envoy xDS control plane, domain route, handshake |
| `pkg/confmanager/` | Certificate & config management |
| `pkg/transport/` | Standalone transport service |
| `pkg/scheduler/` | Scheduler plugins |
| `pkg/web/` | Internal Gin + gRPC web framework |
| `pkg/utils/` | Shared utilities, `nlog`, TLS helpers |
| `pkg/crd/` | Generated Go types, clientset, informers, listers |
| `crds/v1alpha1/` | CRD YAML manifests |
| `proto/api/v1alpha1/` | Protobuf definitions |
| `scripts/deploy/` | Docker deployment scripts |
| `scripts/run_local_kuscia.sh` | Non-Docker local master runner |

### SecretFlow
| Directory | Purpose |
|---|---|
| `secretflow/device/` | `PYU`, `SPU`, `HEU`, `TEEU` devices |
| `secretflow/data/` | Horizontal/vertical/mixed FedDataFrames, FedNdarray |
| `secretflow/ml/` | FL/SL algorithms |
| `secretflow/component/` | Pipeline/component system |
| `secretflow/preprocessing/` | Binning, encoding, scaling |
| `secretflow/stats/` | Statistics and evaluation |
| `secretflow/privacy/` | Differential privacy, k-anonymity |
| `secretflow/security/` | Secure aggregation/comparison |
| `secretflow/kuscia/` | Kuscia task entry point and DataMesh client |
| `secretflow/protos/` | Source `.proto` files |
| `secretflow/spec/extend/` | Generated Python protobuf bindings |
| `tests/` | pytest suite, custom MPC test runner |

### SecretPad Backend
Multi-module Maven project under `org.secretflow.secretpad.*`:

| Module | Responsibility |
|---|---|
| `secretpad-common` | Utilities, exceptions, enums, constants |
| `secretpad-persistence` | JPA entities (`*DO`), repositories, Flyway, data sync |
| `secretpad-manager` | Integration managers (Kuscia, data, node, job, serving) |
| `secretpad-service` | Business logic, DTOs/VOs, DAG graph building |
| `secretpad-scheduled` | Quartz scheduled jobs |
| `secretpad-api` | Generated gRPC clients (`client-java-kusciaapi`) |
| `secretpad-web` | Spring Boot main app, controllers, filters, interceptors |
| `test` | Aggregate Jacoco coverage |

REST controllers live under `/api/v1alpha1/`. Config YAMLs are at `config/` (not under `src/main/resources`).

### SecretPad Frontend
pnpm/Nx monorepo:

| Directory | Purpose |
|---|---|
| `apps/platform/` | Main SecretPad web app |
| `apps/docs/` | Dumi documentation site |
| `packages/dag/` | `@secretflow/dag` DAG graph engine |
| `packages/utils/` | `@secretflow/utils` shared utilities |
| `tooling/eslint/` | Shared ESLint config |
| `tooling/stylelint/` | Shared Stylelint config |
| `tooling/tsconfig/` | Shared TypeScript configs |
| `tooling/jest/` | Shared Jest config |
| `tooling/tsup/` | Shared tsup config |

---

## 6. Code Style Guidelines

### Kuscia (Go)
- Run `make fmt` (`go fmt ./...`) before committing.
- Imports grouped with `local-prefixes: github.com/secretflow/kuscia` (golangci-lint).
- Every file must have an Apache-2.0 license header.
- Use `pkg/errors` style wrapping; web layer uses `pkg/web/errorcode.Errs` for validation.
- Prefer constructors + interfaces for dependency injection.
- Table-driven tests with `testify` and `gomock`/`go.uber.org/mock`.
- Pre-commit hooks: gitleaks, golangci-lint, shellcheck, trailing-whitespace.

### SecretFlow (Python)
- Format with **Black** (line length 88, target py310).
- Sort imports with **isort** (`profile = "black"`).
- Use type hints widely; mypy is configured but not strict.
- Docstrings are often Numpy-style and bilingual.
- Every file starts with an Apache-2.0 Ant Group copyright header.

### SecretPad Backend (Java)
- Java 17 syntax; Lombok is enabled.
- Package naming: `org.secretflow.secretpad.<module>.<feature>`.
- Entities suffix `DO` (e.g. `ProjectDO`); repositories extend `BaseRepository`.
- Service implementations go in `impl/` packages.
- Controllers are `@RestController` under `/api/v1alpha1/`.
- DTOs use Lombok `@Builder`, `@Getter`, `@Setter`, `@ToString`.
- All files start with an Apache-2.0 license header.

### SecretPad Frontend (TypeScript/React)
- **Prettier**: printWidth 88, singleQuote, trailingComma all.
- **ESLint**: `@secretflow/config-eslint` + project root overrides.
- **Stylelint**: for `.less` files.
- Conventional Commits enforced by Husky/commitlint.
- lint-staged runs prettier, stylelint, eslint on commit.
- State management uses Valtio via `src/util/valtio-helper.ts` (not Dva).

---

## 7. Testing Instructions

### Kuscia
```bash
make test                                      # unit tests
make integration_test TEST_SUITE=center.base   # integration suite
make integration_test TEST_SUITE=all
```
Unit tests use `testify`, `gomock`, `gomonkey`, `go-sqlmock`, Kubernetes fake clients.

### SecretFlow
```bash
python -m pytest tests/ -v                     # sim mode
python -m pytest tests/ --env=prod -v          # MPC mode
python -m pytest tests/ -n auto --env=prod     # parallel
```
MPC tests marked `@pytest.mark.mpc(parties=[...])` are executed in spawned child processes. Configuration fixtures are in `tests/conftest.py`, `tests/sf_fixtures.py`, `tests/sf_config.py`.

### SecretPad Backend
```bash
mvn clean test
mvn test -pl secretpad-web -Dtest=ProjectControllerTest
```
Tests use JUnit 5, Mockito, Spring Boot Test. The `test` profile disables auth and uses SQLite/H2. `ControllerTest` runs `scripts/test/setup.sh` before all tests to generate certificates.

### SecretPad Frontend
```bash
pnpm test
pnpm --filter secretpad test
pnpm --filter @secretflow/utils test
pnpm --filter @secretflow/dag test
```
Jest config uses `ts-jest`, `jsdom`, `identity-obj-proxy` for CSS/Less/SVG.

---

## 8. Runtime Architecture & Ports

### Non-Docker local development (`run-all-no-docker.sh`)
The script at `/home/charles/code/sfwork/scripts/run-all-no-docker.sh` boots everything in this order:

1. Activate conda env `sf310` and build/install local SecretFlow (`pip install -e ./secretflow`)
2. Build Kuscia binary (`kuscia/hack/build.sh -t kuscia`)
3. Start Kuscia Master via `kuscia/scripts/run_local_kuscia.sh` master (requires sudo for ports 53/80)
4. Build SecretPad backend (`mvn clean install -Dmaven.test.skip=true`)
5. Generate certificates (`secretpad/scripts/test/setup.sh`)
6. Start SecretPad backend
7. Start SecretPad frontend

Default local ports:

| Service | Port | Notes |
|---|---|---|
| SecretPad frontend dev server | 8000 | Umi dev, proxies `/api` to backend |
| SecretPad backend HTTP | 8080 | Spring Boot `server.http-port` |
| SecretPad backend HTTPS | 8443 | Spring Boot `server.port` |
| SecretPad inner API | 9001 | `server.http-port-inner` |
| Kuscia API gRPC | 8083 | internal, non-Docker mode |
| Kuscia Envoy internal | 80 | non-Docker mode |
| CoreDNS | 53 | requires root |

Dev login: `admin` / `12345678`.

### Local development with Docker Kuscia

When Kuscia master + alice + bob are running via local Docker with host port mappings (as in the current setup), use these connection parameters for SecretPad backend:

| Env Var | Value | Notes |
|---|---|---|
| `KUSCIA_API_ADDRESS` | `127.0.0.1` | Kuscia API gRPC host |
| `KUSCIA_API_PORT` | `18083` | Mapped from container port 8083 |
| `KUSCIA_GW_ADDRESS` | `127.0.0.1:13081` | Mapped from container Envoy port 80/1080 |
| `KUSCIA_PROTOCOL` | `notls` | Dev profile, no mTLS |

Backend data path should point to the host bind mount of Kuscia master data, e.g.:

```bash
-Dsecretpad.data.dir-path=/home/charles/kuscia/master/data/
```

The startup helper `scripts/dev-start.sh` sets this automatically.

### Key Kuscia ports (Docker deployment)
| Service | Default Port |
|---|---|
| KusciaAPI HTTP external | 8082 |
| KusciaAPI gRPC | 8083 |
| KusciaAPI HTTP internal | 8092 |
| DataMesh HTTP | 8070 |
| DataMesh gRPC | 8071 |
| ConfManager HTTP | 8060 |
| ConfManager gRPC | 8061 |
| Reporter HTTP | 8050 |
| Transport gRPC | 9090 |
| Gateway public | 1080 |
| Gateway internal | 80 |

---

## 9. Deployment Processes

### Docker (production)
- **Kuscia**: `scripts/deploy/start_standalone.sh center|p2p|cxc|cxp`, or `scripts/deploy/deploy.sh master|lite|autonomy ...`.
- **SecretFlow**: release/dev/GPU Docker images under `docker/release/` and `docker/dev/`.
- **SecretPad**: `make image` (builds `secretpad.jar` + frontend + Anolis image).
- **All-in-one offline package**: `secretpad/scripts/pack/pack_allinone.sh` bundles Kuscia/SecretPad/SecretFlow/Serving/DataProxy/SCQL/TEE images.

### Non-Docker (development)
Use `run-all-no-docker.sh`, or manually:

```bash
# 1. Install local SecretFlow (conda env sf310)
cd /home/charles/code/sfwork/secretflow
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate sf310
pip install -i https://mirrors.aliyun.com/pypi/simple/ kuscia
pip install -e .

# 2. Build Kuscia
cd /home/charles/code/sfwork/kuscia
bash hack/build.sh -t kuscia

# 3. Start Kuscia Master
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
sudo bash scripts/run_local_kuscia.sh master

# 4. Build SecretPad backend
cd /home/charles/code/sfwork/secretpad
mvn clean install -Dmaven.test.skip=true

# 5. Generate certs
rm -f config/server.jks
rm -rf config/certs/
bash scripts/test/setup.sh

# 6. Start SecretPad backend (adjust ports for Docker Kuscia vs non-Docker)
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083      # use 8083 for non-Docker Kuscia
export KUSCIA_GW_ADDRESS=127.0.0.1:13081  # use 127.0.0.1:80 for non-Docker
export KUSCIA_PROTOCOL=notls
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -Dsecretpad.data.dir-path=/home/charles/kuscia/master/data/ \
     -jar target/secretpad.jar

# 7. Start SecretPad frontend
cd /home/charles/code/sfwork/secretpad/frontend-src
echo "PROXY_URL=http://127.0.0.1:8080" > apps/platform/.env
pnpm bootstrap
pnpm --filter secretpad dev
```

Stop everything with `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop`.

---

## 10. Security Considerations

- **mTLS**: Kuscia uses mTLS for cross-domain communication and KusciaAPI in production. The `dev` profile uses `KUSCIA_PROTOCOL=notls`.
- **Certificates**: `secretpad/scripts/test/setup.sh` generates dev CA/client certs and `config/server.jks`. Never commit these.
- **Authentication**: SecretPad uses a custom `LoginInterceptor` + token DB, not Spring Security.
- **Authorization**: Kuscia uses Casbin; DataMesh enforces domaindata grants.
- **Secrets**: gitleaks runs in Kuscia pre-commit hooks. Do not hard-code passwords, tokens, or cert keys.
- **sudo**: Local Kuscia needs root for CoreDNS port 53. The helper script uses `sudo` internally.
- **Sensitive files**: `.env` for frontend proxy URL is gitignored. Certificates under `config/certs/` and `.local-kuscia/var/certs/` are local-only.

---

## 11. Cross-Project Integration

When modifying code, understand which layer owns the contract:

- **Frontend ↔ Backend**: REST JSON under `/api/v1alpha1/*`. DTOs live in `secretpad-service`.
- **Backend ↔ Kuscia**: gRPC via generated clients in `secretpad-api/client-java-kusciaapi`. Env vars control the connection.
- **Kuscia ↔ SecretFlow**: Kuscia schedules containerized SecretFlow tasks; SecretFlow reads `DomainData` via DataMesh.
- **DataMesh ↔ SecretFlow**: gRPC + Apache Arrow Flight; `secretflow/kuscia/datamesh.py` is the client.
- **Protobuf contracts**: Shared `.proto` files are in `kuscia/proto/` and `secretflow/protos/`. Changing a proto requires regenerating stubs in all consuming languages.

---

## 12. Common Development Workflow

1. **Start from the root**: `/home/charles/code/sfwork`.
2. **Choose a launcher**:
   - Non-Docker all-in-one: `bash scripts/run-all-no-docker.sh`
   - Docker Kuscia + local backend/frontend: `bash scripts/dev-start.sh`
3. **Make backend changes**: `cd secretpad && mvn clean install -Dmaven.test.skip=true`, restart backend.
4. **Make frontend changes**: `cd secretpad/frontend-src && pnpm --filter secretpad dev` supports hot reload.
5. **Make Kuscia changes**: `cd kuscia && bash hack/build.sh -t kuscia`, then restart Kuscia Master.
6. **Run tests** in the relevant subproject before committing.
7. **Check logs**: `logs/kuscia-master.log`, `logs/backend.log`, `logs/frontend.log`, plus per-project log directories.

---

## 13. Quick Reference

| Goal | Command |
|---|---|
| Build Kuscia | `cd kuscia && make build` |
| Test Kuscia | `cd kuscia && make test` |
| Build SecretFlow wheel | `cd secretflow && python -m build --wheel` |
| Test SecretFlow | `cd secretflow && python -m pytest tests/ --env=prod -v` |
| Build SecretPad jar | `cd secretpad && mvn clean package -DskipTests` |
| Test SecretPad | `cd secretpad && mvn clean test` |
| Build SecretPad image | `cd secretpad && make image` |
| Bootstrap frontend | `cd secretpad/frontend-src && pnpm bootstrap` |
| Dev frontend | `cd secretpad/frontend-src && pnpm --filter secretpad dev` |
| Run all locally (non-Docker) | `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh` |
| Stop all locally (non-Docker) | `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop` |
| Start with Docker Kuscia | `bash /home/charles/code/sfwork/scripts/dev-start.sh` |
| Stop Docker Kuscia setup | `bash /home/charles/code/sfwork/scripts/dev-start.sh --stop` |
| Test privacy-java-sdk | `cd privacy-java-sdk && mvn test` |
| Test privacy-go-sdk | `cd privacy-go-sdk && go test ./...` |
| Test privacy-local-agent | `cd privacy-local-agent && PYTHONPATH=. pytest tests -q` |
