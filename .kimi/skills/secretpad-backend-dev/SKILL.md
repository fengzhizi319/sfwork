---
name: secretpad-backend-dev
description: Develop the SecretPad backend. Use when the user asks about Java/Spring Boot code, REST APIs, JPA entities, repositories, service logic, Kuscia API integration, DataMesh integration, database migrations, or backend build/test.
---

# SecretPad Backend Development

SecretPad backend is a Spring Boot 3.3.5 multi-module Maven project.

## Stack

- Java 17
- Spring Boot 3.3.5, Spring Data JPA + Hibernate
- SQLite default, MySQL optional
- Flyway migrations
- gRPC 1.62.2 + Protobuf 3.25.5
- Quartz scheduling, Ehcache 3

## Module Structure

```
secretpad/
├── secretpad-common/       # Utilities, exceptions, enums
├── secretpad-persistence/  # JPA entities (*DO), repositories, Flyway
├── secretpad-manager/      # Integration managers (Kuscia, data, node, job)
├── secretpad-service/      # Business logic, DTOs/VOs, DAG building
├── secretpad-scheduled/    # Quartz jobs
├── secretpad-api/          # Generated gRPC clients
├── secretpad-web/          # Spring Boot main app, controllers
└── config/                 # Config files (not under resources)
```

## Key Commands

```bash
cd secretpad

# Run tests
mvn clean test

# Build jar (skip tests)
mvn clean package -DskipTests -Dfile.encoding=UTF-8

# Full build with frontend assets
./scripts/build/build.sh true

# Docker image
make image

# Generate dev certs
bash scripts/test/setup.sh
```

## Conventions

- Package: `org.secretflow.secretpad.<module>.<feature>`
- Entities suffix `DO` (e.g., `ProjectDO`)
- Repositories extend `BaseRepository`
- Service implementations in `impl/` packages
- Controllers are `@RestController` under `/api/v1alpha1/`
- DTOs use Lombok `@Builder`, `@Getter`, `@Setter`, `@ToString`
- All files start with Apache-2.0 header

## Critical Integration

- **Kuscia API**: `secretpad-api/client-java-kusciaapi/`
- **Env vars**: `KUSCIA_API_ADDRESS`, `KUSCIA_API_PORT`, `KUSCIA_GW_ADDRESS`, `KUSCIA_PROTOCOL`
- **Data dir**: `-Dsecretpad.data.dir-path=$HOME/kuscia/master/data/`

## Running Locally

```bash
export KUSCIA_API_ADDRESS=127.0.0.1
export KUSCIA_API_PORT=18083
export KUSCIA_GW_ADDRESS=127.0.0.1:13081
export KUSCIA_PROTOCOL=notls
java -Dspring.profiles.active=dev \
     -Dsun.net.http.allowRestrictedHeaders=true \
     -Dserver.port=8443 \
     -Dsecretpad.data.dir-path=/home/charles/kuscia/master/data/ \
     -jar target/secretpad.jar
```

## Important References

- Backend design: `docs/doc-center/03-后端开发/secretpad-SecretPad设计文档.md`
- Kuscia integration: `docs/doc-center/03-后端开发/secretpad-api_and_kuscia_datamesh_integration.md`
- Storage: `docs/doc-center/03-后端开发/secretpad-SecretPad存储说明.md`
