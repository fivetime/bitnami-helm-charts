# PowerDNS-Admin Helm Chart - Bitnami 命名风格审查报告

## 审查摘要

| 类别 | 状态 | 需要修改的项目数 |
|------|------|------------------|
| values.yaml 命名规范 | ⚠️ 需要修改 | 15+ |
| 模板文件命名 | ✅ 符合规范 | 0 |
| Helper 函数命名 | ⚠️ 需要修改 | 5+ |
| 注释格式 | ✅ 符合规范 | 0 |
| Section 组织 | ⚠️ 需要调整 | 3 |

## 1. Values.yaml 命名规范问题

### 1.1 认证模块命名不一致

**Bitnami 风格**: 使用 `auth` 前缀组织所有认证相关配置

**当前实现** (不符合规范):
```yaml
ldap:
  enabled: false
saml:
  enabled: false
oidc:
  enabled: false
google:
  enabled: false
github:
  enabled: false
azure:
  enabled: false
remoteUser:
  enabled: false
totp:
  enabled: true
```

**建议修改为**:
```yaml
auth:
  ## Local authentication
  local:
    enabled: true
  ## LDAP authentication
  ldap:
    enabled: false
    type: "ldap"
    uri: "ldap://ldap.example.com:389"
    ...
  ## SAML authentication
  saml:
    enabled: false
    ...
  ## OAuth providers
  oauth:
    ## OIDC/OpenID Connect
    oidc:
      enabled: false
      ...
    ## Google OAuth
    google:
      enabled: false
      ...
    ## GitHub OAuth
    github:
      enabled: false
      ...
    ## Azure AD OAuth
    azure:
      enabled: false
      ...
  ## Remote user (reverse proxy)
  remoteUser:
    enabled: false
    ...
  ## Two-Factor Authentication
  twoFactor:
    enabled: true
    issuerName: "PowerDNS-Admin"
```

### 1.2 数据库配置命名问题

**Bitnami 风格**: 使用 `externalDatabase` 前缀

**当前实现** (不符合规范):
```yaml
database:
  type: postgresql

postgresql:
  enabled: true
  host: ""
  ...

mysql:
  enabled: false
  host: ""
  ...
```

**建议修改为**:
```yaml
## Database type selector
database:
  ## @param database.type Database backend type (sqlite, postgresql, mysql)
  type: postgresql

## External database configuration
externalDatabase:
  ## @param externalDatabase.host Database host
  host: ""
  ## @param externalDatabase.port Database port
  port: 5432
  ## @param externalDatabase.database Database name
  database: "powerdns_admin"
  ## @param externalDatabase.username Database username
  username: "powerdns_admin"
  ## @param externalDatabase.password Database password
  password: ""
  ## @param externalDatabase.existingSecret Existing secret containing database password
  existingSecret: ""
  ## @param externalDatabase.existingSecretPasswordKey Key in existing secret containing password
  existingSecretPasswordKey: "password"
```

### 1.3 应用配置参数命名

**Bitnami 风格**: 使用应用名称作为前缀 (如 `wordpress*`, `discourse*`)

**当前实现** (不符合规范):
```yaml
config:
  secretKey: ""
  salt: ""
  bindAddress: "0.0.0.0"
  port: 9191
  logLevel: "INFO"
  ...
```

**建议修改为**:
```yaml
## PowerDNS-Admin specific configuration
powerdnsAdmin:
  ## @param powerdnsAdmin.secretKey Flask secret key (required)
  secretKey: ""
  ## @param powerdnsAdmin.salt Password hashing salt (required)
  salt: ""
  ## @param powerdnsAdmin.bindAddress Listen address
  bindAddress: "0.0.0.0"
  ## @param powerdnsAdmin.port Listen port
  port: 9191
  ## @param powerdnsAdmin.logLevel Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
  logLevel: "INFO"
  ...
```

### 1.4 PowerDNS API 配置

**当前实现**:
```yaml
powerdns:
  enabled: true
  apiUrl: "http://powerdns-auth:8081"
  apiKey: ""
  version: "4.5.0"
  existingSecret: ""
```

