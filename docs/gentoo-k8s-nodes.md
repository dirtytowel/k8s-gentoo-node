# Gentoo k8s HA Control Plane — Build & Deploy Plan

## Cluster Overview

- 3x identical hardware nodes, all running as HA control plane members
- All 3 nodes also run workload pods (NoSchedule taint removed)
- Single base tarball deployed identically to all 3 nodes
- Ansible is the sole source of truth for all configuration — nodes are cattle
- No separate `/etc` partition — Ansible re-applies all config on every redeploy

## Network Layout

```
10.30.2.100     k8s-api-vip       keepalived floating IP — kubeadm --control-plane-endpoint
10.30.2.101     k8s-cp1           node 1 static IP
10.30.2.102     k8s-cp2           node 2 static IP
10.30.2.103     k8s-cp3           node 3 static IP
10.30.2.200     k8s-ingress-vip   MetalLB pool — Traefik LoadBalancer IP
```

## Partition Layout (All 3 Nodes, Identical)

```
/dev/sda1   /boot    512M   vfat
/dev/sda2   /        rest   ext4
```

`/` is wiped and re-untarred on every redeploy. No state lives here between deploys.

## Cluster Components

```
Layer               Component         Role
-----------         ---------         ----
Infrastructure      containerd        container runtime
Infrastructure      kubelet           node agent
Infrastructure      kubeadm           cluster bootstrap
Infrastructure      keepalived        k8s API VIP (10.30.2.100)
Infrastructure      nfs-utils         NFS client for ZFS NAS mounts
Infrastructure      etcd-utils        etcdctl — used during rolling redeploy

Cluster             Cilium            CNI + full kube-proxy replacement (eBPF)
Cluster             MetalLB           L2 LoadBalancer IP assignment (bare metal)
Cluster             Traefik           Ingress controller, TLS, Let's Encrypt
Cluster             NFS CSI driver    Persistent volumes backed by ZFS NAS
```

Cilium, MetalLB, Traefik, and NFS CSI are deployed inside the cluster by Ansible.
They do not live in the base tarball.

---

## Phase 1: Catalyst Build

**Goal:** Produce a single `stage4-k8s.tar.xz` that is 100% node-agnostic.
Rebuild this tarball whenever you want base system updates (new kernel, package upgrades, etc).

### Packages

```
sys-kernel/gentoo-kernel
sys-apps/systemd
app-containers/containerd
sys-cluster/kubeadm
sys-cluster/kubelet
sys-cluster/kubectl
net-misc/openssh
sys-cluster/keepalived
net-fs/nfs-utils
dev-db/etcd
```

### Kernel Config (Required for Cilium kube-proxy Replacement)

```
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_NET_CLS_BPF=y
CONFIG_NET_CLS_ACT=y
CONFIG_NET_SCH_INGRESS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_BPF=y
CONFIG_CRYPTO_SHA1=y
CONFIG_CRYPTO_USER_API_HASH=y
```

Plus all hardware-specific drivers for your NIC, storage controller, etc.
Same kernel config used for all 3 nodes (identical hardware).

### Systemd Services Enabled in Tarball

```
sshd
containerd
kubelet
keepalived
systemd-networkd
systemd-resolved
firstboot          (custom oneshot — see Phase 3)
```

### What the Tarball Does NOT Contain

- Hostname
- Static IP or network config
- Any kubeadm or kubelet config
- Cluster certificates or tokens

---

## Phase 2: Install (Per Node, ~5 Minutes)

**Goal:** Get base system onto disk, give the node its identity, get it to first boot.
Performed from a Gentoo minimal install ISO.

```bash
# Partition
parted /dev/sda mklabel gpt
parted /dev/sda mkpart primary fat32 1MiB 513MiB
parted /dev/sda mkpart primary ext4 513MiB 100%
mkfs.vfat /dev/sda1
mkfs.ext4 /dev/sda2

# Mount
mount /dev/sda2 /mnt/gentoo
mkdir /mnt/gentoo/boot
mount /dev/sda1 /mnt/gentoo/boot

# Untar base system
tar -xpf stage4-k8s.tar.xz -C /mnt/gentoo

# Drop node identity — the ONLY per-node manual step
cat > /mnt/gentoo/boot/node-config <<EOF
NODE_IP=10.30.2.10x
NODE_GW=10.30.2.1
NODE_HOSTNAME=k8s-cpX
EOF

# Bootloader and fstab
grub-install --target=x86_64-efi --efi-directory=/mnt/gentoo/boot /dev/sda
# write /mnt/gentoo/etc/fstab

reboot
```

---

## Phase 3: Firstboot (Automatic, No Intervention Required)

**Goal:** Node gets a static IP and sshd comes up so Ansible can reach it.

