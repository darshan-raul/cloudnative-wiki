---
title: Container Networking
tags: [containers, networking, linux, docker, cni]
date: 2026-10-10
description: How a container gets a network — network namespaces, veth pairs, bridges, NAT and port publishing — built by hand, then mapped onto Docker's network drivers and the Kubernetes CNI model.
---

# Container Networking

A container's network is not magic or a special kind of interface. It is a handful of ordinary Linux primitives wired together. Once you have built it by hand, Docker networks, Kubernetes pods and CNI plugins stop being black boxes.

## The primitives

| Primitive             | What it is                                                                     | Deep dive                                                     |
| :-------------------- | :----------------------------------------------------------------------------- | :------------------------------------------------------------ |
| **Network namespace** | A private copy of the network stack: interfaces, routes, firewall rules, ports | [[Linux/virtualization/network-namespace\|Network namespace]] |
| **veth pair**         | A virtual cable: what enters one end leaves the other                          |                                                               |
| **Bridge**            | A virtual layer-2 switch inside the kernel                                     |                                                               |
| **Routing**           | Where to send a packet next                                                    | [[Linux/networking/routing\|Linux routing]]                   |
| **netfilter / NAT**   | Rewriting addresses and filtering packets                                      | [[Linux/networking/iptables\|iptables]]                       |

## Build it by hand

```bash
# 1. A namespace standing in for a container
sudo ip netns add c1

# 2. A virtual cable; move one end into the namespace
sudo ip link add veth-host type veth peer name veth-c1
sudo ip link set veth-c1 netns c1

# 3. A bridge on the host, with the host end plugged into it
sudo ip link add br0 type bridge
sudo ip addr add 172.30.0.1/24 dev br0
sudo ip link set br0 up
sudo ip link set veth-host master br0 up

# 4. Address and default route inside the namespace
sudo ip netns exec c1 ip addr add 172.30.0.2/24 dev veth-c1
sudo ip netns exec c1 ip link set veth-c1 up
sudo ip netns exec c1 ip link set lo up
sudo ip netns exec c1 ip route add default via 172.30.0.1

# 5. Let it reach the outside world: forward, and masquerade its source address
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 172.30.0.0/24 ! -o br0 -j MASQUERADE

sudo ip netns exec c1 ping -c1 1.1.1.1
```

Add a second namespace on the same bridge and the two can reach each other directly. That is, in essence, everything Docker's default network does. The commands are explained in [[Linux/networking/ip-command|the `ip` command]].

```
┌──────────── host network namespace ─────────────┐
│                                                 │
│   eth0 ◄── MASQUERADE ── br0 (172.30.0.1)       │
│                           │        │            │
│                      veth-host   veth-host2     │
└───────────────────────────│────────│────────────┘
                       veth-c1     veth-c2
                    ┌──────────┐ ┌──────────┐
                    │ c1  .2   │ │ c2  .3   │
                    └──────────┘ └──────────┘
```

## Reaching a container from outside

A container's address is private to the host. **Publishing a port** adds a destination-NAT rule that forwards a host port to it:

```bash
docker run -p 8080:80 nginx
# roughly: iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 172.17.0.2:80
```

Details that cause surprises:

- `-p 8080:80` binds on **all** host interfaces. Use `-p 127.0.0.1:8080:80` to keep it local.
- Docker inserts its rules ahead of host firewall rules, so a published port can bypass `ufw` or [[Linux/networking/firewalld|firewalld]] policies.
- A container reaching its own published port through the host's address needs "hairpin" NAT.
- `EXPOSE` in a Dockerfile is documentation; it publishes nothing.

Check what is actually listening and translated with [[Linux/networking/ss|`ss`]] and `iptables -t nat -L -n -v`; port basics are in [[Linux/networking/ports|ports]] and NAT in [[Architecture/solution-architecture-concepts/networking/nat|NAT]].

## Docker's network drivers

| Driver               | Behaviour                                                        | Use                                               |
| :------------------- | :--------------------------------------------------------------- | :------------------------------------------------ |
| `bridge`             | The setup above. User-defined bridges add DNS by container name. | Single-host development                           |
| `host`               | No network namespace: the container uses the host's stack        | Maximum performance, no isolation, port conflicts |
| `none`               | Only loopback                                                    | Batch jobs with no network                        |
| `overlay`            | VXLAN tunnels between hosts                                      | Swarm multi-host networking                       |
| `macvlan` / `ipvlan` | The container gets an address on the physical network            | Appliances, legacy integration                    |
| `container:<id>`     | Join another container's namespace                               | Sidecars — and exactly what a Kubernetes pod does |

Always create a user-defined network for Compose-style setups. The default `bridge` network has no name resolution between containers; user-defined ones run an embedded DNS server at `127.0.0.11`.

## DNS inside containers

