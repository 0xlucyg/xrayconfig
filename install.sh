#!/bin/bash

# Variables (moved to the top)
XRAY_PORT=10080
WSPATH="/vless-ws"
NGINX_PORT=80
XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_TEMPLATE_URL="https://github.com/0xlucyg/xrayconfig/raw/refs/heads/main/xray-config.json" # URL for Xray template
XRAY_TEMPLATE_FILE="xray-config.json.template"  # Local filename for Xray template
NGINX_TEMPLATE_URL="https://github.com/0xlucyg/xrayconfig/raw/refs/heads/main/nginx-config.template" # URL for Nginx template
NGINX_TEMPLATE_FILE="nginx-config.template" # Local filename for Nginx template
NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN" # Dynamic, will be set later
STATIC_UUID="dcd099af-57bc-4dbc-b404-79851facfb36" # Static UUID

# Function to output text in green
green_echo() {
  echo -e "\e[32m$1\e[0m"  # Green text: \e[32m, Reset: \e[0m
}

# Function to output text in red (for errors)
red_echo() {
  echo -e "\e[31m$1\e[0m"  # Red text: \e[31m, Reset: \e[0m
}

# Run apt-get update ONCE at the beginning of the script, and then clear the screen
apt-get update && clear

# Function to download the templates
download_templates() {
  green_echo "Downloading Xray template..."
  curl -sSL "$XRAY_TEMPLATE_URL" > "$XRAY_TEMPLATE_FILE"
  if [[ ! -f "$XRAY_TEMPLATE_FILE" ]]; then
    red_echo "Error: Failed to download Xray template."
    exit 1
  fi

  green_echo "Downloading Nginx template..."
  curl -sSL "$NGINX_TEMPLATE_URL" > "$NGINX_TEMPLATE_FILE"
  if [[ ! -f "$NGINX_TEMPLATE_FILE" ]]; then
    red_echo "Error: Failed to download Nginx template."
    exit 1
  fi
}


# Function to install Xray using xray-install
install_xray() {
  green_echo "Installing Xray..."
  bash <(curl -Ls https://raw.githubusercontent.com/XTLS/xray-install/master/install-release.sh)

  EMAIL="admin@$DOMAIN" # Email set to admin@DOMAIN

  apt-get install -y jq  # jq install

  # Use the template and replace the UUID, email, domain, ws path, and Xray port.
  jq -r '.inbounds[0].settings.clients[0].id = "'$STATIC_UUID'"' $XRAY_TEMPLATE_FILE | \
    jq -r '.inbounds[0].settings.clients[0].email = "'$EMAIL'"' | \
    jq -r '.inbounds[1].settings.clients[0].id = "'$STATIC_UUID'"' | \
    jq -r '.inbounds[1].settings.clients[0].email = "'$EMAIL'"' | \
    jq -r '.inbounds[0].fallbacks[0].path = "'$WSPATH'"' | \
    jq -r '.inbounds[1].streamSettings.wsSettings.path = "'$WSPATH'"' | \
    jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile = "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"' | \
    jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].keyFile = "/etc/letsencrypt/live/$DOMAIN/privkey.pem"' | \
    jq -r '.inbounds[0].port = '"$XRAY_PORT"'' | \
    jq -r '.inbounds[0].fallbacks[1].dest = '"$NGINX_PORT"'' | \
    jq -r '.inbounds[1].listen = "@vless-ws"' > $XRAY_CONFIG_FILE

  green_echo "UUID: $STATIC_UUID"
  green_echo "Email: $EMAIL"
  green_echo "WebSocket Path: $WSPATH"
  green_echo "Xray Port: $XRAY_PORT"
  green_echo "Fallback Port: $NGINX_PORT"

  # Allow the loopback port in ufw
  if command -v ufw &> /dev/null; then
    sudo ufw allow from 127.0.0.1 to 127.0.0.1 port "$XRAY_PORT"
    green_echo "ufw rule added for loopback port $XRAY_PORT"
  else
    green_echo "ufw is not installed. Skipping firewall rule."
  fi
}

install_nginx() {
  green_echo "Checking if Nginx is already installed..."

  if command -v nginx &> /dev/null; then  # Check if nginx command exists
    green_echo "Nginx is already installed."

    # Check if Nginx is running and restart it to load config (optional)
    if systemctl is-active --quiet nginx; then
      green_echo "Nginx is running. Restarting to load new configuration (if any)..."
      systemctl restart nginx
    fi
    return  # Exit the function early if Nginx is already installed
  fi

  green_echo "Installing Nginx..."
  apt-get install -y nginx

  green_echo "Nginx installed."
}

install_letsencrypt() {
  green_echo "Installing Certbot..."
  apt-get install -y certbot python3-certbot-nginx

  green_echo "Stopping Nginx..."
  systemctl stop nginx

  green_echo "Generating SSL certificate..."

  # Use certonly --standalone and specify certificate and key paths
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" \
    --cert-name "$DOMAIN" \
    --cert-path "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    --key-path "/etc/letsencrypt/live/$DOMAIN/privkey.pem" || {
    red_echo "Error: Certbot failed. Please check the logs for more details."
    systemctl start nginx # Restart Nginx even if Certbot fails
    exit 1  # Exit the script if Certbot fails
  }

  green_echo "Starting Nginx..."
  systemctl start nginx
  green_echo "Certbot certificate generation successful."
}

configure_nginx_websocket() {
  green_echo "Configuring Nginx for WebSocket..."

  # Use the template and replace the domain, Xray port, and WebSocket path
  sed "s/YOUR_DOMAIN/$DOMAIN/g" $NGINX_TEMPLATE_FILE | \
    sed "s/XRAY_PORT/$XRAY_PORT/g" | \
    sed "s/WSPATH/$WSPATH/g" > $NGINX_CONFIG_FILE.tmp
  mv $NGINX_CONFIG_FILE.tmp $NGINX_CONFIG_FILE

  # Create or update the symbolic link in sites-enabled
  ln -sf $NGINX_CONFIG_FILE /etc/nginx/sites-enabled/$DOMAIN

  # Remove the default site configuration (if it exists)
  if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
    green_echo "Removed default Nginx site configuration."
  fi

  nginx -t  # Test Nginx configuration

  # Check if Nginx is already running
  if systemctl is-active --quiet nginx; then
    green_echo "Nginx is already running. Restarting..."
    systemctl restart nginx
  else
    green_echo "Nginx is not running. Starting..."
    systemctl start nginx
  fi
}


# Main execution
read -p "Enter your domain: " DOMAIN  # Get domain from the user

# Download the templates
download_templates

# Set the Nginx config file path (dynamic)
NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"

install_xray
install_nginx
install_letsencrypt
configure_nginx_websocket

green_echo "Installation complete!"

# Print all information at the end
green_echo "----------------------------------------"
green_echo "Domain: $DOMAIN"
green_echo "Email: admin@$DOMAIN"
green_echo "UUID: $STATIC_UUID"
green_echo "WebSocket Path: $WSPATH"
green_echo "Xray Port: $XRAY_PORT"
green_echo "Nginx Port: $NGINX_PORT"
green_echo "Xray Config File: $XRAY_CONFIG_FILE"
green_echo "Nginx Config File: $NGINX_CONFIG_FILE"
green_echo "----------------------------------------"
green_echo "Xray is running (internal)."
green_echo "Nginx is listening on port 80 and 443."
green_echo "Remember to replace 'your_domain.com' with your actual domain if you haven't already."
