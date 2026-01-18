# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.2] - 2026-01-17

### Added

- `auth.azure.tenantId` parameter for Azure AD tenant configuration
- `auth.oidc.accountNameProperty` and `auth.oidc.accountDescriptionProperty` for OIDC account mapping
- `auth.saml.certData` and `auth.saml.keyData` for inline SAML certificate configuration
- `persistence.labels` for PVC labels
- `updateStrategy.rollingUpdate.maxSurge` and `updateStrategy.rollingUpdate.maxUnavailable` parameters
- `autoscaling.hpa.behavior` with default scaleUp/scaleDown policies
- `defaultInitContainers.waitForDatabase.resources` with default limits
- `backup.resources` with default limits
- `metrics.grafana.labels.grafana_dashboard` default label

### Fixed

- Complete parameter parity with v1.2.0 (356 parameters mapped)
- All v1.2.0 features now available through renamed paths

## [2.0.1] - 2026-01-17

### Added

- `hostNetwork` parameter for host network mode
- `hostIPC` parameter for host IPC namespace
- `dnsPolicy` parameter for DNS policy configuration
- `dnsConfig` parameter for custom DNS configuration
- `hostAliases` parameter for /etc/hosts entries
- `runtimeClassName` parameter for container runtime selection (e.g., gvisor, kata)
- `revisionHistoryLimit` parameter for deployment history retention

### Fixed

- Missing deployment parameters that were present in v1.2.0
- Complete parameter parity with v1.2.0

## [2.0.0] - 2026-01-17

### ⚠️ Breaking Changes

This release adopts Bitnami naming conventions. Users upgrading from v1.x must update their values files.

#### Configuration Path Changes

| Old Path | New Path | Description |
|----------|----------|-------------|
| `config.*` | `powerdnsAdmin.*` | Application configuration |
| `postgresql.*` | `externalDatabase.*` | Database configuration |
| `mysql.*` | `externalDatabase.*` | Database configuration |
| `powerdns.*` | `powerdnsApi.*` | PowerDNS API configuration |
| `ldap.*` | `auth.ldap.*` | LDAP authentication |
| `saml.*` | `auth.saml.*` | SAML authentication |
| `oidc.*` | `auth.oidc.*` | OIDC authentication |
| `google.*` | `auth.google.*` | Google OAuth |
| `github.*` | `auth.github.*` | GitHub OAuth |
| `azure.*` | `auth.azure.*` | Azure OAuth |
| `remoteUser.*` | `auth.remoteUser.*` | Remote user authentication |
| `totp.*` | `auth.twoFactor.*` | Two-factor authentication |
| `initContainersConfig.*` | `defaultInitContainers.*` | Init containers |
| `autoscaling.*` | `autoscaling.hpa.*` | HPA configuration |
| `existingSecret` | `powerdnsAdmin.existingSecret` | Existing secret reference |

#### Secret Key Changes

| Old Key | New Key |
|---------|---------|
| `password` | `password` (unchanged) |
| `LDAP_ADMIN_PASSWORD` | `bind-password` |
| `OIDC_CLIENT_SECRET` | `client-secret` |
| `GOOGLE_CLIENT_SECRET` | `client-secret` |
| `GITHUB_CLIENT_SECRET` | `client-secret` |
| `AZURE_CLIENT_SECRET` | `client-secret` |
| `MAIL_PASSWORD` | `smtp-password` |
| `PDNS_API_KEY` | `api-key` |

### Added

- Full Bitnami naming convention compliance
- `resourcesPreset` parameter for simplified resource configuration
- Unified `auth.*` namespace for all authentication methods
- Unified `externalDatabase.*` for database configuration
- `auth.local.enabled` for local database authentication toggle
- `externalDatabase.existingSecretPasswordKey` for flexible secret key names
- `powerdnsAdmin.sqlalchemyTrackModifications` configuration
- `powerdnsAdmin.sqlalchemyEngineOptions` for advanced database tuning
- `common.ingress.supportsPathType` helper function
- `common.ingress.supportsIngressClassname` helper function
- Conditional secret references (avoid errors when secrets not provided)
- Better organized values.yaml with clear section headers
- Validation helpers for required configuration

### Changed

- Reorganized all authentication providers under `auth.*`
- Database configuration unified under `externalDatabase.*`
- Application config moved to `powerdnsAdmin.*`
- PowerDNS API config moved to `powerdnsApi.*`
- HPA config moved to `autoscaling.hpa.*`
- Init containers config moved to `defaultInitContainers.*`
- Secret keys standardized (e.g., `client-secret`, `bind-password`)
- NetworkPolicy now references correct value paths

### Fixed

- Secret references now check for both value and existingSecret
- Empty YAML documents in secret.yaml when conditions not met
- NetworkPolicy references to old value paths
- RBAC references to old helper function names
- Ingress pathType and ingressClassName compatibility

## [1.3.0] - 2026-01-17

### Added

- TOTP (Two-Factor Authentication) support
- PowerDNS API environment variables (PDNS_API_URL, PDNS_API_KEY, PDNS_VERSION)
- SAML advanced configuration options
- CAPTCHA session key configuration

### Fixed

- PowerDNS API key not being passed to container
- SAML certificate path configuration

## [1.2.0] - 2026-01-17

### Added

- VPA (Vertical Pod Autoscaler) support
- Custom health check endpoints
- OpenTelemetry tracing integration
- Advanced RBAC configuration
- Multi-tenancy support
- HPA behavior configuration

## [1.1.0] - 2026-01-17

### Added

- ServiceMonitor for Prometheus monitoring
- Grafana Dashboard with 7 panels
- Init container for database wait
- Backup CronJob for PostgreSQL/MySQL

## [1.0.0] - 2026-01-17

### Added

- Initial release
- Support for PostgreSQL, MySQL, SQLite databases
- LDAP, SAML, OIDC, Google, GitHub, Azure authentication
- Ingress, NetworkPolicy, PDB support
- HPA autoscaling
- Prometheus metrics endpoint
- Bitnami common library integration
