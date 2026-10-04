# Teammate AI Agent Runbook & Prompt Handbook

This document provides **ready-to-use, complete AI prompts** for each team member. 

Each teammate can copy their respective prompt, paste it directly into their IDE AI assistant (such as **Antigravity**, **Cursor**, **Claude Dev / Cline**, **Copilot**, or **Gemini Code Assist**), and their AI will autonomously execute and verify their entire part of the project.

---

## Team Roster & Master Task Allocation

| Node | Name | Role | Primary Assigned Tasks (from Brief) | Ports & Services |
|---|---|---|---|---|
| **Mac 1** | **Sarthak Mishra** (Lead) | DNS Server + Controller + Test Client | **Task A** (LAN Matrix), **Task B** (Private DNS `dnsmasq`), **Task E** (Client CA Trust), **Task F** (Caching Revalidation), **Task G** (Packet Capture & Protocol Inspection), **Report & Evidence** | `53/udp+tcp` |
| **Mac 2** | **Preetish Ubhrani** | Nginx Edge + TLS Termination + Load Balancer | **Task A** (LAN IP), **Task D** (Reverse Proxy & Round-Robin Load Balancing), **Task E** (PKI Root CA Creation, Server Cert with SANs, TLS 1.3 on 8443) | `8443/tcp` |
| **Mac 3** | **Shitanshu Tiwari** | Backend A Service | **Task A** (LAN IP), **Task C** (Backend A Python REST, `X-Backend: A`, `0.0.0.0:3001`), **Task D & F** (LB target & ETag caching) | `3001/tcp` |
| **Mac 4** | **Shane** | Backend B Service + 2nd Client | **Task A** (LAN IP), **Task C** (Backend B Python REST, `X-Backend: B`, `0.0.0.0:3002`), **Task B** (2nd Client Scoped Resolver), **Task D & F** (LB target & ETag caching) | `3002/tcp` |

---

## Strict Execution Sequence

1. **Step 1:** Shitanshu (Mac 3) and Shane (Mac 4) launch their backends first.
2. **Step 2:** Preetish (Mac 2) launches the Nginx edge proxy, generates the Root CA, and pushes `pki/ca.crt` to GitHub.
3. **Step 3:** Sarthak (Mac 1) pulls `pki/ca.crt`, starts `dnsmasq`, and configures the resolver.
4. **Step 4:** Shane (Mac 4) configures secondary client DNS.
5. **Step 5:** Sarthak and team run `./bin/test-all`, collect evidence with `./bin/collect-evidence`, and capture packets.

---

<br/>

---

# Prompt 1: For Shitanshu Tiwari (Mac 3 — Backend A)

```markdown
You are pairing with me on my Mac (Mac 3) for our university Computer Networks Phase 1 project.
Our GitHub repository is: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Shitanshu Tiwari
- Node: Mac 3
- Service: Backend A (Python stdlib HTTP REST API)
- Port: 3001/TCP
- My Tasks from the brief:
  1. Task A: Network topology and IP identification.
  2. Task C: Run Backend A on port 3001, bound to 0.0.0.0, returning X-Backend: A and /api/status JSON with owner Shitanshu.
  3. Task D & F support: Provide upstream target for Nginx round-robin LB and serve identical ETag headers on /api/cacheable for caching tests.
  4. Failure demo support: Participate in backend failover tests (stopping/restarting Backend A).

PLEASE EXECUTE THE FOLLOWING STEPS FOR ME:

1. Clone and inspect the repository:
   - Ensure you are in the cloned cn_project_PS3 repository root.
   - Run `git pull origin main` to get the latest codebase.

2. Verify prerequisites:
   - Check if python3 is installed.
   - Run `./scripts/verify-prerequisites.sh shitanshu` and fix any issues.

3. Detect and display my LAN IP:
   - Run `./scripts/macos-network-info.sh`.
   - Print my IP clearly so I can share it with Sarthak (Mac 1) and Preetish (Mac 2).

4. Setup and start Backend A:
   - Run `./macs/mac3-shitanshu/setup.sh`.
   - When prompted:
     - Team name: team1
     - Network mode: lan
   - Start the service with `./macs/mac3-shitanshu/start.sh`.

5. Verify service health locally:
   - Run `./macs/mac3-shitanshu/status.sh`.
   - Run `curl -i http://127.0.0.1:3001/api/status` and verify that the response contains:
     - Header `X-Backend: A`
     - JSON body `{"backend": "A", "owner": "Shitanshu", "status": "ok"}`
   - Test cacheable endpoint: `curl -i http://127.0.0.1:3001/api/cacheable` and verify `Cache-Control: max-age=60` and `ETag`.

