# Phase 2 Team Runbook & Execution Guide
## Private Network Service Platform — Harden, Recover & Troubleshoot

**Repository:** `https://github.com/mishrasarthak08/cn_project_PS3.git`  
**Target Environment:** 4 macOS Laptops on Shared Private Wi-Fi / LAN  
**Review 2 Value:** **50 Marks** (Combined Total: 100 Marks)  
**Core Motto:** *The application stays simple — the network is the project.*

---

## 1. Executive Summary & Review 2 Marks Breakdown

In Phase 1, we successfully built the foundation: private DNS resolution (`dnsmasq`), TLS 1.3 termination, reverse proxying with round-robin load balancing (`nginx`), HTTP caching headers (`Cache-Control`/`ETag`), and packet captures across all layers.

In **Phase 2**, our objective is to **harden the network, demonstrate automated recovery, enforce zero-trust service isolation, and defend our infrastructure against intentional faults**.

### Review 2 Scoring Breakdown (50 Marks)

| Area | Scope & Tasks | Marks | Success Criteria |
|---|---|---|---|
| **Resilience & HA Failover** | **Extensions A, B, D** | **15 Marks** | Backup DNS resolver failover demonstrated; DNS TTL caching dynamics proven; Zero-downtime Nginx backend failover & recovery verified. |
| **Service Isolation & Edge Migration** | **Extensions C, E** | **10 Marks** | macOS `pf` firewall rules block direct backend access; Standby edge proxy activated via DNS cutover with TTL effect. |
| **Troubleshooting Challenge** | **Extension F** | **10 Marks** | Faculty injects a live fault; team performs systematic layer-by-layer diagnosis (L3 $\rightarrow$ L7) and isolates/resolves the issue. |
| **Final Documentation** | **Phase 2 Report & Evidence** | **5 Marks** | Clean topology updates, before/after test outputs, packet captures, and 1-paragraph learning summary per extension. |
| **Individual Viva** | **Phase 2 & End-to-End System** | **10 Marks** | Every teammate individually answers questions about their role, failure recovery, packet flows, and cloud equivalents. |
| **TOTAL** | **Review 2 Combined** | **50 Marks** | **Target: 50 / 50** |

---

## 2. Team Roster & Phase 2 Responsibilities Matrix

| Node | Teammate | Primary Role | Phase 2 Ownership | Services & Ports | LAN IP Address |
|---|---|---|---|---|---|
| **Mac 1** | **Sarthak Mishra** (Lead) | Primary DNS + Controller + Test Client | **Ext B** (DNS TTL Cutover), **Ext E** (DNS Record Edge Cutover), **Ext F** (Triage Coordinator), **Live Demo Conductor** | `dnsmasq` (`53/udp+tcp`), Controller CLI | `10.7.7.126` |
| **Mac 2** | **Preetish Ubhrani** | Edge Reverse Proxy & Load Balancer | **Ext D** (HA Passive Failover Tuning & Self-Healing), **Ext C** (Edge Firewall Access Verification), Standby TLS Cert Sharing | `nginx` (`8443/tcp`), TLS 1.3 | `10.7.11.189` |
| **Mac 3** | **Shitanshu Tiwari** | Backend A Service | **Ext C** (macOS `pf` Firewall Isolation on port 3001), **Ext E** (Standby Nginx Edge Host), **Ext D** (Failover Target A) | Python REST (`3001/tcp`), Standby Nginx (`8443`) | `10.7.7.23` |
| **Mac 4** | **Shane** | Backend B Service + 2nd Client | **Ext A** (Backup DNS Server on port 53), **Ext C** (macOS `pf` Firewall Isolation on port 3002), **Ext A** (Client Dual-Resolver Verification) | Python REST (`3002/tcp`), Backup `dnsmasq` (`53`) | `10.7.14.16` |

---

## 3. Mandatory Extensions Technical Runbook (Extensions A to F)

---

### Extension A: Backup DNS Resolver (High Availability DNS)
> **Goal:** Run a secondary DNS server so that if the Primary DNS server crashes, client name resolution continues uninterrupted without manual intervention.

