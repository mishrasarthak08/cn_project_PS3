#!/usr/bin/env bash
# scripts/backend-firewall.sh - Extension C: Service Isolation via macOS pf
# Restricts access to backend ports (3001/3002) so ONLY the Edge (Mac 2) and localhost can connect.
# Usage:
#   scripts/backend-firewall.sh enable [EDGE_IP] [PORT]
#   scripts/backend-firewall.sh disable
#   scripts/backend-firewall.sh status
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO/scripts/common.sh"
load_config

ANCHOR="cn_backend_isolation"
ACTION="${1:-status}"

# Determine target port based on role or argument
case "${ROLE:-}" in
  shitanshu) DEFAULT_PORT="$BACKEND_A_PORT" ;;
  shane)     DEFAULT_PORT="$BACKEND_B_PORT" ;;
  *)         DEFAULT_PORT=3001 ;;
esac

EDGE="${2:-$EDGE_IP}"
PORT="${3:-$DEFAULT_PORT}"

case "$ACTION" in
  enable)
    [ -n "$EDGE" ] || die "EDGE_IP is not set. Usage: $0 enable <EDGE_IP> [PORT]"
    info "Configuring macOS pf firewall for Service Isolation (Extension C)..."
    info "Target Port: $PORT | Allowed Edge IP: $EDGE | Allowed Localhost: 127.0.0.1"

    RULES=$(cat <<EOF
# CN Phase 2 Service Isolation Anchor
pass in quick proto tcp from 127.0.0.1 to any port $PORT
pass in quick proto tcp from $EDGE to any port $PORT
block return in quick proto tcp to any port $PORT
EOF
)
    # Load rules into our dedicated anchor
    echo "$RULES" | sudo pfctl -a "$ANCHOR" -f - 2>&1 | grep -v "flushing of rules" || true
    
    # Enable pf if disabled
    sudo pfctl -e 2>/dev/null || true
    
    ok "PF Firewall isolation ENABLED on port $PORT"
    echo ""
    info "Active Isolation Rules (Anchor: $ANCHOR):"
    sudo pfctl -a "$ANCHOR" -s rules
    echo ""
    ok "Verification steps:"
    echo "  1. From Preetish (Mac 2): curl -I http://<this-ip>:$PORT/api/status  --> 200 OK"
    echo "  2. From Sarthak (Mac 1) : nc -vz -G 2 <this-ip> $PORT              --> Connection refused / blocked"
    echo "  3. From Client via Edge : curl https://$APP_DOMAIN:$EDGE_PORT/     --> 200 OK (routed via Edge)"
    ;;

  disable|rollback)
    info "Rolling back and disabling firewall isolation..."
    sudo pfctl -a "$ANCHOR" -F rules 2>&1 | grep -v "flushing of rules" || true
    # Only disable pf if no other custom anchors exist, or simply leave empty anchor
    sudo pfctl -d 2>/dev/null || true
    ok "PF Firewall rules for $ANCHOR flushed. Port $PORT is open to LAN again."
    ;;

  status)
    info "Checking PF Firewall status for $ANCHOR..."
    sudo pfctl -s info 2>/dev/null | grep -E "Status:|State Table" || true
    echo "Rules in anchor '$ANCHOR':"
    sudo pfctl -a "$ANCHOR" -s rules 2>/dev/null || echo "  (no rules loaded in anchor $ANCHOR)"
    ;;

  *)
    echo "Usage: $0 {enable|disable|status} [EDGE_IP] [PORT]"
    exit 1
    ;;
esac