The runtime writes `/etc/resolv.conf` into the container. On Docker it points at the embedded resolver or copies the host's; on Kubernetes it points at the cluster DNS Service with search domains for the pod's namespace. Slow or failing lookups inside a container while the host resolves fine is nearly always this file — see [[Linux/networking/dns-resolution|DNS resolution]] and [[Kubernetes/concepts/L04-services-networking/03-dns|Kubernetes DNS]].

## From one host to a cluster

The bridge-and-NAT model breaks down across many hosts: container addresses overlap between hosts, and everything outbound is hidden behind NAT. Kubernetes replaces it with a simple requirement:

> Every pod gets its own IP address, and every pod can reach every other pod without NAT.

How that is achieved is left to a **CNI plugin**. When the runtime creates a pod sandbox, it calls the plugin with the path of the new network namespace, and the plugin does the equivalent of the manual steps above — create an interface, assign an address, set up routes.

| Approach                   | How pods on different nodes reach each other                        | Examples                                                                             |
| :------------------------- | :------------------------------------------------------------------ | :----------------------------------------------------------------------------------- |
| **Overlay**                | Encapsulate pod packets (VXLAN, Geneve) inside node-to-node packets | Flannel, Calico VXLAN, Cilium tunnel                                                 |
| **Native routing**         | The network itself routes pod CIDRs (BGP or cloud route tables)     | Calico BGP, Cilium native                                                            |
| **Cloud-native addresses** | Pods get real VPC addresses from the cloud network                  | [[Kubernetes/eks/networking/vpc-cni/README\|AWS VPC CNI]], Azure CNI, GKE VPC-native |
| **eBPF data path**         | Replaces bridges and iptables with kernel programs                  | Cilium — see [[Observability/ebpf\|eBPF]]                                            |

A **pod** is several containers sharing one network namespace, which is why they talk over `localhost` and cannot bind the same port. **Services** then add stable virtual IPs and load balancing on top, implemented by kube-proxy with iptables, IPVS or nftables rules, or by eBPF. That next layer is covered in [[Kubernetes/concepts/L04-services-networking/01-networking|Kubernetes networking]], [[Kubernetes/concepts/L04-services-networking/06-cni|CNI]], [[Kubernetes/concepts/L04-services-networking/02-services|Services]] and the packet-level [[Kubernetes/concepts/L04-services-networking/07-k8s-networking-deep-dive|deep dive]].

## Debugging

Work from inside the container outwards.

```bash
# The container's view, using the host's tools (works for images with no shell)
PID=$(docker inspect -f '{{.State.Pid}}' web)      # or: crictl inspect <id> | jq .info.pid
sudo nsenter -t $PID -n ip addr
sudo nsenter -t $PID -n ip route
sudo nsenter -t $PID -n ss -tlnp
sudo nsenter -t $PID -n cat /etc/resolv.conf

# The host side
ip link show type veth
bridge link
sudo iptables -t nat -L -n -v | less
sudo conntrack -L | grep 172.17.0.2
sudo tcpdump -ni any host 172.17.0.2
```

| Symptom                                         | Check                                                                                              |
| :---------------------------------------------- | :------------------------------------------------------------------------------------------------- |
| Connection refused from another container       | Is the process listening on `0.0.0.0`, or only on `127.0.0.1` inside its namespace?                |
| Works by IP, not by name                        | DNS: default bridge network, or a broken `resolv.conf`                                             |
| Container cannot reach the internet             | `ip_forward`, the MASQUERADE rule, host firewall, corporate proxy                                  |
| Intermittent drops under load                   | Conntrack table full (`nf_conntrack_max`); ephemeral port exhaustion                               |
| Large transfers stall, small ones work          | MTU: an overlay adds headers, so the inner MTU must be smaller                                     |
| Published port unreachable from another machine | Bound to `127.0.0.1`, or blocked by a cloud [[AWS/networking/vpc/security-groups\|security group]] |

"Listening on localhost inside the container" is the single most common mistake: the process works when tested inside and is unreachable from everywhere else.

## Related

- [[Containers|Containers hub]]
- [[Containers/namespaces-and-cgroups|Namespaces and cgroups]]
- [[Linux/networking/README|Linux networking]] and [[Linux/networking/tcp-ip-model|the TCP/IP model]]
- [[Architecture/solution-architecture-concepts/networking/README|Networking fundamentals]]
- [[Kubernetes/guides/troubleshooting/service-unreachable|Service unreachable]]

## Across the wiki

- [[Azure/compute/aks/networking-cni|AKS Networking Deep Dive — Azure CNI, CNI Overlay, and Dynamic Pod IP Allocation]] — pod networking (Azure)
- [[GCP/compute/gke/networking|GKE Networking Deep Dive — Datapath V2, Alias IPs & Gateway API]] — pod networking (GCP)