* **Owner:** **Shane (Mac 4)** runs the Backup Resolver; **All Clients** configure dual resolvers.
* **Theory / Course Mapping:** DNS Redundancy, Dual Resolver Failover, Application vs DNS Failure.
  - *DNS Failure:* Client cannot map `app.team1.test` $\rightarrow$ IP (`NXDOMAIN` or query timeout). Zero TCP/TLS traffic leaves the client.
  - *Application Failure:* Client successfully resolves IP $\rightarrow$ connects to Nginx $\rightarrow$ Nginx returns `502 Bad Gateway`.

#### Step-by-Step Implementation:

1. **Shane (Mac 4) starts the Backup DNS Resolver:**
   ```bash
   # On Shane's Mac:
   git pull origin main
   ./scripts/setup-backup-dns.sh start
   ```
   *Verification:*
   ```bash
   dig +short -p 53 @127.0.0.1 app.team1.test
   # Expected output: 10.7.11.189 (Preetish's Edge IP)
   ```

2. **Configure Client Macs with Dual Resolvers:**
   Both Sarthak (Mac 1) and Shane (Mac 4) configure `/etc/resolver/team1.test` to list **both** Primary and Backup nameservers:
   ```bash
   # On Mac 1, Mac 2, or Mac 4:
   ./scripts/setup-backup-dns.sh configure-client 10.7.7.126 10.7.14.16
   ```
   *Inspect the resolver configuration:*
   ```bash
   cat /etc/resolver/team1.test
   # Expected output:
   # # managed by cn-phase2 backup dns
   # nameserver 10.7.7.126
   # nameserver 10.7.14.16
   ```

3. **Demonstrate DNS Failover (The Proof):**
   - **Step 3.1:** Verify resolution works through Primary:
     ```bash
     dig app.team1.test
     # In output: SERVER: 10.7.7.126#53
     ```
   - **Step 3.2:** Stop the Primary DNS service on Mac 1:
     ```bash
     # Sarthak runs on Mac 1:
     ./macs/mac1-sarthak/stop.sh
     ```
   - **Step 3.3:** Immediately query from a client:
     ```bash
     # Shane or Sarthak runs:
     dig app.team1.test
     # Result: Resolves successfully!
     # In output: SERVER: 10.7.14.16#53 (Fell back to Shane's Backup DNS!)
     curl -i https://app.team1.test:8443/api/status
     # Returns HTTP 200 OK!
     ```
   - **Step 3.4:** Restart Primary DNS:
     ```bash
     ./macs/mac1-sarthak/start.sh
     ```

---

### Extension B: DNS TTL and Controlled Record Change
> **Goal:** Prove how DNS caching works in practice, how clients obey TTL limits, and how manual cache invalidation triggers immediate cutovers.

* **Owner:** **Sarthak (Mac 1)** controls TTL; **Any Client** observes caching.
* **Theory / Course Mapping:** DNS Caching Hierarchy, TTL Expiration, macOS `mDNSResponder`, Zero-Downtime Cutover Strategy in Cloud (AWS Route 53 / Cloudflare).

#### Step-by-Step Implementation:

1. **Set a Short TTL (30 seconds) on Primary DNS:**
   In Sarthak's `~/.config/cn-phase1/project.env`, ensure:
   ```bash
   DNS_TTL=30
   ```
   Restart DNS:
   ```bash
   ./macs/mac1-sarthak/start.sh
   ```

2. **Step 1 — Initial Query:**
   From a client machine:
   ```bash
   dig app.team1.test
   ```
   *Observe:* In the ANSWER section:
   ```
   app.team1.test.    30    IN    A    10.7.11.189
   ```
   Repeated `dig` commands show the TTL decrementing: `28`, `25`, `20`...

3. **Step 2 — Sarthak changes the DNS record to a new IP:**
   Sarthak temporarily simulates pointing the domain to a different host (e.g. `192.0.2.99` or a standby IP):
   ```bash
   ./bin/failure-demo wrong-dns-record break
   ```

4. **Step 3 — Observe Client-Side Caching (Within the 30s Window):**
   Client queries again immediately:
   ```bash
   dscacheutil -q host -a name app.team1.test
   ```
   *Observation:* The client **still receives the old IP (`10.7.11.189`)** because the OS DNS cache hasn't expired yet!

