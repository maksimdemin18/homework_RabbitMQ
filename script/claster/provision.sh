#!/usr/bin/env bash
set -euo pipefail


if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <rmq01|rmq02> <node_ip> <peer_ip>" >&2
  exit 2
fi

NODE_NAME="$1"
NODE_IP="$2"
PEER_IP="$3"
export DEBIAN_FRONTEND=noninteractive
ERLANG_COOKIE="RABBITMQ_LAB_COOKIE_2026_CHANGE_ME"

log() { echo -e "\n==> $*\n"; }
die() { echo -e "\nERROR: $*\n" >&2; exit 1; }

wait_port() {
  local host="$1" port="$2" tries="${3:-90}" delay="${4:-2}"
  for _ in $(seq 1 "$tries"); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

wait_rmq() {
  local tries="${1:-90}" delay="${2:-2}"
  for _ in $(seq 1 "$tries"); do
    if rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

cluster_has_two_nodes() {
  local cs
  cs="$(rabbitmqctl cluster_status 2>/dev/null || true)"
  echo "$cs" | grep -q "rabbit@rmq01" && echo "$cs" | grep -q "rabbit@rmq02"
}

log "Ensure hostname is $NODE_NAME"
if [ "$(hostname -s || true)" != "$NODE_NAME" ]; then
  echo "$NODE_NAME" > /etc/hostname
  hostnamectl set-hostname "$NODE_NAME" || true
fi

log "Configure /etc/hosts"
grep -qE '^\s*192\.168\.56\.10\s+rmq01\s*$' /etc/hosts || echo "192.168.56.10 rmq01" >> /etc/hosts
grep -qE '^\s*192\.168\.56\.11\s+rmq02\s*$' /etc/hosts || echo "192.168.56.11 rmq02" >> /etc/hosts

log "Remove external RabbitMQ/Erlang repos (to avoid Erlang 27 / RMQ 4.x)"
rm -f /etc/apt/sources.list.d/*rabbitmq*.list || true
rm -f /etc/apt/preferences.d/*rabbitmq* || true

log "Install base dependencies + enable Universe"
apt-get update -y
apt-get install -y software-properties-common ca-certificates curl gnupg apt-transport-https
add-apt-repository -y universe >/dev/null 2>&1 || true
apt-get update -y

log "Install RabbitMQ from Ubuntu repository (3.x)"
apt-get install -y rabbitmq-server

log "Stop service to apply cookie + enable management offline"
systemctl stop rabbitmq-server || true

log "Set Erlang cookie (must be identical on both nodes)"
install -d -o rabbitmq -g rabbitmq -m 0700 /var/lib/rabbitmq
echo -n "$ERLANG_COOKIE" > /var/lib/rabbitmq/.erlang.cookie
chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie

log "Enable management plugin (offline)"
rabbitmq-plugins enable --offline rabbitmq_management >/dev/null

log "Start RabbitMQ"
systemctl enable --now rabbitmq-server

if ! wait_rmq 120 2; then
  journalctl -u rabbitmq-server --no-pager -n 200 || true
  die "RabbitMQ did not start"
fi

log "Create admin user (admin/admin) for UI and remote clients"
rabbitmqctl add_user admin admin >/dev/null 2>&1 || true
rabbitmqctl set_user_tags admin administrator >/dev/null
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*" >/dev/null

if [ "$NODE_NAME" = "rmq02" ]; then
  log "Cluster: wait for rmq01:5672 to be reachable"
  getent hosts rmq01 >/dev/null 2>&1 || die "rmq01 is not resolvable. Check /etc/hosts."
  if ! wait_port "rmq01" 5672 180 2; then
    die "rmq01:5672 is not reachable"
  fi

  if cluster_has_two_nodes; then
    log "Cluster already formed (rmq01 + rmq02)"
  else
    log "Join rmq02 to cluster rabbit@rmq01"
    rabbitmqctl stop_app >/dev/null
    rabbitmqctl reset >/dev/null
    rabbitmqctl join_cluster rabbit@rmq01 >/dev/null
    rabbitmqctl start_app >/dev/null
  fi

  log "Verify cluster contains both nodes"
  ok=0
  for _ in $(seq 1 60); do
    if cluster_has_two_nodes; then ok=1; break; fi
    sleep 2
  done
  if [ "$ok" -ne 1 ]; then
    rabbitmqctl cluster_status || true
    die "Cluster was not formed within timeout"
  fi

  log "Set HA policy ha-all (classic mirroring) for all queues"
  rabbitmqctl set_policy ha-all '.*' '{"ha-mode":"all","ha-sync-mode":"automatic"}' --apply-to queues

  log "Policies:"
  rabbitmqctl list_policies -p / || true
fi

log "RabbitMQ ready on $NODE_NAME ($NODE_IP)"
log "UI: http://$NODE_IP:15672  login: admin/admin"
log "Version:"
rabbitmqctl version || true
