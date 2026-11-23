# Phase 2 Evidence & Demonstration Log
## Computer Networks Project — Private Network Service Platform
**Review 2 Value:** 50 Marks  
**Date of Execution:** 2026-11-24  
**Team Members & Active IPs:**
* **Mac 1 (Lead & Primary DNS):** Sarthak Mishra — `10.7.0.226`
* **Mac 2 (Edge Nginx Proxy & TLS):** Preetish Ubhrani — `10.7.16.162`
* **Mac 3 (Backend A & Firewall):** Shitanshu Tiwari — `10.7.2.192` (Port 3001)
* **Mac 4 (Backend B & Backup DNS):** Shane — `10.7.6.77` (Port 3002, DNS Port 53)

---

## 1. Extension A: Backup DNS Resolver Failover (15 Marks Group)

### Objective
Demonstrate that when the Primary DNS server (Mac 1) fails, client Macs seamlessly fall back to the Backup DNS server (Mac 4) with zero manual reconfiguration.

### Execution Log

#### 1. Primary DNS Stopped
```bash
# On Mac 1 (Sarthak):
pkill -9 -f dnsmasq
```

#### 2. Direct Query to Primary DNS (Timed Out)
```text
$ dig +time=2 +tries=1 @10.7.0.226 app.team1.test

; <<>> DiG 9.10.6 <<>> +time=2 +tries=1 @10.7.0.226 app.team1.test
;; connection timed out; no servers could be reached
```

#### 3. Direct Query to Backup DNS (Answered)
```text
$ dig +time=2 +tries=1 @10.7.6.77 app.team1.test

;; QUESTION SECTION:
;app.team1.test.			IN	A

;; ANSWER SECTION:
app.team1.test.		30	IN	A	10.7.16.162

;; Query time: 11 msec
;; SERVER: 10.7.6.77#53(10.7.6.77)
```

#### 4. System Resolver Fallback Proof (Non-Cached Fresh Query)
```bash
$ name="proof-1795459579.app.team1.test"
$ dscacheutil -q host -a name "$name"
name: proof-1795459579.app.team1.test
ip_address: 10.7.16.162
```
**Confirmation in Backup DNS Log (`10.7.6.77`):**
Query for `proof-1795459579.app.team1.test` from client `10.7.0.226` was logged in Shane's `~/Library/Logs/cn-phase1/dnsmasq-backup.log` and returned `10.7.16.162`.

#### 5. Restored Primary DNS
Primary DNS restarted (`PID 57776`). Both servers answer with `10.7.16.162` and 30-second TTL.

**Outcome:** **100% PASS**

---

## 2. Extension D: High-Availability Failover & Self-Healing (15 Marks Group)

### Objective
Demonstrate automated backend failover via Nginx passive health checks (`proxy_next_upstream`, `max_fails=1`, `fail_timeout=5s`, `proxy_connect_timeout 2s`) and automated self-healing upon backend recovery.

### Execution Log

#### 1. Initial State (Round-Robin)
```text
"backend": "A"
"backend": "B"
"backend": "A"
"backend": "B"
```

#### 2. Backend A Stopped on Mac 3 (`./macs/mac3-shitanshu/stop.sh`)
```bash
$ for i in {1..4}; do curl -s -k https://app.team1.test:8443/api/status; echo ""; done
{"backend": "B", "owner": "Shane", "status": "ok"}
{"backend": "B", "owner": "Shane", "status": "ok"}
{"backend": "B", "owner": "Shane", "status": "ok"}
{"backend": "B", "owner": "Shane", "status": "ok"}
```
**Nginx Access Log Entry (Edge Mac 2):**
```text
127.0.0.1 [...] "GET /api/status HTTP/2.0" 200 upstream=10.7.2.192:3001, 10.7.6.77:3002 backend=B rt=1.149
127.0.0.1 [...] "GET /api/status HTTP/2.0" 200 upstream=10.7.6.77:3002 backend=B rt=0.040
```
Nginx detected Backend A was unreachable, immediately tried Backend B via `proxy_next_upstream`, and flagged Backend A inactive for 5 seconds. **Zero 502 errors occurred.**

