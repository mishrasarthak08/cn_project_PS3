#!/usr/bin/env bash
# scripts/backend-firewall.sh - Extension C: Service Isolation via macOS pf
# Restricts access to backend ports (3001/3002) so ONLY the Edge (Mac 2) and localhost can connect.
# Usage:
#   scripts/backend-firewall.sh enable [EDGE_IP] [PORT]
#   scripts/backend-firewall.sh disable
#   scripts/backend-firewall.sh status
#   scripts/backend-firewall.sh verify
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO/scripts/common.sh"
load_config

# macOS /etc/pf.conf evaluates anchors matching "com.apple/*"
ANCHOR="com.apple/cn_backend_isolation"
ACTION="${1:-status}"

# Determine target port based on role or argument
case "${ROLE:-}" in
  shitanshu) DEFAULT_PORT="$BACKEND_A_PORT" ;;
  shane)     DEFAULT_PORT="$BACKEND_B_PORT" ;;
  *)         DEFAULT_PORT="${BACKEND_A_PORT:-3001}" ;;
esac

EDGE="${2:-${EDGE_IP:-10.7.16.162}}"
PORT="${3:-$DEFAULT_PORT}"

case "$ACTION" in
  enable)
    [ -n "$EDGE" ] || die "EDGE_IP is not set. Usage: $0 enable <EDGE_IP> [PORT]"
    info "Configuring macOS pf firewall for Service Isolation (Extension C)..."
    info "Target Port: $PORT | Allowed Edge IP: $EDGE | Allowed Local: 127.0.0.1 / lo0"

    RULES=$(cat <<EOF
# CN Phase 2 Service Isolation Anchor ($ANCHOR)
pass in quick on lo0 proto tcp to any port $PORT
pass in quick proto tcp from 127.0.0.1 to any port $PORT
pass in quick proto tcp from $EDGE to any port $PORT
block return in quick proto tcp to any port $PORT
EOF
)
    # Load rules into our dedicated anchor under com.apple/
    echo "$RULES" | sudo pfctl -a "$ANCHOR" -f - 2>&1 | grep -v "flushing of rules" || true
    
    # Enable pf (-e enables; -E adds reference count on macOS)
    sudo pfctl -e 2>/dev/null || true
    
    ok "PF Firewall isolation ENABLED on port $PORT"
    echo ""
    info "Active Isolation Rules in anchor '$ANCHOR':"
    sudo pfctl -a "$ANCHOR" -s rules 2>/dev/null || true
    echo ""
    ok "Verification steps:"
    echo "  1. From Preetish (Mac 2 Edge): curl -I http://<this-ip>:$PORT/api/status  --> 200 OK (Allowed)"
    echo "  2. From Sarthak (Mac 1 Client): nc -vz -G 2 <this-ip> $PORT              --> Connection refused (Blocked)"
    echo "  3. From Client via Edge      : curl https://$APP_DOMAIN:$EDGE_PORT/api/status --> 200 OK (Routed via Edge)"
    ;;

  disable|rollback)
    info "Rolling back and disabling firewall isolation..."
    # Flush all rules in our specific anchor
    sudo pfctl -a "$ANCHOR" -F all 2>&1 | grep -v "flushing of rules" || true
    ok "PF Firewall anchor '$ANCHOR' flushed. Port $PORT is open to LAN again."
    ;;

  status)
    info "Checking PF Firewall status..."
    sudo pfctl -s info 2>/dev/null | grep -E "Status:|State Table" || true
    echo ""
    info "Rules loaded in anchor '$ANCHOR':"
    rules="$(sudo pfctl -a "$ANCHOR" -s rules 2>/dev/null || true)"
    if [ -n "$rules" ]; then
      echo "$rules"
    else
      echo "  (no rules currently active in anchor $ANCHOR)"
    fi
    ;;

  verify)
    info "Testing local reachability on port $PORT..."
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
      ok "Local connection to port $PORT succeeded (loopback pass rule working)."
    else
      warn "Local connection to port $PORT failed. Is the backend running?"
    fi
    ;;

  *)
    echo "Usage: $0 {enable|disable|status|verify} [EDGE_IP] [PORT]"
    exit 1
    ;;
esac
