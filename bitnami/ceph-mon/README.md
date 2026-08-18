# ceph-mon

External Ceph monitors with **stable per-instance LoadBalancer (VIP) addresses**, coexisting
with a Rook-managed cluster. Modeled after the per-broker LoadBalancer pattern used for
Redpanda/Kafka external access: one instance = one VIP.

## Why

Rook mons on `network.provider: host` advertise **node IPs** and get a **new name and
address** on every failover — clients, libvirt XML and hand-written `ceph.conf` files go
stale. A mon deployed by this chart advertises a VIP (`--public-addr`) while binding its
pod IP (`--public-bind-addr`, resolved at runtime via the downward API); msgr2 accepts
this because the address clients dial equals the address the mon advertises. The pods run
on the ordinary pod network (no hostNetwork, so no port-3300 collision with Rook's own
host-network mons) and are **not pinned**: instances repel each other with a hard
anti-affinity and can be rescheduled to any node — the LoadBalancer follows the pod, the
VIP (and therefore the monmap entry) never changes, and the mon store re-syncs from
quorum wherever it lands. Each mon is a single-replica StatefulSet (pod name `...-0`) for
at-most-one semantics: a mon identity must never run twice concurrently.

Clients can then bootstrap with nothing but the VIPs:

```
mon_host = v2:10.224.18.21:3300,v2:10.224.18.22:3300
```

and learn the full monmap (including the Rook mons) automatically.

Verified 2026-08-17 on Ceph 20.2 (tentacle) / Rook v1.20.4 / Cilium LB-IPAM: quorum join,
Rook `externalMonIDs` acceptance, automatic propagation to `rook-ceph-mon-endpoints`
and the CSI config, and `ceph -s` / `rbd ls` / `ceph df` with the VIP as the only
`mon_host`. A freshly created mon logs `failed to assign global_id` for up to ~1 minute
while auth paxos catches up — this is a normal transient.

## Prerequisites

- An existing Rook Ceph cluster in `cluster.namespace` (default `rook-ceph`); the chart
  mounts Rook's `rook-ceph-mons-keyring` and `rook-ceph-mon` secrets, so install the
  release **into the same namespace**.
- A LoadBalancer implementation that honors `spec.loadBalancerIP` (Cilium LB-IPAM does;
  add its pool-selector labels via `serviceLabels`).
- `image.tag` must match the Rook cluster's Ceph version.
- Register the mon IDs in Rook **before** installing (see below), or Rook's health
  checker will remove the unknown mons from quorum. `spec.mon.externalMonIDs` is a Rook
  *experimental* feature (v1.17+).
- Keep the total mon count odd: Rook `mon.count` + `len(mons)`.

## Install

```bash
# 1. Tell Rook about the mons FIRST
kubectl -n rook-ceph patch cephcluster rook-ceph --type=merge \
  -p '{"spec":{"mon":{"externalMonIDs":["ext1","ext2"]}}}'

# 2. Install (values-production.yaml example below)
helm install ceph-mon ./ceph-mon -n rook-ceph -f my-values.yaml
```

```yaml
# my-values.yaml
# No mon bootstrap addresses needed: --mon-host / --mon-initial-members resolve at pod
# creation from the Rook-maintained `rook-ceph-config` secret (Rook rewrites it on every
# monmap change, and a fresh store needs current addresses exactly when a new pod is
# created; an already-initialized mon trusts its own monmap and ignores stale values).
# On a foreign cluster, create an equivalent secret by hand (see below).
mons:
  - name: ext1
    vip: 10.224.18.21
    serviceLabels:
      io.cilium/ip-pool-private: "true"
      io.cilium/bgp-advertise-external-ip: "true"
  - name: ext2
    vip: 10.224.18.22
    serviceLabels:
      io.cilium/ip-pool-private: "true"
      io.cilium/bgp-advertise-external-ip: "true"
```

Scheduling is free-floating by default (`podAntiAffinityPreset: hard` keeps the mons on
different nodes). Use `nodeSelector` / `nodeAffinityPreset` / `affinity` to constrain
placement if you want to.

## Verify

```bash
TB="kubectl -n rook-ceph exec deploy/rook-ceph-tools --"
$TB ceph quorum_status -f json | jq .quorum_names        # includes ext1, ext2 (allow ~1 min)
$TB ceph -s -m v2:10.224.18.21:3300 --connect-timeout 20 # bootstrap from the VIP alone
kubectl -n rook-ceph get cm rook-ceph-mon-endpoints -o jsonpath='{.data.data}'  # Rook publishes the VIPs
```

## Deploying into a different Kubernetes cluster

This is exactly the upstream use case for Rook's external mons (a tie-breaker in a
third failure domain). The mons only need Ceph-level connectivity, not the Rook
cluster's Kubernetes API:

1. Copy the mon keyring to the target cluster (sensitive: `[mon.]` + `[client.admin]`):

   ```bash
   kubectl --context source -n rook-ceph get secret rook-ceph-mons-keyring -o yaml \
     | kubectl --context target -n ceph-mon apply -f -
   ```

