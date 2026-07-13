# SecretPad 数据层详解

本文档系统介绍 SecretPad 的数据层实现，包括数据库选型与配置、JPA/Hibernate 持久化、连接池、Flyway 数据库迁移、缓存机制、事务管理、数据备份与 MySQL 迁移等内容。

---

## 1. 数据层整体架构

SecretPad 采用 **Spring Data JPA + Hibernate** 作为 ORM 层，默认使用 **SQLite** 作为业务数据库，**H2** 作为 Quartz 定时任务存储。缓存方面使用 **EhCache 3（JCache/JSR-107）**，项目中**没有使用 Redis**。

```
┌─────────────────────────────────────────────────────────────┐
│                        SecretPad 服务层                       │
│                  Service / Manager / Controller               │
└─────────────────────────┬───────────────────────────────────┘
                          │ @Transactional / Repository / Cache
┌─────────────────────────▼───────────────────────────────────┐
│              Spring Data JPA + Hibernate                      │
│  • Entity / Repository / Specification / Native Query        │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼──────┐  ┌───────▼──────┐  ┌──────▼─────┐
│   SQLite     │  │      H2      │  │   EhCache  │
│ 业务数据库    │  │ Quartz 任务库 │  │  本地缓存   │
│ secretpad    │  │ secretpadQuartz│  │ 堆外缓存    │
│ .sqlite      │  │ .mv.db       │  │            │
└──────────────┘  └──────────────┘  └────────────┘
```

---

## 2. 数据库选型与配置

### 2.1 默认数据库：SQLite

SecretPad 默认使用 **SQLite** 文件数据库，适合单机、快速部署的场景。配置位于 `config/application.yaml`：

```yaml
spring:
  jpa:
    database-platform: org.hibernate.community.dialect.SQLiteDialect
    show-sql: false
    open-in-view: false
  datasource:
    default:
      driver-class-name: org.sqlite.JDBC
      jdbc-url: jdbc:sqlite:./db/secretpad.sqlite
```

SQLite 数据库文件默认存放在 `./db/` 目录：

```text
./db/
├── secretpad.sqlite
├── secretpad.sqlite-shm
└── secretpad.sqlite-wal
```

> 注：启动时 `PersistenceConfiguration` 会执行 `PRAGMA journal_mode=WAL;`，开启 WAL 模式以提升并发读取性能。因此备份时必须同时复制 `.sqlite`、`.sqlite-shm`、`.sqlite-wal` 三个文件。

### 2.2 Quartz 任务库：H2

Quartz 使用独立的 **H2** 数据库存储任务、触发器、执行状态：

```yaml
spring:
  quartz:
    job-store-type: jdbc
    jdbc:
      initialize-schema: never
  datasource:
    quartz:
      driver-class-name: org.h2.Driver
      jdbc-url: jdbc:h2:./db/secretpadQuartz.mv.db;DB_CLOSE_ON_EXIT=FALSE
      username: sa
      password: password
```

### 2.3 可选数据库：MySQL

SecretPad 也支持 MySQL，但需要手动切换配置。`config/application.yaml` 中提供了注释掉的示例：

```yaml
#  jpa:
#    database-platform: org.hibernate.dialect.MySQLDialect
#  datasource:
#    driver-class-name: com.mysql.cj.jdbc.Driver
#    url: your mysql url
#    username:
#    password:
#    hikari:
#      idle-timeout: 60000
#      maximum-pool-size: 10
#      connection-timeout: 5000
```

MySQL 建表语句位于 `config/schemamysql/create_table.sql`，示例数据位于 `config/schemamysql/insert.sql`。SQLite 迁移到 MySQL 的详细步骤见 `docs/development/SUPPORT_MYSQL.md`。

### 2.4 不同部署模式的数据库配置

