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

# Run apt-get update ONCE at the beginning of the script, and then clear the screen
apt-get update && clear

# Function to download the templates
download_templates() {
  echo "Downloading Xray template..."
  curl -sSL "$XRAY_TEMPLATE_URL" > "$XRAY_TEMPLATE_FILE"
  if [[ ! -f "$XRAY_TEMPLATE_FILE" ]]; then
    echo "Error: Failed to download Xray template."
    exit 1
  fi

  echo "Downloading Nginx template..."
  curl -sSL "$NGINX_TEMPLATE_URL" > "$NGINX_TEMPLATE_FILE"
  if [[ ! -f "$NGINX_TEMPLATE_FILE" ]]; then
    echo "Error: Failed to download Nginx template."
    exit 1
  fi
}


# Function to install Xray using xray-install
install_xray() {
  echo "Installing Xray..."
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

  echo "UUID: $STATIC_UUID"
  echo "Email: $EMAIL"
  echo "WebSocket Path: $WSPATH"
  echo "Xray Port: $XRAY_PORT"
  echo "Fallback Port: $NGINX_PORT"

  # Allow the loopback port in ufw
  if command -v ufw &> /dev/null; then
    sudo ufw allow from 127.0.0.1 to 127.0.0.1 port "$XRAY_PORT"
    echo "ufw rule added for loopback port $XRAY_PORT"
  else
    echo "ufw is not installed. Skipping firewall rule."
  fi
}

# Function to install Nginx
install_nginx() {
  echo "Checking if Nginx is already installed..."

  if command -v nginx &> /dev/null; then  # Check if nginx command exists
    echo "Nginx is already installed."

    # Check if Nginx is running and restart it to load config (optional)
    if systemctl is-active --quiet nginx; then
      echo "Nginx is running. Restarting to load new configuration (if any)..."
      systemctl restart nginx
    fi
    return  # Exit the function early if Nginx is already installed
  fi

  echo "Installing Nginx..."
  apt-get install -y nginx

  echo "Nginx installed."
}

# Function to install and configure Let's Encrypt
install_letsencrypt() {
  echo "Installing Certbot..."
  apt-get install -y certbot python3-certbot-nginx

  echo "Stopping Nginx..."
  systemctl stop nginx

  echo "Generating SSL certificate..."

  # Use certonly --standalone and specify certificate and key paths
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" \
    --cert-name "$DOMAIN" \
    --cert-path "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    --key-path "/etc/letsencrypt/live/$DOMAIN/privkey.pem" || {
    echo "Error: Certbot failed. Please check the logs for more details."
    systemctl start nginx # Restart Nginx even if Certbot fails
    exit 1  # Exit the script if Certbot fails
  }

  echo "Starting Nginx..."
  systemctl start nginx
  echo "Certbot certificate generation successful."
}

# Function to configure Nginx for WebSocket proxy
configure_nginx_websocket() {
  echo "Configuring Nginx for WebSocket..."

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
    echo "Removed default Nginx site configuration."
  fi

  nginx -t  # Test Nginx configuration

  # Check if Nginx is already running
  if systemctl is-active --quiet nginx; then
    echo "Nginx is already running. Restarting..."
    systemctl restart nginx
  else
    echo "Nginx is not running. Starting..."
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

echo "Installation complete!"

# Print all information at the end
echo "----------------------------------------"
echo "Domain: $DOMAIN"
echo "Email: admin@$DOMAIN"
echo "UUID: $STATIC_UUID"
echo "WebSocket Path: $WSPATH"
echo "Xray Port: $XRAY_PORT"
echo "Nginx Port: $NGINX_PORT"
echo "Xray Config File: $XRAY_CONFIG_FILE"
echo "Nginx Config File: $NGINX_CONFIG_FILE"
echo "----------------------------------------"
echo "Xray is running (internal)."
echo "Nginx is listening on port 80 and 443."
echo "Remember to replace 'your_domain.com' with your actual domain if you haven't already."