6. Prepare my Viva Answers:
   - Print a concise explanation of:
     - Why we bind to 0.0.0.0 instead of 127.0.0.1 (0.0.0.0 listens on all interfaces so Nginx on Preetish's Mac can reach it; 127.0.0.1 only permits local connections).
     - How HTTP caching works with ETag and 304 Not Modified.
     - What happens during failover when my backend is stopped (Nginx detects error/timeout and routes to Backend B).
```

---

<br/>

---

# Prompt 2: For Shane (Mac 4 — Backend B & 2nd Client)

```markdown
You are pairing with me on my Mac (Mac 4) for our university Computer Networks Phase 1 project.
Our GitHub repository is: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Shane
- Node: Mac 4
- Service: Backend B (Python stdlib HTTP REST API) + 2nd Test Client
- Port: 3002/TCP
- My Tasks from the brief:
  1. Task A: Network topology and IP identification.
  2. Task C: Run Backend B on port 3002, bound to 0.0.0.0, returning X-Backend: B and /api/status JSON with owner Shane.
  3. Task B support: Configure my Mac as a 2nd DNS client pointing to Sarthak's dnsmasq server.
  4. Task D & F support: Provide upstream target for Nginx round-robin LB and serve identical ETag headers on /api/cacheable.
  5. Failure demo support: Participate in backend failover tests (stopping/restarting Backend B).

PLEASE EXECUTE THE FOLLOWING STEPS FOR ME:

1. Clone and inspect the repository:
   - Ensure you are in the cloned cn_project_PS3 repository root.
   - Run `git pull origin main` to get the latest codebase.

2. Verify prerequisites:
   - Check if python3 is installed.
   - Run `./scripts/verify-prerequisites.sh shane` and fix any issues.

3. Detect and display my LAN IP:
   - Run `./scripts/macos-network-info.sh`.
   - Print my IP clearly so I can share it with Sarthak (Mac 1) and Preetish (Mac 2).

4. Setup and start Backend B:
   - Run `./macs/mac4-shane/setup.sh`.
   - When prompted:
     - Team name: team1
     - Network mode: lan
   - Start the service with `./macs/mac4-shane/start.sh`.

5. Verify service health locally:
   - Run `./macs/mac4-shane/status.sh`.
   - Run `curl -i http://127.0.0.1:3002/api/status` and verify that the response contains:
     - Header `X-Backend: B`
     - JSON body `{"backend": "B", "owner": "Shane", "status": "ok"}`
   - Test cacheable endpoint: `curl -i http://127.0.0.1:3002/api/cacheable` and verify `Cache-Control: max-age=60` and `ETag`.

6. Configure Second Client DNS (after Sarthak starts Mac 1):
   - When Sarthak provides his DNS_IP and Preetish pushes pki/ca.crt:
     - Run `git pull`
     - Run `scripts/configure-client-dns.sh` (enter Sarthak's DNS IP when prompted).
     - Test resolving the domain: `dig @<DNS_IP> app.team1.test +short`
     - Test HTTPS request without `-k`: `curl -v https://app.team1.test:8443/api/status`

7. Prepare my Viva Answers:
   - Print a concise explanation of:
     - Why we bind to 0.0.0.0 instead of 127.0.0.1.
     - Why both backends return the exact same ETag for /api/cacheable (so conditional revalidation works seamlessly whichever backend is chosen by round-robin).
     - How being a second client proves DNS works across multiple independent machines.
```

---

<br/>

---

# Prompt 3: For Preetish Ubhrani (Mac 2 — Nginx Edge, TLS & Load Balancer)

```markdown
You are pairing with me on my Mac (Mac 2) for our university Computer Networks Phase 1 project.
Our GitHub repository is: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Preetish Ubhrani
- Node: Mac 2
- Service: Nginx Edge Reverse Proxy + TLS Termination + Round-Robin Load Balancer + Local PKI CA Generator
- Port: 8443/TCP
- My Tasks from the brief:
  1. Task A: Network topology and IP identification.
  2. Task D: Reverse proxy and round-robin load balancing between Backend A (Shitanshu) and Backend B (Shane).
  3. Task E: PKI infrastructure — Generate local Root CA, issue server certificate with SANs (`app.team1.test`, `api.team1.test`), terminate TLS 1.3 on port 8443, and publish public `pki/ca.crt`.
  4. Resilience: Configure passive upstream health checks (`max_fails=1`, `fail_timeout=5s`, `proxy_next_upstream`).

BEFORE STARTING:
Ensure Shitanshu (Mac 3) and Shane (Mac 4) have run their backends and provided their LAN IPs!

PLEASE EXECUTE THE FOLLOWING STEPS FOR ME:

1. Clone and update the repository:
   - Run `git pull origin main` in the cn_project_PS3 repository root.

2. Verify prerequisites:
   - Check if Homebrew, nginx, and openssl are installed.
   - Run `./scripts/verify-prerequisites.sh preetish`.
   - If nginx is missing, install it: `brew install nginx`.

3. Detect and display my LAN IP:
   - Run `./scripts/macos-network-info.sh`.
   - Share my IP with Sarthak (Mac 1) so he points `app.team1.test` to my Mac.

4. Run Edge Setup & CA Generation:
   - Run `./macs/mac2-preetish/setup.sh`.
   - When prompted:
     - Team name: team1
     - Network mode: lan
     - Sarthak's (DNS server) LAN IP: <Enter Sarthak's IP>
     - Shitanshu's (Backend A) LAN IP: <Enter Shitanshu's IP>
     - Shane's (Backend B) LAN IP: <Enter Shane's IP>
   - Setup will generate:
     - Root CA key & cert in `~/.config/cn-phase1/tls/ca.key` & `ca.crt`
     - Server key & cert in `~/.config/cn-phase1/tls/server.key` & `server.crt`
     - Public CA certificate copied to `pki/ca.crt` in the repo root.
     - Custom Nginx configuration and start Nginx on port 8443.

5. CRITICAL STEP — Push the public CA certificate to GitHub:
   - Run:
     ```bash
     git add pki/ca.crt
     git commit -m "feat(pki): publish team CA public certificate"
     git push origin main
     ```
   - Notify Sarthak and Shane that `pki/ca.crt` is pushed!

6. Verify Edge & Load Balancing:
   - Run `./macs/mac2-preetish/status.sh` to confirm Nginx is running and both upstreams are healthy.
   - Run test requests through Nginx:
     ```bash
     for i in {1..6}; do curl -k -s https://127.0.0.1:8443/api/status | jq .backend; done
     ```
     (Should alternate: "A", "B", "A", "B"...)

7. Prepare my Viva Answers:
   - Print a concise explanation of:
     - Reverse proxy vs Forward proxy (Reverse proxy acts on behalf of the servers to shield them; forward proxy acts on behalf of clients).
     - TLS 1.3 handshake, SNI (Server Name Indication), and SAN (Subject Alternative Name).
     - Difference between Root CA and Server Certificate (CA signs the cert; server cert validates domain identity).
     - How passive health check and `proxy_next_upstream` seamlessly reroute requests when one backend fails.
```

---

<br/>

---

# Prompt 4: For Sarthak Mishra (Mac 1 — Lead, DNS Server & Test Client)

```markdown
You are pairing with me on my Mac (Mac 1) for our university Computer Networks Phase 1 project.
Our GitHub repository is: https://github.com/mishrasarthak08/cn_project_PS3.git

MY ROLE:
- Name: Sarthak Mishra (Team Lead)
- Node: Mac 1
- Service: Authoritative Private DNS (dnsmasq) + Cluster Controller + Primary Test Client
- Port: 53/UDP+TCP
- My Tasks from the brief:
  1. Task A: Network topology inventory, IP gathering, and pairwise ping validation.
  2. Task B: Private DNS server running `dnsmasq` resolving `app.team1.test` and `api.team1.test` to Preetish's Edge IP; scoped macOS resolver `/etc/resolver/team1.test`.
  3. Task E: Install team Root CA (`pki/ca.crt`) into macOS System Keychain to achieve native, secure TLS trust (0 warnings, NO `-k` / `--insecure`).
  4. Task F: Validate HTTP caching (`max-age=60`, `ETag`, `304 Not Modified`).
  5. Task G: Execute bounded packet captures with tcpdump/Wireshark and inspect DNS, TCP handshake, TLS handshake, and HTTP flows.
  6. Failure Demonstration & Evidence: Run `bin/failure-demo`, `bin/doctor`, `bin/collect-evidence`, and complete `docs/REPORT_TEMPLATE.md`.

BEFORE STARTING:
Ensure Preetish has run Mac 2 setup and pushed `pki/ca.crt` to GitHub!

PLEASE EXECUTE THE FOLLOWING STEPS FOR ME:

1. Pull latest changes (including `pki/ca.crt`):
   - Run `git pull origin main`.
   - Confirm `pki/ca.crt` exists.

2. Verify prerequisites:
   - Run `./scripts/verify-prerequisites.sh sarthak`.
   - Confirm `python3`, `openssl`, `curl`, `nc`, `dig`, and `dnsmasq` are all verified (`✓`).

3. Run Mac 1 Setup:
   - Run `./macs/mac1-sarthak/setup.sh`.
   - When prompted:
     - Team name: team1
     - Network mode: lan
     - Preetish's (edge) LAN IP: <Preetish IP>
     - Shitanshu's (Backend A) LAN IP: <Shitanshu IP>
     - Shane's (Backend B) LAN IP: <Shane IP>
   - When prompted for macOS sudo password, enter it to bind port 53 and create `/etc/resolver/team1.test`.

4. Run Complete Verification Suite:
   - Test DNS resolution:
     ```bash
     dig @127.0.0.1 app.team1.test +short
     dig app.team1.test +short
     ```
   - Run automated end-to-end test suite:
     ```bash
     ./bin/test-all
     ```
     (All tests for DNS, TCP, TLS, Backends, Load Balancing, and Cache must PASS).

5. Collect Evidence & Packet Captures:
   - Run automated evidence collector:
     ```bash
     ./bin/collect-evidence
     ```
   - Run bounded packet capture:
     ```bash
     scripts/capture-packets.sh 30 evidence/demo-traffic.pcap
     ```
     (While capturing, trigger traffic: `curl https://app.team1.test:8443/api/status`).

6. Run Failure Scenario Demonstration:
   - Run `./bin/failure-demo wrong-dns-record break` -> verify DNS breaks -> `./bin/failure-demo wrong-dns-record rollback`.
   - Have Shitanshu run `./bin/failure-demo backend-a break` -> run `./bin/test-all load-balancing` -> confirm 100% traffic rerouted to Shane without downtime.

7. Finalize Report & Viva Prep:
   - Fill in IP/MAC addresses in `docs/REPORT_TEMPLATE.md`.
   - Prepare Viva defense using `docs/VIVA.md`.
```

---

## Where to Find Everything in the Repository

- **Step-by-step Team Runbook:** [`docs/TEAM_SETUP.md`](file:///Users/SarMish/Downloads/cn_project-main%202/docs/TEAM_SETUP.md)
- **Detailed Task Checklist (Tasks A-G):** [`docs/PHASE1.md`](file:///Users/SarMish/Downloads/cn_project-main%202/docs/PHASE1.md)
- **Report Template for Submission:** [`docs/REPORT_TEMPLATE.md`](file:///Users/SarMish/Downloads/cn_project-main%202/docs/REPORT_TEMPLATE.md)
- **Viva Questions & Answers:** [`docs/VIVA.md`](file:///Users/SarMish/Downloads/cn_project-main%202/docs/VIVA.md)
- **Failure Demonstrations:** [`docs/FAILURE_DEMOS.md`](file:///Users/SarMish/Downloads/cn_project-main%202/docs/FAILURE_DEMOS.md)