| Profile | 配置文件 | Flyway 迁移位置 | 说明 |
|---|---|---|---|
| CENTER（默认） | `config/application.yaml` | `filesystem:./config/schema/center` | 中心节点 |
| EDGE | `config/application-edge.yaml` | `filesystem:./config/schema/edge` | 边缘节点 |
| P2P / AUTONOMY | `config/application-p2p.yaml` | `filesystem:./config/schema/p2p` | 自治节点 |
| DEV | `config/application-dev.yaml` | 同 center | 本地开发 |
| TEST | `config/application-test.yaml` | 同 center | 测试 |

---

## 3. 数据源与连接池

### 3.1 双数据源配置

`secretpad-persistence/src/main/java/org/secretflow/secretpad/persistence/configuration/DataSourceConfig.java` 定义了两个 `HikariDataSource`：

```java
@Configuration
public class DataSourceConfig {

    @Primary
    @Bean(name = "defaultDataSource")
    @ConfigurationProperties("spring.datasource.default")
    public DataSource defaultDataSource() {
        HikariDataSource hikariDataSource = DataSourceBuilder.create().type(HikariDataSource.class).build();
        hikariDataSource.setMaximumPoolSize(1);   // SQLite 单写约束
        hikariDataSource.setMinimumIdle(1);
        hikariDataSource.setConnectionTimeout(20000);
        hikariDataSource.setIdleTimeout(60000);
        return hikariDataSource;
    }

    @Bean(name = "quartzDataSource")
    @ConfigurationProperties("spring.datasource.quartz")
    public DataSource quartzDataSource() {
        HikariDataSource hikariDataSource = DataSourceBuilder.create().type(HikariDataSource.class).build();
        hikariDataSource.setMaximumPoolSize(100);
        hikariDataSource.setMinimumIdle(10);
        hikariDataSource.setConnectionTimeout(20000);
        hikariDataSource.setIdleTimeout(60000);
        return hikariDataSource;
    }
}
```

### 3.2 连接池参数说明

| 参数 | 默认值（default） | 默认值（quartz） | 说明 |
|---|---|---|---|
| `MaximumPoolSize` | 1 | 100 | SQLite 为避免写冲突强制设为 1；H2 Quartz 可支持大量任务 |
| `MinimumIdle` | 1 | 10 | 最小空闲连接 |
| `ConnectionTimeout` | 20000 ms | 20000 ms | 获取连接最大等待时间 |
| `IdleTimeout` | 60000 ms | 60000 ms | 空闲连接回收时间 |

### 3.3 JdbcTemplate

同时暴露了两个 `JdbcTemplate` Bean，方便执行原生 SQL：

```java
@Bean
public JdbcTemplate jdbcTemplate(@Qualifier("defaultDataSource") DataSource dataSource) {
    return new JdbcTemplate(dataSource);
}

@Bean
public JdbcTemplate quartzJdbcTemplate(@Qualifier("quartzDataSource") DataSource dataSource) {
    return new JdbcTemplate(dataSource);
}
```

---

## 4. JPA / Hibernate 持久化

### 4.1 配置类

`PersistenceConfiguration.java` 负责扫描实体与仓库，并在启动时初始化 SQLite WAL 模式：

```java
@EntityScan(basePackages = "org.secretflow.secretpad.persistence.*")
@EnableJpaRepositories(basePackages = {"org.secretflow.secretpad.persistence.*"})
@Configuration
public class PersistenceConfiguration {
    @Bean
    public DataSourceInitializer dataSourceInitializer(@Qualifier("defaultDataSource") DataSource dataSource) {
        ...
        statement.execute("PRAGMA journal_mode=WAL;");
    }
}
```

### 4.2 实体基类

所有业务实体继承 `BaseAggregationRoot`，提供：

- 软删除标记 `is_deleted`
- 创建/修改时间 `gmt_create` / `gmt_modified`
- 数据同步监听器 `EntityChangeListener`（用于 P2P/EDGE 模式下的数据同步）

```java
@Entity
@Table(name = "project")
@SQLDelete(sql = "update project set is_deleted = 1 where project_id = ?")
@Where(clause = "is_deleted = 0")
public class ProjectDO extends BaseAggregationRoot<ProjectDO> {
    @Id
    @Column(name = "project_id", unique = true, nullable = false, length = 64)
    private String projectId;
    ...
}
```

