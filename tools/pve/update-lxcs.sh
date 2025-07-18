#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info() {
  clear
  cat <<"EOF"
   __  __          __      __          __   _  ________
  / / / /___  ____/ /___ _/ /____     / /  | |/ / ____/
 / / / / __ \/ __  / __ `/ __/ _ \   / /   |   / /
/ /_/ / /_/ / /_/ / /_/ / /_/  __/  / /___/   / /___
\____/ .___/\__,_/\__,_/\__/\___/  /_____/_/|_\____/
    /_/

EOF
}
set -eEuo pipefail
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
CM='\xE2\x9C\x94\033'
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
header_info
echo "Loading..."
whiptail --backtitle "Proxmox VE Helper Scripts" --title "Proxmox VE LXC Updater" --yesno "This Will Update LXC Containers. Proceed?" 10 58
NODE=$(hostname)
UPDATE_MENU=()
MSG_MAX_LENGTH=0
UPDATEABLE_CONTAINERS=()
OTHER_CONTAINERS=()

# Collect all running containers and categorize them
while read -r TAG ITEM; do
  # Only include running containers in the menu
  status=$(pct status "$TAG")
  if [ "$status" == "status: running" ]; then
    # Check if container has "updateable" tag
    if pct config "$TAG" | grep -q "^tags:.*updateable"; then
      UPDATEABLE_CONTAINERS+=("$TAG" "$ITEM")
    else
      OTHER_CONTAINERS+=("$TAG" "$ITEM")
    fi
  fi
done < <(pct list | awk 'NR>1')

# Add updateable containers to menu first
for ((i=0; i<${#UPDATEABLE_CONTAINERS[@]}; i+=2)); do
  TAG="${UPDATEABLE_CONTAINERS[i]}"
  ITEM="${UPDATEABLE_CONTAINERS[i+1]}"
  OFFSET=2
  ((${#ITEM} + OFFSET + 13 > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET+13
  UPDATE_MENU+=("$TAG" "[$ITEM] (updateable)" "OFF")
done

# Add a separator if we have updateable containers and other containers
if [ ${#UPDATEABLE_CONTAINERS[@]} -gt 0 ] && [ ${#OTHER_CONTAINERS[@]} -gt 0 ]; then
  SEPARATOR_TEXT="--- Other Running Containers ---"
  ((${#SEPARATOR_TEXT} + 2 > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#SEPARATOR_TEXT}+2
  UPDATE_MENU+=("" "$SEPARATOR_TEXT" "OFF")
fi

# Add other containers to menu
for ((i=0; i<${#OTHER_CONTAINERS[@]}; i+=2)); do
  TAG="${OTHER_CONTAINERS[i]}"
  ITEM="${OTHER_CONTAINERS[i+1]}"
  OFFSET=2
  ((${#ITEM} + OFFSET > MSG_MAX_LENGTH)) && MSG_MAX_LENGTH=${#ITEM}+OFFSET
  UPDATE_MENU+=("$TAG" "$ITEM " "OFF")
done

# Check if we have any containers to display
if [ ${#UPDATE_MENU[@]} -eq 0 ]; then
  echo -e "${RD}No running containers found. Exiting.${CL}"
  exit 0
fi

selected_containers=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Running Containers on $NODE" --checklist "\nSelect containers to update:\n" 16 $((MSG_MAX_LENGTH + 23)) 6 "${UPDATE_MENU[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

function needs_reboot() {
  local container=$1
  local os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  local reboot_required_file="/var/run/reboot-required.pkgs"
  if [ -f "$reboot_required_file" ]; then
    if [[ "$os" == "ubuntu" || "$os" == "debian" ]]; then
      if pct exec "$container" -- [ -s "$reboot_required_file" ]; then
        return 0
      fi
    fi
  fi
  return 1
}

function update_container() {
  container=$1
  header_info
  name=$(pct exec "$container" hostname)
  os=$(pct config "$container" | awk '/^ostype/ {print $2}')
  if [[ "$os" == "ubuntu" || "$os" == "debian" || "$os" == "fedora" ]]; then
    disk_info=$(pct exec "$container" df /boot | awk 'NR==2{gsub("%","",$5); printf "%s %.1fG %.1fG %.1fG", $5, $3/1024/1024, $2/1024/1024, $4/1024/1024 }')
    read -ra disk_info_array <<<"$disk_info"
    echo -e "${BL}[Info]${GN} Updating ${BL}$container${CL} : ${GN}$name${CL} - ${YW}Boot Disk: ${disk_info_array[0]}% full [${disk_info_array[1]}/${disk_info_array[2]} used, ${disk_info_array[3]} free]${CL}\n"
  else
    echo -e "${BL}[Info]${GN} Updating ${BL}$container${CL} : ${GN}$name${CL} - ${YW}[No disk info for ${os}]${CL}\n"
  fi
  case "$os" in
  alpine) pct exec "$container" -- ash -c "apk -U upgrade" ;;
  archlinux) pct exec "$container" -- bash -c "pacman -Syyu --noconfirm" ;;
  fedora | rocky | centos | alma) pct exec "$container" -- bash -c "dnf -y update && dnf -y upgrade" ;;
  ubuntu | debian | devuan) pct exec "$container" -- bash -c "apt-get update 2>/dev/null | grep 'packages.*upgraded'; apt list --upgradable && apt-get -yq dist-upgrade 2>&1; rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED" ;;
  opensuse) pct exec "$container" -- bash -c "zypper ref && zypper --non-interactive dup" ;;
  esac
  
  # Check if /usr/bin/update exists and run it
  if pct exec "$container" -- [ -f "/usr/bin/update" ]; then
    echo -e "${BL}[Info]${GN} Running service update script for ${BL}$container${CL} : ${GN}$name${CL}\n"
    pct exec "$container" -- /usr/bin/update
  fi
}

containers_needing_reboot=()
header_info

# Check if any containers were selected
if [[ -z "$selected_containers" ]]; then
  echo -e "${RD}No containers selected for update. Exiting.${CL}"
  exit 0
fi

# Only process selected containers (which are all running)
for container in $selected_containers; do
  # Skip empty container IDs (separators)
  if [[ -n "$container" ]]; then
    # Container is selected and already running, so update it
    update_container "$container"
    if pct exec "$container" -- [ -e "/var/run/reboot-required" ]; then
      # Get the container's hostname and add it to the list
      container_hostname=$(pct exec "$container" hostname)
      containers_needing_reboot+=("$container ($container_hostname)")
    fi
  fi
done
wait
header_info
echo -e "${GN}The process is complete, and the selected containers have been successfully updated.${CL}\n"
if [ "${#containers_needing_reboot[@]}" -gt 0 ]; then
  echo -e "${RD}The following containers require a reboot:${CL}"
  for container_name in "${containers_needing_reboot[@]}"; do
    echo "$container_name"
  done
fi
echo ""
