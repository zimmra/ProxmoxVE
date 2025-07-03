#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (Canbiz) && Desert_Gamer
# License: MIT
# Source: https://github.com/gitsang/iptag

function header_info {
  clear
  cat <<"EOF"
 ___ ____     _   _       _            
|_ _|  _ \ _ | \ | | ___ | |_ ___  ___ 
 | || |_) (_)|  \| |/ _ \| __/ _ \/ __|
 | ||  __/ _ | |\  | (_) | ||  __/\__ \
|___|_|   (_)|_| \_|\___/ \__\___||___/
EOF
}

clear
header_info
APP="IP-Notes"
hostname=$(hostname)

# Farbvariablen
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD=" "
CM=" ✔️ ${CL}"
CROSS=" ✖️ ${CL}"

# This function enables error handling in the script by setting options and defining a trap for the ERR signal.
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

# This function is called when an error occurs. It receives the exit code, line number, and command that caused the error, and displays an error message.
error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then
    kill "$SPINNER_PID" >/dev/null
  fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

# This function displays a spinner.
spinner() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local interval=0.1
  printf "\e[?25l"

  local color="${YWB}"

  while true; do
    printf "\r ${color}%s${CL}" "${frames[spin_i]}"
    spin_i=$(((spin_i + 1) % ${#frames[@]}))
    sleep "$interval"
  done
}

# This function displays an informational message with a yellow color.
msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

# This function displays a success message with a green color.
msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then
    kill $SPINNER_PID >/dev/null
  fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

# This function displays a error message with a red color.
msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p "$SPINNER_PID" >/dev/null; then
    kill "$SPINNER_PID" >/dev/null
  fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

# Check if service exists
check_service_exists() {
  if systemctl is-active --quiet ipnotes.service; then
    return 0
  else
    return 1
  fi
}

# Migrate configuration from old path to new
migrate_config() {
  local old_config="/opt/lxc-ipnotes"
  local new_config="/opt/ipnotes/ipnotes.conf"

  if [[ -f "$old_config" ]]; then
    msg_info "Migrating configuration from old path"
    if cp "$old_config" "$new_config" &>/dev/null; then
      rm -rf "$old_config" &>/dev/null
      msg_ok "Configuration migrated and old config removed"
    else
      msg_error "Failed to migrate configuration"
    fi
  fi
}

# Update existing installation
update_installation() {
  msg_info "Updating IP-Notes Scripts"
  systemctl stop ipnotes.service &>/dev/null

  # Create directory if it doesn't exist
  if [[ ! -d "/opt/ipnotes" ]]; then
    mkdir -p /opt/ipnotes
  fi

  # Migrate config if needed
  migrate_config

  # Update main script
  cat <<'EOF' >/opt/ipnotes/ipnotes
#!/bin/bash
# =============== CONFIGURATION =============== #
readonly CONFIG_FILE="/opt/ipnotes/ipnotes.conf"
readonly DEFAULT_CHECK_INTERVAL=60

# Load the configuration file if it exists
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=./ipnotes.conf
    source "$CONFIG_FILE"
fi

# Check if IP is in CIDR
ip_in_cidr() {
    local ip="$1" cidr="$2"
    ipcalc -c "$ip" "$cidr" >/dev/null 2>&1 || return 1

    local network prefix ip_parts net_parts
    network=$(echo "$cidr" | cut -d/ -f1)
    prefix=$(echo "$cidr" | cut -d/ -f2)
    IFS=. read -r -a ip_parts <<< "$ip"
    IFS=. read -r -a net_parts <<< "$network"

    case $prefix in
        8)  [[ "${ip_parts[0]}" == "${net_parts[0]}" ]] ;;
        16) [[ "${ip_parts[0]}.${ip_parts[1]}" == "${net_parts[0]}.${net_parts[1]}" ]] ;;
        24) [[ "${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}" == "${net_parts[0]}.${net_parts[1]}.${net_parts[2]}" ]] ;;
        32) [[ "$ip" == "$network" ]] ;;
        *)  return 1 ;;
    esac
}

# Check if IP is in any CIDRs
ip_in_cidrs() {
    local ip="$1" cidrs="$2"
    [[ -z "$cidrs" ]] && return 1
    local IFS=' '
    for cidr in $cidrs; do ip_in_cidr "$ip" "$cidr" && return 0; done
    return 1
}