### 4.3 主要实体清单

| 领域 | 实体 |
|---|---|
| 认证 | `AccountsDO`、`TokensDO` |
| 机构/节点 | `InstDO`、`NodeDO`、`NodeRouteDO`、`NodeRouteApprovalConfigDO` |
| 项目 | `ProjectDO`、`ProjectInfoDO`、`ProjectInstDO`、`ProjectNodeDO` |
| 数据 | `ProjectDatatableDO`、`ProjectFeatureTableDO`、`ProjectFedTableDO`、`FeatureTableDO`、`TeeNodeDatatableManagementDO`、`ProjectReadDataDO` |
| 图/任务 | `ProjectGraphDO`、`ProjectGraphNodeDO`、`ProjectGraphDomainDatasourceDO`、`ProjectGraphNodeKusciaParamsDO`、`ProjectJobDO`、`ProjectTaskDO`、`ProjectJobTaskLogDO` |
| 结果/模型 | `ProjectResultDO`、`ProjectReportDO`、`ProjectModelDO`、`ProjectModelPackDO`、`ProjectModelServingDO` |
| 审批/投票 | `ProjectApprovalConfigDO`、`VoteRequestDO`、`VoteInviteDO` |
| 调度 | `ProjectScheduleDO`、`ProjectScheduleJobDO`、`ProjectScheduleTaskDO` |
| RBAC | `SysResourceDO`、`SysRoleDO`、`SysRoleResourceRelDO`、`SysUserNodeRelDO`、`SysUserPermissionRelDO` |

### 4.4 Repository 模式

所有 Repository 继承自定义的 `BaseRepository`：

```java
@NoRepositoryBean
public interface BaseRepository<T, ID extends Serializable>
        extends JpaRepository<T, ID>, JpaSpecificationExecutor<T>, PagingAndSortingRepository<T, ID> {
}
```

支持 Spring Data 派生查询、`@Query` 原生查询、JPA Criteria、分页与排序。示例：

```java
public interface ProjectJobRepository extends BaseRepository<ProjectJobDO, ProjectJobDO.UPK> {
    @EntityGraph(value = "project_job.all_task")
    @Query("from ProjectJobDO pj where pj.upk.jobId=:jobId")
    Optional<ProjectJobDO> findByJobId(@Param("jobId") String jobId);
}
```

---

## 5. Flyway 数据库迁移

SecretPad 使用 **Flyway** 管理数据库 schema 版本。迁移脚本按 profile 分别存放在 `config/schema/` 下：

```text
config/schema/
├── center/
│   ├── V1__init.sql
│   ├── V2__0.8.0.sql
│   ├── V2_1__0.8.0.sql
│   ├── V3__0.9.0.sql
│   ├── V4__0.10.0.sql
│   └── V5__0.11.0.sql
├── edge/
│   └── ...（同 center 结构）
├── p2p/
│   └── ...（同 center 结构）
└── quartz/
    └── V1__init.sql
```

### 5.1 Flyway 配置

`FlywayConfig.java` 为两个数据源分别创建 Flyway 实例：

```java
@Bean
public Flyway defaultFlyway(@Qualifier("defaultDataSource") DataSource dataSource) {
    FlywayProperties flywayProperties = defaultFlywayProperties();
    Flyway flyway = Flyway.configure()
            .dataSource(dataSource)
            .locations(flywayProperties.getLocations().toArray(new String[0]))
            .baselineOnMigrate(true)
            .load();
    flyway.migrate();
    return flyway;
}
```

### 5.2 迁移策略

- `baselineOnMigrate(true)`：对已有数据库启用基线，避免从 V1 重新执行。
- `initialize-schema: never`：Quartz 表由 Flyway 管理，不由 Spring Boot 自动创建。
- 新增版本时按 `V{version}__{description}.sql` 命名并放入对应 profile 目录。

### 5.3 MySQL 静态脚本

对于 MySQL 部署，使用静态脚本而非 Flyway：