5. **Step 4 — Observe Expiration & Manual Flush:**
   - Wait 30 seconds: query returns the new IP (`192.0.2.99`).
   - OR trigger an immediate flush:
     ```bash
     sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
     dig +short app.team1.test
     # Instantly returns 192.0.2.99!
     ```

6. **Rollback:**
   ```bash
   ./bin/failure-demo wrong-dns-record rollback
   ```

* **Viva Explanation:** *"In production cloud architectures, before migrating an active service between data centers or cloud providers, engineers lower the DNS record's TTL from 86400s (24 hours) to 60s several days in advance. Once all stale caches have cleared, the DNS record is updated to the new IP. Clients switch within 60 seconds with minimal traffic loss. Afterwards, the TTL is restored to a higher value to reduce nameserver load."*

---

### Extension C: Service Isolation (macOS `pf` Firewall Rules)
> **Goal:** Zero Trust perimeter enforcement. Backends must ONLY accept incoming requests from the reverse proxy (Mac 2 Nginx). Direct client access to ports 3001 and 3002 is strictly blocked at Layer 4.

* **Owners:** **Shitanshu (Mac 3)** restricts port 3001; **Shane (Mac 4)** restricts port 3002; **Preetish (Mac 2)** verifies access.
* **Theory / Course Mapping:** Perimeter Security, Private Subnet Emulation, Layer 4 Packet Filtering (`pf`), Defense in Depth. In cloud environments (AWS VPC), backends sit in a private subnet with Security Groups allowing ingress only from the Application Load Balancer (ALB).

#### Step-by-Step Implementation:

1. **Enable Firewall Isolation on Backend Nodes:**
   - **On Mac 3 (Shitanshu):**
     ```bash
     git pull origin main
     ./scripts/backend-firewall.sh enable 10.7.11.189 3001
     ```
   - **On Mac 4 (Shane):**
     ```bash
     git pull origin main
     ./scripts/backend-firewall.sh enable 10.7.11.189 3002
     ```