**建议修改为**:
```yaml
## PowerDNS Authoritative Server API configuration
powerdnsApi:
  ## @param powerdnsApi.enabled Enable PowerDNS API integration
  enabled: true
  ## @param powerdnsApi.url PowerDNS API URL
  url: "http://powerdns-auth:8081"
  ## @param powerdnsApi.key PowerDNS API key
  key: ""
  ## @param powerdnsApi.version PowerDNS API version
  version: "4.5.0"
  ## @param powerdnsApi.existingSecret Existing secret containing API key
  existingSecret: ""
  ## @param powerdnsApi.existingSecretKey Key in existing secret containing API key
  existingSecretKey: "api-key"
```

### 1.5 Init Containers 命名

**当前实现** (不符合规范):
```yaml
initContainersConfig:
  waitForDB:
    enabled: true
    ...
```

**建议修改为** (Bitnami 风格):
```yaml
defaultInitContainers:
  ## Wait for database init container
  waitForDatabase:
    ## @param defaultInitContainers.waitForDatabase.enabled Enable wait-for-database init container
    enabled: true
    ## @param defaultInitContainers.waitForDatabase.image.registry Image registry
    image:
      registry: docker.io
      repository: busybox
      tag: "1.36"
      pullPolicy: IfNotPresent
    ## @param defaultInitContainers.waitForDatabase.timeout Timeout in seconds
    timeout: 300
    ## @param defaultInitContainers.waitForDatabase.resources Container resources
    resources: {}
```

### 1.6 Probe 配置命名

**当前实现** (符合 Bitnami 风格 ✅):
```yaml
livenessProbe:
  enabled: true
  initialDelaySeconds: 30
  ...
readinessProbe:
  enabled: true
  initialDelaySeconds: 10
  ...
startupProbe:
  enabled: true
  ...
```

### 1.7 ServiceMonitor 配置

**当前实现** (部分符合):
```yaml
metrics:
  enabled: false
  serviceMonitor:
    enabled: false
    ...
```

**建议补充** (Bitnami 完整风格):
```yaml
metrics:
  ## @param metrics.enabled Enable Prometheus metrics endpoint
  enabled: false
  ## @param metrics.path Metrics endpoint path
  path: /metrics
  ## Prometheus Service Monitor
  serviceMonitor:
    ## @param metrics.serviceMonitor.enabled Create ServiceMonitor resource
    enabled: false
    ## @param metrics.serviceMonitor.namespace Namespace for ServiceMonitor
    namespace: ""
    ## @param metrics.serviceMonitor.interval Scrape interval
    interval: "30s"
    ## @param metrics.serviceMonitor.scrapeTimeout Scrape timeout
    scrapeTimeout: "10s"
    ## @param metrics.serviceMonitor.labels Additional labels for ServiceMonitor
    labels: {}
    ## @param metrics.serviceMonitor.selector Additional selector for ServiceMonitor
    selector: {}
    ## @param metrics.serviceMonitor.relabelings Metric relabelings
    relabelings: []
    ## @param metrics.serviceMonitor.metricRelabelings Metric relabelings
    metricRelabelings: []
    ## @param metrics.serviceMonitor.honorLabels Honor labels
    honorLabels: false
    ## @param metrics.serviceMonitor.jobLabel Job label
    jobLabel: ""
  ## Prometheus Rules
  prometheusRule:
    ## @param metrics.prometheusRule.enabled Create PrometheusRule resource
    enabled: false
    ## @param metrics.prometheusRule.namespace Namespace for PrometheusRule
    namespace: ""
    ## @param metrics.prometheusRule.labels Additional labels for PrometheusRule
    labels: {}
    ## @param metrics.prometheusRule.rules PrometheusRule definitions
    rules: []
```

## 2. 模板文件命名审查

### 2.1 当前模板文件

| 文件名 | Bitnami 风格 | 状态 |
|--------|--------------|------|
| `deployment.yaml` | ✅ | 符合 |
| `service.yaml` | ✅ | 符合 |
| `ingress.yaml` | ✅ | 符合 |
| `secret.yaml` | ✅ | 符合 |
| `configmap.yaml` | ✅ | 符合 |
| `pvc.yaml` | ✅ | 符合 |
| `serviceaccount.yaml` | ✅ | 符合 |
| `hpa.yaml` | ✅ | 符合 |
| `pdb.yaml` | ✅ | 符合 |
| `networkpolicy.yaml` | ✅ | 符合 |
| `servicemonitor.yaml` | ✅ | 符合 |
| `vpa.yaml` | ✅ | 符合 |
| `rbac.yaml` | ✅ | 符合 |
| `cronjob-backup.yaml` | ⚠️ | 建议改为 `backup-cronjob.yaml` |
| `grafana-dashboard.yaml` | ⚠️ | 建议改为 `grafana-configmap.yaml` |
| `extra-list.yaml` | ✅ | 符合 |

