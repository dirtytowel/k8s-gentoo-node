# Network TODO

## Subnet map

Each subnet is its own L2 and its own OpenWrt interface. Do not reuse a subnet across interfaces; two interfaces on the same prefix means duplicate connected routes and blackholed traffic.

| Subnet | VLAN | OpenWrt interface | Purpose |
|---|---|---|---|
| `10.30.1.0/24` | 1 (untagged) | `lan` (`br.1`) | Normal LAN clients, gateway `10.30.1.1` |
| `10.30.2.0/24` | n/a (tunnel) | `wg0` | WireGuard tunnel transport, `10.30.2.1`; peers are `/32` |
| `10.30.3.0/24` | 50 (tagged) | `k8s` (`br.50`) | Kubernetes nodes, gateway `10.30.3.1` |
| `104.52.82.0/28` | 100 (tagged) | `pub` (`br.100`) | AT&T public static block via Cascaded Router, `104.52.82.1` |

## k8s allocation: `10.30.3.0/24` (VLAN 50)

Node/cluster IPs only. Do not use this range for pod IPs.

| Range | Purpose |
|---|---|
| `10.30.3.1` | Router/gateway (OpenWrt `k8s` interface) |
| `10.30.3.100` | Kubernetes API VIP via keepalived |
| `10.30.3.101` | `k8s-cp1` static node IP |
| `10.30.3.102` | `k8s-cp2` static node IP |
| `10.30.3.103` | `k8s-cp3` static node IP |
| `10.30.3.104-10.30.3.199` | Future static IPs / expansion |
| `10.30.3.200-10.30.3.220` | MetalLB LoadBalancer pool, Traefik starts at `.200` |
| `10.30.3.221-10.30.3.254` | Reserved |

The three control-plane nodes connect to a downstream managed switch on access ports untagged in VLAN 50. OpenWrt trunks VLAN 50 tagged on the bridge uplink ports (`eth2:t`, `eth3:t`).

## Control-plane VIP

Keepalived owns `10.30.3.100`.

Ansible writes `/etc/keepalived/keepalived.conf` with node priorities:

| Node | IP | Priority |
|---|---|---|
| `k8s-cp1` | `10.30.3.101` | `101` |
| `k8s-cp2` | `10.30.3.102` | `100` |
| `k8s-cp3` | `10.30.3.103` | `99` |

Kubeadm uses:

```sh
kubeadm init --control-plane-endpoint=10.30.3.100:6443
```

## Pod network

Do not use Cilium default `10.0.0.0/8`; it overlaps the `10.30.x` LAN/tunnel/k8s subnets.

Use:

```text
pod CIDR:     172.16.0.0/16
service CIDR: 172.20.0.0/16
```

Avoid `10.0.0.0/8` because future routed `10.x` networks may collide with the cluster.

Pods do not get DHCP leases from the LAN. Cilium allocates pod IPs from the pod CIDR inside Kubernetes.

## Cluster networking stack

PiKVM/SystemRescue, MetalLB, Traefik, and public ingress are planned flow, not implemented roles yet.

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
10. MetalLB advertises LoadBalancer IPs from `10.30.3.200-10.30.3.220`.
11. Traefik gets a MetalLB IP, normally `10.30.3.200`.
12. OpenWrt forwards TCP `80` and `443` from one public static IP to `10.30.3.200`.
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

AT&T provides an on-link public static subnet (`104.52.82.0/28`) via the residential gateway's Cascaded Router mode, in addition to the normal dynamic WAN address, which is CGNAT/double-NAT and unusable for inbound. Public application traffic does not use Cilium Egress Gateway and the public subnet is not part of the MetalLB pool.

```text
Internet
    -> public DNS
    -> 104.52.82.x public static IP on OpenWrt pub (br.100, VLAN 100)
    -> OpenWrt firewall4 DNAT for TCP 80/443
    -> 10.30.3.200 MetalLB VIP
    -> Traefik
    -> host/SNI routing to Kubernetes Services
```

The AT&T gateway is in Cascaded Router mode and routes the `/28` to OpenWrt, which terminates it on the `pub` interface (`br.100`, VLAN 100). No port-forwarding on the AT&T box. `firewall4`/nftables permits and DNATs only TCP `80` and `443` to Traefik. UFW is not used on OpenWrt or the Kubernetes nodes for this path.

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

## VPN access to the cluster

The k8s subnet `10.30.3.0/24` is not on the WireGuard tunnel subnet, so it is not reachable over the VPN by default. It is reached by routing, not by sharing the tunnel's address block:

- Add `10.30.3.0/24` to each WireGuard peer's `AllowedIPs` (client side); this is also the client's route into the tunnel.
- Add an OpenWrt firewall forward rule from the `wg0` zone to the `k8s` zone.
- Server-side peer `allowed_ips` stay `/32`; they identify the peer's own tunnel address, not what it can reach.

## Decisions still needed

- Add a reproducible `sysrescue-customize` build that enables SystemRescue ssh access.
- Add PiKVM and SystemRescue install roles for the rolling rebuild pipeline.
- Confirm final pod CIDR `172.16.0.0/16` and service CIDR `172.20.0.0/16`.
- Create the OpenWrt `k8s` interface (`br.50`, `10.30.3.1/24`), bridge-vlan 50 tagged on `eth2`/`eth3`, and `k8s` firewall zone.
- Confirm downstream managed switch trunks VLAN 50 and sets node ports untagged in VLAN 50.
- Confirm NIC interface naming for the Phase 2 networkd file (must write `10.30.3.x`).
- Record which `104.52.82.x` address is reserved for Traefik DNAT.
- Confirm OpenWrt `firewall4` DNAT for TCP `80`/`443` from `pub` to `10.30.3.200`.
- Add WireGuard `AllowedIPs` for `10.30.3.0/24` and the `wg0` -> `k8s` firewall forward.
- Select the public DNS provider and certificate automation method.
