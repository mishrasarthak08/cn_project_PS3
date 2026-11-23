# Viva guide

Each block: **What / Why / Where / Protocol+port / Packet flow / If it fails / Proof.**

## DNS server (dnsmasq) - Sarthak (Mac 1)
* **What**: a name->IP directory. **Why**: clients use names, not IPs; one record change re-points traffic. **Where**: Mac 1. **Protocol**: DNS over UDP (TCP for large answers) port 53.
* **Flow**: client (ephemeral src port) -> Mac 1:53 "A app.team1.test?" -> answer with Mac 2's IP and a TTL.
* **Fails**: lookups fail, but `ping <ip>` and `curl --resolve` still work - DNS is independent of IP connectivity. **Proof**: `dig @<DNS_IP> app.team1.test`, `tests/test_dns.sh`, `tcpdump`/Wireshark filter `dns`.

## Nginx edge (reverse proxy + TLS termination + load balancer) - Preetish (Mac 2)
* **What**: one public entry point that terminates TLS and forwards requests. **Why**: clients need only one name; backends stay private and interchangeable. **Where**: Mac 2, TCP 8443.
* **Flow**: accepts TCP+TLS from the client, opens a *separate* HTTP connection to A or B, relays the response.
* **Fails**: everything behind it is unreachable even if backends are healthy (single point of failure). **Proof**: `curl -v`, `./bin/status`, nginx access log (`upstream=` and `backend=`).

## Backends - Shitanshu (Mac 3, Backend A) & Shane (Mac 4, Backend B)
* **What**: identical Python REST servers. **Why**: give the LB two targets; `X-Backend` makes distribution visible. **Where**: Mac 3 (3001), Mac 4 (3002). **Port**: bound to `0.0.0.0` (reachable off-machine); `127.0.0.1` would be reachable only locally.
* **Fails**: with one down, nginx marks it failed (`max_fails=1`, `fail_timeout=5s`) and retries on the other; both down -> `502`. **Proof**: stop one and run `./bin/test-all`.

## TLS / CA
* **Certificate** binds a public key to a name; the **CA** is the trusted signer. Our local CA's certificate is installed in each client's trust store; the server certificate carries SANs `app.team1.test`, `api.team1.test`. **Termination**: TLS ends at nginx; nginx->backend is plain HTTP.
* **Handshake** (TLS 1.3): ClientHello (SNI, key share) -> ServerHello + Certificate + Finished -> client Finished -> encrypted HTTP. (TLS 1.2 adds explicit ServerKeyExchange/ChangeCipherSpec.)
* **Fails**: untrusted CA/wrong SAN/expired -> curl exit 60, browser warning. **Proof**: `openssl s_client`, `curl -v` (no `-k`).

## Concept Q&A
* **Resolver vs record**: the resolver is the machine/software that asks and caches (macOS, `/etc/resolver`); a record is the stored answer (`app.team1.test A <ip>`) on the DNS server.
* **IP vs port**: IP picks the host; port picks the process on it. `ping` proves the IP; `nc -vz ip port` proves the port.
* **TCP handshake**: SYN, SYN-ACK, ACK - establishes sequence numbers; reliability comes from sequence/ack numbers, retransmission, flow control.
* **Ephemeral ports**: the OS picks a high random source port (49152-65535) per connection; the socket pair (src ip, src port, dst ip, dst port) identifies it.
* **HTTP vs HTTPS**: HTTPS is HTTP inside TLS: confidentiality, integrity, server authentication. That is why Wireshark shows "Application Data".
* **Reverse vs forward proxy**: reverse proxy sits in front of servers on behalf of *servers* (nginx here); forward proxy sits in front of clients.
* **Load balancing / round robin**: requests alternate A,B,A,B; alternatives: `least_conn`, `ip_hash`. **Upstream**: nginx's named group of backend servers.
* **localhost vs 0.0.0.0**: 127.0.0.1 = loopback only; 0.0.0.0 = all interfaces, so other Macs can connect.
* **Cache-Control / ETag / 304**: `max-age=60` lets clients reuse a response for 60 s without asking (fresh hit); after that, `If-None-Match: <etag>` revalidates and the server answers `304` with no body; otherwise a full `200`.
* **DNS TTL**: how long resolvers may cache an answer; changes propagate only after TTL expiry (Extension B).
* **Cloudflare tunnel**: `cloudflared` opens *outbound* connections to Cloudflare; WARP on the edge sends traffic for `10.250.0.x` into Cloudflare, which delivers it through the tunnel to the backend Mac. It is an **overlay**: virtual IPs on top of the internet.
* **LAN vs overlay tunnel**: LAN = one broadcast domain, direct frames/ARP, no third party; overlay = encapsulated over other networks, extra latency, extra trust in the provider, virtual addressing. Hence tunnel mode changes the topology and is only for remote demo.
* **Why can the client not see backend IPs**: nginx terminates the client connection and makes its own upstream connection; only nginx knows the upstream list.

---

## Phase 2 Viva Defense & Review 2 Q&A (10 Marks)

