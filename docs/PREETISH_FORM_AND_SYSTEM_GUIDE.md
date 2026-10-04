# Computer Networks Phase 1 — Form Submission & System Response Guide
**Role:** Preetish Ubhrani (Mac 2: Nginx Edge, TLS Termination, Reverse Proxy & Load Balancing)  
**Cluster Team:** Sarthak Mishra (Mac 1), Preetish Ubhrani (Mac 2), Shitanshu Tiwari (Mac 3), Shane (Mac 4)  
**Edge IP:** `10.7.11.189` | **MAC:** `2e:3e:87:1c:cc:ab` | **Subnet:** `/19` (`255.255.224.0`)  

---

## 1. Quick Terminal Commands Cheat Sheet for Preetish
If the evaluator or the submission form asks you to **"run a command to prove X on your system"**, copy-paste these exact commands on your Mac:

| What is Asked | Command to Run on Preetish's Mac | What It Proves |
|---|---|---|
| **Your IP & MAC Address** | `./scripts/macos-network-info.sh` | Prints IP `10.7.11.189`, MAC `2e:3e:87:1c:cc:ab`, Interface `en0` |
| **Edge Listening Ports** | `lsof -nP -iTCP:8443 -sTCP:LISTEN` | Proves Nginx is actively bound and listening on port `8443` |
| **Verify Nginx Service** | `ps aux \| grep nginx` or `./bin/status` | Shows Nginx master and worker processes running |
| **Show Nginx Configuration** | `cat ~/.config/cn-phase1/nginx/nginx.conf` | Displays upstream block, TLS settings, and proxy headers |
| **Show TLS Certificate Info** | `openssl x509 -in ~/.config/cn-phase1/tls/server.crt -text -noout \| grep -E "Subject:|Issuer:|DNS:"` | Shows SANs (`app.team1.test`, `api.team1.test`) and Issuer CA |
| **Direct Health of Upstreams** | `curl -s http://10.7.7.23:3001/api/status && echo "" && curl -s http://10.7.14.16:3002/api/status` | Proves direct LAN reachability from Mac 2 to both Backend A and B |
| **Test Full Edge Path Locally** | `curl -i https://app.team1.test:8443/api/status` | Returns `HTTP/2 200 OK` with `x-backend` header |
| **Watch Live Edge Traffic** | `tail -f ~/Library/Logs/cn-phase1/nginx-access.log` | Displays incoming client requests in real-time |
| **Run Whole-System Doctor** | `./bin/doctor` | Shows green PASS across all 8 layers |

---

## 2. Form Field-by-Field Answers (Copy & Paste Reference)

### Section A: Team Details & Roles
- **Team Name:** `team1`
- **Domain Names:** `app.team1.test` (Primary Application), `api.team1.test` (API Endpoint)
- **Team Members & Role Distribution:**
  - **Mac 1:** Sarthak Mishra (`10.7.7.126`, MAC `92:82:a9:6f:7c:8f`) — Authoritative DNS Server (`dnsmasq`) & Controller
  - **Mac 2:** Preetish Ubhrani (`10.7.11.189`, MAC `2e:3e:87:1c:cc:ab`) — Edge Reverse Proxy, TLS 1.3 Termination, Load Balancer
  - **Mac 3:** Shitanshu Tiwari (`10.7.7.23`, MAC `10:9f:41:c2:d9:37`) — Backend A (`3001/TCP`)
  - **Mac 4:** Shane (`10.7.14.16`, MAC `9e:f3:a4:24:4f:f7`) — Backend B (`3002/TCP`)
- **Network Mode:** Local Area Network (`lan` mode, subnet `10.7.0.0/19`, netmask `255.255.224.0`)

---

### Section B: Private DNS (Task B)
- **Q: Which server hosts the private DNS zone, and what software is used?**  
  **A:** Mac 1 (Sarthak Mishra, `10.7.7.126:53/UDP`) running `dnsmasq`.
- **Q: What DNS records are configured?**  
  **A:**
  - `app.team1.test` -> `10.7.11.189` (A record)
  - `api.team1.test` -> `10.7.11.189` (A record)
- **Q: How is DNS resolution configured on client machines?**  
  **A:** Using macOS's native scoped resolver mechanism at `/etc/resolver/team1.test` with `nameserver 10.7.7.126` and `port 53`. This routes all `.team1.test` queries exclusively to our private DNS server without breaking public internet access.
- **Q: How was resolution verified?**  
  **A:** `dig @10.7.7.126 app.team1.test +short` and `dig app.team1.test +short`, both returning `10.7.11.189` in 0 ms.

---

### Section C: Backend Applications (Task C)
- **Q: What framework/language runs on the backends?**  
  **A:** Python 3 standard library HTTP REST server (`backends/server.py`), binding to `0.0.0.0:3001` on Mac 3 and `0.0.0.0:3002` on Mac 4.
- **Q: How does the client identify which backend processed the request?**  
  **A:** Via the custom HTTP response header `X-Backend: A` (or `B`), and the JSON body at `/api/status` containing `{"backend": "A|B", "owner": "Shitanshu|Shane", "status": "ok"}`.