2. Create the mon address source with the **source cluster's current mon addresses**:

   ```bash
   kubectl --context target -n ceph-mon create secret generic rook-ceph-config \
     --from-literal=mon_host='[v2:10.32.16.2:3300],[v2:10.32.16.4:3300],[v2:10.32.16.3:3300]' \
     --from-literal=mon_initial_members='e,f,g'
   ```

   (Or reuse a ceph-consumer-style sync CronJob.)

   The chart automatically prepends its **own VIPs** to `--mon-host` at pod creation,
   so a recreated pod can always bootstrap through a surviving sibling even if this
   secret has gone stale — you do not need to (but harmlessly may) list the VIPs here.
   **Never list this chart's mon names in `mon_initial_members`**: that field controls
   who may form a brand-new quorum, and keeping the chart's mons out of it means a
   fresh mon can only ever *join* the existing cluster, never found a same-fsid
   split-brain when all other bootstrap addresses are dead.

3. Set `cluster.fsid` explicitly in values — this drops the dependency on the
   `rook-ceph-mon` secret entirely.

4. Requirements: L3 reachability both ways (target mons -> every address in the source
   monmap; every source client/daemon -> the target VIPs), NTP within 50 ms, and the
   same Ceph image version. Register the IDs in the **source** cluster's CephCluster
   `externalMonIDs` as usual — Rook only looks at quorum membership, not where the
   pods run. If the remote site has higher latency, put the mons in
   [disallow mode](https://docs.ceph.com/en/latest/rados/operations/change-mon-elections/)
   so they are never elected leader.

## Node moves

Nothing to do — when the scheduler moves a pod, the mkfs init container creates a fresh
store on the new node and the mon re-syncs from quorum (mon↔mon and client sessions are
long-lived but reconnect automatically; expect a seconds-long blip). Old
`<persistence.hostPath>/<name>` directories left on previous nodes are harmless and can
be wiped at leisure.

## Failure tolerance

Verified 2026-08-18 by stopping both chart mons while their IDs stayed registered:
Ceph reports `MON_DOWN` (HEALTH_WARN) and the remaining majority keeps serving; the
monmap is left untouched. After ~3 minutes Rook's health checker only drops the
unreachable mons from `rook-ceph-mon-endpoints` and the CSI config (so CSI clients
stop dialing dead addresses) — it does **not** touch the monmap, attempt a failover,
or restart any daemon. When the pods return, the existing stores rejoin quorum in
seconds and Rook re-publishes the endpoints. Worst case is a transient warning.

## Removing a mon

Reverse order, one at a time, quorum stays odd:

1. Remove the ID from `CephCluster spec.mon.externalMonIDs`. Rook's health checker
   (45 s interval) then removes the mon from the monmap by itself
   (`external mon ... not in quorum: removing it`) and cleans it out of
   `rook-ceph-mon-endpoints` — verified 2026-08-18; steps 2 and 4 are only a
   fallback in case that automation does not kick in.
2. `ceph mon rm <name>` from the toolbox (usually reports "already been removed").
3. `helm upgrade` with the entry removed (or `helm uninstall`).
4. Check `rook-ceph-mon-endpoints` for a stale entry; edit manually only if one remains.
5. Wipe `<persistence.hostPath>/<name>` on the node.

A full uninstall of a foreign-cluster deployment was verified 2026-08-18: quorum
re-elects in seconds, CSI is untouched, and nothing rolled immediately. Note however
that any monmap change leaves the OSD deployments' mon-address env stale, and the
operator syncs it by updating OSD deployments one by one (respecting ok-to-stop) at
the **next** full reconcile — possibly hours later. Treat every monmap change as a
scheduled, non-disruptive OSD rolling restart even if nothing rolls immediately.
Scope the cleanup to what the chart owns: the Helm release, the copied
`rook-ceph-mons-keyring`, the hostPath stores, and the chart files — leave any
consumer-sync machinery (`rook-ceph-config`, `rook-ceph-mon`, the endpoints
ConfigMap, sync CronJobs) alone.

## Parameters

See `values.yaml` — all parameters are documented inline in Bitnami `@param` style.

## Caveats

- Do not front Rook's own host-network mons with a LoadBalancer: msgr2 rejects
  connections whose target address is not in the mon's advertised addrvec
  (`handle_client_ident ... which is not us`). Only a mon that *advertises* the VIP
  (what this chart does) can sit behind one. For the same reason, dialing this chart's
  mon by its **bind address** is rejected — the VIP is its one true identity.
- The Rook cluster must keep at least one Rook-managed mon (`mon.count >= 1`;
  Rook resets `count: 0` back to 3).
- `requireMsgr2: true` clusters must keep `msgr2Only: true` (default).
- **Changing `spec.mon.externalMonIDs` (and any monmap change) schedules a
  rolling restart of every OSD deployment — immediately if a full reconcile runs
  right away, otherwise at the next one (operator restart / any CR change), which
  can be hours later.** Observed 2026-08-17: one patch rolled all 21 OSDs within two minutes;
  the old/new OSD overlap caused transient `MemoryPressure` on the storage nodes and
  kubelet evicted the burstable pods there (MDS / exporter / crashcollector), leaving
  MDS rescheduled onto unintended nodes (their placement is only a *preferred*
  affinity) plus dozens of Failed pod husks. Rook's "safe to stop" checks kept PGs
  active+clean throughout, but treat the change as a cluster-wide OSD restart: apply
  it **once** (list all mon IDs in a single patch, avoid add/remove churn), and
  afterwards check `kubectl get pod -o wide | grep mds` is back on labeled nodes and
  clean up `phase=Failed` debris.
