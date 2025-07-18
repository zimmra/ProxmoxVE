#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: fabrice1236
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://ghost.org/

APP="Ghost"
var_tags="${var_tags:-cms;blog}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg-query -W -f='${Status}' mariadb-server 2>/dev/null | grep -q "install ok installed"; then
    setup_mysql
  fi
  NODE_VERSION="22" setup_nodejs

  msg_info "Updating ${APP} LXC"
  if command -v ghost &>/dev/null; then
    current_version=$(ghost version | grep 'Ghost-CLI version' | awk '{print $3}')
    latest_version=$(npm show ghost-cli version)
    if [ "$current_version" != "$latest_version" ]; then
      msg_info "Updating ${APP} from version v${current_version} to v${latest_version}"
      $STD npm install -g ghost-cli@latest
      msg_ok "Updated Successfully"
    else
      msg_ok "${APP} is already at v${current_version}"
    fi
  else
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:2368${CL}"