- **Q: Are dedicated health probe endpoints implemented?**  
  **A:** Yes. `/__probe/a` specifically probes Backend A and `/__probe/b` probes Backend B.

---

### Section D: Reverse Proxy & Load Balancing (Task D)
- **Q: What reverse proxy software and version is deployed?**  
  **A:** `nginx/1.31.6` running on Mac 2 (`10.7.11.189:8443`).
- **Q: What load balancing policy is used?**  
  **A:** Round-robin upstream distribution across:
  ```nginx
  upstream project_backends {
      server 10.7.7.23:3001 max_fails=1 fail_timeout=10s;
      server 10.7.14.16:3002 max_fails=1 fail_timeout=10s;
  }
  ```
- **Q: How was load balancing verified?**  
  **A:** Sending 8 consecutive HTTPS requests returns an exact alternating sequence: `B A B A B A B A`.

---

### Section E: Transport Layer Security & PKI (Task E)
- **Q: What TLS version and cipher suite are negotiated?**  
  **A:**
  - **Protocol:** `TLSv1.3`
  - **Cipher Suite:** `TLS_AES_256_GCM_SHA384`
  - **Key Exchange Group:** `X25519MLKEM768` (Post-quantum hybrid Kyber key exchange)
  - **ALPN Protocol:** `h2` (HTTP/2)
- **Q: What is the PKI trust architecture?**  
  **A:**
  - Dedicated private Certificate Authority (CA) created on Mac 2: `CN=CN Phase1 Local CA (team1)`, EC curve `prime256v1`.
  - Server certificate issued with Subject Alternative Names (SAN): `DNS:app.team1.test, DNS:api.team1.test`.
  - Root public certificate `pki/ca.crt` installed into `/Library/Keychains/System.keychain` on client machines.
- **Q: Was curl tested without insecure flags?**  
  **A:** Yes. Native trust is achieved: `curl https://app.team1.test:8443/api/status` runs without `-k` or `--insecure`.

---

### Section F: HTTP Caching (Task F)
- **Q: What caching headers are served?**  
  **A:**
  - `Cache-Control: max-age=60`
  - `ETag: "cache-v1"`
- **Q: How is conditional revalidation demonstrated?**  
  **A:**
  - Initial request returns `HTTP/2 200 OK` with JSON payload.
  - Subsequent request with header `If-None-Match: "cache-v1"` returns `HTTP/2 304 Not Modified` with `content-length: 0` (0 bytes payload body).

---

### Section G: Packet Analysis & Ports (Task G)
- **Q: What ports and protocols are observed in Wireshark?**  
  **A:**
  - **DNS:** Port `53/UDP` (`ephemeral -> 53` on Mac 1)
  - **Edge HTTPS:** Port `8443/TCP` (`ephemeral -> 8443` on Mac 2)
  - **Backend A:** Port `3001/TCP` (Edge -> Mac 3)
  - **Backend B:** Port `3002/TCP` (Edge -> Mac 4)
- **Q: What Wireshark display filters isolate each phase?**  
  **A:**
  - `dns`
  - `tcp.flags.syn == 1`
  - `tls.handshake`
  - `tcp.port == 8443`

---

### Section H: Failure Handling & Resilience (Section 6.3)
- **Q: What happens when one backend node fails?**  
  **A:** Nginx's passive health check (`proxy_next_upstream error timeout http_502;`) immediately reroutes client traffic to the healthy backend without throwing errors to the client. 100% of requests succeed on Backend B.
- **Q: What happens when both backends are down?**  
  **A:** The edge server completes TCP and TLS successfully, but returns `HTTP/2 502 Bad Gateway`, proving reverse-proxy isolation.

---

## 3. High-Scoring Viva / Evaluation Answers for Preetish

**Q1: Why terminate TLS at the reverse proxy (Mac 2) instead of each backend?**  
*Answer:* "Centralizing TLS termination at the edge offloads cryptographic CPU overhead from application servers, simplifies certificate lifecycle management to a single node, enables HTTP/2 multiplexing, and allows the edge to inspect headers for intelligent load balancing and caching."

**Q2: What is the difference between an A record and a CNAME record?**  
*Answer:* "An A record directly maps a hostname to an IPv4 address (e.g., `app.team1.test -> 10.7.11.189`). A CNAME maps a hostname to another canonical hostname, requiring an additional DNS lookup round-trip."

**Q3: Why did our conditional request return 304 instead of 200?**  
*Answer:* "Because the client supplied the `If-None-Match` header matching the server's current entity tag (`ETag`). Since the resource had not mutated, the HTTP server returned `304 Not Modified` with no body, saving bandwidth."

**Q4: How does TLS 1.3 improve over TLS 1.2?**  
*Answer:* "TLS 1.3 reduces the handshake from 2 round-trip times (RTT) to 1 RTT by sending key share parameters inside the `ClientHello`. It also removes insecure obsolete legacy ciphers (such as RSA key exchange and CBC ciphers), mandating Forward Secrecy via Diffie-Hellman."