### 1. What is the fundamental difference between a DNS service failure and an application server failure?
* **DNS Service Failure:** Name resolution fails (`NXDOMAIN` or query timeout). The client cannot translate `app.team1.test` into an IP address. As a result, **zero TCP packets leave the client machine** toward the edge proxy. The browser displays `ERR_NAME_NOT_RESOLVED` or `Could not resolve host`.
* **Application Server Failure:** DNS resolution succeeds completely, and the client successfully establishes a TCP connection and TLS handshake with the Nginx edge proxy. However, because both backend application servers are down, Nginx cannot establish an upstream connection and returns an **`HTTP 502 Bad Gateway`**. The network infrastructure worked; the application tier failed.

### 2. Which component in our current design is still a Single Point of Failure (SPOF), and how is it resolved in production?
* **Current SPOF:** The **Edge Nginx reverse proxy on Mac 2 (`10.7.16.162`)**. If Mac 2 crashes or loses network connectivity, the entire platform goes offline, even though both backend servers and both DNS resolvers are completely healthy.
* **Production Elimination:**
  1. **VRRP / Keepalived (Floating Virtual IP):** Two Nginx edge instances are paired with a shared Virtual IP (VIP). If the active master misses heartbeat signals, the backup node claims the VIP via Gratuitous ARP within milliseconds.
  2. **BGP Anycast Routing:** Multiple geographically distributed edge proxies announce the identical IP address via BGP. Upstream Internet routers automatically forward traffic to the nearest healthy edge node.
  3. **Cloud Managed Load Balancers:** Cloud providers (AWS ALB / GCP Cloud Load Balancing) utilize multi-Availability-Zone redundant hardware fleets fronted by Anycast virtual IPs.
  4. **DNS-Based Failover:** Monitoring agents perform active HTTP health checks on multiple edge IPs and dynamically remove unhealthy nodes from the DNS zone.

### 3. How does Nginx passive health checking and failover work?
* Configured directives:
  * `proxy_connect_timeout 2s`: Limits the time Nginx waits to establish a TCP socket with a backend.
  * `proxy_next_upstream error timeout http_502 http_503 http_504`: If a backend times out, closes connection, or returns an error, Nginx immediately re-routes the active request to the next backend in the upstream block.
  * `max_fails=1 fail_timeout=5s`: After 1 failed attempt, Nginx marks that backend inactive for 5 seconds, directing 100% of traffic to the survivor with zero latency penalty.
  * **Self-Healing:** Once the 5s window expires, Nginx sends the next incoming request to the previously failed backend. If it answers HTTP 200, it is immediately marked healthy and round-robin resumes.

### 4. Why enforce Service Isolation (Extension C) at Layer 4, and how does macOS `pf` work?
* **Why:** Defense-in-depth and zero-trust segmentation. In cloud architectures (AWS VPC), backends sit in private subnets with Security Groups allowing ingress exclusively from the Application Load Balancer. Direct access bypasses authentication, rate limiting, caching, and TLS inspection.
* **Mechanism:** macOS Packet Filter (`pf`) checks incoming TCP packets on ports 3001 and 3002.
  * Packets from `10.7.16.162` (Edge) or `127.0.0.1` match `pass in quick` and are forwarded to the socket.
  * Packets from any other IP match `block return in quick proto tcp`, causing the kernel to immediately emit a TCP RST (Reset) packet, resulting in `Connection refused`.
* **Anchor Hierarchy:** Rules are placed under `com.apple/cn_backend_isolation` because `/etc/pf.conf` delegates filtering exclusively to `anchor "com.apple/*"`.

### 5. Why do production migrations lower DNS TTL days in advance?
* DNS answers are cached locally by recursive resolvers and client operating systems (`mDNSResponder`) for the duration of the Time-To-Live (TTL).
* If a record has a 24-hour TTL (`86400s`), updating the DNS record will take up to 24 hours to reach all clients, causing stale traffic during cutover.
* **Two-Stage Migration Strategy:**
  1. Days before migration, lower TTL to 30–60 seconds.
  2. On migration day, switch the IP record. Clients detect the change within 60 seconds with minimal downtime.
  3. After cutover stabilizes, raise the TTL back to 86400s to reduce load on authoritative nameservers.

### 6. What is the systematic triage protocol if the faculty introduces a fault?
* **Never guess or edit code randomly.** Follow the **OSI Bottom-Up Traversal**:
  1. **Layer 3 (Network):** `ping <ip>` — proves physical LAN and IP reachability.
  2. **Layer 7 (DNS):** `dig @10.7.0.226 app.team1.test` — proves name resolution independent of connectivity.
  3. **Layer 4 (Transport):** `nc -vz <ip> <port>` — proves whether a process is listening on the TCP port or firewalled.
  4. **Layer 5/6 (TLS):** `openssl s_client -connect <edge>:8443 -servername app.team1.test` — proves certificate validity, SAN matching, and cipher negotiation.
  5. **Layer 7 (Edge HTTP):** `curl http://localhost:8443/__edge/health` — proves local Nginx server processing.
  6. **Layer 7 (Upstream Backend):** `curl http://<backend_ip>:<port>/api/status` — proves application logic.
* **Fast Path:** Run `./bin/doctor` on Mac 1 to pinpoint the failing layer in under 3 seconds.
