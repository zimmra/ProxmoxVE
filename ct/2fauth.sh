#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: jkrgr0
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.2fauth.app/

APP="2FAuth"
var_tags="${var_tags:-2fa;authenticator}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
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

  if [[ ! -d "/opt/2fauth" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if ! command -v jq &>/dev/null; then
    $STD apt-get install -y jq
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/Bubka/2FAuth/releases/latest | jq -r '.tag_name' | sed 's/^v//')
  if [[ "${RELEASE}" != "$(cat ~/.2fauth 2>/dev/null)" ]] || [[ ! -f ~/.2fauth ]]; then
    msg_info "Updating $APP to ${RELEASE}"
    $STD apt-get update
    $STD apt-get -y upgrade

    msg_info "Creating Backup"
    mv "/opt/2fauth" "/opt/2fauth-backup"
    if ! dpkg -l | grep -q 'php8.3'; then
      cp /etc/nginx/conf.d/2fauth.conf /etc/nginx/conf.d/2fauth.conf.bak
    fi
    msg_ok "Backup Created"

    if ! dpkg -l | grep -q 'php8.3'; then
      $STD apt-get install -y \
        lsb-release \
        gnupg2
      PHP_VERSION="8.3" PHP_MODULE="common,ctype,fileinfo,mysql,cli" PHP_FPM="YES" setup_php
      sed -i 's/php8.2/php8.3/g' /etc/nginx/conf.d/2fauth.conf
    fi
    fetch_and_deploy_gh_release "2fauth" "Bubka/2FAuth"
    setup_composer
    mv "/opt/2fauth-backup/.env" "/opt/2fauth/.env"
    mv "/opt/2fauth-backup/storage" "/opt/2fauth/storage"
    cd "/opt/2fauth" || return
    chown -R www-data: "/opt/2fauth"
    chmod -R 755 "/opt/2fauth"
    export COMPOSER_ALLOW_SUPERUSER=1
    $STD composer install --no-dev --prefer-source
    php artisan 2fauth:install
    $STD systemctl restart nginx

    msg_info "Cleaning Up"
    rm -rf "v${RELEASE}.zip"
    if dpkg -l | grep -q 'php8.2'; then
      $STD apt-get remove --purge -y php8.2*
    fi
    $STD apt-get -y autoremove
    $STD apt-get -y autoclean
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/2fauth_version.txt
    msg_ok "Updated $APP to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