#### 3. Backend A Restarted & Self-Healing Verified
```bash
$ for i in {1..6}; do curl -k -s https://app.team1.test:8443/api/status | grep -o '"backend": "[AB]"'; sleep 0.2; done
"backend": "A"
"backend": "B"
"backend": "A"
"backend": "B"
"backend": "A"
"backend": "B"
```
After 5 seconds, Nginx automatically probed Backend A, confirmed recovery, and resumed 50/50 round-robin distribution.

**Outcome:** **100% PASS**

---

## 3. Extension C: Service Isolation via macOS `pf` Firewall (10 Marks Group)

### Objective
Enforce Zero-Trust network segmentation at Layer 4: backend port 3001 must ONLY accept connections from the Edge Proxy (`10.7.16.162`) and localhost (`127.0.0.1`). Direct client access from the LAN must be strictly rejected.

### Execution Log

#### 1. Rules Loaded in Anchor `com.apple/cn_backend_isolation`
```pf
pass in quick on lo0 proto tcp to any port 3001
pass in quick proto tcp from 127.0.0.1 to any port 3001
pass in quick proto tcp from 10.7.16.162 to any port 3001
block return in quick proto tcp to any port 3001
```

#### 2. Direct Access from Mac 1 Client (`10.7.0.226`) — BLOCKED
```bash
$ nc -vz -G 2 10.7.2.192 3001
nc: connectx to 10.7.2.192 port 3001 (tcp) failed: Connection refused
```
*(Packet Filter sent a TCP RST to the unauthorized client machine).*

#### 3. Authorized Access from Mac 2 Edge (`10.7.16.162`) — ALLOWED
```bash
$ curl -I http://10.7.2.192:3001/api/status
HTTP/1.1 200 OK
Server: cn-backend/1.0 Python/3.9.6
X-Backend: A
```

#### 4. End-to-End Client Request via Domain — PROXIED
```bash
$ curl -k -i https://app.team1.test:8443/api/status
HTTP/2 200 
server: nginx/1.31.9
x-backend: A
{"backend": "A", "owner": "Shitanshu", "status": "ok"}
```
Round-robin continued alternating **B, A, B, A** through the Edge with Backend A protected behind the firewall.

#### 5. Rollback Verified
```bash
$ sudo pfctl -a com.apple/cn_backend_isolation -F all
$ nc -vz -G 2 10.7.2.192 3001
Connection to 10.7.2.192 port 3001 [tcp] succeeded!
```
Normal LAN reachability restored.

**Outcome:** **100% PASS**

---

## 4. Extension B: DNS TTL Dynamics (15 Marks Group)

### Objective
Demonstrate DNS caching, client TTL expiration, and manual cache invalidation.

### Execution Log
* Configured `DNS_TTL=30` in `dnsmasq.conf`.
* Client query `dig app.team1.test` showed 30-second TTL in ANSWER section:
  ```text
  app.team1.test.    30    IN    A    10.7.16.162
  ```
* Simulated record cutover via `bin/failure-demo wrong-dns-record break` $\rightarrow$ client cache maintained previous answer until TTL expiration / cache flush (`dscacheutil -flushcache`).

**Outcome:** **100% PASS**

---

## 5. Summary & Viva Defense Checklist

| Requirement | Defense / Concept | Verification Reference |
|---|---|---|
| **DNS Redundancy** | Dual resolvers in `/etc/resolver/team1.test`; fallback to Mac 4 when Mac 1 dies. | Extension A Log |
| **SPOF Analysis** | Nginx Edge (Mac 2) is the remaining SPOF; resolved in cloud via VRRP/Keepalived floating VIP or AWS Multi-AZ ALB. | Section 3 Viva Defense |
| **Layer 4 Isolation** | macOS `pf` stateful firewall; restricts backend ingress to edge proxy only. | Extension C Log |
| **Circuit Breaking** | `proxy_next_upstream` rerouting within 2s, marking upstream down for `fail_timeout=5s`. | Extension D Log |
| **Layer-by-Layer Triage** | `./bin/doctor` bottom-up diagnosis (L3 Network $\rightarrow$ L7 DNS $\rightarrow$ L4 TCP $\rightarrow$ L5 TLS $\rightarrow$ L7 App). | Extension F Tool |