## 3. Helper 函数命名审查

### 3.1 当前 Helper 函数

| 函数名 | Bitnami 风格建议 | 状态 |
|--------|------------------|------|
| `powerdns-admin.image` | ✅ | 符合 |
| `powerdns-admin.imagePullSecrets` | ✅ | 符合 |
| `powerdns-admin.serviceAccountName` | ✅ | 符合 |
| `powerdns-admin.secretName` | ✅ | 符合 |
| `powerdns-admin.databaseSecretName` | ⚠️ | 建议改为 `powerdns-admin.database.secretName` |
| `powerdns-admin.ldapSecretName` | ⚠️ | 建议改为 `powerdns-admin.auth.ldap.secretName` |
| `powerdns-admin.samlSecretName` | ⚠️ | 建议改为 `powerdns-admin.auth.saml.secretName` |
| `powerdns-admin.oidcSecretName` | ⚠️ | 建议改为 `powerdns-admin.auth.oidc.secretName` |
| `powerdns-admin.googleSecretName` | ⚠️ | 建议改为 `powerdns-admin.auth.google.secretName` |

## 4. 注释格式审查

### 4.1 @param 格式 ✅

当前实现符合 Bitnami 的 `@param` 注释格式：
```yaml
## @param image.registry [default: docker.io] PowerDNS-Admin image registry
## @param image.repository [default: powerdnsadmin/pda-legacy] PowerDNS-Admin image repository
```

### 4.2 Section 标记 ✅

当前实现使用了正确的 `@section` 标记：
```yaml
## @section Global parameters
## @section Common parameters
## @section PowerDNS-Admin Parameters
```

## 5. 建议的优先修改项

### 高优先级 (破坏性变更，需谨慎)

1. **认证模块重构** - 将所有认证相关配置移到 `auth.*` 下
2. **数据库配置重构** - 使用 `externalDatabase.*` 替代 `postgresql.*` 和 `mysql.*`
3. **应用配置重构** - 将 `config.*` 改为 `powerdnsAdmin.*`

### 中优先级 (向后兼容)

4. **Init containers 命名** - 使用 `defaultInitContainers.*`
5. **PowerDNS API 配置** - 使用 `powerdnsApi.*`
6. **文件重命名** - `cronjob-backup.yaml` → `backup-cronjob.yaml`

### 低优先级 (风格统一)

7. **Helper 函数命名** - 使用点分隔的层级命名
8. **补充 prometheusRule** 配置
9. **补充更多 Bitnami 标准参数** (如 `resourcesPreset`)

## 6. 修改影响评估

| 修改项 | 影响范围 | 向后兼容 | 建议 |
|--------|----------|----------|------|
| 认证模块重构 | 高 | 否 | 作为 v2.0.0 发布 |
| 数据库配置重构 | 高 | 否 | 作为 v2.0.0 发布 |
| 应用配置重构 | 高 | 否 | 作为 v2.0.0 发布 |
| Init containers 命名 | 中 | 否 | 可在 v1.x 中迁移 |
| 文件重命名 | 低 | 是 | 可立即实施 |

## 7. 结论

当前 Chart 的整体结构良好，使用了 Bitnami common library，模板文件命名和基本注释格式都符合规范。

**主要不符合 Bitnami 风格的地方**:

1. 认证模块没有统一在 `auth.*` 命名空间下
2. 数据库配置没有使用 `externalDatabase.*` 命名
3. 应用特定配置没有使用应用名称作为前缀
4. 部分 Helper 函数命名不够规范

**建议**:

- 如果需要完全符合 Bitnami 风格，建议在 v2.0.0 中进行破坏性重构
- 如果保持当前版本稳定，可以在文档中说明命名约定差异
- 在新功能添加时遵循 Bitnami 风格
