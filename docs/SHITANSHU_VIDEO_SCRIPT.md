# Computer Networks Phase 1 — 5-Minute Video Demonstration Guide
**Presenter:** Shitanshu Tiwari (Mac 3: Backend A)  
**Cluster Team:** Sarthak Mishra (Mac 1), Preetish Ubhrani (Mac 2), Shitanshu Tiwari (Mac 3), Shane (Mac 4)  
**Total Target Duration:** Exactly 5 Minutes (0:00 – 5:00)  
**Video Output Goal:** Show complete proof of all Phase 1 tasks (Tasks A–G), failure resilience, and 100% automated test compliance.

---

## 1. Recording Setup & Preparation Checklist

Before hitting record:
1. **Screen Resolution:** 1080p (1920x1080) or Retina display scaled cleanly.
2. **Terminal Setup:**
   - Open your terminal (e.g., iTerm2 or Terminal.app) with a clean dark theme and large font (`20pt+`).
   - Have **2 terminal tabs** ready:
     - **Tab 1:** Main demonstration tab (navigate to repo root).
     - **Tab 2:** Backend control tab (on Shitanshu's Mac) to execute `./macs/mac3-shitanshu/stop.sh` during the failure demo.
3. **Verify All Services Are Running:**
   ```bash
   ./bin/doctor
   ```
   *(Ensure it prints: `All layers healthy. Load balancing: B A B A B A`)*.
4. **Microphone:** Clear audio, quiet room, speak with confidence and steady pacing.

---

## 2. Minute-by-Minute Master Video Script

```
┌──────────┬────────────────────────────────────────────────────────────────┐
│ Time     │ Segment Description                                            │
├──────────┼────────────────────────────────────────────────────────────────┤
│ 0:00–0:35│ 1. Introduction, Team Roles & Physical Topology (Task A)       │
│ 0:35–1:15│ 2. Private DNS Server & Custom Resolver Verification (Task B) │
│ 1:15–2:00│ 3. HTTPS / TLS 1.3 Native Trust & Certificate Chain (Task E)   │
│ 2:00–2:45│ 4. HTTP/2 Reverse Proxy & Alternating Load Balancing (Tasks C&D)│
│ 2:45–3:30│ 5. HTTP Caching & 304 Not Modified Revalidation (Task F)       │
│ 3:30–4:15│ 6. Packet Analysis & Wireshark Protocol Flow (Task G)          │
│ 4:15–4:45│ 7. Fault Resilience Demo: Backend Node Outage (Section 6.3)    │
│ 4:45–5:00│ 8. Automated Integration Suite (9/9 PASS) & Closing           │
└──────────┴────────────────────────────────────────────────────────────────┘
```

---

### Segment 1: Introduction & Physical Topology (Task A)
**Timestamp:** `0:00 – 0:35` (35 seconds)  
**Visual on Screen:** Show terminal with `./scripts/macos-network-info.sh` or display the topology table from `docs/REPORT_TEMPLATE.md`.

> **Voiceover (Shitanshu):**  
> *"Hello everyone and welcome to our Computer Networks Phase 1 Demonstration. I'm Shitanshu Tiwari, and together with my teammates Sarthak Mishra, Preetish Ubhrani, and Shane, we have designed and deployed a distributed, multi-node private network cluster across four real macOS laptops connected on a shared private local area network.*  
>  
> *Here is our network topology on subnet `10.7.0.0/19`:  
> - Mac 1, Sarthak, operates our authoritative private DNS server via `dnsmasq` on `10.7.7.126`.  
> - Mac 2, Preetish, acts as our secure Nginx Edge Reverse Proxy on `10.7.11.189`, handling TLS termination and load balancing.  
> - Mac 3, my machine, runs Backend A on port `3001` at `10.7.7.23`.  
> - Mac 4, Shane, runs Backend B on port `3002` at `10.7.14.16`.*  
>  
> *As demonstrated by our pairwise ping matrix across all nodes, we achieve 100% packet delivery with zero loss."*

**Commands to run on screen:**
```bash
ping -c 2 10.7.11.189
ping -c 2 10.7.14.16
```

---

### Segment 2: Private DNS & Scoped Resolver (Task B)
**Timestamp:** `0:35 – 1:15` (40 seconds)  
**Visual on Screen:** Run `dig` commands in the terminal.

> **Voiceover (Shitanshu):**  
> *"Next is Task B: Private Domain Name Resolution. We created a private root zone `team1.test` and registered `app.team1.test` and `api.team1.test`.*  
>  
> *Notice that we do not use public DNS or static `/etc/hosts` hacks. Sarthak's Mac 1 runs `dnsmasq` on port 53. On every client machine, macOS is configured with a scoped resolver file at `/etc/resolver/team1.test` pointing to Sarthak's IP.*  
>  
> *Let's test resolution using `dig`:*  
> *(Run command)*  
> *Querying our DNS server directly returns Preetish's Edge IP `10.7.11.189` in 0 milliseconds. Furthermore, standard system resolution via the OS resolver matches perfectly."*

**Commands to run on screen:**
```bash
cat /etc/resolver/team1.test
dig @10.7.7.126 app.team1.test +short
dig app.team1.test +short
```

---

### Segment 3: Native Transport Layer Security & PKI (Task E)
**Timestamp:** `1:15 – 2:00` (45 seconds)  
**Visual on Screen:** Run `curl -v` and `openssl s_client`.

> **Voiceover (Shitanshu):**  
> *"Moving to Task E: Transport Layer Security. Our Edge reverse proxy terminates TLS on port 8443. Crucially, we enforce strict zero-trust standards: we never use `-k` or `--insecure`.*  
>  
> *Preetish generated a dedicated private Certificate Authority root using ECDSA with curve prime256v1, and signed an edge certificate with Subject Alternative Names for `app.team1.test` and `api.team1.test`. This public CA certificate was imported into the macOS System Keychain.*  
>  
> *When we inspect the handshake with OpenSSL s_client, we see:*  
> *- Protocol is TLS 1.3,*  
> *- Cipher is `TLS_AES_256_GCM_SHA384`,*  
> *- Key exchange utilizes post-quantum hybrid group `X25519MLKEM768`,*  
> *- And Verification returns code 0: Verification OK.*  
>  
> *A clean `curl` to our domain completes natively with complete cryptographic trust."*

**Commands to run on screen:**
```bash
openssl s_client -connect app.team1.test:8443 -servername app.team1.test </dev/null 2>&1 | grep -E "Protocol|Cipher|Verification|CN="
curl https://app.team1.test:8443/__edge/health
```

---

### Segment 4: HTTP/2 Reverse Proxy & Round-Robin Load Balancing (Tasks C & D)
**Timestamp:** `2:00 – 2:45` (45 seconds)  
**Visual on Screen:** Run 8 consecutive curls showing alternating backends.

> **Voiceover (Shitanshu):**  
> *"In Tasks C and D, we demonstrate our backend services and reverse proxy load balancing.*  
>  
> *Behind Preetish's Nginx edge, we have two independent upstream microservices: Backend A running on my machine, and Backend B running on Shane's machine. Nginx negotiates HTTP/2 binary framing with the client, and proxies requests to our upstream pool.*  
>  
> *Watch what happens when we send a sequence of requests to `/api/status`:*  
> *(Run loop)*  
> *B ... A ... B ... A ... B ... A!*  
>  
> *Each backend injects its unique `X-Backend` header and JSON metadata. The reverse proxy distributes incoming requests in a perfect, deterministic round-robin pattern across the distributed nodes."*

**Commands to run on screen:**
```bash
for i in {1..8}; do curl -s https://app.team1.test:8443/api/status | jq -r .backend; done
```

---

### Segment 5: HTTP Caching & Conditional Revalidation (Task F)
**Timestamp:** `2:45 – 3:30` (45 seconds)  
**Visual on Screen:** Show first fetch with 200, followed by conditional request returning 304.

> **Voiceover (Shitanshu):**  
> *"For Task F, we implement efficient HTTP caching and conditional revalidation on `/api/cacheable`.*  
>  
> *When a client first requests the resource, the edge returns `HTTP/2 200 OK` with two critical headers: `Cache-Control: max-age=60`, declaring the payload fresh for 60 seconds, and an entity tag `ETag`.*  
>  
> *When the client revalidates using the conditional header `If-None-Match`, the server checks whether the underlying data has changed.*  
> *(Run conditional curl)*  
> *Notice the result: `HTTP/2 304 Not Modified` with `content-length: 0`! The client reuses its cached copy, saving network bandwidth and compute overhead."*

**Commands to run on screen:**
```bash
curl -i https://app.team1.test:8443/api/cacheable
curl -i -H 'If-None-Match: "cache-v1"' https://app.team1.test:8443/api/cacheable | head -n 10
```

---

### Segment 6: Wireshark Packet Capture & Protocol Hierarchy (Task G)
**Timestamp:** `3:30 – 4:15` (45 seconds)  
**Visual on Screen:** Open Wireshark showing captured packets or show the capture output summary from `evidence/`.

> **Voiceover (Shitanshu):**  
> *"In Task G, we performed packet analysis using `tcpdump` and Wireshark to verify the complete protocol encapsulation down to the transport layer.*  
>  
> *Filtering on `dns`, we observe the client sending a UDP query on port 53 to Sarthak's DNS server and receiving an A-record answer for `10.7.11.189`.*  
>  
> *Next, filtering on `tcp.flags.syn==1`, we capture the TCP 3-way handshake on port 8443: SYN from the client, SYN-ACK from Preetish's edge, and client ACK.*  
>  
> *Then, under `tls.handshake`, we see the TLS 1.3 `ClientHello` packet carrying the Server Name Indication `app.team1.test`, followed by the `ServerHello` agreeing on encryption parameters, before transitioning into encrypted Application Data."*

**Filter to point out or display:**
```text
Display Filters in Wireshark:
1. dns                                    -> Port 53 UDP query & response
2. tcp.flags.syn==1                       -> TCP 3-way handshake on 8443
3. tls.handshake.type==1                  -> ClientHello with SNI
4. tcp.port==8443                         -> Encrypted application records
```

---

### Segment 7: Fault Resilience & Single Node Outage (Section 6.3)
**Timestamp:** `4:15 – 4:45` (30 seconds)  
**Visual on Screen:** Switch to Tab 2 to stop Backend A, then run curl in Tab 1 showing uninterrupted traffic via Backend B.

> **Voiceover (Shitanshu):**  
> *"Now we demonstrate system resilience under hardware failure.*  
>  
> *I am now going to intentionally kill Backend A on my machine:*  
> *(Execute `./macs/mac3-shitanshu/stop.sh` in Tab 2)*  
>  
> *Now, in Tab 1, let's curl our domain again:*  
> *(Run curl in Tab 1)*  
> *Notice: Zero downtime. Every single request continues to succeed with `200 OK`, now served 100% by Shane's Backend B.*  
>  
> *Nginx's upstream passive health checks automatically detected the failure and redirected traffic without dropping client connections. When I restart Backend A, Nginx seamlessly re-admits it to the round-robin pool."*

**Commands to run on screen:**
```bash
# Tab 2:
./macs/mac3-shitanshu/stop.sh

# Tab 1:
for i in {1..4}; do curl -s https://app.team1.test:8443/api/status | jq -r .backend; done

# Tab 2 (restart):
./macs/mac3-shitanshu/start.sh
```

---

### Segment 8: Automated Doctor, Test-All Suite (9/9 PASS) & Conclusion
**Timestamp:** `4:45 – 5:00` (15 seconds)  
**Visual on Screen:** Run `./bin/test-all` showing all green checkmarks.

> **Voiceover (Shitanshu):**  
> *"To conclude our demonstration, we execute our automated end-to-end integration test suite:*  
> *(Run `./bin/test-all`)*  
>  
> *All 9 layers pass: Prerequisites, Local Network, DNS, TCP, TLS, Backends, HTTP/2, Load Balancing, and Caching.*  
>  
> *Thank you very much!"*

**Command to run on screen:**
```bash
./bin/test-all
```

---

## 3. Quick Video Checklist for Shitanshu
- [ ] Record in 1 continuous take (or 2 takes if comfortable splicing).
- [ ] Keep video length between **4:45 and 5:15**.
- [ ] Verify audio is loud and crisp.
- [ ] Upload video file to Google Drive / YouTube (unlisted) as specified by the professor.