- `config/schemamysql/create_table.sql`：完整建表语句。
- `config/schemamysql/insert.sql`：示例种子数据。

### 5.4 遗留脚本

`scripts/sql/update-sql.sh` 是旧版手动初始化脚本，用于从 `config/schema/init.sql` 与 profile-specific `v1.sql` 重建 SQLite。当前正式运行使用 Flyway。

---

## 6. 缓存机制

### 6.1 未使用 Redis

SecretPad 中**没有使用 Redis**。搜索 `RedisTemplate`、`StringRedisTemplate`、`spring-data-redis` 均无结果。若未来需要集群级缓存或会话共享，才需要引入 Redis。

### 6.2 使用 EhCache 3（JCache）

本地缓存基于 **EhCache 3**，通过 JCache（JSR-107）规范接入 Spring Cache。

依赖：

```xml
<!-- secretpad-common/pom.xml -->
<dependency>
    <artifactId>spring-boot-starter-cache</artifactId>
</dependency>
<dependency>
    <groupId>org.ehcache</groupId>
    <artifactId>ehcache</artifactId>
    <classifier>jakarta</classifier>
</dependency>
```

配置：`secretpad-common/src/main/resources/ehcache.xml`

```xml
<config xmlns='http://www.ehcache.org/v3' xmlns:jsr107='http://www.ehcache.org/v3/jsr107'>
    <service>
        <jsr107:defaults enable-statistics="true"/>
    </service>

    <cache alias="user_lock">
        <key-type>java.lang.String</key-type>
        <value-type>java.util.HashMap</value-type>
        <expiry><ttl unit="minutes">30</ttl></expiry>
        <resources><offheap unit="MB">100</offheap></resources>
    </cache>

    <cache alias="model_export_cache">
        <key-type>java.lang.String</key-type>
        <value-type>java.lang.String</value-type>
        <expiry><ttl unit="minutes">300</ttl></expiry>
        <resources><offheap unit="MB">100</offheap></resources>
    </cache>

    <cache alias="project_vote_parties_cache">
        <key-type>java.lang.String</key-type>
        <value-type>java.util.ArrayList</value-type>
        <expiry><ttl unit="seconds">10</ttl></expiry>
        <resources><offheap unit="MB">10</offheap></resources>
    </cache>
</config>
```

### 6.3 缓存用途

| Cache Name | 用途 | 过期时间 |
|---|---|---|
| `user_lock` | 登录失败锁定计数 | 30 分钟 |
| `model_export_cache` | 模型导出进度/状态 | 300 分钟 |
| `project_vote_parties_cache` | 项目投票参与方临时缓存 | 10 秒 |

### 6.4 缓存使用方式

代码中主要使用命令式 `CacheManager` 操作，而非 `@Cacheable` 注解：

- `AuthServiceImpl`：读写 `user_lock`
- `ModelExportServiceImpl`：读写 `model_export_cache`
- `ProjectCreateMessageHandler` / `P2pPaddingNodeServiceImpl`：读写 `project_vote_parties_cache`

缓存常量定义：`secretpad-common/.../constant/CacheConstants.java`

---

## 7. 事务管理

SecretPad 使用 Spring 声明式事务。典型配置：

```java
@Transactional(rollbackFor = Exception.class)
public CreateProjectVO createProject(CreateProjectRequest request) { ... }
```

部分方法对 `SecretpadException` 做不回滚处理：

```java
@Transactional(rollbackFor = Exception.class, noRollbackFor = SecretpadException.class)
public UserContextDTO login(String name, String passwordHash) { ... }
```

Repository 层的修改操作也标注 `@Transactional`：

```java
@Query(nativeQuery = true, value = "delete from project")
@Modifying
@Transactional
void deleteAllAuthentic();
```

Spring Boot 自动从 `spring-boot-starter-data-jpa` 配置 `JpaTransactionManager`。

---

## 8. 数据备份与恢复

### 8.1 SQLite 备份

由于启用了 WAL 模式，必须同时备份三个文件：

