# PowerDNS-Admin Helm Chart

[PowerDNS-Admin](https://github.com/PowerDNS-Admin/PowerDNS-Admin) 是一个功能强大的 PowerDNS Web 管理界面，提供用户管理、区域模板、多种认证方式等企业级功能。

## 概述

本 Helm Chart 基于 Bitnami 风格开发，提供生产就绪的 PowerDNS-Admin 部署方案，支持：

- 多种数据库后端（PostgreSQL、MySQL、SQLite）
- 多种认证方式（LDAP、SAML、OAuth/OIDC、Google、GitHub、Azure AD）
- 双因素认证（TOTP）
- 高可用部署（HPA、VPA、PDB）
- Ingress 和 TLS 支持
- NetworkPolicy 网络隔离
- Prometheus/Grafana 监控
- OpenTelemetry 分布式追踪
- 自动备份

## 架构图

```
                                    ┌─────────────────┐
                                    │    Ingress      │
                                    │  (可选 TLS)     │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │     Service     │
                                    │   (ClusterIP)   │
                                    └────────┬────────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
           ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
           │   Pod (PDA)     │      │   Pod (PDA)     │      │   Pod (PDA)     │
           │   Gunicorn      │      │   Gunicorn      │      │   Gunicorn      │
           └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                    │                        │                        │
                    └────────────────────────┼────────────────────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              │                              │                              │
     ┌────────▼────────┐            ┌────────▼────────┐            ┌────────▼────────┐
     │   PostgreSQL    │            │   PowerDNS      │            │   LDAP/OAuth    │
     │   (外部)        │            │   Auth API      │            │   (可选)        │
     └─────────────────┘            └─────────────────┘            └─────────────────┘
```

## TL;DR

```bash
# 添加依赖
helm dependency update

# 安装（使用外部 PostgreSQL）
helm install powerdns-admin . \
  --set powerdnsAdmin.secretKey="$(python3 -c 'import os; print(os.urandom(32).hex())')" \
  --set externalDatabase.host=my-postgresql \
  --set externalDatabase.password=mypassword

# 安装（使用 SQLite，仅开发环境）
helm install powerdns-admin . \
  --set powerdnsAdmin.secretKey="$(python3 -c 'import os; print(os.urandom(32).hex())')" \
  --set database.type=sqlite
```

## 前提条件

- Kubernetes 1.23+
- Helm 3.8+
- PV provisioner（如需持久化）
- 外部数据库（生产环境推荐 PostgreSQL 或 MySQL）

## 安装

### 基本安装

```bash
# 生成 SECRET_KEY
export SECRET_KEY=$(python3 -c "import os; print(os.urandom(32).hex())")

# 创建数据库 Secret（如使用外部数据库）
kubectl create secret generic powerdns-admin-db \
  --from-literal=password=your-db-password

# 安装 Chart
helm install powerdns-admin . \
  --set powerdnsAdmin.secretKey="${SECRET_KEY}" \
  --set externalDatabase.host=my-postgresql \
  --set externalDatabase.existingSecret=powerdns-admin-db
```

### 使用 values 文件

```bash
helm install powerdns-admin . -f my-values.yaml
```

## 卸载

```bash
helm uninstall powerdns-admin

# 清理 PVC（如需要）
kubectl delete pvc -l app.kubernetes.io/name=powerdns-admin
```

## 参数

> 本 Chart 包含 363 个可配置参数。

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC | `"auto"` |
| `global.defaultStorageClass` | Global default StorageClass for Persistent Volume(s) | `""` |
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `[]` |
| `global.imageRegistry` | Global Docker image registry | `""` |
| `global.security.allowInsecureImages` | Allows skipping image verification | `false` |

### 通用参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `clusterDomain` | Kubernetes cluster domain name | `"cluster.local"` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `extraDeploy` | Array of extra objects to deploy with the release | `[]` |
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `kubeVersion` | Override Kubernetes version | `""` |
| `nameOverride` | String to partially override common.names.fullname | `""` |
| `namespaceOverride` | String to fully override common.names.namespace | `""` |

### 诊断模式

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `diagnosticMode.args` | Args to override all containers in the deployment | 见 values.yaml |
| `diagnosticMode.command` | Command to override all containers in the deployment | 见 values.yaml |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false` |

### 镜像参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.digest` | PowerDNS-Admin image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag | `""` |
| `image.pullPolicy` | PowerDNS-Admin image pull policy | `"IfNotPresent"` |
| `image.pullSecrets` | PowerDNS-Admin image pull secrets | `[]` |
| `image.registry` | [default: docker.io] PowerDNS-Admin image registry | `"docker.io"` |
| `image.repository` | [default: powerdnsadmin/pda-legacy] PowerDNS-Admin image repository | `"powerdnsadmin/pda-legacy"` |
| `image.tag` | PowerDNS-Admin image tag (immutable tags are recommended) | `"v0.4.2"` |

### PowerDNS-Admin 应用配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `powerdnsAdmin.bindAddress` | Listen address | `"0.0.0.0"` |
| `powerdnsAdmin.csrfCookieSecure` | Set CSRF cookie secure flag | `false` |
| `powerdnsAdmin.existingSecret` | Name of existing secret containing secretKey and salt | `""` |
| `powerdnsAdmin.hstsEnabled` | Enable HTTP Strict Transport Security header | `false` |
| `powerdnsAdmin.logLevel` | Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL) | `"INFO"` |
| `powerdnsAdmin.offlineMode` | Enable offline mode (disable external JS/CSS) | `false` |
| `powerdnsAdmin.port` | Listen port | `9191` |
| `powerdnsAdmin.salt` | Password hashing salt (required) | `""` |
| `powerdnsAdmin.scriptName` | URL prefix path (e.g., /pdns for reverse proxy) | `""` |
| `powerdnsAdmin.secretKey` | Flask secret key for session management (required) | `""` |
| `powerdnsAdmin.serverExternalSsl` | Force HTTPS URL generation | `false` |
| `powerdnsAdmin.sessionCookieSecure` | Set session cookie secure flag | `false` |
| `powerdnsAdmin.sessionType` | Session storage type (sqlalchemy, filesystem) | `"sqlalchemy"` |
| `powerdnsAdmin.signupEnabled` | Allow user self-registration | `true` |
| `powerdnsAdmin.sqlalchemyEngineOptions` | SQLAlchemy engine options (JSON format) | `""` |
| `powerdnsAdmin.sqlalchemyTrackModifications` | Enable SQLAlchemy track modifications | `true` |