# Check if IP is valid
is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    
    local IFS='.' parts
    read -ra parts <<< "$ip"
    for part in "${parts[@]}"; do
        (( part >= 0 && part <= 255 )) || return 1
    done
    return 0
}

# Get IP address for LXC container
get_lxc_ip() {
    local ctId="$1"
    local ipAddress=""
    
    # First try to get IP from inside the container
    ipAddress=$(pct exec "$ctId" -- bash -c "ip -o -4 addr list eth0 | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null)
    
    if [ -n "$ipAddress" ]; then
        echo "$ipAddress"
        return 0
    fi
    
    # If that fails, try to get IP via MAC address lookup
    local macAddress
    macAddress=$(pct config "$ctId" | grep -E '^net[0-9]+:' | grep -oP 'hwaddr=\K[^,]+')
    if [ -z "$macAddress" ]; then
        return 1
    fi
    
    local vlan
    vlan=$(pct config "$ctId" | grep -E '^net[0-9]+:' | grep -oP 'bridge=\K[^,]+')
    if [ -z "$vlan" ]; then
        return 1
    fi
    
    # Use arp-scan to find the IP based on the MAC address
    ipAddress=$(arp-scan --interface="$vlan" --localnet 2>/dev/null | grep -i "$macAddress" | awk '{print $1}')
    
    if [ -n "$ipAddress" ]; then
        echo "$ipAddress"
        return 0
    fi
    
    return 1
}

# Get VM IPs using MAC addresses and ARP table
get_vm_ips() {
    local vmid=$1 ips="" macs found_ip=false
    qm status "$vmid" 2>/dev/null | grep -q "status: running" || return

    macs=$(qm config "$vmid" 2>/dev/null | grep -E 'net[0-9]+' | grep -oE '[a-fA-F0-9]{2}(:[a-fA-F0-9]{2}){5}')
    [[ -z "$macs" ]] && return

    for mac in $macs; do
        local ip
        ip=$(arp -an 2>/dev/null | grep -i "$mac" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
        [[ -n "$ip" ]] && { ips+="$ip "; found_ip=true; }
    done

    if ! $found_ip; then
        local agent_ip
        agent_ip=$(qm agent "$vmid" network-get-interfaces 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
        [[ -n "$agent_ip" ]] && ips+="$agent_ip "
    fi

    echo "${ips% }"
}

# Update notes for container or VM
update_notes() {
    local type="$1" vmid="$2" config_cmd="pct"
    [[ "$type" == "vm" ]] && config_cmd="qm"

    local current_ip=""
    if [[ "$type" == "lxc" ]]; then
        current_ip=$(get_lxc_ip "$vmid")
    else
        current_ip=$(get_vm_ips "$vmid")
    fi

    if [[ -z "$current_ip" ]]; then
        current_ip="Could not determine IP address"
    fi

    # Only update if IP is in allowed CIDRs (or if we couldn't determine the IP)
    if [[ "$current_ip" != "Could not determine IP address" ]] && ! ip_in_cidrs "$current_ip" "${CIDR_LIST[*]}"; then
        echo "${type^} ${vmid}: IP $current_ip not in allowed CIDRs, skipping"
        return
    fi

    # Get existing notes
    local existing_notes
    existing_notes=$($config_cmd config "$vmid" 2>/dev/null | sed -n 's/^notes: //p' | base64 -d 2>/dev/null || echo "")

    # Check if IP line already exists and is current
    local current_ip_line
    current_ip_line=$(echo "$existing_notes" | grep "^IP Address:" | sed 's/^IP Address: //')
    
    if [[ "$current_ip_line" == "$current_ip" ]]; then
        echo "${type^} ${vmid}: IP address already up to date: $current_ip"
        return
    fi

    # Update or add IP address line
    local updated_notes
    if echo "$existing_notes" | grep -q "^IP Address:"; then
        updated_notes=$(echo "$existing_notes" | sed -E "s|^IP Address:.*|IP Address: $current_ip|")
        echo "${type^} ${vmid}: updated IP address: $current_ip"
    else
        if [[ -n "$existing_notes" ]]; then
            updated_notes="$existing_notes

IP Address: $current_ip"
        else
            updated_notes="IP Address: $current_ip"
        fi
        echo "${type^} ${vmid}: added IP address: $current_ip"
    fi

    # Update the notes
    $config_cmd set "$vmid" --description "$updated_notes" &>/dev/null
}

# Update all instances
update_all() {
    local type="$1" list_cmd="pct" vmids count=0
    [[ "$type" == "vm" ]] && list_cmd="qm"
    
    # Only get running containers/VMs
    if [[ "$type" == "lxc" ]]; then
        vmids=$($list_cmd list 2>/dev/null | grep -v VMID | awk '$2=="running" {print $1}')
    else
        vmids=$($list_cmd list 2>/dev/null | grep -v VMID | awk '$3=="running" {print $1}')
    fi
    
    for vmid in $vmids; do ((count++)); done
    
    echo "Found ${count} running ${type}s"
    [[ $count -eq 0 ]] && return

    for vmid in $vmids; do 
        update_notes "$type" "$vmid"
    done
}

# Check if status changed
check_status() {
    local type="$1" current
    case "$type" in
        "lxc") current=$(pct list 2>/dev/null | grep -v VMID) ;;
        "vm")  current=$(qm list 2>/dev/null | grep -v VMID) ;;
        "fw")  current=$(ifconfig 2>/dev/null | grep "^fw") ;;
    esac
    local last_var="last_${type}_status"
    [[ "${!last_var}" == "$current" ]] && return 1
    eval "$last_var='$current'"
    return 0
}