2. **Step 2 — Verify Legitimate Access (From Preetish's Edge Mac 2):**
   Preetish runs:
   ```bash
   # Edge -> Backend A
   curl -I http://10.7.7.23:3001/api/status
   # Edge -> Backend B
   curl -I http://10.7.14.16:3002/api/status
   ```
   *Result:* **HTTP 200 OK!** (Traffic from the Edge IP is explicitly permitted).

3. **Step 3 — Verify Blocked Access (From Sarthak Mac 1 or Any Client):**
   Sarthak tries to bypass the proxy and hit the backends directly:
   ```bash
   nc -vz -G 2 10.7.7.23 3001
   nc -vz -G 2 10.7.14.16 3002
   ```
   *Result:* **Connection refused / Timed out!** (Packet filter immediately rejects direct client requests).

4. **Step 4 — Verify End-to-End Service Still Works:**
   Client accesses through the domain:
   ```bash
   curl -i https://app.team1.test:8443/api/status
   ```
   *Result:* **HTTP 200 OK!** The edge forwards traffic seamlessly.

5. **Rollback (After demo):**
   ```bash
   # On Mac 3 and Mac 4:
   ./scripts/backend-firewall.sh disable
   ```

---

### Extension D: High-Availability Failover Behavior
> **Goal:** Demonstrate automated, zero-downtime failover and self-healing when a backend node crashes.

* **Owners:** **Preetish (Mac 2)** controls Nginx failover; **Shitanshu (Mac 3)** simulates failure.
* **Theory / Course Mapping:** Passive Health Checking, Circuit Breaking, Single Point of Failure (SPOF) Analysis.
  - Nginx directives in `config/nginx/nginx.conf.template`:
    ```nginx
    upstream project_backends {
        server 10.7.7.23:3001 max_fails=1 fail_timeout=5s;
        server 10.7.14.16:3002 max_fails=1 fail_timeout=5s;
    }
    proxy_connect_timeout 2s;
    proxy_next_upstream error timeout http_502 http_503 http_504;
    proxy_next_upstream_tries 2;
    ```

#### Step-by-Step Implementation:

1. **Start Live Traffic Loop (From Client Mac):**
   ```bash
   while true; do
     curl -s https://app.team1.test:8443/api/status | grep -o '"backend": "[AB]"'
     sleep 0.5
   done
   ```
   *Initial observation:* Alternates evenly:
   ```
   "backend": "A"
   "backend": "B"
   "backend": "A"
   "backend": "B"
   ```

2. **Simulate Crash of Backend A:**
   Shitanshu stops his backend on Mac 3:
   ```bash
   ./macs/mac3-shitanshu/stop.sh
   ```

3. **Observe Automated Failover:**
   The client's stream **never throws an error or drops a request**.
   Output immediately converts to:
   ```
   "backend": "B"
   "backend": "B"
   "backend": "B"
   "backend": "B"
   ```
   *What happened under the hood:* Nginx attempted to connect to Backend A, hit a TCP reset / 2s connection timeout, triggered `proxy_next_upstream`, and transparently completed the request via Backend B. It then flagged Backend A as dead for `5s` (`fail_timeout`), directing 100% of traffic to Backend B with zero added latency.

4. **Demonstrate Self-Healing Recovery:**
   Shitanshu restarts Backend A:
   ```bash
   ./macs/mac3-shitanshu/start.sh
   ```
   *Observation:* After `5s`, Nginx automatically probes Backend A again, detects it is alive, and resumes round-robin distribution (`A B A B`)!

5. **Critical Viva Defense — Single Point of Failure (SPOF) Analysis:**
   - **Question:** *"Which component in your architecture is still a Single Point of Failure?"*
   - **Answer:** *"The Edge Nginx proxy on Mac 2. If Mac 2 crashes, the entire platform goes down, even though both backends are healthy."*
   - **Question:** *"How is this eliminated in enterprise/cloud production networks?"*
   - **Answer:**
     1. **VRRP / Keepalived:** Pair two Nginx nodes with a shared Virtual IP (Floating IP). The backup node takes over the MAC/IP if the primary stops sending heartbeats.
     2. **BGP Anycast:** Announce the same IP address from multiple edge nodes via BGP; routers send traffic to the nearest healthy edge.
     3. **DNS-Based Failover:** AWS Route 53 health-checked multi-A-record pool.
     4. **Cloud Managed ALB:** Multi-AZ AWS Application Load Balancer with redundant edge proxies.

---

### Extension E: Controlled Edge Migration (DNS-Based Cutover)
> **Goal:** Migrate client traffic from the primary edge node (Preetish) to a standby edge node (Shitanshu or Shane) without changing client configuration or dropping TLS trust.

* **Owners:** **Shitanshu (Mac 3)** hosts the Standby Edge; **Sarthak (Mac 1)** conducts DNS cutover.
* **Theory / Course Mapping:** Active-Passive Edge Redundancy, Blue/Green Edge Deployment, TLS SAN sharing.

#### Step-by-Step Implementation:

1. **Prepare Standby Edge on Mac 3:**
   - Shitanshu ensures Nginx is installed (`brew install nginx`).
   - Copy `tls/server.crt` and `tls/server.key` from Preetish's setup.
   - Launch Nginx on Mac 3 bound to port 8443 proxying to both backends.

2. **Step 2 — Switch DNS Record on Sarthak (Mac 1):**
   In Sarthak's `config/dns/dnsmasq.conf`:
   ```conf
   # Update EDGE_IP to Shitanshu's LAN IP:
   address=/app.team1.test/10.7.7.23
   address=/api.team1.test/10.7.7.23
   ```
   Restart Sarthak's DNS:
   ```bash
   ./macs/mac1-sarthak/start.sh
   ```

3. **Step 3 — Observe TTL Migration:**
   - Clients with cached records continue reaching Preetish's edge briefly.
   - Once the 30s TTL expires (or after `dscacheutil -flushcache`), clients resolve `10.7.7.23` and hit the Standby Edge!
   - Standby edge logs (`~/Library/Logs/cn-phase1/nginx-access.log`) verify incoming client traffic.

---

### Extension F: Faculty-Injected Troubleshooting Challenge
> **Goal:** When the evaluator injects an unknown configuration fault into our running system, systematically diagnose and isolate the exact failing layer within 60 seconds.

* **Team Strategy:** Never randomly guess or edit files. Always apply the **OSI Bottom-Up Triage Method** out loud.

#### The 6-Step Layer Triage Checklist:

```
[Layer 3 - Network IP]      --> ping <target_ip>
[Layer 7 - DNS Resolution]  --> dig @10.7.7.126 app.team1.test
[Layer 4 - Transport TCP]   --> nc -vz <edge_ip> 8443
[Layer 5/6 - TLS Handshake] --> openssl s_client -connect <edge_ip>:8443 -servername app.team1.test
[Layer 7 - Edge Nginx HTTP] --> curl -i http://localhost:8443/__edge/health
[Layer 7 - Backend REST]    --> curl -i http://localhost:3001/api/status
```

#### Our Secret Weapon: `./bin/doctor`
Run this immediately on any client or node:
```bash
./bin/doctor
```
In 3 seconds, `doctor` tests every layer and prints:
- Which layer failed (`LOCAL NETWORK`, `DNS`, `TCP EDGE`, `TLS`, `NGINX / EDGE`, `BACKEND A`, `BACKEND B`, or `APP`).
- The exact underlying cause.
- The precise command to prove and fix it.

#### Common Faculty Sabotage Scenarios & How to Catch Them:

| Sabotage Injected by Faculty | Symptom Observed | `doctor` Output | Diagnostic Command | Immediate Fix |
|---|---|---|---|---|
| **Wrong Resolver on Client** | `curl` fails with "Could not resolve host" | `DNS: FAIL` | `cat /etc/resolver/team1.test` | Re-run `./scripts/configure-client-dns.sh` |
| **DNS Record Pointed to Wrong IP** | `dig` succeeds with `192.0.2.99`, curl times out | `DNS: FAIL (answer 192.0.2.99 != EDGE_IP)` | `dig +short app.team1.test` | Fix `EDGE_IP` in Sarthak's config & restart dnsmasq |
| **Nginx Stopped on Mac 2** | `nc -vz <edge_ip> 8443` refused | `TCP EDGE: FAIL` | `lsof -iTCP:8443 -sTCP:LISTEN` | Run `./macs/mac2-preetish/start.sh` |
| **Cert Expired / Wrong Hostname** | Browser/curl throws `SSL certificate problem` | `TLS: FAIL` | `openssl s_client -connect ...` | Re-install CA (`./scripts/install-ca.sh`) or check SAN |
| **One or Both Backends Stopped** | Curl returns `502 Bad Gateway` from Nginx | `BACKEND A: FAIL` | `nc -vz <backend_ip> 3001` | Owner runs `./macs/mac3-shitanshu/start.sh` |
| **Wrong Port Requested** | `https://app.team1.test:9999` connection refused | DNS passes, TCP fails | `nc -vz <edge_ip> 9999` | Connect to correct port `8443` |

---

## 4. The 11-Step Final Demonstration Sequence (Section 8 Script)

During evaluation, follow this exact sequence without skipping:

1. **Step 1 — Show Topology & Service Inventory:**
   - *Speaker:* **Sarthak**
   - *Action:* Display Network Architecture Diagram (`docs/diagrams.md`), table of 4 Macs, roles, and LAN IPs.
2. **Step 2 — Confirm LAN Connectivity:**
   - *Speaker:* **Sarthak**
   - *Action:* Run pairwise ping script: `ping -c 1 10.7.11.189` (all ping matrix green).
3. **Step 3 — Resolve Private Domain:**
   - *Speaker:* **Shane**
   - *Action:* On Mac 4: `dig app.team1.test` $\rightarrow$ shows resolved IP `10.7.11.189`.
4. **Step 4 — Open Service over HTTPS:**
   - *Speaker:* **Preetish**
   - *Action:* Open `https://app.team1.test:8443/` in Safari/Chrome. Show green padlock, zero warnings, valid local CA certificate.
5. **Step 5 — Show Round-Robin Load Balancing:**
   - *Speaker:* **Preetish / Shitanshu**
   - *Action:* Run 6 consecutive `curl` commands: show `X-Backend: A` and `X-Backend: B` alternating.
6. **Step 6 — Wireshark Evidence:**
   - *Speaker:* **Sarthak**
   - *Action:* Open pre-saved pcap in Wireshark. Filter:
     - `dns` (query + response with 30s TTL)
     - `tcp.flags.syn == 1` (3-way handshake SYN $\rightarrow$ SYN-ACK $\rightarrow$ ACK)
     - `tls.handshake` (ClientHello, ServerHello, Certificate, Finished)
     - Point out ephemeral client port vs well-known service ports (`53`, `8443`, `3001`).
7. **Step 7 — HTTP Caching Demonstration:**
   - *Speaker:* **Shane**
   - *Action:* Run `curl -I https://app.team1.test:8443/api/cacheable`. Show `Cache-Control: max-age=60` and `ETag`. Run conditional request with `If-None-Match` $\rightarrow$ show **HTTP 304 Not Modified**!
8. **Step 8 — Fail One Backend (HA Failover):**
   - *Speaker:* **Shitanshu & Preetish**
   - *Action:* Shitanshu kills Backend A (`./macs/mac3-shitanshu/stop.sh`). Sarthak curls 4 times $\rightarrow$ 100% served by Backend B with HTTP 200 OK! Shitanshu restarts Backend A $\rightarrow$ round-robin resumes.
9. **Step 9 — Phase 2 Resilience Demonstration:**
   - *Speaker:* **Shane & Sarthak**
   - *Action:* 
     - *Demo A:* Sarthak kills Primary DNS $\rightarrow$ Shane's backup DNS immediately answers for the client!
     - *Demo B:* Shitanshu shows firewall isolation (`./scripts/backend-firewall.sh status`) $\rightarrow$ Preetish connects, client gets blocked!
10. **Step 10 — Diagnose Faculty-Injected Fault:**
    - *Speaker:* **Whole Team**
    - *Action:* Evaluator injects fault. Team runs `./bin/doctor`, explains failing layer out loud, and applies fix.
11. **Step 11 — Individual Viva Defense:**
    - *Speaker:* **Each Teammate Individually**
    - *Action:* Answer conceptual viva questions with confidence.

---

## 5. Copy-and-Paste AI Agent Prompts for Each Teammate

Each teammate can copy their respective prompt below into their AI coding assistant (**Cursor**, **Antigravity**, **Claude Dev**, or **Copilot**) to execute their Phase 2 setup autonomously.

---

### Prompt for Preetish Ubhrani (Mac 2 — Edge Proxy & HA Failover)

```markdown
You are pairing with me on Mac 2 (Edge Nginx Proxy) for our Computer Networks Phase 2 Project.
Repo: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Preetish Ubhrani (Mac 2)
- Service: Nginx Edge Reverse Proxy + Round-Robin Load Balancer + TLS 1.3 Termination (:8443)
- Phase 2 Tasks:
  1. Extension D: Verify high-availability passive failover configuration (proxy_next_upstream, max_fails=1, fail_timeout=5s, proxy_connect_timeout 2s).
  2. Extension C: Verify that Mac 2 can access Shitanshu (3001) and Shane (3002) through their pf firewalls.
  3. Assist Extension E: Share server TLS certificates for the standby edge node.

INSTRUCTIONS:
1. Pull the latest code: `git pull origin main`.
2. Inspect `config/nginx/nginx.conf.template` to confirm failover parameters.
3. Start the edge proxy: `./macs/mac2-preetish/start.sh`.
4. Run `./macs/mac2-preetish/status.sh` to confirm healthy operation.
5. Test connectivity to backends:
   `curl -I http://10.7.7.23:3001/api/status`
   `curl -I http://10.7.14.16:3002/api/status`
6. Run continuous curls during the failover drill to verify zero dropped requests.
```

---

### Prompt for Shitanshu Tiwari (Mac 3 — Backend A & Service Isolation)

```markdown
You are pairing with me on Mac 3 (Backend A) for our Computer Networks Phase 2 Project.
Repo: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Shitanshu Tiwari (Mac 3)
- Service: Backend A (Python REST, port 3001/TCP)
- Phase 2 Tasks:
  1. Task C: Run Backend A on port 3001.
  2. Extension C: Enable macOS pf firewall to isolate port 3001 so ONLY Preetish (10.7.11.189) and localhost can connect.
  3. Extension D: Participate in backend failover drill (stopping and restarting Backend A).
  4. Extension E: Host standby Nginx edge if required.

INSTRUCTIONS:
1. Pull the latest code: `git pull origin main`.
2. Start Backend A: `./macs/mac3-shitanshu/start.sh`.
3. Check status: `./macs/mac3-shitanshu/status.sh`.
4. Test enabling the PF firewall isolation:
   `./scripts/backend-firewall.sh enable 10.7.11.189 3001`
5. Verify firewall rules with `./scripts/backend-firewall.sh status`.
6. When testing is complete or before git commits, test rollback:
   `./scripts/backend-firewall.sh disable`
```

---

### Prompt for Shane (Mac 4 — Backend B & Backup DNS Resolver)

```markdown
You are pairing with me on Mac 4 (Backend B & Backup DNS) for our Computer Networks Phase 2 Project.
Repo: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Shane (Mac 4)
- Service: Backend B (port 3002/TCP) + Backup DNS Resolver (port 53/UDP) + Secondary Client
- Phase 2 Tasks:
  1. Task C: Run Backend B on port 3002.
  2. Extension A: Launch secondary dnsmasq resolver with identical records pointing to Preetish (10.7.11.189).
  3. Extension A: Configure client dual-resolver in /etc/resolver/team1.test.
  4. Extension C: Enable macOS pf firewall isolation on port 3002 for Preetish's IP.

INSTRUCTIONS:
1. Pull the latest code: `git pull origin main`.
2. Start Backend B: `./macs/mac4-shane/start.sh`.
3. Start Backup DNS Resolver:
   `./scripts/setup-backup-dns.sh start`
4. Verify backup resolver answers queries:
   `dig +short -p 53 @127.0.0.1 app.team1.test`
5. Configure dual DNS on Mac 4:
   `./scripts/setup-backup-dns.sh configure-client 10.7.7.126 10.7.14.16`
6. Test isolation firewall on port 3002:
   `./scripts/backend-firewall.sh enable 10.7.11.189 3002`
```

---

### Prompt for Sarthak Mishra (Mac 1 — Controller, Primary DNS & Triage)

```markdown
You are pairing with me on Mac 1 (Lead & Primary DNS) for our Computer Networks Phase 2 Project.
Repo: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Sarthak Mishra (Mac 1, Lead)
- Service: Primary DNS (dnsmasq, port 53), Controller, Test Client
- Phase 2 Tasks:
  1. Extension B: Configure DNS TTL=30s and execute controlled record change demo.
  2. Extension A: Verify backup DNS takeover when Mac 1 dnsmasq is stopped.
  3. Extension E: Execute DNS record migration for standby edge cutover.
  4. Extension F: Run `./bin/doctor` and lead systematic layer-by-layer triage for the faculty challenge.
  5. Coordinate full system tests: `./bin/test-all` and collect evidence: `./bin/collect-evidence`.

INSTRUCTIONS:
1. Ensure latest code: `git pull origin main`.
2. Start Primary DNS: `./macs/mac1-sarthak/start.sh`.
3. Run whole-system health check: `./bin/doctor` and `./bin/test-all`.
4. Test TTL cutover: `./bin/failure-demo wrong-dns-record break` followed by `rollback`.
5. Capture packet evidence: `./scripts/capture-packets.sh 60`.
```

---

## 6. Deliverables & Evidence Collection Checklist

Before the Review 2 evaluation slot, collect and commit the following evidence into `evidence/phase2/`:

- [ ] **Extension A:** Screenshot of `dig app.team1.test` resolving through Shane's IP (`10.7.14.16#53`) while Mac 1's dnsmasq is stopped.
- [ ] **Extension B:** Terminal log showing `dig` TTL counting down (`30`, `25`, `20`...) and `dscacheutil -flushcache` forcing immediate IP cutover.
- [ ] **Extension C:** Terminal comparison:
  - From Mac 2 (Edge): `curl http://...:3001/api/status` $\rightarrow$ `200 OK`.
  - From Mac 1 (Client): `nc -vz -G 2 ... 3001` $\rightarrow$ Connection refused (Blocked by `pf`).
- [ ] **Extension D:** Terminal log of continuous curl loop during failover showing seamless transition from `A B A B` $\rightarrow$ `B B B B` without errors.
- [ ] **Extension E:** DNS cutover log showing traffic routing to standby edge node.
- [ ] **Extension F:** Screenshot of `./bin/doctor` diagnosing a simulated fault layer-by-layer.
- [ ] **Wireshark Capture:** `.pcap` containing DNS query/response, TCP handshake, TLS handshake, and failover re-routing.

---
*Ready to execute! Pull the latest repo changes and let's ace Review 2!*
