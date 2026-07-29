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

Use:

```text
pod CIDR:     172.16.0.0/16
service CIDR: 172.20.0.0/16
```

Avoid `10.0.0.0/8` because future routed `10.x` networks may collide with the cluster.

Pods do not get DHCP leases from the LAN. Cilium allocates pod IPs from the pod CIDR inside Kubernetes.

## Cluster networking stack

Order of operations:

1. Ansible uses PiKVM to mount and boot a customized SystemRescue ISO.
2. SystemRescue starts DHCP and sshd from `sysrescue.d` autorun configuration.
3. Ansible connects to SystemRescue, installs the stage4, and writes the node LAN config.
4. PiKVM unmounts the ISO and reboots the node from disk.
5. Node boots with static IP and sshd.
6. Ansible applies sysctls and kernel module config.
7. Ansible configures keepalived API VIP.
8. Kubeadm initializes or joins control plane nodes.
9. Cilium handles pod networking and kube-proxy replacement.
10. MetalLB advertises LoadBalancer IPs from `10.30.2.200-10.30.2.220`.
11. Traefik gets a MetalLB IP, normally `10.30.2.200`.
12. OpenWrt forwards TCP `80` and `443` from one public static IP to `10.30.2.200`.
13. Public DNS points application hostnames at that public static IP.

Required sysctls:

```text
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
```

## Public ingress

The ISP provides an on-link public static subnet in addition to the normal dynamic WAN address. Public application traffic does not use Cilium Egress Gateway and the public subnet is not part of the MetalLB pool.

```text
Internet
    -> public DNS
    -> public static IP on OpenWrt WAN
    -> OpenWrt firewall4 DNAT for TCP 80/443
    -> 10.30.2.200 MetalLB VIP
    -> Traefik
    -> host/SNI routing to Kubernetes Services
```

OpenWrt owns one usable address from the public subnet as a secondary WAN address and responds to ARP for it. `firewall4`/nftables permits and DNATs only TCP `80` and `443` to Traefik. UFW is not used on OpenWrt or the Kubernetes nodes for this path.

Multiple public DNS records can point to the same public IP. Traefik selects the backend using the HTTP `Host` header or TLS SNI. Use split DNS or NAT reflection if LAN clients must reach the same public names.

Before configuring Kubernetes ingress, verify from an external network that OpenWrt can own the selected public address and that the ISP permits inbound TCP `80` and `443`.

## Pod egress

Normal pod Internet access leaves through OpenWrt using Cilium BPF masquerading. This is separate from Cilium Egress Gateway.

Initial Cilium settings:

```yaml
kubeProxyReplacement: true
bpf:
  masquerade: true
egressGateway:
  enabled: false
```

Cilium Egress Gateway is only needed later if selected namespaces or pods must use a predictable outbound source IP. It does not provide inbound port forwarding, public DNS routing, or reverse proxying.

## Decisions still needed

- Add a reproducible `sysrescue-customize` build that enables SystemRescue ssh access.
- Add PiKVM and SystemRescue install roles for the rolling rebuild pipeline.
- Confirm final pod CIDR `172.16.0.0/16` and service CIDR `172.20.0.0/16`.
- Confirm actual router DHCP pool excludes `.100-.103` and `.200-.220`.
- Confirm NIC interface naming for the Phase 2 networkd file.
- Record the public subnet prefix, provider gateway, and public IP reserved for Traefik.
- Confirm OpenWrt WAN aliasing, ARP, DNAT, and firewall behavior with the ISP.
- Select the public DNS provider and certificate automation method.
