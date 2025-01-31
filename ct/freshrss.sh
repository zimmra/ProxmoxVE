#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2024 community-scripts ORG
# Author: zimmra
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/FreshRSS/FreshRSS

# App Default Values
APP="FreshRSS"
RELEASE_URL="https://api.github.com/repos/FreshRSS/FreshRSS/releases/latest"
var_tags="rss;feed-reader"
var_cpu="2"
var_ram="2048"
var_disk="4"
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

# Update function for FreshRSS
# This function checks for updates and performs the update process
# It includes backup creation, file updates, and permission fixes
function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Check if installation exists
    if [[ ! -d /opt/FreshRSS ]]; then
        msg_error "No ${APP} Installation Found!"
        exit 1
    fi

    # Check if version file exists in the correct location
    if [[ ! -f /opt/FreshRSS/VERSION ]]; then
        msg_error "Version file not found!"
        exit 1
    fi

    # Get latest version with error handling
    CURRENT_VERSION=$(cat /opt/FreshRSS/VERSION)
    msg_info "Checking for updates..."
    if ! RELEASE=$(curl -fsSL "${RELEASE_URL}" | grep -Po '"tag_name": "\K.*?(?=")'); then
        msg_error "Failed to fetch latest version!"
        exit 1
    fi
    RELEASE="${RELEASE#v}"  # Remove 'v' prefix if present

    if [[ "${RELEASE}" != "${CURRENT_VERSION}" ]]; then
        msg_info "Updating ${APP} from v${CURRENT_VERSION} to v${RELEASE}"

        # Stop Apache
        msg_info "Stopping Apache"
        if ! systemctl stop apache2 &>/dev/null; then
            msg_error "Failed to stop Apache!"
            exit 1
        fi
        msg_ok "Stopped Apache"

        # Backup current installation
        msg_info "Creating Backup"
        BACKUP_FILE="/opt/FreshRSS_backup_$(date +%F).tar.gz"
        if ! tar -czf "$BACKUP_FILE" /opt/FreshRSS/data/ &>/dev/null; then
            msg_error "Failed to create backup!"
            systemctl start apache2 &>/dev/null
            exit 1
        fi
        msg_ok "Created Backup at ${BACKUP_FILE}"

        # Update FreshRSS
        msg_info "Downloading ${APP} v${RELEASE}"
        cd /opt || exit 1
        if ! wget -q "https://github.com/FreshRSS/FreshRSS/archive/refs/tags/v${RELEASE}.tar.gz"; then
            msg_error "Failed to download update!"
            systemctl start apache2 &>/dev/null
            exit 1
        fi

        if ! tar -xzf "v${RELEASE}.tar.gz" &>/dev/null; then
            msg_error "Failed to extract update!"
            rm -f "v${RELEASE}.tar.gz"
            systemctl start apache2 &>/dev/null
            exit 1
        fi

        # Preserve configuration
        msg_info "Updating Installation"
        cp -a /opt/FreshRSS/data /opt/FreshRSS/data.bak
        if ! cp -r FreshRSS-${RELEASE}/* /opt/FreshRSS/ &>/dev/null; then
            msg_error "Failed to copy new files!"
            mv /opt/FreshRSS/data.bak /opt/FreshRSS/data
            rm -rf "v${RELEASE}.tar.gz" "FreshRSS-${RELEASE}"
            systemctl start apache2 &>/dev/null
            exit 1
        fi
        rm -rf /opt/FreshRSS/data
        mv /opt/FreshRSS/data.bak /opt/FreshRSS/data
        msg_ok "Updated Installation"

        # Set permissions
        msg_info "Setting Permissions"
        if ! chown -R www-data:www-data /opt/FreshRSS/ &>/dev/null || \
           ! chmod -R 755 /opt/FreshRSS/ &>/dev/null || \
           ! chmod -R 775 /opt/FreshRSS/data/ &>/dev/null; then
            msg_error "Failed to set permissions!"
            systemctl start apache2 &>/dev/null
            exit 1
        fi
        msg_ok "Set Permissions"

        # Update Apache configuration
        msg_info "Updating Apache Configuration"
        if [[ -f /etc/apache2/sites-enabled/FreshRSS.conf ]]; then
            if ! sed -i "s|/var/www/FreshRSS|/opt/FreshRSS|g" /etc/apache2/sites-enabled/FreshRSS.conf &>/dev/null; then
                msg_error "Failed to update Apache configuration!"
                exit 1
            fi
        fi
        msg_ok "Updated Apache Configuration"

        # Start Apache
        msg_info "Starting Apache"
        if ! systemctl start apache2 &>/dev/null; then
            msg_error "Failed to start Apache!"
            exit 1
        fi
        msg_ok "Started Apache"

        # Cleanup
        msg_info "Cleaning Up"
        rm -rf "v${RELEASE}.tar.gz" "FreshRSS-${RELEASE}"
        echo "${RELEASE}" > /opt/FreshRSS/VERSION
        msg_ok "Cleaned Up"

        msg_ok "Update Completed Successfully!"
    else
        msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
