# Computer Networks Phase 1 — 5-Minute Master Video Demonstration Playbook
**Presenter:** Sarthak Mishra (Mac 1: Lead, DNS Server & Primary Test Client)  
**Cluster Team:** Sarthak Mishra (Mac 1), Preetish Ubhrani (Mac 2), Shitanshu Tiwari (Mac 3), Shane (Mac 4)  
**Target Duration:** Exactly 5 Minutes (0:00 – 5:00)  
**Video File Name Format:** `CN_Phase1_PS3_Type1.mp4`

---

## 1. Quick Recording Preparation Checklist

Before starting recording on Mac 1:
1. **Resolution & Audio:** 1080p (1920x1080), clean microphone, quiet room.
2. **Terminal Setup:**
   - Use a clear dark terminal with a large font size (`20pt+`).
   - Split your screen or keep 2 tabs open:
     - **Tab 1:** Main demonstration tab (navigate to `~/Desktop/cn_project_PS3`).
     - **Tab 2:** Wireshark / test evidence tab.
3. **Pre-flight Check:**
   Run `./bin/doctor` on Mac 1 to ensure all nodes are connected and green.

---

## 2. Minute-by-Minute Master Video Script

```
┌──────────┬────────────────────────────────────────────────────────────────┐
│ Time     │ Segment Description & Tasks                                    │
├──────────┼────────────────────────────────────────────────────────────────┤
│ 0:00–1:00│ Part 1A: Team Intro, Roles & Network Topology (Task A)         │
│ 1:00–2:00│ Part 1B: Private DNS (dnsmasq) & PKI Trust Root CA (Task B & E)│
│ 2:00–3:00│ Part 2A: HTTPS TLS 1.3 & Round-Robin Load Balancing (Task C&D) │
│ 3:00–4:00│ Part 2B: HTTP Caching (304) & Wireshark Packet Proof (Task F&G)│
│ 4:00–5:00│ Part 3: Failure Resilience Demo & Automated Test Suite         │
└──────────┴────────────────────────────────────────────────────────────────┘
```

---

### **Part 1A: Team Intro & Network Topology (0:00 – 1:00)**

**Visual on Screen:** Show terminal with `./scripts/macos-network-info.sh` and ping tests.

> **Voiceover (Sarthak):**  
> *"Hello everyone, welcome to Team PS3's Phase 1 Computer Networks demonstration. I'm Sarthak Mishra, the team lead, presenting from Mac 1. Our team consists of Preetish Ubhrani on Mac 2, Shitanshu Tiwari on Mac 3, and Shane on Mac 4.*  
>  
> *For our infrastructure, we deployed a distributed, multi-node cluster across four physical macOS laptops on a shared private local area network (subnet `10.7.0.0/19`).*  
>  
> *Here is our active node topology:  
> - **Mac 1 (My Mac):** `10.7.7.126` — Authoritative Private DNS Server using `dnsmasq` and primary test controller.  
> - **Mac 2 (Preetish):** `10.7.11.189` — Nginx Edge Reverse Proxy terminating TLS 1.3 on port `8443` and load balancing requests.  
> - **Mac 3 (Shitanshu):** `10.7.7.23` — Backend Application A running on port `3001`.  
> - **Mac 4 (Shane):** `10.7.14.16` — Backend Application B running on port `3002`.*  
>  
> *Let's confirm 100% pairwise IP reachability with 0% packet loss across the nodes."*

#### **Commands to run on Mac 1:**
```bash
# Verify local IP
./scripts/macos-network-info.sh

# Pairwise ping verification (0% packet loss)
ping -c 2 10.7.11.189
ping -c 2 10.7.7.23
ping -c 2 10.7.14.16
```

---

### **Part 1B: Private DNS & PKI Trust Setup (1:00 – 2:00)**

**Visual on Screen:** Show `dnsmasq` answering and scoped resolver `/etc/resolver/team1.test`.

> **Voiceover (Sarthak):**  
> *"Now let's examine Task B: Private DNS Infrastructure. Mac 1 runs `dnsmasq` on UDP port 53 authoritatively managing our custom `.team1.test` zone.*  
>  
> *Instead of polluting static `/etc/hosts` files or changing global router settings, each Mac uses a scoped resolver at `/etc/resolver/team1.test`. All queries for `.team1.test` route to Mac 1, while regular internet DNS remains untouched.*  
>  
> *When we query `app.team1.test`, it resolves directly to Preetish's Edge IP `10.7.11.189` in under 1 millisecond. When we query public DNS `8.8.8.8`, it returns `NXDOMAIN`, proving our namespace is strictly private.*  
>  
> *For PKI (Task E), Preetish generated a custom Root CA (`pki/ca.crt`), which we installed into our macOS System Keychain. This guarantees native cryptographic trust with zero security warnings and no `-k` flags."*

#### **Commands to run on Mac 1:**
```bash
# Check scoped resolver
cat /etc/resolver/team1.test

# Query private DNS (Resolves to Edge 10.7.11.189)
dig @127.0.0.1 app.team1.test +short
dig app.team1.test +short

# Query public DNS (Proves private zone isolation)
dig @8.8.8.8 app.team1.test
```

---

### **Part 2A: HTTPS, TLS 1.3 & Round-Robin Load Balancing (2:00 – 3:00)**

**Visual on Screen:** Run `curl -v` and the load balancing loop.

