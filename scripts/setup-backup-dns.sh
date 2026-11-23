#!/usr/bin/env bash
# scripts/setup-backup-dns.sh - Extension A: Backup DNS Resolver
# Runs a second DNS resolver (dnsmasq) on Mac 4 (Shane) or any designated node.
# Usage:
#   scripts/setup-backup-dns.sh start        (on Backup DNS node, e.g. Shane)
#   scripts/setup-backup-dns.sh stop         (on Backup DNS node)
#   scripts/setup-backup-dns.sh status       (on Backup DNS node)
#   scripts/setup-backup-dns.sh configure-client <PRIMARY_DNS_IP> <BACKUP_DNS_IP>
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO/scripts/common.sh"
. "$REPO/scripts/checks.sh"
load_config

BACKUP_DNSMASQ_PID="$CN_RUN_DIR/dnsmasq-backup.pid"
BACKUP_DNSMASQ_CONF="$CN_GEN_DIR/dnsmasq-backup.conf"
BACKUP_DNS_PORT="${BACKUP_DNS_PORT:-$DNS_PORT}"

ACTION="${1:-status}"

backup_dns_render() {
  ensure_dirs
  local my_ip; my_ip="$(local_ip || true)"
  [ -n "$my_ip" ] || my_ip="127.0.0.1"
  [ -n "${EDGE_IP:-}" ] || die "EDGE_IP not set in configuration"

  cat > "$BACKUP_DNSMASQ_CONF" <<EOF
port=$BACKUP_DNS_PORT
listen-address=127.0.0.1,$my_ip
bind-interfaces
no-resolv
no-hosts
domain-needed
bogus-priv
local=/$TEST_ZONE/
address=/$APP_DOMAIN/$EDGE_IP
address=/$API_DOMAIN/$EDGE_IP
local-ttl=${DNS_TTL:-30}
log-queries
log-facility=-
pid-file=$BACKUP_DNSMASQ_PID
EOF
}

case "$ACTION" in
  start)
    info "Starting Backup DNS Resolver (Extension A)..."
    ensure_formula dnsmasq dnsmasq
    bin="$(brew_bin dnsmasq)"
    backup_dns_render
    
    "$bin" --test --conf-file="$BACKUP_DNSMASQ_CONF" >/dev/null 2>&1 || die "dnsmasq config test failed"
    
    # Stop any previous backup dnsmasq
    if [ -f "$BACKUP_DNSMASQ_PID" ]; then stop_pidfile "$BACKUP_DNSMASQ_PID" sudo; fi
    
    sudo -v
    sudo "$bin" --keep-in-foreground --conf-file="$BACKUP_DNSMASQ_CONF" >> "$CN_LOG_DIR/dnsmasq-backup.log" 2>&1 &
    disown || true
    
    for i in $(seq 1 20); do
      if dig +short +time=1 +tries=1 -p "$BACKUP_DNS_PORT" @127.0.0.1 "$APP_DOMAIN" 2>/dev/null | grep -q .; then
        ok "Backup DNS server is ACTIVE on port $BACKUP_DNS_PORT!"
        ok "Resolving $APP_DOMAIN -> $EDGE_IP"
        return 0
      fi
      sleep 0.3
    done
    die "Backup DNS did not respond. Check $CN_LOG_DIR/dnsmasq-backup.log"
    ;;

  stop)
    info "Stopping Backup DNS Resolver..."
    if [ -f "$BACKUP_DNSMASQ_PID" ]; then stop_pidfile "$BACKUP_DNSMASQ_PID" sudo; fi
    sudo pkill -f "dnsmasq.*$BACKUP_DNSMASQ_CONF" 2>/dev/null || true
    rm -f "$BACKUP_DNSMASQ_PID"
    ok "Backup DNS stopped."
    ;;

  status)
    if [ -f "$BACKUP_DNSMASQ_PID" ] && kill -0 "$(cat "$BACKUP_DNSMASQ_PID" 2>/dev/null)" 2>/dev/null; then
      ok "Backup DNS is running (PID $(cat "$BACKUP_DNSMASQ_PID"))"
      dig +short -p "$BACKUP_DNS_PORT" @127.0.0.1 "$APP_DOMAIN" || true
    else
      info "Backup DNS is NOT running"
    fi
    ;;

  configure-client)
    primary="${2:-$DNS_IP}"
    backup="${3:-${SHANE_LAN_IP:-}}"
    [ -n "$primary" ] && [ -n "$backup" ] || die "Usage: $0 configure-client <PRIMARY_DNS_IP> <BACKUP_DNS_IP>"
    
    info "Configuring dual-resolver (/etc/resolver/$TEST_ZONE) with Primary: $primary and Backup: $backup"
    sudo mkdir -p /etc/resolver
    tmp="$(mktemp)"
    cat > "$tmp" <<EOF
# managed by cn-phase2 backup dns
nameserver $primary
nameserver $backup
EOF
    sudo cp "$tmp" "/etc/resolver/$TEST_ZONE"
    sudo chmod 644 "/etc/resolver/$TEST_ZONE"
    rm -f "$tmp"
    
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall -HUP mDNSResponder 2>/dev/null || true
    ok "Dual DNS resolvers configured in /etc/resolver/$TEST_ZONE:"
    cat "/etc/resolver/$TEST_ZONE"
    ;;

  *)
    echo "Usage: $0 {start|stop|status|configure-client <PRIMARY> <BACKUP>}"
    exit 1
    ;;
esac
