#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
msg_ok "Installed Dependencies"

get_latest_release() {
  curl -sL https://api.github.com/repos/$1/releases/latest | grep '"tag_name":' | cut -d'"' -f4
}

DOCKER_LATEST_VERSION=$(get_latest_release "moby/moby")
PORTAINER_LATEST_VERSION=$(get_latest_release "portainer/portainer")
PORTAINER_AGENT_LATEST_VERSION=$(get_latest_release "portainer/agent")
DOCKER_COMPOSE_LATEST_VERSION=$(get_latest_release "docker/compose")
KASM_WORKSPACES_LATEST_VERSION=$(get_latest_release "kasmtech/kasm-install-wizard")

msg_info "Installing Docker $DOCKER_LATEST_VERSION"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -sSL https://get.docker.com)
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

read -r -p "Would you like to add Portainer? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  msg_info "Installing Portainer $PORTAINER_LATEST_VERSION"
  docker volume create portainer_data >/dev/null
  $STD docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name=portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  msg_ok "Installed Portainer $PORTAINER_LATEST_VERSION"
else
  read -r -p "Would you like to add the Portainer Agent? <y/N> " prompt
  if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    msg_info "Installing Portainer agent $PORTAINER_AGENT_LATEST_VERSION"
    $STD docker run -d \
      -p 9001:9001 \
      --name portainer_agent \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent
    msg_ok "Installed Portainer Agent $PORTAINER_AGENT_LATEST_VERSION"
  fi
fi

msg_info "Downloading Kasm Workspaces"
cd /tmp
$STD wget https://github.com/kasmtech/kasm-install-wizard/releases/download/$KASM_WORKSPACES_LATEST_VERSION/kasm_release.tar.gz
$STD tar -xf kasm_release.tar.gz
$STD sed -i 's/\$(apt-get update && apt-get install -y wireguard)/apt-get update \&\& apt-get install -y wireguard/' kasm_release/install_dependencies.sh
msg_ok "Downloaded Kasm Workspaces"

INSTALL_FLAGS="--accept-eula"

read -r -p "Would you like to set a custom Kasm admin password (admin@kasm.local)? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  read -r -s -p "Enter admin password: " admin_password
  echo
  INSTALL_FLAGS="${INSTALL_FLAGS} --admin-password ${admin_password}"
fi

read -r -p "Would you like to set a custom Kasm user password (user@kasm.local)? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  read -r -s -p "Enter user password: " user_password
  echo
  INSTALL_FLAGS="${INSTALL_FLAGS} --user-password ${user_password}"
fi

read -r -p "Would you like to enable lossless streaming? <y/N> " prompt
if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
  INSTALL_FLAGS="${INSTALL_FLAGS} --enable-lossless"
fi

read -r -p "Do you need VPN egress capabilities for containers? <y/N> " prompt
if [[ ! ${prompt,,} =~ ^(y|yes)$ ]]; then
  INSTALL_FLAGS="${INSTALL_FLAGS} --skip-egress"
fi

msg_info "Installing Kasm Workspaces"
bash kasm_release/install.sh ${INSTALL_FLAGS} 2>&1 | grep -A 25 "Kasm UI Login Credentials"
echo -e "\n${YW}⚠️ WARNING: Please save these credentials - they will not be shown again!${CL}\n"
msg_ok "Installed Kasm Workspaces"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
