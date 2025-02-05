#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/zimmra/ProxmoxVE/refs/heads/add-kasm-lxc/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.docker.com/, https://kasmweb.com

# App Default Values
APP="Kasm-Workspaces"
var_tags="kasm-workspaces"
var_cpu="2"
var_ram="4096"
var_disk="12"
var_os="debian"
var_version="12"
var_unprivileged="1"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /var ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi
    msg_info "Updating ${APP} LXC"
    apt-get update &>/dev/null
    apt-get -y upgrade &>/dev/null

    # Get latest version from GitHub
    KASM_WORKSPACES_LATEST_VERSION=$(curl -sL https://api.github.com/repos/kasmtech/kasm-install-wizard/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    
    # Get current installed version
    CURRENT_VERSION=$(readlink -f /opt/kasm/current | awk -F'/' '{print $4}')

    if [ "$CURRENT_VERSION" = "$KASM_WORKSPACES_LATEST_VERSION" ]; then
        msg_ok "Kasm Workspaces is already at the latest version ($CURRENT_VERSION)"
        exit
    fi

    msg_info "Current version: $CURRENT_VERSION"
    msg_info "Latest version: $KASM_WORKSPACES_LATEST_VERSION"
    msg_info "Update available!"

    INSTALL_FLAGS="--proxy-port 443"
    read -r -p "Would you like to enable lossless streaming? <y/N> " prompt
    if [[ ${prompt,,} =~ ^(y|yes)$ ]]; then
    INSTALL_FLAGS="${INSTALL_FLAGS} --enable-lossless"
    fi

    read -r -p "Do you need VPN egress capabilities for containers? <y/N> " prompt
    if [[ ! ${prompt,,} =~ ^(y|yes)$ ]]; then
    INSTALL_FLAGS="${INSTALL_FLAGS} --skip-egress"
    fi

    cd /tmp
    msg_info "Downloading Kasm release package..."
    wget -q https://github.com/kasmtech/kasm-install-wizard/releases/download/$KASM_WORKSPACES_LATEST_VERSION/kasm_release.tar.gz
    
    msg_info "Extracting release package..."
    tar -xf kasm_release.tar.gz

    msg_info "Running upgrade script..."
    bash kasm_release/upgrade.sh ${INSTALL_FLAGS}

    # Cleanup
    rm -rf /tmp/kasm_release.tar.gz /tmp/kasm_release

    msg_ok "Updated ${APP} to version $KASM_WORKSPACES_LATEST_VERSION"
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"