# Main check function
check() {
    local current_time changes_detected=false
    current_time=$(date +%s)

    for type in "lxc" "vm"; do
        local interval_var="${type^^}_STATUS_CHECK_INTERVAL"
        local last_check_var="last_${type}_check_time"
        local last_update_var="last_update_${type}_time"
        
        if [[ "${!interval_var}" -gt 0 ]] && (( current_time - ${!last_check_var} >= ${!interval_var} )); then
            echo "Checking ${type^^} status..."
            eval "${last_check_var}=\$current_time"
            if check_status "$type"; then
                changes_detected=true
                update_all "$type"
                eval "${last_update_var}=\$current_time"
            fi
        fi

        if (( current_time - ${!last_update_var} >= FORCE_UPDATE_INTERVAL )); then
            echo "Force updating ${type} notes..."
            changes_detected=true
            update_all "$type"
            eval "${last_update_var}=\$current_time"
        fi
    done

    if [[ "${FW_NET_INTERFACE_CHECK_INTERVAL}" -gt 0 ]] && \
       (( current_time - last_fw_check_time >= FW_NET_INTERFACE_CHECK_INTERVAL )); then
        echo "Checking network interfaces..."
        last_fw_check_time=$current_time
        if check_status "fw"; then
            changes_detected=true
            update_all "lxc"
            update_all "vm"
            last_update_lxc_time=$current_time
            last_update_vm_time=$current_time
        fi
    fi

    $changes_detected || echo "No changes detected in system status"
}

# Initialize time variables
declare -g last_lxc_status="" last_vm_status="" last_fw_status=""
declare -g last_lxc_check_time=0 last_vm_check_time=0 last_fw_check_time=0
declare -g last_update_lxc_time=0 last_update_vm_time=0

# Main loop
main() {
    while true; do
        check
        sleep "${LOOP_INTERVAL:-$DEFAULT_CHECK_INTERVAL}"
    done
}

main
EOF
  chmod +x /opt/ipnotes/ipnotes

  # Update service file
  cat <<EOF >/lib/systemd/system/ipnotes.service
[Unit]
Description=IP-Notes service
After=network.target

[Service]
Type=simple
ExecStart=/opt/ipnotes/ipnotes
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload &>/dev/null
  systemctl enable -q --now ipnotes.service &>/dev/null
  msg_ok "Updated IP-Notes Scripts"
}

# Main installation process
if check_service_exists; then
  while true; do
    read -p "IP-Notes service is already installed. Do you want to update it? (y/n): " yn
    case $yn in
    [Yy]*)
      update_installation
      exit 0
      ;;
    [Nn]*)
      msg_error "Installation cancelled."
      exit 0
      ;;
    *)
      msg_error "Please answer yes or no."
      ;;
    esac
  done
fi

while true; do
  read -p "This will install ${APP} on ${hostname}. Proceed? (y/n): " yn
  case $yn in
  [Yy]*)
    break
    ;;
  [Nn]*)
    msg_error "Installation cancelled."
    exit
    ;;
  *)
    msg_error "Please answer yes or no."
    ;;
  esac
