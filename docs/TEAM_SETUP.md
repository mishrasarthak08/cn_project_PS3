# Team Setup & Collaboration Guide (Phase 1)

This document provides a step-by-step onboarding and execution runbook for our 4-node distributed network infrastructure.

---

## 1. Team Members & Machine Roles

| Node | Name | GitHub / Handle | Role | Ports & Services |
|---|---|---|---|---|
| **Mac 1** | **Sarthak Mishra** (Lead) | `mishrasarthak08` | Private DNS (dnsmasq) + Controller + Test Client | `53/udp+tcp` |
| **Mac 2** | **Preetish Ubhrani** | `ubhranipreetish` | Nginx Edge: TLS 1.3 Termination, Reverse Proxy, Round-Robin Load Balancer | `8443/tcp` |
| **Mac 3** | **Shitanshu Tiwari** | Teammate | Backend A (Python stdlib REST) | `3001/tcp` |
| **Mac 4** | **Shane** | Teammate | Backend B (Python stdlib REST) + 2nd Client | `3002/tcp` |

---

## 2. Cloning the Project Repository

Every teammate should clone Sarthak's forked repository:

```bash
git clone https://github.com/mishrasarthak08/cn_project_PS3.git
cd cn_project_PS3
```

Ensure Homebrew is installed on your Mac.

---

## 3. Gathering & Sharing Network Information (Task A)

All four Macs must be connected to the **same Wi-Fi network or hotspot** (ensure router "client isolation" / "guest mode" is disabled).

Before running setup, each teammate must run:

```bash
scripts/macos-network-info.sh
```

Share your `NET_IP` with the team:
- **`DNS_IP`** = Sarthak's IP
- **`EDGE_IP`** = Preetish's IP
- **`SHITANSHU_LAN_IP`** = Shitanshu's IP (Backend A)
- **`SHANE_LAN_IP`** = Shane's IP (Backend B)

Verify pairwise connectivity:
```bash
ping <teammate-ip>
```

---

## 4. Strict Execution Order

Because higher network layers depend on lower services and the local CA certificate, execute setup **in this exact sequence**:

### Step 1: Backends First (Shitanshu & Shane)

Backends must run first so the Edge can verify reachability during its setup.

* **On Mac 3 (Shitanshu):**
  ```bash
  ./macs/mac3-shitanshu/setup.sh
  ```
  *(Enter your team name, e.g., `team1`, mode `lan`. Prompts save to `~/.config/cn-phase1/project.env`.)*

* **On Mac 4 (Shane):**
  ```bash
  ./macs/mac4-shane/setup.sh
  ```

* **Verify:**
  ```bash
  ./bin/status
  ```

---

### Step 2: Edge Setup & CA Generation (Preetish)

Preetish's setup generates our private Root CA and issues the server TLS certificate for `app.<team>.test`.

* **On Mac 2 (Preetish):**
  ```bash
  ./macs/mac2-preetish/setup.sh
  ```
  *When prompted for IPs, provide:*
  - `Sarthak's (DNS server) LAN IP`
  - `Shitanshu's (Backend A) LAN IP`
  - `Shane's (Backend B) LAN IP`

* **Commit and Push the Public CA Cert:**
  The private key stays strictly on Preetish's Mac (`~/.config/cn-phase1/tls/ca.key`). The **public certificate** `pki/ca.crt` must be shared via git so Sarthak and clients can trust the domain without `-k` / `--insecure`:
  ```bash
  git add pki/ca.crt
  git commit -m "feat(pki): publish team CA public certificate"
  git push origin main
  ```

---

### Step 3: DNS Server & Controller Setup (Sarthak)

Once Preetish has pushed `pki/ca.crt`:

* **On Mac 1 (Sarthak):**
  ```bash
  git pull
  ./macs/mac1-sarthak/setup.sh
  ```
  *When prompted for IPs, provide:*
  - `Preetish's (edge) LAN IP`
  - `Shitanshu's (Backend A) LAN IP`
  - `Shane's (Backend B) LAN IP`

Setup will install `dnsmasq`, start the private DNS server on port 53, install the scoped resolver `/etc/resolver/<zone>`, and import `pki/ca.crt` into the macOS System Keychain.

---

### Step 4: Configure Additional Client Machines (Shane / Evaluator)

To access `https://app.team1.test:8443` natively on Mac 4 or any additional machine:

```bash
git pull
scripts/configure-client-dns.sh
```
*(Enter Sarthak's DNS IP when prompted. This configures `/etc/resolver/team1.test` and installs the trusted CA cert.)*

---

## 5. Daily Operations & Verification Commands

Any teammate can run these commands from the repo root:

```bash
./bin/status              # Full multi-node status check from this machine's perspective
./bin/test-all            # Runs all layered tests (DNS, TCP, TLS, Backends, LB, Caching)
./bin/doctor              # Diagnoses any failing layer with root cause and fix
./bin/collect-evidence    # Collects evidence artifacts with timestamps into evidence/
./bin/failure-demo <scen> # Reversible failure demo (wrong-resolver, wrong-dns-record, backend-a, both-backends, wrong-port)
./bin/teardown            # Cleanly stops services and removes scoped resolvers
```

---

## 6. Git & Security Rules

1. **Never commit secrets or private keys:**
   - Private keys (`~/.config/cn-phase1/tls/*.key`), `.env` files, and tunnel tokens are kept local and ignored by `.gitignore`.
2. **Only commit the public certificate:**
   - `pki/ca.crt` is safe to commit.
3. **No `-k` / `--insecure` in scripts:**
   - Native TLS trust is mandatory.

---

## 7. Viva Preparation — Individual Responsibilities

During the evaluation, each member will be asked questions about their node and the overall network:

* **Sarthak (Mac 1 - DNS & Client):**
  - Explain how `dnsmasq` acts as an authoritative nameserver for `.test`.
  - Explain `/etc/resolver/` scoped resolution vs system-wide DNS.
  - Explain DNS query flow (UDP/53, ephemeral source port, TTL).
  - Demonstrate DNS failure injection via `./bin/failure-demo wrong-dns-record break` and explain why `ping` still works even if DNS fails.

* **Preetish (Mac 2 - Nginx Edge & TLS):**
  - Explain TLS 1.3 handshake, SNI (`app.team1.test`), and Subject Alternative Names (SAN).
  - Explain difference between Root CA and Server Certificate.
  - Explain reverse proxy vs forward proxy.
  - Explain round-robin upstream scheduling and passive failover (`max_fails=1`, `fail_timeout=5s`, `proxy_next_upstream`).
  - Demonstrate what happens when both backends are down (`502 Bad Gateway`).

* **Shitanshu & Shane (Macs 3 & 4 - Backends & Caching):**
  - Explain `0.0.0.0` (all interfaces) vs `127.0.0.1` (loopback only).
  - Explain HTTP response headers: `X-Backend: A|B`, `Cache-Control: max-age=60`, and `ETag`.
  - Explain conditional validation: `If-None-Match` and `304 Not Modified`.
  - Demonstrate stopping one backend and showing seamless failover to the other node.