> **Voiceover (Sarthak):**  
> *"In Task D & E, all external traffic hits Preetish's Nginx Edge proxy on port `8443`.*  
>  
> *Running `curl -v` reveals a complete TLS 1.3 handshake with HTTP/2 binary framing. Notice that the server certificate presents Subject Alternative Names for `app.team1.test` and `api.team1.test`, verified cleanly by macOS's trust store.*  
>  
> *Next, let's verify round-robin load balancing. When we send consecutive requests to `https://app.team1.test:8443/api/status`, Nginx distributes traffic evenly across Backend A on Mac 3 and Backend B on Mac 4, returning an exact alternating sequence: A, B, A, B."*

#### **Commands to run on Mac 1:**
```bash
# Clean TLS 1.3 Handshake (No -k flag!)
curl -v https://app.team1.test:8443/api/status 2>&1 | grep -E "SSL connection|ALPN|Server certificate|verify ok|HTTP/2 200"

# 6 Consecutive requests showing perfect alternating round-robin
for i in {1..6}; do curl -s https://app.team1.test:8443/api/status; echo ""; done
```

---

### **Part 2B: HTTP Caching & Wireshark Packet Inspection (3:00 – 4:00)**

**Visual on Screen:** Run caching curl commands, then briefly show Wireshark.

> **Voiceover (Sarthak):**  
> *"In Task F, we implemented HTTP caching headers. Our `/api/cacheable` endpoint serves `Cache-Control: max-age=60` and an `ETag` entity tag.*  
>  
> *On the initial request, we receive `HTTP/2 200 OK` with the full payload. When the client makes a conditional request with `If-None-Match`, the server responds with `HTTP/2 304 Not Modified` and zero content length, confirming bandwidth is preserved.*  
>  
> *In Wireshark (Task G), we inspect four key protocol phases:  
> 1. DNS query on UDP port 53.  
> 2. TCP 3-way handshake (`SYN -> SYN-ACK -> ACK`) establishing port 8443.  
> 3. TLS 1.3 ClientHello with SNI and ServerHello.  
> 4. Encrypted Application Data records ensuring HTTP headers and payloads remain unreadable to passive eavesdroppers."*

#### **Commands to run on Mac 1:**
```bash
# Initial request with Cache-Control and ETag
curl -s -i https://app.team1.test:8443/api/cacheable | grep -E "HTTP|etag|cache-control|x-backend"

# Conditional Revalidation (Returns 304 Not Modified with 0 bytes body)
curl -s -i -H 'If-None-Match: "cache-v1"' https://app.team1.test:8443/api/cacheable | head -n 6
```

---

### **Part 3: Failure Demonstration & Automated Integration Suite (4:00 – 5:00)**

**Visual on Screen:** Demonstrate Backend A failure failover, restore it, and run `./bin/test-all`.

> **Voiceover (Sarthak):**  
> *"Finally, let's demonstrate Section 6.3 Failure Scenario Option A: Backend Node Outage and Edge Resilience.*  
>  
> *Currently, traffic alternates evenly between Backend A and B. Now, Shitanshu will stop Backend A on Mac 3.*  
>  
> *(Shitanshu stops Backend A)*  
>  
> *Notice what happens: Nginx's passive health check (`max_fails=1`, `fail_timeout=5s`, `proxy_next_upstream`) immediately detects that port 3001 is unavailable. With zero downtime, 100% of client traffic seamlessly fails over to Shane's Backend B.*  
>  
> *(Shitanshu restarts Backend A)*  
>  
> *Once Backend A comes back online, Nginx automatically restores it to the round-robin pool.*  
>  
> *To conclude our demonstration, let's execute our end-to-end automated test suite `./bin/test-all`. As you can see, all 9 comprehensive test suites across DNS, TCP, TLS, Backends, Load Balancing, and Caching pass with flying colors.*  
>  
> *Thank you!"*

#### **Commands to run on Mac 1:**
```bash
# 1. Before failure: alternating A and B
for i in {1..2}; do curl -s https://app.team1.test:8443/api/status; echo ""; done

# 2. After Shitanshu stops Backend A: 100% routed to Backend B
for i in {1..4}; do curl -s https://app.team1.test:8443/api/status; echo ""; done

# 3. After Shitanshu restarts Backend A: alternating restored
for i in {1..4}; do curl -s https://app.team1.test:8443/api/status; echo ""; done

# 4. Run automated test suite (All tests PASS!)
./bin/test-all
```

---

## 3. Quick Copy-Paste Command Sheet for Mac 1

```bash
# --- PART 1: TOPOLOGY & DNS ---
./scripts/macos-network-info.sh
ping -c 2 10.7.11.189
ping -c 2 10.7.7.23
ping -c 2 10.7.14.16
cat /etc/resolver/team1.test
dig @127.0.0.1 app.team1.test +short
dig app.team1.test +short
dig @8.8.8.8 app.team1.test

# --- PART 2: TLS, LOAD BALANCING & CACHE ---
curl -v https://app.team1.test:8443/api/status 2>&1 | grep -E "SSL connection|ALPN|Server certificate|verify ok|HTTP/2 200"
for i in {1..6}; do curl -s https://app.team1.test:8443/api/status; echo ""; done
curl -s -i https://app.team1.test:8443/api/cacheable | grep -E "HTTP|etag|cache-control|x-backend"
curl -s -i -H 'If-None-Match: "cache-v1"' https://app.team1.test:8443/api/cacheable | head -n 6

# --- PART 3: FAILOVER DEMO & TEST-ALL ---
for i in {1..4}; do curl -s https://app.team1.test:8443/api/status; echo ""; done
./bin/test-all
```