```bash
cd /root/kuscia/master/secretpad/kuscia-system/db
cp secretpad.sqlite secretpad.sqlite-shm secretpad.sqlite-wal /backup/secretpad/db/
```

### 8.2 升级备份

`scripts/deploy/secretpad.sh` 在升级前会自动备份整个数据目录：

```bash
cp -rp "${dst_path}" "${dst_path}"_back_up_"${x}"
```

### 8.3 定期备份建议

- 使用 `sqlite3 secretpad.sqlite ".backup to /backup/secretpad.sqlite"` 做热备份。
- 备份前可先执行 `PRAGMA wal_checkpoint(FULL);` 合并 WAL 文件。
- 同时备份 `config/` 目录（证书、组件配置、Flyway 状态）。

---

## 9. SQLite 迁移到 MySQL

详细步骤见 `docs/development/SUPPORT_MYSQL.md`，核心流程如下：

1. 在新集群安装完成后、未登录前停止服务。
2. 导出 SQLite：
   ```bash
   sqlite3 secretpad.sqlite .dump > secretpad_dump.sql
   ```
3. 清理 SQL：只保留 `INSERT` 语句，删除 `sqlite_sequence` 相关语句，去掉表名双引号。
4. 在 MySQL 中执行 `config/schemamysql/create_table.sql` 建表。
5. 导入处理后的 `INSERT` 语句。
6. 修改 `application.yaml`，启用 MySQL 配置并注释 SQLite 配置。
7. 重启 SecretPad。

> 注意：若已登录，需额外处理 `tokens` 表中 `datetime` 字段类型兼容问题。

---

## 10. 关键文件索引

| 文件 | 说明 |
|---|---|
| `config/application.yaml` | 默认数据源、JPA、Flyway、缓存配置 |
| `config/application-edge.yaml` | Edge 模式配置 |
| `config/application-p2p.yaml` | P2P 模式配置 |
| `config/application-dev.yaml` | 开发模式配置 |
| `config/application-test.yaml` | 测试模式配置 |
| `secretpad-persistence/src/main/java/.../configuration/PersistenceConfiguration.java` | 实体扫描、JPA 仓库、WAL 初始化 |
| `secretpad-persistence/src/main/java/.../configuration/DataSourceConfig.java` | 双 HikariCP 数据源 |
| `secretpad-persistence/src/main/java/.../configuration/FlywayConfig.java` | Flyway 配置与迁移 |
| `secretpad-persistence/src/main/java/.../entity/` | 所有 JPA 实体 |
| `secretpad-persistence/src/main/java/.../repository/` | 所有 Repository |
| `secretpad-common/src/main/resources/ehcache.xml` | EhCache 配置 |
| `secretpad-common/src/main/java/.../constant/CacheConstants.java` | 缓存名称常量 |
| `config/schema/center/` / `edge/` / `p2p/` / `quartz/` | Flyway 迁移脚本 |
| `config/schemamysql/create_table.sql` | MySQL 建表脚本 |
| `config/schemamysql/insert.sql` | MySQL 示例数据 |
| `docs/development/SUPPORT_MYSQL.md` | SQLite 迁移 MySQL 指南 |
| `secretpad-scheduled/src/main/java/.../config/QuartzConfig.java` | Quartz 调度器配置 |

---

## 11. 总结

- SecretPad 默认使用 **SQLite + H2** 的轻量级组合，通过 **HikariCP** 管理连接池。
- 持久化层基于 **Spring Data JPA + Hibernate**，支持软删除、复合主键、原生查询等。
- 数据库版本由 **Flyway** 管理，按 CENTER/EDGE/P2P 分 profile 存放迁移脚本。
- 缓存使用 **EhCache 3** 本地堆外缓存，未使用 Redis；多实例部署时缓存不共享。
- Quartz 使用 JDBC 存储但未开启集群，调度任务仅限单实例执行。
- 生产环境如需高可用，可切换至 **MySQL** 并配合共享缓存/会话存储，但需手动迁移数据。
