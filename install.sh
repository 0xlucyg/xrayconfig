#!/bin/bash

# Variables (moved to the top)
XRAY_PORT=443  # Xray will directly handle TLS on port 443
WSPATH="/vless-ws"  # Default WebSocket path
XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
XRAY_TEMPLATE_URL="https://github.com/0xlucyg/xrayconfig/raw/refs/heads/main/xray-config.json" # URL for Xray template
XRAY_TEMPLATE_FILE="xray-config.json"  # Local filename for Xray template
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
}


# Function to install Xray using xray-install (modified)
install_xray() {
  green_echo "Checking if Xray is already installed..."

  if command -v xray &> /dev/null; then  # Check if xray command exists
    green_echo "Xray is already installed. Skipping installation."
  else
    green_echo "Xray is not installed. Installing Xray..."
    bash <(curl -Ls https://raw.githubusercontent.com/XTLS/xray-install/master/install-release.sh)
  fi # Close the if statement here

  # This part is ALWAYS executed, whether Xray was already installed or not
  EMAIL="admin@$DOMAIN" # Email set to admin@DOMAIN

  # Use the template and replace the UUID, email, domain and ws path.
  # Use sed with # as delimiter to replace placeholders
  sed "s#%%UUID%%#$STATIC_UUID#g" $XRAY_TEMPLATE_FILE | \
    sed "s#%%EMAIL%%#$EMAIL#g" | \
    sed "s#%%DOMAIN%%#$DOMAIN#g" | \
    sed "s#%%WSPATH%%#$WSPATH#g" > $XRAY_CONFIG_FILE

  green_echo "UUID: $STATIC_UUID"
  green_echo "Email: $EMAIL"
  green_echo "WebSocket Path: $WSPATH"
  green_echo "Xray Port: $XRAY_PORT" # Show the port

  # Restart Xray Service to load new config (even if it was just installed)
  systemctl enable xray
  systemctl restart xray
  green_echo "Xray service started."

}


install_letsencrypt() {
  green_echo "Checking if SSL certificate already exists..."

  if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    green_echo "SSL certificate already exists. Skipping installation."
    return  # Exit the function early
  fi

  green_echo "Installing Certbot..."
  apt-get install -y certbot python3-certbot-nginx

  green_echo "Generating SSL certificate..."

  # Use certonly --standalone and specify certificate and key paths
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" \
    --cert-name "$DOMAIN" \
    --cert-path "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    --key-path "/etc/letsencrypt/live/$DOMAIN/privkey.pem" || {
    red_echo "Error: Certbot failed. Please check the logs for more details."
    exit 1  # Exit the script if Certbot fails
  }

  green_echo "Certbot certificate generation successful."
}


# Main execution
read -p "Enter your domain: " DOMAIN  # Get domain from the user

# Download the templates
download_templates

install_xray
install_letsencrypt

green_echo "Installation complete!"

# Print all information at the end
green_echo "----------------------------------------"
green_echo "Domain: $DOMAIN"
green_echo "Email: admin@$DOMAIN"
green_echo "UUID: $STATIC_UUID"
green_echo "WebSocket Path: $WSPATH"
green_echo "Xray Port: $XRAY_PORT"
green_echo "Xray Config File: $XRAY_CONFIG_FILE"
green_echo "----------------------------------------"
green_echo "Xray is running (internal)."
green_echo "Xray is listening on port 443."
green_echo "Remember to replace 'your_domain.com' with your actual domain if you haven't already."
