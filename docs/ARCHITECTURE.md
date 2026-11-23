# Architecture

## Roles and address inventory (Phase 1 & Phase 2 Verified)

| Mac | Person | Role | IP (LAN) | Interface | MAC Address | Service / port |
|---|---|---|---|---|---|---|
| **Mac 1** | **Sarthak Mishra** (Lead) | Primary DNS + Client + Controller | `10.7.0.226` | `en0` | `92:82:a9:6f:7c:8f` | `dnsmasq` 53/udp,tcp (TTL: 30s) |
| **Mac 2** | **Preetish Ubhrani** | Nginx Edge (TLS + Proxy + LB) | `10.7.16.162` | `en0` | `2e:3e:87:1c:cc:ab` | `nginx` 8443/tcp (TLS 1.3 Termination) |
| **Mac 3** | **Shitanshu Tiwari** | Backend A + Service Isolation | `10.7.2.192` | `en0` | `10:9f:41:c2:d9:37` | Python REST 3001/tcp + PF Firewall |
| **Mac 4** | **Shane** | Backend B + Backup DNS Resolver | `10.7.6.77` | `en0` | `9e:f3:a4:24:4f:f7` | Python REST 3002/tcp + `dnsmasq` 53/udp |

Each Mac prints its row with `scripts/macos-network-info.sh`. Tunnel mode adds virtual IPs 10.250.0.3 (A) and 10.250.0.4 (B).

## Cloud equivalents

| Component | Cloud analogue |
|---|---|
| dnsmasq (Mac 1) | Route 53 private hosted zone |
| nginx (Mac 2) | ALB / CDN edge node (TLS termination + LB) |
| Backends (Mac 3/4) | Two instances in a target group |
| Cloudflare tunnel (tunnel mode only) | VPN / private-link overlay between VPCs |

## OSI / TCP-IP mapping

| Layer | Item in this project |
|---|---|
| Application | DNS, HTTP/1.1 and HTTP/2, REST JSON, Cache-Control/ETag |
| Session/Presentation | TLS 1.2/1.3 (terminated at nginx) |
| Transport | UDP 53 (DNS), TCP 8443 (client-edge), TCP 3001/3002 (edge-backend) |
| Network | IPv4 addressing; in tunnel mode a virtual IP overlay |
| Link | Wi-Fi / Ethernet frames, MAC addresses |

## Design decisions

* **One config source** - `config/project.example.env` -> `~/.config/cn-phase1/project.env`. Templates use `@@VAR@@` placeholders rendered by `render_template`.
* **Nothing global is modified** - dnsmasq/nginx run with our own generated config files and prefix dirs (not brew services). DNS on clients uses the scoped `/etc/resolver/<zone>` file, so unrelated DNS settings are untouched.
* **TLS ends at nginx.** Nginx -> backend is plain HTTP inside the trusted segment; in tunnel mode Cloudflare only carries that hop and never sees client-facing TLS.
* **Same ETag on both backends** - `/api/cacheable` body is identical on A and B so a conditional request works whichever backend is picked.
* **Health probes** - nginx exposes `/__probe/a`, `/__probe/b`, `/__edge/health` so a client that cannot reach the backends directly (tunnel mode) can still prove each layer individually.
* **Failover** - `max_fails=1 fail_timeout=5s`, `proxy_next_upstream error timeout http_502/503/504`, connect timeout 2s. If both fail, nginx returns a clear `502`.

## Single Points of Failure & Resilience (Phase 2 Hardening)

* **DNS Layer (Resolved):** In Phase 1, Mac 1 was a Single Point of Failure. In Phase 2, this was eliminated by introducing a secondary `dnsmasq` resolver on Mac 4 (`10.7.6.77`). Client Macs configure dual resolvers in `/etc/resolver/team1.test`, allowing seamless fallback if Mac 1 goes down.
* **Backend Tier (Resolved):** If Backend A or B crashes, Nginx passive health checks (`proxy_next_upstream`, `max_fails=1`, `fail_timeout=5s`, `proxy_connect_timeout 2s`) immediately route 100% of traffic to the healthy instance with zero 502 errors and automatically self-heal upon recovery.
* **Service Isolation (Hardened):** Backends are isolated behind macOS `pf` packet filter rules (anchor `com.apple/cn_backend_isolation`), rejecting direct LAN client access with TCP RST (`block return`) while permitting reverse proxy traffic.
* **Edge Proxy SPOF (Production Solution):** In our local testbed, Mac 2 remains the active edge proxy. In enterprise production systems, this SPOF is resolved via:
  1. **VRRP / Keepalived:** Active-Passive edge pairing with a shared Floating VIP.
  2. **BGP Anycast:** Multiple edge nodes announcing the same IP; routers send traffic to the nearest healthy instance.
  3. **Cloud Managed ALB:** Multi-AZ AWS Application Load Balancers with redundant edge endpoints.
  4. **DNS Failover (Extension E):** Standby edge node with automated DNS health-check cutover.
