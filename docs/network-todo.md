# Network TODO

## LAN allocation: `10.30.2.0/24`

Physical LAN IPs only. Do not use this range for pod IPs, because apparently we enjoy clusters that route packets instead of eating themselves.

| Range | Purpose |
|---|---|
| `10.30.2.1` | Router/gateway |
| `10.30.2.2-10.30.2.99` | DHCP pool or normal LAN clients |
| `10.30.2.100` | Kubernetes API VIP via keepalived |
| `10.30.2.101` | `k8s-cp1` static node IP |
| `10.30.2.102` | `k8s-cp2` static node IP |
| `10.30.2.103` | `k8s-cp3` static node IP |
| `10.30.2.104-10.30.2.199` | Future static IPs / expansion |
| `10.30.2.200-10.30.2.220` | MetalLB LoadBalancer pool, Traefik starts at `.200` |
| `10.30.2.221-10.30.2.254` | Reserved |

## Firstboot node identity

Each node gets `/boot/node-config` during install:

```sh
NODE_IP=10.30.2.101
NODE_GW=10.30.2.1
NODE_HOSTNAME=k8s-cp1
NODE_IFACE=eth0
```

Required: `NODE_IP`, `NODE_GW`, `NODE_HOSTNAME`.
Optional: `NODE_IFACE`; if missing, firstboot uses the first non-loopback NIC.

Firstboot only writes the static node IP, gateway, DNS fallback, and hostname so Ansible can SSH in. It does not configure k8s, VIPs, Cilium, or MetalLB.

## Control-plane VIP

Keepalived owns `10.30.2.100`.

Ansible writes `/etc/keepalived/keepalived.conf` with node priorities:

| Node | IP | Priority |
|---|---|---|
| `k8s-cp1` | `10.30.2.101` | `101` |
| `k8s-cp2` | `10.30.2.102` | `100` |
| `k8s-cp3` | `10.30.2.103` | `99` |

Kubeadm uses:

```sh
kubeadm init --control-plane-endpoint=10.30.2.100:6443
```

## Pod network

Do not use Cilium default `10.0.0.0/8`; it overlaps `10.30.2.0/24`.

Use one of:

```text
172.16.0.0/12
10.244.0.0/16
```

Preferred: `10.244.0.0/16`, unless another local network already uses it.

Pods do not get DHCP leases from the LAN. Cilium allocates pod IPs from the pod CIDR inside Kubernetes.

## Cluster networking stack

Order of operations:

1. Firstboot configures node LAN IP.
2. Ansible applies sysctls and kernel module config.
3. Ansible configures keepalived API VIP.
4. Kubeadm initializes or joins control plane nodes.
5. Cilium handles pod networking and kube-proxy replacement.
6. MetalLB advertises LoadBalancer IPs from `10.30.2.200-10.30.2.220`.
7. Traefik gets a MetalLB IP, normally `10.30.2.200`.

Required sysctls:

```text
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
```

## Decisions still needed

- Confirm final pod CIDR: `10.244.0.0/16` or `172.16.0.0/12`.
- Confirm actual router DHCP pool excludes `.100-.103` and `.200-.220`.
- Confirm NIC interface naming, or leave `NODE_IFACE` unset and trust auto-detection like a gambler with root access.