done

if ! pveversion | grep -Eq "pve-manager/8\.[0-4](\.[0-9]+)*"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  msg_error "⚠️ Requires Proxmox Virtual Environment Version 8.0 or later."
  msg_error "Exiting..."
  sleep 2
  exit
fi

FILE_PATH="/usr/local/bin/ipnotes"
if [[ -f "$FILE_PATH" ]]; then
  msg_info "The file already exists: '$FILE_PATH'. Skipping installation."
  exit 0
fi

msg_info "Installing Dependencies"
apt-get update &>/dev/null
apt-get install -y ipcalc net-tools arp-scan &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Setting up IP-Notes Scripts"
mkdir -p /opt/ipnotes
msg_ok "Setup IP-Notes Scripts"

# Migrate config if needed
migrate_config

msg_info "Setup Default Config"
if [[ ! -f /opt/ipnotes/ipnotes.conf ]]; then
  cat <<EOF >/opt/ipnotes/ipnotes.conf
# Configuration file for LXC/VM IP notes management

# List of allowed CIDRs
CIDR_LIST=(
  192.168.0.0/16
  172.16.0.0/12
  10.0.0.0/8
  100.64.0.0/10
)

# Interval settings (in seconds)
LOOP_INTERVAL=60
VM_STATUS_CHECK_INTERVAL=60
FW_NET_INTERFACE_CHECK_INTERVAL=60
LXC_STATUS_CHECK_INTERVAL=60
FORCE_UPDATE_INTERVAL=1800
EOF
  msg_ok "Setup default config"
else
  msg_ok "Default config already exists"
fi

msg_info "Setup Main Function"
if [[ ! -f /opt/ipnotes/ipnotes ]]; then
  cat <<'EOF' >/opt/ipnotes/ipnotes
#!/bin/bash
# =============== CONFIGURATION =============== #
readonly CONFIG_FILE="/opt/ipnotes/ipnotes.conf"
readonly DEFAULT_CHECK_INTERVAL=60

# Load the configuration file if it exists
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=./ipnotes.conf
    source "$CONFIG_FILE"
fi

# Check if IP is in CIDR
ip_in_cidr() {
    local ip="$1" cidr="$2"
    ipcalc -c "$ip" "$cidr" >/dev/null 2>&1 || return 1

    local network prefix ip_parts net_parts
    network=$(echo "$cidr" | cut -d/ -f1)
    prefix=$(echo "$cidr" | cut -d/ -f2)
    IFS=. read -r -a ip_parts <<< "$ip"
    IFS=. read -r -a net_parts <<< "$network"

    case $prefix in
        8)  [[ "${ip_parts[0]}" == "${net_parts[0]}" ]] ;;
        16) [[ "${ip_parts[0]}.${ip_parts[1]}" == "${net_parts[0]}.${net_parts[1]}" ]] ;;
        24) [[ "${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}" == "${net_parts[0]}.${net_parts[1]}.${net_parts[2]}" ]] ;;
        32) [[ "$ip" == "$network" ]] ;;
        *)  return 1 ;;
    esac
}

# Check if IP is in any CIDRs
ip_in_cidrs() {
    local ip="$1" cidrs="$2"
    [[ -z "$cidrs" ]] && return 1
    local IFS=' '
    for cidr in $cidrs; do 
        ip_in_cidr "$ip" "$cidr" && return 0
    done
    return 1
}

# Check if IP is valid
is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    
    local IFS='.' parts
    read -ra parts <<< "$ip"
    for part in "${parts[@]}"; do
        (( part >= 0 && part <= 255 )) || return 1
    done
    return 0
}

