#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/zimmra/ProxmoxVE/refs/heads/fix-lxc-calibre-web/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster) | Co-Author: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/janeczku/calibre-web

APP="Calibre-Web"
var_tags="eBook"
var_cpu="2"
var_ram="2048"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/cps.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Stopping ${APP}"
  systemctl stop cps
  msg_ok "Stopped ${APP}"

  msg_info "Updating ${APP}"
  cd /opt/kepubify
  rm -rf kepubify-linux-64bit
  curl -fsSLO https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-64bit
  chmod +x kepubify-linux-64bit
  menu_array=("1" "Enables gdrive as storage backend for your ebooks" OFF \
    "2" "Enables sending emails via a googlemail account without enabling insecure apps" OFF \
    "3" "Enables displaying of additional author infos on the authors page" OFF \
    "4" "Enables login via LDAP server" OFF \
    "5" "Enables login via google or github oauth" OFF \
    "6" "Enables extracting of metadata from epub, fb2, pdf files, and also extraction of covers from cbr, cbz, cbt files" OFF \
    "7" "Enables extracting of metadata from cbr, cbz, cbt files" OFF \
    "8" "Enables syncing with your kobo reader" OFF)
  if [ -f "/opt/calibre-web/options.txt" ]; then
    cps_options="$(cat /opt/calibre-web/options.txt)"
    IFS=',' read -ra ADDR <<<"$cps_options"
    for i in "${ADDR[@]}"; do
      if [ $i == "gdrive" ]; then
        line=0
      elif [ $i == "gmail" ]; then
        line=1
      elif [ $i == "goodreads" ]; then
        line=2
      elif [ $i == "ldap" ]; then
        line=3
      elif [ $i == "oauth" ]; then
        line=4
      elif [ $i == "metadata" ]; then
        line=5
      elif [ $i == "comics" ]; then
        line=6
      elif [ $i == "kobo" ]; then
        line=7
      fi
      array_index=$((3 * line + 2))
      menu_array[$array_index]=ON
    done
  fi
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  CHOICES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CALIBRE-WEB OPTIONS" --separate-output --checklist "Choose Additional Options" 15 125 8 "${menu_array[@]}" 3>&1 1>&2 2>&3)
  spinner &
  SPINNER_PID=$!
  options=()
  if [ ! -z "$CHOICES" ]; then
    for CHOICE in $CHOICES; do
      case "$CHOICE" in
      "1")
        options+=(gdrive)
        ;;
      "2")
        options+=(gmail)
        ;;
      "3")
        options+=(goodreads)
        ;;
      "4")
        options+=(ldap)
        apt-get install -qqy libldap2-dev libsasl2-dev
        ;;
      "5")
        options+=(oauth)
        ;;
      "6")
        options+=(metadata)
        ;;
      "7")
        options+=(comics)
        ;;
      "8")
        options+=(kobo)
        ;;
      *)
        echo "Unsupported item $CHOICE!" >&2
        exit 1
        ;;
      esac
    done
  fi
  if [ ${#options[@]} -gt 0 ]; then
    cps_options=$(
      IFS=,
      echo "${options[*]}"
    )
    echo $cps_options >/opt/calibre-web/options.txt
    pip install --upgrade calibreweb[$cps_options] &>/dev/null
  else
    rm -rf /opt/calibre-web/options.txt
    pip install --upgrade calibreweb &>/dev/null
  fi

  msg_info "Starting ${APP}"
  systemctl start cps
  msg_ok "Started ${APP}"
  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8083${CL}"
