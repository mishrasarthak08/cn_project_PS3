# Evidence Folder

Store proof here so any item can be found in 30 seconds during evaluations and Review 2.

## Phase 2 Key Deliverables & Drill Evidence

| Evidence Item | Description | Direct Link |
|---|---|---|
| **Phase 2 Final Report (PDF)** | Formatted, signed PDF report ready for evaluator submission | [`Phase2_Final_Report_Team1.pdf`](Phase2_Final_Report_Team1.pdf) |
| **Phase 2 Results & Drill Logs** | Complete raw terminal logs of all 3 live LAN drills (DNS failover, Backend HA failover, PF firewall isolation) | [`phase2_results.md`](phase2_results.md) |
| **DNS Packet Capture (.pcap)** | Wireshark-compatible packet capture showing UDP port 53 DNS query/response packets | [`dns-traffic.pcap`](dns-traffic.pcap) |

---

## Phase 1 & Baseline Directory Layout

| Subfolder | Put here |
|---|---|
| `dns/` | `dig` / `nslookup` output, resolver config, Wireshark DNS screenshot |
| `tcp/` | SYN/SYN-ACK/ACK capture + ports table |
| `tls/` | `openssl s_client`, certificate details, ClientHello/ServerHello screenshots |
| `http/` | `curl -v`, `curl -I` (Cache-Control, ETag), 304 demo, browser DevTools |
| `load-balancing/` | repeated-request output showing A and B |
| `failures/` | one file per failure demo (break output, observation, rollback) |

`./bin/collect-evidence` creates `evidence/<timestamp>/` (git-ignored by default; add the good runs with `git add -f`).  
`scripts/capture-packets.sh 60` writes a bounded `.pcap` for Wireshark (commit deliberately with `git add -f`).  
Never place keys, tokens or credentials here.