# Get IP address for LXC container
get_lxc_ip() {
    local ctId="$1"
    local ipAddress=""
    
    # First try to get IP from inside the container
    ipAddress=$(pct exec "$ctId" -- bash -c "ip -o -4 addr list eth0 | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null)
    
    if [ -n "$ipAddress" ]; then
        echo "$ipAddress"
        return 0
    fi
    
    # If that fails, try to get IP via MAC address lookup
    local macAddress
    macAddress=$(pct config "$ctId" | grep -E '^net[0-9]+:' | grep -oP 'hwaddr=\K[^,]+')
    if [ -z "$macAddress" ]; then
        return 1
    fi
    
    local vlan
    vlan=$(pct config "$ctId" | grep -E '^net[0-9]+:' | grep -oP 'bridge=\K[^,]+')
    if [ -z "$vlan" ]; then
        return 1
    fi
    
    # Use arp-scan to find the IP based on the MAC address
    ipAddress=$(arp-scan --interface="$vlan" --localnet 2>/dev/null | grep -i "$macAddress" | awk '{print $1}')
    
    if [ -n "$ipAddress" ]; then
        echo "$ipAddress"
        return 0
    fi
    
    return 1
}

# Get VM IPs using MAC addresses and ARP table
get_vm_ips() {
    local vmid=$1 ips="" macs found_ip=false
    qm status "$vmid" 2>/dev/null | grep -q "status: running" || return

    macs=$(qm config "$vmid" 2>/dev/null | grep -E 'net[0-9]+' | grep -oE '[a-fA-F0-9]{2}(:[a-fA-F0-9]{2}){5}')
    [[ -z "$macs" ]] && return

    for mac in $macs; do
        local ip
        ip=$(arp -an 2>/dev/null | grep -i "$mac" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
        [[ -n "$ip" ]] && { ips+="$ip "; found_ip=true; }
    done

    if ! $found_ip; then
        local agent_ip
        agent_ip=$(qm agent "$vmid" network-get-interfaces 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
        [[ -n "$agent_ip" ]] && ips+="$agent_ip "
    fi

    echo "${ips% }"
}

# Update notes for container or VM
update_notes() {
    local type="$1" vmid="$2" config_cmd="pct"
    [[ "$type" == "vm" ]] && config_cmd="qm"

    local current_ip=""
    if [[ "$type" == "lxc" ]]; then
        current_ip=$(get_lxc_ip "$vmid")
    else
        current_ip=$(get_vm_ips "$vmid")
    fi

    if [[ -z "$current_ip" ]]; then
        current_ip="Could not determine IP address"
    fi

    # Only update if IP is in allowed CIDRs (or if we couldn't determine the IP)
    if [[ "$current_ip" != "Could not determine IP address" ]] && ! ip_in_cidrs "$current_ip" "${CIDR_LIST[*]}"; then
        echo "${type^} ${vmid}: IP $current_ip not in allowed CIDRs, skipping"
        return
    fi

    # Get existing notes
    local existing_notes
    existing_notes=$($config_cmd config "$vmid" 2>/dev/null | sed -n 's/^notes: //p' | base64 -d 2>/dev/null || echo "")

    # Check if IP line already exists and is current
    local current_ip_line
    current_ip_line=$(echo "$existing_notes" | grep "^IP Address:" | sed 's/^IP Address: //')
    
    if [[ "$current_ip_line" == "$current_ip" ]]; then
        echo "${type^} ${vmid}: IP address already up to date: $current_ip"
        return
    fi

    # Update or add IP address line
    local updated_notes
    if echo "$existing_notes" | grep -q "^IP Address:"; then
        updated_notes=$(echo "$existing_notes" | sed -E "s|^IP Address:.*|IP Address: $current_ip|")
        echo "${type^} ${vmid}: updated IP address: $current_ip"
    else
        if [[ -n "$existing_notes" ]]; then
            updated_notes="$existing_notes

IP Address: $current_ip"
        else
            updated_notes="IP Address: $current_ip"
        fi
        echo "${type^} ${vmid}: added IP address: $current_ip"
    fi

    # Update the notes
    $config_cmd set "$vmid" --description "$updated_notes" &>/dev/null
}

# Update all instances of specified type
update_all_notes() {
    local type="$1" list_cmd="pct" vmids count=0
    [[ "$type" == "vm" ]] && list_cmd="qm"
    
    # Only get running containers/VMs
    if [[ "$type" == "lxc" ]]; then
        vmids=$($list_cmd list 2>/dev/null | grep -v VMID | awk '$2=="running" {print $1}')
    else
        vmids=$($list_cmd list 2>/dev/null | grep -v VMID | awk '$3=="running" {print $1}')
    fi
    
    for vmid in $vmids; do ((count++)); done
    
    echo "Found ${count} running ${type}s"
    [[ $count -eq 0 ]] && return

    for vmid in $vmids; do 
        update_notes "$type" "$vmid"
    done
}

# Check if status changed
check_status_changed() {
    local type="$1" current
    case "$type" in
        "lxc") current=$(pct list 2>/dev/null | grep -v VMID) ;;
        "vm")  current=$(qm list 2>/dev/null | grep -v VMID) ;;
        "fw")  current=$(ifconfig 2>/dev/null | grep "^fw") ;;
    esac
    local last_var="last_${type}_status"
    [[ "${!last_var}" == "$current" ]] && return 1
    eval "$last_var='$current'"
    return 0
}

