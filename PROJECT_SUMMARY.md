# SFWork Project Summary

This document provides an overview of the projects within the sfwork workspace, including their programming languages and common programming techniques.

## Projects Overview

### 1. Kuscia
**Description**: Kuscia is the underlying orchestration engine for the SecretFlow ecosystem. It serves as the runtime infrastructure that manages distributed computing tasks, data assets, and inter-party communication in federated learning scenarios. It uses Kubernetes CRDs (Custom Resource Definitions) for managing jobs, tasks, and data assets.

**Primary Language**: Go

**Key Components**:
- Agent: Handles communication with Kubernetes API server
- Controllers: Manages CRDs like KusciaJob, KusciaTask, DomainData
- DataMesh: Provides data access and authorization layer
- Gateway: Manages inter-domain communication
- KusciaAPI: Provides gRPC/REST APIs for external systems

**Common Programming Techniques**:
- **Kubernetes Controller Pattern**: Uses informers and workqueues to watch for resource changes and reconcile desired state
- **Dependency Injection**: Uses constructors and interfaces for loose coupling
- **Error Handling**: Comprehensive error wrapping with stack traces using pkg/errors
- **Logging**: Structured logging with Zap logger
- **Configuration Management**: Uses viper for configuration handling
- **gRPC Services**: Implements services for inter-component communication
- **CRD Management**: Defines and manages custom Kubernetes resources
- **Security**: Implements mTLS authentication and authorization
- **Testing**: Extensive use of table-driven tests and mocking with gomock

### 2. SecretFlow
**Description**: SecretFlow is a unified framework for privacy-preserving computation. It enables secure multi-party computation (MPC), homomorphic encryption (HE), and trusted execution environments (TEE) to perform joint analysis and modeling without exposing raw data.

**Primary Language**: Python

**Key Components**:
- Component: Building blocks for privacy-preserving algorithms
- Compute: Distributed computing infrastructure
- Data: Data handling and preprocessing modules
- Device: Abstraction layer for different computing devices (SPU, HEU, etc.)
- ML: Machine learning algorithms adapted for privacy preservation
- Kuscia Integration: Adapters for orchestrating with Kuscia

**Common Programming Techniques**:
- **Functional Programming**: Heavy use of functional patterns for data transformations
- **Type Hints**: Extensive use of Python type annotations
- **Context Managers**: Resource management using 'with' statements
- **Decorators**: Custom decorators for logging, validation, and performance monitoring
- **Protocol Buffers**: Used for serialization and inter-process communication
- **JAX**: Numerical computing library for machine learning operations
- **Dependency Injection**: Configuration and service management
- **Async/Await**: Asynchronous programming for I/O operations
- **Testing**: Unit tests using pytest with fixtures and parameterized tests

### 3. SecretPad
**Description**: SecretPad is the web-based management console for the SecretFlow ecosystem. It provides a user-friendly interface for data management, federated learning task creation, and result visualization. It handles business logic, persistence, and communication with Kuscia.

**Primary Language**: Java

**Key Components**:
- API Layer: RESTful APIs for frontend communication
- Service Layer: Business logic and workflow orchestration
- Persistence Layer: Database interactions and entity management
- Manager Layer: Domain-specific operations and validation
- Web Layer: Controller layer for request handling
- Common: Shared utilities, enums, and constants

**Common Programming Techniques**:
- **Spring Framework**: Dependency injection, transaction management, and MVC architecture
- **MyBatis**: SQL mapping and database interaction
- **Spring Boot**: Auto-configuration and embedded server capabilities
- **MVC Pattern**: Clear separation of concerns between models, views, and controllers
- **Exception Handling**: Custom exception hierarchy with global exception handler
- **Validation**: Bean validation with JSR-303 annotations
- **Configuration Properties**: Type-safe configuration properties
- **Transaction Management**: Declarative transaction handling with @Transactional
- **Security**: Authentication and authorization mechanisms
- **Testing**: Unit and integration testing with JUnit and Mockito

### 4. SecretPad Frontend
**Description**: The frontend component of SecretPad built with modern web technologies. It provides an intuitive user interface for managing privacy-preserving computations, visualizing data flows, and monitoring job progress.

**Primary Languages**: TypeScript, JavaScript

**Key Technologies**:
- **React**: Component-based UI architecture
- **Umi**: Pluggable enterprise-level React application framework
- **Ant Design**: Enterprise-class UI design system
- **ESLint/Stylelint**: Code quality and style enforcement
- **Husky/Lint-staged**: Git hooks for code quality
- **Nx**: Monorepo management

**Common Programming Techniques**:
- **Component-Based Architecture**: Reusable and modular UI components
- **Hooks**: State management and side effects with React hooks
- **TypeScript**: Static type checking for improved code reliability
- **State Management**: Context API and potential Redux/Zustand for global state
- **Asynchronous Operations**: Promise/async-await for API calls
- **Module Bundling**: ES modules and tree shaking for optimization
- **Testing**: Jest and React Testing Library for unit and integration tests
- **Form Handling**: Form libraries for data collection and validation
- **Internationalization**: Multi-language support

### 5. DataMesh
**Description**: DataMesh is the data access and authorization layer within the Kuscia ecosystem. It abstracts underlying data sources and provides secure access controls for federated learning scenarios. It manages DomainData, DomainDataSource, and DomainDataGrant resources.

**Primary Language**: Go (as part of Kuscia project)

**Key Components**:
- MetaServer: Centralized metadata management
- DomainData Service: Data asset management
- DomainDataSource Service: Data source registration and connection
- Operator: Kubernetes operator for CRD management

**Common Programming Techniques**:
- **Microservices Architecture**: Service-oriented design principles
- **API-First Design**: Well-defined contracts using Protocol Buffers
- **Authentication & Authorization**: RBAC and fine-grained access control
- **Data Validation**: Input sanitization and schema validation
- **Event-Driven Architecture**: Reacting to resource changes in Kubernetes
- **Connection Pooling**: Efficient resource management for data sources
- **Caching**: Performance optimization for frequently accessed metadata
- **Monitoring**: Metrics collection and health checks

## Architecture Integration

The projects work together in the following way:

1. **Frontend (TypeScript/React)** communicates with **SecretPad Backend (Java)**
2. **SecretPad Backend (Java)** orchestrates with **Kuscia (Go)** via APIs
3. **Kuscia (Go)** manages the execution environment and coordinates with **SecretFlow (Python)**
4. **SecretFlow (Python)** performs actual privacy-preserving computations
5. **DataMesh (Go)** provides secure data access across domains

## Common Cross-Project Patterns

- **gRPC Communication**: Standardized inter-service communication
- **Protocol Buffers**: Consistent data serialization across languages
- **Containerization**: Docker-based deployment across all components
- **Kubernetes Orchestration**: Platform for deployment and scaling
- **Observability**: Logging, metrics, and tracing across the stack
- **Security**: End-to-end encryption and authentication mechanisms
- **CI/CD**: Automated testing and deployment pipelines
- **Documentation**: Comprehensive API and architecture documentation