#!/usr/bin/env bash

# Copyright (c) 2021-2024 community-scripts ORG
# Author: zimmra
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/FreshRSS/FreshRSS

# Import Functions and Setup
source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Define Variables
APP="FreshRSS"
REPO_URL="https://github.com/FreshRSS/FreshRSS"
API_URL="https://api.github.com/repos/FreshRSS/FreshRSS/releases/latest"
PHP_VERSION="8.2"
INSTALL_DIR="/opt/${APP}"
DATA_DIR="${INSTALL_DIR}/data"
WEB_DIR="${INSTALL_DIR}/p"

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
    curl \
    sudo \
    mc \
    nginx \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-{curl,gmp,intl,mbstring,xml,zip,sqlite3,mysql,pgsql} \
    ca-certificates \
    cron
msg_ok "Installed Dependencies"

# Configure PHP-FPM
msg_info "Configuring PHP-FPM"
PHP_POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
cat <<EOF >${PHP_POOL_DIR}/freshrss.conf
[freshrss]
user = root
group = root
listen = /run/php/php${PHP_VERSION}-fpm.sock
listen.owner = root
listen.group = root
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

# Configure PHP
PHP_INI_DIR="/etc/php/${PHP_VERSION}/fpm"
if [[ -f "${PHP_INI_DIR}/php.ini" ]]; then
    sed -i \
        -e 's/^;*\s*date.timezone.*/date.timezone = UTC/' \
        -e 's/^;*\s*post_max_size.*/post_max_size = 32M/' \
        -e 's/^;*\s*upload_max_filesize.*/upload_max_filesize = 32M/' \
        "${PHP_INI_DIR}/php.ini"
fi
msg_ok "Configured PHP"

# Configure Nginx
msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/conf.d/freshrss.conf
server {
    listen 80;
    server_name _;
    root ${WEB_DIR};
    index index.php index.html;

    # Security headers
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Logs
    access_log /dev/stdout combined;
    error_log /dev/stderr notice;

    # Handle PHP files
    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # API access
    location /api/ {
        try_files \$uri \$uri/ /api/index.php?\$args;
    }

    # Static files
    location /themes/ {
        expires 30d;
        add_header Pragma public;
        add_header Cache-Control "public, must-revalidate, proxy-revalidate";
    }

    # Deny access to sensitive files
    location ~ /\.(?!well-known) {
        deny all;
    }

    # Main location
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

# Remove default config
rm -f /etc/nginx/sites-enabled/default
msg_ok "Configured Nginx"

# Setup FreshRSS
msg_info "Setting up ${APP}"
RELEASE=$(curl -fsSL "${API_URL}" | grep -Po '"tag_name": "\K.*?(?=")')
RELEASE="${RELEASE#v}"  # Remove 'v' prefix if present

cd /opt || exit 1
wget -q "${REPO_URL}/archive/refs/tags/v${RELEASE}.tar.gz"
tar -xzf "v${RELEASE}.tar.gz"
mv "${APP}-${RELEASE}" "${APP}"

# Create required directories and structure
msg_info "Creating Directory Structure"
mkdir -p ${INSTALL_DIR}/{data,extensions,lib,app,p}
mkdir -p ${WEB_DIR}/{api,i,themes}
mkdir -p ${DATA_DIR}/{cache,favicons,feeds,log,tokens,users,xdg}

# Move files to correct locations
mv ${INSTALL_DIR}/app/* ${INSTALL_DIR}/app/
mv ${INSTALL_DIR}/lib/* ${INSTALL_DIR}/lib/
mv ${INSTALL_DIR}/p/* ${WEB_DIR}/

# Set ownership and permissions
chown -R root:root ${INSTALL_DIR}
chmod -R 755 ${INSTALL_DIR}
chmod -R 775 ${DATA_DIR}
chmod -R 775 ${INSTALL_DIR}/extensions
chmod -R 775 ${WEB_DIR}/i

# Save version for updates
echo "${RELEASE}" > ${INSTALL_DIR}/VERSION
chmod 644 ${INSTALL_DIR}/VERSION
msg_ok "Setup ${APP}"

# Setup Cron
msg_info "Setting up Cron Job"
CRON_FILE="/etc/cron.d/freshrss"
echo "7,37 * * * * root php ${INSTALL_DIR}/app/actualize_script.php > /tmp/FreshRSS.log 2>&1" > ${CRON_FILE}
chmod 0644 ${CRON_FILE}
msg_ok "Setup Cron Job"

# Start Services
msg_info "Starting Services"
systemctl enable -q --now php${PHP_VERSION}-fpm
systemctl enable -q --now nginx
systemctl enable -q --now cron
msg_ok "Started Services"

# Cleanup
msg_info "Cleaning up"
rm -f "v${RELEASE}.tar.gz"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

motd_ssh
customize
