---
name: sfwork-workspace
description: Work in the sfwork mono-repo workspace containing Kuscia, SecretFlow, SecretPad backend, and SecretPad frontend. Use for any task that spans multiple sub-projects, needs environment setup, build/test commands, or cross-project integration. Also use when the user asks about the overall workspace structure, ports, or how to run everything locally.
---

# SFWork Workspace

The sfwork workspace bundles four main projects: Kuscia (Go), SecretFlow (Python), SecretPad backend (Java/Spring Boot), and SecretPad frontend (TypeScript/React/Vite).

## Workspace Layout

```
sfwork/
├── kuscia/                 # Go orchestration engine
├── secretflow/             # Python privacy-preserving ML framework
├── secretpad/              # Java backend + web/ frontend (active)
├── privacy-java-sdk/       # Java local privacy SDK
├── privacy-go-sdk/         # Go local privacy SDK
├── privacy-local-agent/    # Python REST/gRPC privacy agent
├── deploy/                 # Docker Compose deployment
├── scripts/                # Dev scripts (run-all-no-docker.sh, etc.)
├── scripts1/               # Secondary copy of dev scripts
├── docs/doc-center/        # Centralized documentation archive
└── AGENTS.md               # Agent guide for this workspace
```

## Critical Environment

- **Python**: conda env `sf310`, Python 3.10
- **Node.js**: >= 18.0.0, pnpm >= 8.8.0
- **Java**: 17
- **Go**: 1.24.7
- **Frontend dev**: `http://localhost:8000`
- **Backend**: `https://localhost:8443`, HTTP `http://localhost:8080`, inner `http://localhost:9001`
- **Kuscia API gRPC**: `127.0.0.1:18083`
- **Kuscia Gateway**: `127.0.0.1:13081`
- **Login**: `admin` / `12345678`

## Key Commands

```bash
# Start Docker-Kuscia + local SecretPad backend/frontend
bash scripts1/dev-start.sh

# Stop local services (Java backend + Vite frontend)
bash scripts1/dev-stop.sh

# Stop local services + Kuscia Docker
bash scripts1/dev-stop.sh --kuscia

# Run all locally (non-Docker)
bash scripts/run-all-no-docker.sh

# Stop all (non-Docker)
bash scripts/run-all-no-docker.sh --stop

# Build Kuscia
cd kuscia && make build

# Build SecretFlow
cd secretflow && pip install -e .

# Build SecretPad backend
cd secretpad && mvn clean package -DskipTests

# Install frontend dependencies
cd secretpad/web && corepack pnpm install

# Dev frontend
cd secretpad/web && corepack pnpm --filter @secretpad/app dev
```

## Port Conflict Notes

- `scripts1/dev-start.sh` starts the Java SecretPad backend on port 8080 and the Vite dev server on port 8000.
- If another process is already listening on 8080, the script will fail with "端口 8080 被其他进程占用". Kill the conflicting process before starting.
- Use `lsof -i :8080` and `lsof -i :8000` to identify conflicting processes.

## Cross-Project Contracts

- **Frontend ↔ Backend**: REST JSON under `/api/v1alpha1/*` (plus `/api/login`, `/api/logout`)
- **Backend ↔ Kuscia**: gRPC via `secretpad-api/client-java-kusciaapi`
- **Kuscia ↔ SecretFlow**: Kuscia schedules containers; SecretFlow reads DomainData via DataMesh
- **DataMesh ↔ SecretFlow**: gRPC + Apache Arrow Flight

## Workflow

1. Check `AGENTS.md` and `docs/doc-center/README.md` for context.
2. Identify which sub-project owns the change.
3. Make changes, build/test in the relevant sub-project.
4. For frontend/backend integration, restart both services.
5. For Kuscia changes, rebuild the Kuscia binary and restart.

## Safety

- Do not run `git commit/push/reset/rebase` unless explicitly asked.
- Do not modify files outside the working directory.
- Local Kuscia may need `sudo` for ports 53/80.