A systemd oneshot service baked into the tarball. Runs exactly once on first boot,
never again.

```
firstboot.service:
  1. reads /boot/node-config
  2. writes /etc/systemd/network/10-eth0.network  (static IP + gateway)
  3. writes /etc/hostname
  4. touches /etc/firstboot-done
  5. masks itself (never runs again)
  6. network comes up, sshd starts
```

Node is now SSH-reachable on its static IP. Hand off to Ansible.

---

## Phase 4: Ansible

**Goal:** Turn a bare base system into a functioning k8s HA control plane member.
Fully idempotent — safe to re-run on every redeploy.

### Role Structure

```
ansible/
  inventory/
    hosts.yml              # cp1=.101, cp2=.102, cp3=.103
  group_vars/
    k8s_nodes.yml          # pod_cidr, cluster_name, api_vip, ingress_vip pool
  roles/
    common/                # sysctl, ntp, authorized_keys, resolved, modprobe
    containerd/            # /etc/containerd/config.toml (SystemdCgroup = true)
    kubelet/               # kubelet-config.yaml, systemd drop-ins
    keepalived/            # VRRP config, VIP=10.30.2.100, priorities 101/100/99
    kubeadm-init/          # runs on k8s-cp1 ONLY, first deploy ONLY
    kubeadm-join/          # runs on k8s-cp2, k8s-cp3
  site.yml
```

### sysctl Values (common role)

```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
fs.inotify.max_user_watches         = 524288
fs.inotify.max_user_instances       = 512
```

### kubeadm-init role (k8s-cp1, first deploy only)

```
kubeadm init \
  --control-plane-endpoint=10.30.2.100:6443 \
  --upload-certs

# Then apply in order:
1. Cilium          (kubeProxyReplacement: true)
2. MetalLB         + IPAddressPool (10.30.2.200-10.30.2.220)
3. Traefik         (DaemonSet, hostNetwork: true, Service type: LoadBalancer)
4. NFS CSI driver  + StorageClass pointing at ZFS NAS
5. Remove NoSchedule taint from all 3 nodes
```

### kubeadm-join role (k8s-cp2, k8s-cp3)

```
kubeadm join 10.30.2.100:6443 --control-plane
# etcd automatically syncs state from existing members
```

---

## Phase 5: Rolling Redeploy (Future Base System Updates)

**Goal:** Update base system one node at a time with zero cluster downtime.

**Hard constraint:** Only one node at a time. etcd requires 2/3 members healthy for
quorum (Raft consensus). Redeploying 2 nodes simultaneously kills the cluster.

```bash
# 1. Drain the node (reschedules all pods to the other 2 nodes)
kubectl drain k8s-cpX --ignore-daemonsets --delete-emptydir-data

# 2. Remove from etcd cleanly
etcdctl member list
etcdctl member remove <member-id>

# 3. Repeat Phase 2 on the node (ISO boot → untar → node-config → reboot)

# 4. Phase 3 runs automatically (firstboot service, no intervention)

# 5. Re-run Ansible (kubeadm join --control-plane this time, not init)
ansible-playbook site.yml --limit k8s-cpX

# 6. etcd resyncs from the other 2 members automatically

# 7. Return node to service
kubectl uncordon k8s-cpX

# Repeat for the next node only after this one is fully healthy
```

### What kubectl drain Does

`kubectl drain` cordons the node (no new pods) then evicts all running pods.
Whether this causes downtime depends on the workload:

| Workload | Behaviour | Downtime |
|---|---|---|
| Deployment replicas ≥ 2 | Pods evicted, rescheduled on other nodes | No |
| Deployment replicas = 1 | Pod evicted, brief gap while rescheduling | Brief |
| StatefulSet + NFS PVC | Pod evicted, restarts elsewhere, data intact on NFS | Brief |
| DaemonSet | Skipped by `--ignore-daemonsets` | No |
| `emptyDir` volumes | Deleted by `--delete-emptydir-data` | Data lost |

**Rule:** Never store anything you care about in `emptyDir`. Use NFS-backed PVCs.
Run at least `replicas: 2` for anything that matters.

Traefik is a DaemonSet — `--ignore-daemonsets` skips it.
MetalLB shifts the ingress VIP to a remaining healthy node. Traffic keeps flowing.

---

## Open Items Before Building

1. **Pod CIDR** — Cilium default is `10.0.0.0/8`. Confirm it does not overlap your
   LAN (`10.30.2.0/24`). Alternative: `172.16.0.0/12`.

2. **Hardware specs** — CPU, NIC model, storage controller. Required to write the
   kernel `.config` for the Catalyst build.

3. **Domain name** — Traefik needs this for Let's Encrypt. Public domain with DNS
   challenge, or internal `.lan`/`.home` with a self-signed CA?