### PowerDNS API 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `powerdnsApi.enabled` | Enable PowerDNS API integration | `true` |
| `powerdnsApi.existingSecret` | Name of existing secret containing API key (key: api-key) | `""` |
| `powerdnsApi.key` | PowerDNS API key | `""` |
| `powerdnsApi.url` | PowerDNS API URL (e.g., http://powerdns-auth:8081) | `"http://powerdns-auth:8081"` |
| `powerdnsApi.version` | PowerDNS API version | `"4.5.0"` |

### Gunicorn 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `gunicorn.accessLog` | Access log path ("-" for stdout, "" to disable) | `"-"` |
| `gunicorn.errorLog` | Error log path ("-" for stderr) | `"-"` |
| `gunicorn.loglevel` | Gunicorn log level | `"info"` |
| `gunicorn.timeout` | Worker timeout in seconds | `120` |
| `gunicorn.workers` | Number of worker processes | `4` |

### 数据库类型配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.type` | Database backend type (sqlite, postgresql, mysql) | `"postgresql"` |

### SQLite 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `sqlite.path` | SQLite database path | `"/data/powerdns-admin.db"` |

### 外部数据库配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `externalDatabase.database` | Database name | `"powerdns_admin"` |
| `externalDatabase.existingSecret` | Name of existing secret containing database password | `""` |
| `externalDatabase.existingSecretPasswordKey` | Key in existing secret for password | `"password"` |
| `externalDatabase.host` | Database server host | `""` |
| `externalDatabase.password` | Database password | `""` |
| `externalDatabase.port` | Database server port | `5432` |
| `externalDatabase.username` | Database username | `"powerdns_admin"` |

### 本地认证

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.local.enabled` | Enable local database authentication | `true` |

### LDAP 认证

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.ldap.adminGroup` | Admin group | `""` |
| `auth.ldap.adminPassword` | Admin bind password | `""` |
| `auth.ldap.adminUsername` | Admin bind DN | `"cn=admin,dc=example,dc=com"` |
| `auth.ldap.baseDn` | Base DN | `"dc=example,dc=com"` |
| `auth.ldap.domain` | AD domain (for AD type) | `""` |
| `auth.ldap.enabled` | Enable LDAP authentication | `false` |
| `auth.ldap.existingSecret` | Name of existing secret containing password (key: bind-password) | `""` |
| `auth.ldap.filterBasic` | Basic filter | `"(objectClass=inetOrgPerson)"` |
| `auth.ldap.filterGroup` | Group filter | `"(objectClass=posixGroup)"` |
| `auth.ldap.filterGroupToAccount` | Group to account filter | `""` |
| `auth.ldap.filterUsername` | Username filter | `"(uid=%s)"` |
| `auth.ldap.operatorGroup` | Operator group | `""` |
| `auth.ldap.sgEnabled` | Enable security group | `false` |
| `auth.ldap.type` | LDAP type: ldap, ad | `"ldap"` |
| `auth.ldap.uri` | LDAP server URI | `"ldap://ldap.example.com:389"` |
| `auth.ldap.userGroup` | User group | `""` |

### SAML 认证

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.saml.assertionEncrypted` | Expect encrypted assertions | `false` |
| `auth.saml.attributeAccount` | Account attribute name | `""` |
| `auth.saml.attributeAdmin` | Admin attribute name | `""` |
| `auth.saml.attributeEmail` | Email attribute name | `"email"` |
| `auth.saml.attributeGivenname` | Given name attribute name | `"givenname"` |
| `auth.saml.attributeGroup` | Group attribute name | `""` |
| `auth.saml.attributeSurname` | Surname attribute name | `"surname"` |
| `auth.saml.attributeUsername` | Username attribute name | `""` |
| `auth.saml.certData` | SP certificate data (Base64 encoded) | `""` |
| `auth.saml.certPath` | Path to SP certificate file | `""` |
| `auth.saml.debug` | Enable SAML debug mode | `false` |
| `auth.saml.enabled` | Enable SAML authentication | `false` |
| `auth.saml.existingSecret` | Name of existing secret containing SAML cert/key | `""` |
| `auth.saml.groupAdminName` | Admin group name | `""` |
| `auth.saml.groupOperatorName` | Operator group name | `""` |
| `auth.saml.groupToAccountMapping` | Group to account mapping | `""` |
| `auth.saml.idpEntityId` | IdP entity ID | `""` |
| `auth.saml.idpSsoBinding` | IdP SSO binding format | `""` |
| `auth.saml.keyData` | SP private key data (Base64 encoded, stored in Secret) | `""` |
| `auth.saml.keyPath` | Path to SP private key file | `""` |
| `auth.saml.logout` | Enable SAML logout | `false` |
| `auth.saml.logoutUrl` | Logout redirect URL | `""` |
| `auth.saml.metadataCacheLifetime` | Metadata cache lifetime in seconds | `1` |
| `auth.saml.metadataUrl` | IdP metadata URL | `""` |
| `auth.saml.nameidFormat` | NameID format | `""` |
| `auth.saml.path` | Path to SAML configuration directory | `""` |
| `auth.saml.signRequest` | Sign SAML requests | `false` |
| `auth.saml.spContactMail` | SP contact email | `""` |
| `auth.saml.spContactName` | SP contact name | `""` |
| `auth.saml.spEntityId` | SP entity ID | `""` |
| `auth.saml.spRequestedAttributes` | SP requested attributes (JSON) | `""` |
| `auth.saml.wantAttributeStatement` | Require attribute statement (set false for Okta) | `true` |
| `auth.saml.wantMessageSigned` | Require signed messages | `false` |

### OIDC 认证

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.oidc.accountDescriptionProperty` | Account description property | `""` |
| `auth.oidc.accountNameProperty` | Account name property | `""` |
| `auth.oidc.apiUrl` | API URL for user info | `""` |
| `auth.oidc.authorizeUrl` | Authorization endpoint URL | `""` |
| `auth.oidc.clientId` | Client ID | `""` |
| `auth.oidc.clientSecret` | Client secret | `""` |
| `auth.oidc.email` | Email claim | `"email"` |
| `auth.oidc.enabled` | Enable OIDC authentication | `false` |
| `auth.oidc.existingSecret` | Name of existing secret containing client secret (key: client-secret) | `""` |
| `auth.oidc.firstName` | First name claim | `"given_name"` |
| `auth.oidc.lastName` | Last name claim | `"family_name"` |
| `auth.oidc.logoutUrl` | Logout URL | `""` |
| `auth.oidc.metadataUrl` | OIDC discovery URL | `""` |
| `auth.oidc.scope` | OAuth scope | `"openid email profile"` |
| `auth.oidc.tokenUrl` | Token endpoint URL | `""` |
| `auth.oidc.username` | Username claim | `"preferred_username"` |

### Google OAuth

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.google.clientId` | Google Client ID | `""` |
| `auth.google.clientSecret` | Google Client secret | `""` |
| `auth.google.enabled` | Enable Google OAuth | `false` |
| `auth.google.existingSecret` | Name of existing secret containing client secret (key: client-secret) | `""` |
| `auth.google.scope` | OAuth scope | `"openid email profile"` |

### GitHub OAuth

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.github.clientId` | GitHub Client ID | `""` |
| `auth.github.clientSecret` | GitHub Client secret | `""` |
| `auth.github.enabled` | Enable GitHub OAuth | `false` |
| `auth.github.existingSecret` | Name of existing secret containing client secret (key: client-secret) | `""` |
| `auth.github.scope` | OAuth scope | `"user:email"` |

### Azure AD OAuth

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.azure.apiUrl` | API URL | `""` |
| `auth.azure.authorizeUrl` | Authorization URL | `""` |
| `auth.azure.clientId` | Azure AD Client ID | `""` |
| `auth.azure.clientSecret` | Azure AD Client secret | `""` |
| `auth.azure.enabled` | Enable Azure AD OAuth | `false` |
| `auth.azure.existingSecret` | Name of existing secret containing client secret (key: client-secret) | `""` |
| `auth.azure.scope` | OAuth scope | `"User.Read openid email profile"` |
| `auth.azure.tenantId` | Azure AD Tenant ID | `""` |
| `auth.azure.tokenUrl` | Token URL | `""` |

### 远程用户认证

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.remoteUser.cookies` | Cookies to clear on logout (comma-separated) | `""` |
| `auth.remoteUser.enabled` | Enable remote user authentication | `false` |
| `auth.remoteUser.logoutUrl` | Logout redirect URL | `""` |

### 双因素认证 (TOTP)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.twoFactor.enabled` | Enable TOTP two-factor authentication | `true` |
| `auth.twoFactor.issuerName` | Issuer name shown in authenticator apps | `"PowerDNS-Admin"` |

### 验证码配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `captcha.enabled` | Enable CAPTCHA on login | `true` |
| `captcha.height` | CAPTCHA image height | `60` |
| `captcha.length` | CAPTCHA character length | `6` |
| `captcha.sessionKey` | CAPTCHA session key name | `"captcha_image"` |
| `captcha.width` | CAPTCHA image width | `160` |

### 邮件配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `mail.debug` | Enable mail debug mode | `false` |
| `mail.defaultSender` | Default sender (tuple format: '("Name", "email@example.com")') | 见 values.yaml |
| `mail.enabled` | Enable mail notifications | `false` |
| `mail.existingSecret` | Name of existing secret containing password (key: smtp-password) | `""` |
| `mail.password` | SMTP password | `""` |
| `mail.port` | SMTP port | `25` |
| `mail.server` | SMTP server address | `"localhost"` |
| `mail.useSsl` | Use SSL | `false` |
| `mail.useTls` | Use TLS | `false` |
| `mail.username` | SMTP username | `""` |

### 部署配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `dnsConfig` | DNS Configuration for pod | `{}` |
| `dnsPolicy` | DNS Policy for pod | `""` |
| `hostAliases` | Add host aliases | `[]` |
| `hostIPC` | Specify if host IPC should be enabled for PowerDNS-Admin pod | `false` |
| `hostNetwork` | Specify if host network should be enabled for PowerDNS-Admin pod | `false` |
| `podAnnotations` | Annotations for PowerDNS-Admin pods | `{}` |
| `podLabels` | Extra labels for PowerDNS-Admin pods | `{}` |
| `priorityClassName` | Priority class name for pod scheduling | `""` |
| `replicaCount` | Number of PowerDNS-Admin replicas to deploy | `1` |
| `revisionHistoryLimit` | The number of old ReplicaSets to retain | `10` |
| `runtimeClassName` | Name of the runtime class to be used | `""` |
| `schedulerName` | Name of the scheduler to use | `""` |
| `terminationGracePeriodSeconds` | Termination grace period in seconds | `""` |
| `updateStrategy.rollingUpdate.maxSurge` | Maximum number of pods that can be created above the desired amount | `1` |
| `updateStrategy.rollingUpdate.maxUnavailable` | Maximum number of pods that can be unavailable during update | `0` |
| `updateStrategy.type` | Deployment strategy type | `"RollingUpdate"` |

### 亲和性配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `affinity` | Affinity for pod assignment | `{}` |
| `nodeAffinityPreset.key` | Node label key to match. Ignored if `affinity` is set | `""` |
| `nodeAffinityPreset.type` | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `nodeAffinityPreset.values` | Node label values to match. Ignored if `affinity` is set | `[]` |
| `nodeSelector` | Node labels for pod assignment | `{}` |
| `podAffinityPreset` | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard` | `""` |
| `podAntiAffinityPreset` | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard` | `"soft"` |
| `tolerations` | Tolerations for pod assignment | `[]` |
| `topologySpreadConstraints` | Topology Spread Constraints for pod assignment | `[]` |

### 安全配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation | `false` |
| `containerSecurityContext.capabilities.drop` | List of capabilities to be dropped | 见 values.yaml |
| `containerSecurityContext.enabled` | Enable containers' Security Context | `true` |
| `containerSecurityContext.privileged` | Set container's Security Context privileged | `false` |
| `containerSecurityContext.readOnlyRootFilesystem` | Set container's Security Context readOnlyRootFilesystem | `false` |
| `containerSecurityContext.runAsGroup` | Set containers' Security Context runAsGroup | `1001` |
| `containerSecurityContext.runAsNonRoot` | Set container's Security Context runAsNonRoot | `true` |
| `containerSecurityContext.runAsUser` | Set containers' Security Context runAsUser | `1001` |
| `containerSecurityContext.seLinuxOptions` | [object,nullable] Set SELinux options in container | `{}` |
| `containerSecurityContext.seccompProfile.type` | Set container's Security Context seccomp profile | `"RuntimeDefault"` |
| `podSecurityContext.enabled` | Enable pods' Security Context | `true` |
| `podSecurityContext.fsGroup` | Set PowerDNS-Admin pod's Security Context fsGroup | `1001` |
| `podSecurityContext.fsGroupChangePolicy` | Set filesystem group change policy | `"Always"` |
| `podSecurityContext.supplementalGroups` | Set filesystem extra groups | `[]` |
| `podSecurityContext.sysctls` | Set kernel settings using the sysctl interface | `[]` |

### 容器配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `args` | Override default container args (useful when using custom images) | `[]` |
| `command` | Override default container command (useful when using custom images) | `[]` |
| `extraEnvVars` | Array with extra environment variables to add to the container | `[]` |
| `extraEnvVarsCM` | Name of existing ConfigMap containing extra env vars | `""` |
| `extraEnvVarsSecret` | Name of existing Secret containing extra env vars | `""` |
| `extraVolumeMounts` | Optionally specify extra list of additional volumeMounts for the container | `[]` |
| `extraVolumes` | Optionally specify extra list of additional volumes for the pod | `[]` |
| `initContainers` | Add additional init containers to the pod | `[]` |
| `lifecycleHooks` | for the container to automate configuration before or after startup | `{}` |
| `sidecars` | Add additional sidecar containers to the pod | `[]` |

### 默认 Init Containers 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `defaultInitContainers.waitForDatabase.enabled` | Enable wait-for-database init container | `true` |
| `defaultInitContainers.waitForDatabase.image.pullPolicy` | Image pull policy | `"IfNotPresent"` |
| `defaultInitContainers.waitForDatabase.image.registry` | Image registry | `"docker.io"` |
| `defaultInitContainers.waitForDatabase.image.repository` | Image repository | `"busybox"` |
| `defaultInitContainers.waitForDatabase.image.tag` | Image tag | `"1.36"` |
| `defaultInitContainers.waitForDatabase.resources.limits.cpu` | CPU limit | `"100m"` |
| `defaultInitContainers.waitForDatabase.resources.limits.memory` | Memory limit | `"64Mi"` |
| `defaultInitContainers.waitForDatabase.resources.requests.cpu` | CPU request | `"50m"` |
| `defaultInitContainers.waitForDatabase.resources.requests.memory` | Memory request | `"32Mi"` |
| `defaultInitContainers.waitForDatabase.timeout` | Timeout in seconds | `300` |

### 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resources` | Set container requests and limits for different resources like CPU or memory (essential for production workloads) | `{}` |
| `resourcesPreset` | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if resources is set. | `"small"` |

### 容器端口

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerPorts.http` | HTTP container port | `9191` |

### 健康检查 - Liveness Probe

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `livenessProbe.enabled` | Enable livenessProbe | `true` |
| `livenessProbe.failureThreshold` | Failure threshold for livenessProbe | `6` |
| `livenessProbe.initialDelaySeconds` | Initial delay seconds for livenessProbe | `30` |
| `livenessProbe.path` | HTTP path for livenessProbe | `"/"` |
| `livenessProbe.periodSeconds` | Period seconds for livenessProbe | `10` |
| `livenessProbe.successThreshold` | Success threshold for livenessProbe | `1` |
| `livenessProbe.timeoutSeconds` | Timeout seconds for livenessProbe | `5` |

### 健康检查 - Readiness Probe

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `readinessProbe.enabled` | Enable readinessProbe | `true` |
| `readinessProbe.failureThreshold` | Failure threshold for readinessProbe | `3` |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe | `10` |
| `readinessProbe.path` | HTTP path for readinessProbe | `"/"` |
| `readinessProbe.periodSeconds` | Period seconds for readinessProbe | `10` |
| `readinessProbe.successThreshold` | Success threshold for readinessProbe | `1` |
| `readinessProbe.timeoutSeconds` | Timeout seconds for readinessProbe | `5` |

### 健康检查 - Startup Probe

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `startupProbe.enabled` | Enable startupProbe | `true` |
| `startupProbe.failureThreshold` | Failure threshold for startupProbe | `30` |
| `startupProbe.initialDelaySeconds` | Initial delay seconds for startupProbe | `5` |
| `startupProbe.path` | HTTP path for startupProbe | `"/"` |
| `startupProbe.periodSeconds` | Period seconds for startupProbe | `5` |
| `startupProbe.successThreshold` | Success threshold for startupProbe | `1` |
| `startupProbe.timeoutSeconds` | Timeout seconds for startupProbe | `3` |

### 自定义健康检查

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `customLivenessProbe` | Custom livenessProbe that overrides the default one | `{}` |
| `customReadinessProbe` | Custom readinessProbe that overrides the default one | `{}` |
| `customStartupProbe` | Custom startupProbe that overrides the default one | `{}` |

### Service 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.annotations` | Additional custom annotations for service | `{}` |
| `service.clusterIP` | Service Cluster IP | `""` |
| `service.externalTrafficPolicy` | Service external traffic policy | `"Cluster"` |
| `service.extraPorts` | Extra ports to expose in the service | `[]` |
| `service.loadBalancerIP` | Service Load Balancer IP | `""` |
| `service.loadBalancerSourceRanges` | Service Load Balancer sources | `[]` |
| `service.nodePorts.http` | Node port for HTTP | `""` |
| `service.ports.http` | HTTP service port | `80` |
| `service.sessionAffinity` | Session affinity for the service | `"None"` |
| `service.sessionAffinityConfig` | Additional settings for the sessionAffinity | `{}` |
| `service.type` | Service type | `"ClusterIP"` |

### Ingress 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `ingress.annotations` | Additional annotations for the Ingress resource | `{}` |
| `ingress.apiVersion` | Force Ingress API version (automatically detected if not set) | `""` |
| `ingress.enabled` | Enable ingress record generation | `false` |
| `ingress.extraHosts` | An array with additional hostname(s) to be covered with the ingress record | `[]` |
| `ingress.extraPaths` | An array with additional arbitrary paths | `[]` |
| `ingress.extraRules` | Additional rules to be covered with this ingress record | `[]` |
| `ingress.extraTls` | TLS configuration for additional hostname(s) | `[]` |
| `ingress.hostname` | Default host for the ingress record | `"powerdns-admin.local"` |
| `ingress.ingressClassName` | IngressClass that will be used to implement the Ingress | `""` |
| `ingress.path` | Default path for the ingress record | `"/"` |
| `ingress.pathType` | Ingress path type | `"ImplementationSpecific"` |
| `ingress.secrets` | Custom TLS certificates as secrets | `[]` |
| `ingress.selfSigned` | Create a TLS secret using self-signed certificates | `false` |
| `ingress.tls` | Enable TLS configuration for the hostname | `false` |

### 持久化配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `persistence.accessModes` | PVC Access Mode | 见 values.yaml |
| `persistence.annotations` | Persistent Volume Claim annotations | `{}` |
| `persistence.dataSource` | Custom PVC data source | `{}` |
| `persistence.enabled` | Enable persistence using Persistent Volume Claims | `true` |
| `persistence.existingClaim` | Name of an existing PVC to use | `""` |
| `persistence.labels` | Persistent Volume Claim labels | `{}` |
| `persistence.selector` | Selector to match an existing Persistent Volume | `{}` |
| `persistence.size` | PVC Storage Request | `"1Gi"` |
| `persistence.storageClass` | Storage class for the PV claim | `""` |

### ServiceAccount 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `serviceAccount.annotations` | Additional Service Account annotations | `{}` |
| `serviceAccount.automountServiceAccountToken` | Automount service account token for the pod | `false` |
| `serviceAccount.create` | Specifies whether a ServiceAccount should be created | `true` |
| `serviceAccount.name` | Name of the ServiceAccount to use | `""` |

### RBAC 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `rbac.create` | Specifies whether RBAC resources should be created | `false` |
| `rbac.rules` | Custom RBAC rules to set | `[]` |

### HPA 自动扩缩容

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.hpa.behavior.scaleDown.policies` | Scale down policies | 见 values.yaml |
| `autoscaling.hpa.behavior.scaleDown.stabilizationWindowSeconds` | Scale down stabilization window (seconds) | `300` |
| `autoscaling.hpa.behavior.scaleUp.policies` | Scale up policies | 见 values.yaml |
| `autoscaling.hpa.behavior.scaleUp.selectPolicy` | Scale up policy selection (Max, Min, Disabled) | `"Max"` |
| `autoscaling.hpa.behavior.scaleUp.stabilizationWindowSeconds` | Scale up stabilization window (seconds) | `0` |
| `autoscaling.hpa.enabled` | Enable HPA | `false` |
| `autoscaling.hpa.maxReplicas` | Maximum number of replicas | `10` |
| `autoscaling.hpa.minReplicas` | Minimum number of replicas | `1` |
| `autoscaling.hpa.targetCPU` | Target CPU utilization percentage | `80` |
| `autoscaling.hpa.targetMemory` | Target Memory utilization percentage | `""` |

### VPA 自动扩缩容

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.vpa.annotations` | VPA annotations | `{}` |
| `autoscaling.vpa.controlledResources` | VPA controlled resources (cpu, memory) | `[]` |
| `autoscaling.vpa.enabled` | Enable VPA | `false` |
| `autoscaling.vpa.maxAllowed` | VPA max allowed resources | `{}` |
| `autoscaling.vpa.minAllowed` | VPA min allowed resources | `{}` |
| `autoscaling.vpa.updatePolicy.updateMode` | VPA update mode (Auto, Recreate, Initial, Off) | `"Auto"` |

### PodDisruptionBudget 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `pdb.create` | Enable/disable a Pod Disruption Budget creation | `true` |
| `pdb.maxUnavailable` | Maximum number/percentage of pods that may be made unavailable | `1` |
| `pdb.minAvailable` | Minimum number/percentage of pods that should remain scheduled | `""` |

### 网络策略配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `networkPolicy.allowExternal` | Don't require server label for connections | `true` |
| `networkPolicy.allowExternalEgress` | Allow the pod to access any range of port and all destinations | `true` |
| `networkPolicy.enabled` | Enable network policy | `false` |
| `networkPolicy.extraEgress` | Add extra egress rules to the NetworkPolicy | `[]` |
| `networkPolicy.extraIngress` | Add extra ingress rules to the NetworkPolicy | `[]` |
| `networkPolicy.ingressNSMatchLabels` | Labels to match to allow traffic from other namespaces | `{}` |
| `networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces | `{}` |

### 监控 - 基本配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | Enable Prometheus metrics endpoint | `false` |
| `metrics.path` | Metrics endpoint path | `"/metrics"` |
| `metrics.port` | Metrics endpoint port (if different from container port) | `""` |

### 监控 - ServiceMonitor

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.serviceMonitor.enabled` | Create ServiceMonitor resource | `false` |
| `metrics.serviceMonitor.honorLabels` | Honor labels from the target | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `"30s"` |
| `metrics.serviceMonitor.jobLabel` | The name of the label on the target service to use as the job name | `""` |
| `metrics.serviceMonitor.labels` | Additional labels for the ServiceMonitor | `{}` |
| `metrics.serviceMonitor.metricRelabelings` | Metric relabelings | `[]` |
| `metrics.serviceMonitor.namespace` | Namespace for the ServiceMonitor | `""` |
| `metrics.serviceMonitor.relabelings` | Metric relabelings | `[]` |
| `metrics.serviceMonitor.scrapeTimeout` | Scrape timeout | `"10s"` |
| `metrics.serviceMonitor.selector` | Additional selector for the ServiceMonitor | `{}` |

### 监控 - PrometheusRule

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.prometheusRule.enabled` | Create PrometheusRule resource | `false` |
| `metrics.prometheusRule.labels` | Additional labels for the PrometheusRule | `{}` |
| `metrics.prometheusRule.namespace` | Namespace for the PrometheusRule | `""` |
| `metrics.prometheusRule.rules` | PrometheusRule definitions | `[]` |

### 监控 - Grafana Dashboard

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.grafana.annotations` | Additional annotations for the ConfigMap | `{}` |
| `metrics.grafana.enabled` | Create Grafana dashboard ConfigMap | `false` |
| `metrics.grafana.labels.grafana_dashboard` | Grafana dashboard discovery label | `"1"` |
| `metrics.grafana.namespace` | Namespace for the ConfigMap | `""` |

### 备份配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `backup.enabled` | Enable backup CronJob | `false` |
| `backup.image.pullPolicy` | Backup image pull policy | `"IfNotPresent"` |
| `backup.image.registry` | Backup image registry | `"docker.io"` |
| `backup.image.repository` | Backup image repository | `"postgres"` |
| `backup.image.tag` | Backup image tag | `"16-alpine"` |
| `backup.resources.limits.cpu` | CPU limit for backup container | `"500m"` |
| `backup.resources.limits.memory` | Memory limit for backup container | `"256Mi"` |
| `backup.resources.requests.cpu` | CPU request for backup container | `"100m"` |
| `backup.resources.requests.memory` | Memory request for backup container | `"128Mi"` |
| `backup.retention` | Number of backups to retain | `7` |
| `backup.schedule` | Cron schedule for backup | `"0 2 * * *"` |
| `backup.storage.pvc.existingClaim` | Use existing PVC | `""` |
| `backup.storage.pvc.size` | PVC size | `"5Gi"` |
| `backup.storage.pvc.storageClass` | PVC storage class | `""` |
| `backup.storage.s3.bucket` | S3 bucket name | `""` |
| `backup.storage.s3.endpoint` | S3 endpoint URL | `""` |
| `backup.storage.s3.existingSecret` | Existing secret with S3 credentials (keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) | `""` |
| `backup.storage.type` | Storage type (pvc or s3) | `"pvc"` |

### OpenTelemetry 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `opentelemetry.enabled` | Enable OpenTelemetry tracing | `false` |
| `opentelemetry.endpoint` | OTLP exporter endpoint | `""` |
| `opentelemetry.propagators` | Trace context propagators | 见 values.yaml |
| `opentelemetry.sampler.ratio` | Sampling ratio (0.0 to 1.0) | `"0.1"` |
| `opentelemetry.sampler.type` | Sampler type (e.g., parentbased_traceidratio) | `"parentbased_traceidratio"` |
| `opentelemetry.serviceName` | Service name for traces | `"powerdns-admin"` |

### 多租户配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `multiTenancy.defaultTenant` | Default tenant name | `"default"` |
| `multiTenancy.enabled` | Enable multi-tenancy features | `false` |
| `multiTenancy.isolationMode` | Isolation mode (namespace or label) | `"namespace"` |

## 配置示例

### 使用外部 PostgreSQL

```yaml
powerdnsAdmin:
  secretKey: "your-very-long-secret-key-here"

database:
  type: postgresql

externalDatabase:
  host: "postgresql.database.svc.cluster.local"
  port: 5432
  database: "powerdns_admin"
  username: "powerdns_admin"
  existingSecret: "postgresql-credentials"
```

### 启用 LDAP 认证

```yaml
auth:
  ldap:
    enabled: true
    type: "ad"
    uri: "ldap://ad.example.com:389"
    baseDn: "DC=example,DC=com"
    adminUsername: "CN=ldap-reader,OU=Service Accounts,DC=example,DC=com"
    existingSecret: "ldap-credentials"
    filterBasic: "(objectClass=user)"
    filterUsername: "(sAMAccountName=%s)"
    sgEnabled: true
    adminGroup: "PowerDNS-Admins"
    operatorGroup: "PowerDNS-Operators"
    userGroup: "PowerDNS-Users"
    domain: "example.com"
```

### 启用 OIDC (Keycloak)

```yaml
auth:
  oidc:
    enabled: true
    clientId: "powerdns-admin"
    existingSecret: "oidc-credentials"
    scope: "openid email profile"
    tokenUrl: "https://keycloak.example.com/realms/master/protocol/openid-connect/token"
    authorizeUrl: "https://keycloak.example.com/realms/master/protocol/openid-connect/auth"
    metadataUrl: "https://keycloak.example.com/realms/master/.well-known/openid-configuration"
    logoutUrl: "https://keycloak.example.com/realms/master/protocol/openid-connect/logout"
```

### 高可用配置

```yaml
replicaCount: 3

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70

pdb:
  create: true
  minAvailable: 2

podAntiAffinityPreset: hard

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-admin
```

### 启用 Ingress 和 TLS

```yaml
ingress:
  enabled: true
  hostname: "dns-admin.example.com"
  ingressClassName: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls: true
```

### 与 PowerDNS Auth 集成

```yaml
powerdnsApi:
  enabled: true
  url: "http://powerdns-auth:8081"
  existingSecret: "powerdns-api-key"
  version: "4.8.0"
```

### 启用 Prometheus 监控

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: "30s"
    labels:
      release: prometheus
  grafana:
    enabled: true
    labels:
      grafana_dashboard: "1"
```

### 启用定时备份

```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  retention: 7
  storage:
    type: pvc
    pvc:
      size: 10Gi
      storageClass: "standard"
```

### 启用 OpenTelemetry 追踪

```yaml
opentelemetry:
  enabled: true
  endpoint: "http://otel-collector:4317"
  serviceName: "powerdns-admin"
  sampler:
    type: "parentbased_traceidratio"
    ratio: "0.1"
```

## 从 v1.x 升级到 v2.0

### ⚠️ 重大变更

v2.0.0 完全重构了参数命名以符合 Bitnami 规范，**所有参数路径都已变更**。

### 主要变更映射

| v1.x 路径 | v2.0 路径 |
|-----------|-----------|
| `config.*` | `powerdnsAdmin.*` |
| `postgresql.*` / `mysql.*` | `externalDatabase.*` |
| `powerdns.*` | `powerdnsApi.*` |
| `ldap.*` | `auth.ldap.*` |
| `saml.*` | `auth.saml.*` |
| `oidc.*` | `auth.oidc.*` |
| `google.*` | `auth.google.*` |
| `github.*` | `auth.github.*` |
| `azure.*` | `auth.azure.*` |
| `totp.*` | `auth.twoFactor.*` |
| `autoscaling.enabled` | `autoscaling.hpa.enabled` |
| `initContainersConfig.*` | `defaultInitContainers.*` |

### 升级步骤

1. **备份数据库和配置**

```bash
# 备份当前 values
helm get values powerdns-admin > values-backup.yaml

# 备份数据库
kubectl exec -it <db-pod> -- pg_dump powerdns_admin > backup.sql
```

2. **转换 values 文件**

将旧的 values 转换为新格式，参考上面的映射表。

3. **执行升级**

```bash
helm upgrade powerdns-admin . -f values-v2.yaml
```

## 故障排除

### Pod 启动失败

检查 Pod 日志：
```bash
kubectl logs -l app.kubernetes.io/name=powerdns-admin
```

常见原因：
1. `powerdnsAdmin.secretKey` 未设置
2. 数据库连接失败
3. 资源不足

### 数据库连接失败

验证数据库连接：
```bash
kubectl exec -it <pod-name> -- python3 -c "
from sqlalchemy import create_engine
engine = create_engine('postgresql://user:pass@host:5432/db')
engine.connect()
print('Connection successful')
"
```

### OAuth/LDAP 认证失败

启用调试模式：
```yaml
powerdnsAdmin:
  logLevel: "DEBUG"

# 对于 SAML
auth:
  saml:
    debug: true
```

## License

Apache 2.0 License - 详见 [LICENSE](LICENSE)
