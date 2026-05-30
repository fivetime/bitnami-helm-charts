# Envoy (data plane)

A Helm chart that deploys a **bare Envoy data plane** whose dynamic configuration (LDS/CDS/RDS/EDS/SDS) is
served by an **external xDS control plane** over gRPC ADS — for example a `java-control-plane` based control
plane. Built on the Bitnami `common` library following Bitnami chart conventions, but using the **official
`envoyproxy/envoy`** image.

> This is **not** Envoy Gateway. There is no bundled control plane and no Kubernetes Gateway API. Envoy connects
> out to the control plane you point it at and applies whatever xDS that control plane pushes.

## TL;DR

```console
helm dependency build ./bitnami/envoy
helm install my-envoy ./bitnami/envoy \
  --set controlPlane.host=xds-control-plane.my-ns.svc.cluster.local \
  --set controlPlane.port=18000
```

## How it works

The chart renders an Envoy **bootstrap** (a ConfigMap, key `envoy.yaml`) containing:

- `admin` (bound to `127.0.0.1` unless `exposeAdmin=true`);
- `node` (`id`/`cluster`, defaults derived from the release; per-pod `--service-node $(POD_NAME)` is also set);
- `dynamic_resources.ads_config` → gRPC ADS to a static `xds_cluster` (HTTP/2), plus `cds_config`/`lds_config`
  via ADS;
- `static_resources.clusters[xds_cluster]` → `controlPlane.host:controlPlane.port`.

Everything else (listeners, routes, clusters, secrets) comes from your control plane at runtime.

## Key parameters

| Parameter | Description | Default |
|---|---|---|
| `image.tag` | Envoy image tag. Use `distroless-v1.38.0` (slim, prod), `v1.38.0` (Ubuntu+shell), `contrib-distroless-v1.38.0` / `contrib-v1.38.0` (full extensions) | `distroless-v1.38.0` |
| `controlPlane.host` | xDS control plane gRPC service (**required**) | `xds-control-plane` |
| `controlPlane.port` | xDS control plane gRPC port | `18000` |
| `controlPlane.apiType` | `DELTA_GRPC` (incremental, recommended) or `GRPC` | `DELTA_GRPC` |
| `containerPorts.http` | Main proxy listener port — **must match the port your LDS listener binds** | `10000` |
| `extraContainerPorts` / `service.extraPorts` | Additional listener ports (e.g. an HTTPS listener) | `[]` |
| `exposeAdmin` | Publish the admin interface on the Service (keep `false` in production) | `false` |
| `overrideConfiguration` | Object deep-merged onto the generated bootstrap (static listeners, tracing, stats sinks…) | `{}` |
| `existingConfigMap` | Use your own full bootstrap (key `envoy.yaml`) instead of the generated one | `""` |
| `replicaCount` / `autoscaling.hpa.*` | Replicas / HPA | `2` / disabled |
| `resourcesPreset` | `nano`…`2xlarge` (ignored if `resources` set) | `small` |

See `values.yaml` for the full set (security context, probes, affinity, PDB, NetworkPolicy, metrics, …).

## Ports

Because listeners are delivered dynamically via LDS, the container/Service ports must match the ports your
control plane's listeners bind. The default exposes one listener on `containerPorts.http` (10000) mapped to
`service.ports.http` (80). For an HTTPS listener add an entry to `extraContainerPorts` and `service.extraPorts`.

To bind privileged ports (80/443) directly inside the pod, add the capability:

```yaml
containerSecurityContext:
  capabilities:
    add: ["NET_BIND_SERVICE"]
```

## Verifying

```console
kubectl port-forward svc/my-envoy 9901:9901   # if exposeAdmin=true, else port-forward the pod
curl localhost:9901/ready
curl localhost:9901/config_dump   # what the control plane has pushed
```
