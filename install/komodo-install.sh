#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://komo.do/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y ca-certificates
msg_ok "Installed Dependencies"

msg_info "Setup Docker Repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
$STD apt-get update
msg_ok "Setup Docker Repository"

msg_info "Installing Docker"
$STD apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
msg_ok "Installed Docker"

echo "${TAB3}Choose the database for Komodo installation:"
echo "${TAB3}1) MongoDB (recommended)"
echo "${TAB3}2) FerretDB"
read -rp "${TAB3}Enter your choice (default: 1): " DB_CHOICE
DB_CHOICE=${DB_CHOICE:-1}

case $DB_CHOICE in
1)
  DB_COMPOSE_FILE="mongo.compose.yaml"
  ;;
2)
  DB_COMPOSE_FILE="ferretdb.compose.yaml"
  ;;
*)
  echo "Invalid choice. Defaulting to MongoDB."
  DB_COMPOSE_FILE="mongo.compose.yaml"
  ;;
esac
mkdir -p /opt/komodo
cd /opt/komodo
curl -fsSL "https://raw.githubusercontent.com/moghtech/komodo/main/compose/$DB_COMPOSE_FILE" -o "/opt/komodo/$DB_COMPOSE_FILE"

msg_info "Setup Komodo Environment"
curl -fsSL "https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env" -o "/opt/komodo/compose.env"
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=')
PASSKEY=$(openssl rand -base64 24 | tr -d '/+=')
WEBHOOK_SECRET=$(openssl rand -base64 24 | tr -d '/+=')
JWT_SECRET=$(openssl rand -base64 24 | tr -d '/+=')

sed -i "s/^KOMODO_DB_USERNAME=.*/KOMODO_DB_USERNAME=komodo_admin/" /opt/komodo/compose.env
sed -i "s/^KOMODO_DB_PASSWORD=.*/KOMODO_DB_PASSWORD=${DB_PASSWORD}/" /opt/komodo/compose.env
sed -i "s/^KOMODO_PASSKEY=.*/KOMODO_PASSKEY=${PASSKEY}/" /opt/komodo/compose.env
sed -i "s/^KOMODO_WEBHOOK_SECRET=.*/KOMODO_WEBHOOK_SECRET=${WEBHOOK_SECRET}/" /opt/komodo/compose.env
sed -i "s/^KOMODO_JWT_SECRET=.*/KOMODO_JWT_SECRET=${JWT_SECRET}/" /opt/komodo/compose.env
msg_ok "Setup Komodo Environment"

msg_info "Initialize Komodo"
$STD docker compose -p komodo -f /opt/komodo/$DB_COMPOSE_FILE --env-file /opt/komodo/compose.env up -d
msg_ok "Initialized Komodo"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