# Main check function
check() {
    local current_time changes_detected=false
    current_time=$(date +%s)

    # Check LXC status
    local time_since_last_lxc_check=$((current_time - last_lxc_status_check_time))
    if [[ "${LXC_STATUS_CHECK_INTERVAL:-60}" -gt 0 ]] && \
       [[ "${time_since_last_lxc_check}" -ge "${LXC_STATUS_CHECK_INTERVAL:-60}" ]]; then
        echo "Checking LXC status..."
        last_lxc_status_check_time=${current_time}
        if check_status_changed "lxc"; then
            changes_detected=true
            update_all_notes "lxc"
            last_update_lxc_time=${current_time}
        fi
    fi

    # Check VM status
    local time_since_last_vm_check=$((current_time - last_vm_status_check_time))
    if [[ "${VM_STATUS_CHECK_INTERVAL:-60}" -gt 0 ]] && \
       [[ "${time_since_last_vm_check}" -ge "${VM_STATUS_CHECK_INTERVAL:-60}" ]]; then
        echo "Checking VM status..."
        last_vm_status_check_time=${current_time}
        if check_status_changed "vm"; then
            changes_detected=true
            update_all_notes "vm"
            last_update_vm_time=${current_time}
        fi
    fi

    # Check network interface changes
    local time_since_last_fw_check=$((current_time - last_fw_net_interface_check_time))
    if [[ "${FW_NET_INTERFACE_CHECK_INTERVAL:-60}" -gt 0 ]] && \
       [[ "${time_since_last_fw_check}" -ge "${FW_NET_INTERFACE_CHECK_INTERVAL:-60}" ]]; then
        echo "Checking network interfaces..."
        last_fw_net_interface_check_time=${current_time}
        if check_status_changed "fw"; then
            changes_detected=true
            update_all_notes "lxc"
            update_all_notes "vm"
            last_update_lxc_time=${current_time}
            last_update_vm_time=${current_time}
        fi
    fi

    # Force update if needed
    for type in "lxc" "vm"; do
        local last_update_var="last_update_${type}_time"
        local time_since_last_update=$((current_time - ${!last_update_var}))
        if [[ ${time_since_last_update} -ge ${FORCE_UPDATE_INTERVAL:-1800} ]]; then
            echo "Force updating ${type} notes..."
            changes_detected=true
            update_all_notes "$type"
            eval "${last_update_var}=${current_time}"
        fi
    done

    $changes_detected || echo "No changes detected in system status"
}

# Initialize time variables
declare -g last_lxc_status="" last_vm_status="" last_fw_status=""
declare -g last_lxc_status_check_time=0 last_vm_status_check_time=0 last_fw_net_interface_check_time=0
declare -g last_update_lxc_time=0 last_update_vm_time=0

# Main loop
main() {
    while true; do
        check
        sleep "${LOOP_INTERVAL:-$DEFAULT_CHECK_INTERVAL}"
    done
}

main
EOF
  msg_ok "Setup Main Function"
else
  msg_ok "Main Function already exists"
fi
chmod +x /opt/ipnotes/ipnotes

msg_info "Creating Service"
if [[ ! -f /lib/systemd/system/ipnotes.service ]]; then
  cat <<EOF >/lib/systemd/system/ipnotes.service
[Unit]
Description=IP-Notes service
After=network.target

[Service]
Type=simple
ExecStart=/opt/ipnotes/ipnotes
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  msg_ok "Created Service"
else
  msg_ok "Service already exists."
fi

msg_ok "Setup IP-Notes Scripts"

msg_info "Starting Service"
systemctl daemon-reload &>/dev/null
systemctl enable -q --now ipnotes.service &>/dev/null
msg_ok "Started Service"
SPINNER_PID=""
echo -e "\n${APP} installation completed successfully! ${CL}\n"
