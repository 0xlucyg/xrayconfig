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

  apt-get update && apt-get install -y jq

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


  # Allow the loopback port in ufw
  if command -v ufw &> /dev/null; then # Check if ufw is installed
    sudo ufw allow from 127.0.0.1 to 127.0.0.1 port "$XRAY_PORT"
    echo "ufw rule added for loopback port $XRAY_PORT"
  else
    echo "ufw is not installed. Skipping firewall rule."
  fi
}

# Function to install Nginx
install_nginx() {
  echo "Installing Nginx..."
  apt-get update && apt-get install -y nginx
}

# Function to install and configure Let's Encrypt
install_letsencrypt() {
  echo "Installing Certbot..."
  apt-get install -y certbot python3-certbot-nginx

  echo "Stopping Nginx..."
  systemctl stop nginx

  echo "Generating SSL certificate..."
  certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --force-renewal || {
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
    sed "s/WSPATH/$WSPATH/g" > $NGINX_CONFIG_FILE.tmp # Add WebSocket path replacement
  mv $NGINX_CONFIG_FILE.tmp $NGINX_CONFIG_FILE

  ln -s $NGINX_CONFIG_FILE $NGINX_CONFIG_FILE # Corrected: link to the file itself
  nginx -t && systemctl reload nginx
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
