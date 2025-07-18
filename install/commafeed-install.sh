#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.commafeed.com/#/welcome

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y rsync
msg_ok "Installed Dependencies"

JAVA_VERSION="17" setup_java
fetch_and_deploy_gh_release "commafeed" "Athou/commafeed" "prebuild" "latest" "/opt/commafeed" "commafeed-*-h2-jvm.zip"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/commafeed.service
[Unit]
Description=CommaFeed Service
After=network.target

[Service]
ExecStart=java -jar quarkus-run.jar
WorkingDirectory=/opt/commafeed/
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now commafeed
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
