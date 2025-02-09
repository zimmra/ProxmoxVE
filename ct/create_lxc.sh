#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# Co-Author: MickLesk
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# This sets verbose mode if the global variable is set to "yes"
# if [ "$VERBOSE" == "yes" ]; then set -x; fi

# This function sets color variables for formatting output in the terminal
# Colors
YW=$(echo "\033[33m")
YWB=$(echo "\033[93m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")

# Formatting
CL=$(echo "\033[m")
UL=$(echo "\033[4m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

# Icons
CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"

# This sets error handling options and defines the error_handler function to handle errors
set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# This function handles errors
function error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  exit 200
}

# This function displays a spinner.
function spinner() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local interval=0.1
  printf "\e[?25l" 

  local color="${YWB}"

  while true; do
    printf "\r ${color}%s${CL}" "${frames[spin_i]}"
    spin_i=$(( (spin_i + 1) % ${#frames[@]} ))
    sleep "$interval"
  done
}

# This function displays an informational message with a yellow color.
function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

# This function displays a success message with a green color.
function msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

# This function displays a error message with a red color.
function msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

# This checks for the presence of valid Container Storage and Template Storage locations
msg_info "Validating Storage"
VALIDCT=$(pvesm status -content rootdir | awk 'NR>1')
if [ -z "$VALIDCT" ]; then
  msg_error "Unable to detect a valid Container Storage location."
  exit 1
fi
VALIDTMP=$(pvesm status -content vztmpl | awk 'NR>1')
if [ -z "$VALIDTMP" ]; then
  msg_error "Unable to detect a valid Template Storage location."
  exit 1
fi

# This function is used to select the storage class and determine the corresponding storage content type and label.
function select_storage() {
  local CLASS=$1
  local CONTENT
  local CONTENT_LABEL
  case $CLASS in
  container)
    CONTENT='rootdir'
    CONTENT_LABEL='Container'
    ;;
  template)
    CONTENT='vztmpl'
    CONTENT_LABEL='Container template'
    ;;
  *) false || { msg_error "Invalid storage class."; exit 201; };
  esac
  
  # This Queries all storage locations
  local -a MENU
  while read -r line; do
    local TAG=$(echo $line | awk '{print $1}')
    local TYPE=$(echo $line | awk '{printf "%-10s", $2}')
    local FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
    local ITEM="Type: $TYPE Free: $FREE "
    local OFFSET=2
    if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      local MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
    fi
    MENU+=("$TAG" "$ITEM" "OFF")
  done < <(pvesm status -content $CONTENT | awk 'NR>1')
  
  # Select storage location
  if [ $((${#MENU[@]}/3)) -eq 1 ]; then
    printf ${MENU[0]}
  else
    local STORAGE
    while [ -z "${STORAGE:+x}" ]; do
      STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool you would like to use for the ${CONTENT_LABEL,,}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${MENU[@]}" 3>&1 1>&2 2>&3) || { msg_error "Menu aborted."; exit 202; }
      if [ $? -ne 0 ]; then
        echo -e "${CROSS}${RD} Menu aborted by user.${CL}"
        exit 0 
      fi
    done
    printf "%s" "$STORAGE"
  fi
}
# Test if required variables are set
[[ "${CTID:-}" ]] || { msg_error "You need to set 'CTID' variable."; exit 203; }
[[ "${PCT_OSTYPE:-}" ]] || { msg_error "You need to set 'PCT_OSTYPE' variable."; exit 204; }

# Test if ID is valid
[ "$CTID" -ge "100" ] || { msg_error "ID cannot be less than 100."; exit 205; }

# Test if ID is in use
if pct status $CTID &>/dev/null; then
  echo -e "ID '$CTID' is already in use."
  unset CTID
  msg_error "Cannot use ID that is already in use."
  exit 206
fi

# Get template storage
TEMPLATE_STORAGE=$(select_storage template) || exit
msg_ok "Using ${BL}$TEMPLATE_STORAGE${CL} ${GN}for Template Storage."

# Get container storage
CONTAINER_STORAGE=$(select_storage container) || exit
msg_ok "Using ${BL}$CONTAINER_STORAGE${CL} ${GN}for Container Storage."

# Update LXC template list
msg_info "Updating LXC Template List"
pveam update >/dev/null
msg_ok "Updated LXC Template List"

# Get LXC template string
TEMPLATE_SEARCH=${PCT_OSTYPE}-${PCT_OSVERSION:-}
mapfile -t TEMPLATES < <(pveam available -section system | sed -n "s/.*\($TEMPLATE_SEARCH.*\)/\1/p" | sort -t - -k 2 -V)
[ ${#TEMPLATES[@]} -gt 0 ] || { msg_error "Unable to find a template when searching for '$TEMPLATE_SEARCH'."; exit 207; }
TEMPLATE="${TEMPLATES[-1]}"

TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"
# Check if template exists, if corrupt remove and redownload
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
  [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"
  msg_info "Downloading LXC Template"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null ||
    { msg_error "A problem occurred while downloading the LXC template."; exit 208; }
  msg_ok "Downloaded LXC Template"
fi

# Check and fix subuid/subgid
grep -q "root:100000:65536" /etc/subuid || echo "root:100000:65536" >> /etc/subuid
grep -q "root:100000:65536" /etc/subgid || echo "root:100000:65536" >> /etc/subgid

# Combine all options
PCT_OPTIONS=(${PCT_OPTIONS[@]:-${DEFAULT_PCT_OPTIONS[@]}})
[[ " ${PCT_OPTIONS[@]} " =~ " -rootfs " ]] || PCT_OPTIONS+=(-rootfs "$CONTAINER_STORAGE:${PCT_DISK_SIZE:-8}")

# Create container with template integrity check
msg_info "Creating LXC Container"
  if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
      [[ -f "$TEMPLATE_PATH" ]] && rm -f "$TEMPLATE_PATH"
      
    msg_ok "Template integrity check completed"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null ||    
      { msg_error "A problem occurred while re-downloading the LXC template."; exit 208; }
    
    msg_ok "Re-downloaded LXC Template"
    if ! pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" "${PCT_OPTIONS[@]}" &>/dev/null; then
        msg_error "A problem occurred while trying to create container after re-downloading template."
      exit 200
    fi
  fi
msg_ok "LXC Container ${BL}$CTID${CL} ${GN}was successfully created."
