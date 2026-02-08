#!/usr/bin/env bash
set -euo pipefail

echo "==> Update + deps"
sudo apt-get update -y
sudo apt-get install -y curl gnupg apt-transport-https

echo "==> Add Team RabbitMQ signing key"
curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg >/dev/null

echo "==> Add Erlang + RabbitMQ repos (jammy)"
sudo tee /etc/apt/sources.list.d/rabbitmq.list >/dev/null <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/ubuntu/jammy jammy main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/ubuntu/jammy jammy main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/ubuntu/jammy jammy main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/ubuntu/jammy jammy main
EOF

sudo apt-get update -y

echo "==> Install Erlang (per RabbitMQ docs)"
sudo apt-get install -y erlang-base \
  erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
  erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
  erlang-runtime-tools erlang-snmp erlang-ssl \
  erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

echo "==> Install RabbitMQ"
sudo apt-get install -y rabbitmq-server

echo "==> Enable management plugin"
sudo rabbitmq-plugins enable rabbitmq_management

echo "==> Create admin user (guest is localhost-only)"
sudo rabbitmqctl add_user admin admin 2>/dev/null || true
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

echo "==> Ensure service is running"
sudo systemctl enable --now rabbitmq-server

echo "==> Done. UI: http://192.168.56.10:15672  login/pass: admin/admin"
