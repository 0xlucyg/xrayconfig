#!/bin/bash

# Variables
UUID="dcd099af-57bc-4dbc-b404-79851facfb36"
WEBSOCKET_PATH="/vless-ws"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
NGINX_CONFIG="/etc/nginx/sites-available/xray"
LOG_FILE="xray-setup.log"

# GitHub raw URLs for templates
XRAY_TEMPLATE_URL="https://raw.githubusercontent.com/0xlucyg/xrayconfig/refs/heads/main/xray-config.json"
NGINX_TEMPLATE_URL="https://raw.githubusercontent.com/0xlucyg/xrayconfig/refs/heads/main/nginx-config.template"

# Redirect output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to validate domain name
validate_domain() {
    local DOMAIN=$1
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Error: Invalid domain name."
        exit 1
    fi
}

# Function to download templates from GitHub
download_templates() {
    echo "Downloading Xray config template..."
    curl -s -o xray-config.json.template "$XRAY_TEMPLATE_URL" || { echo "Failed to download Xray template"; exit 1; }

    echo "Downloading Nginx config template..."
    curl -s -o nginx-config.template "$NGINX_TEMPLATE_URL" || { echo "Failed to download Nginx template"; exit 1; }

    echo "Templates downloaded successfully."
}

# Function to update the system and install dependencies
install_dependencies() {
    echo "Updating system and installing dependencies..."
    sudo apt update
    sudo apt install -y curl wget nginx certbot python3-certbot-nginx
    echo "Dependencies installed successfully."
}

# Function to install Xray
install_xray() {
    echo "Installing Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    echo "Xray installed successfully."
}

# Function to configure Xray
configure_xray() {
    local DOMAIN=$1
    echo "Configuring Xray with VLESS + TLS and WebSocket on port 443..."

    # Use a template to generate the Xray configuration
    export DOMAIN UUID WEBSOCKET_PATH
    envsubst < xray-config.json.template > "$XRAY_CONFIG"

    # Add DNS servers to the Xray configuration
    echo "Adding DNS servers to Xray configuration..."
    sed -i '/"outbounds": \[/a \    {\n      "protocol": "dns",\n      "tag": "dns-out"\n    },' "$XRAY_CONFIG"
    sed -i '/"routing": {/i \  "dns": {\n    "servers": [\n      "1.1.1.1",\n      "8.8.8.8",\n      "9.9.9.9"\n    ]\n  },' "$XRAY_CONFIG"

    echo "Xray configuration completed."
}

# Function to set up Let's Encrypt SSL
setup_ssl() {
    local DOMAIN=$1
    echo "Setting up Let's Encrypt SSL for $DOMAIN..."

    # Stop Nginx temporarily to free port 80
    echo "Stopping Nginx to free port 80..."
    sudo systemctl stop nginx

    # Generate SSL certificate using Certbot
    echo "Generating SSL certificate..."
    sudo certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN

    # Restart Nginx after obtaining the certificate
    echo "Restarting Nginx..."
    sudo systemctl start nginx

    echo "SSL certificate generated successfully."
}

# Function to configure Nginx
configure_nginx() {
    local DOMAIN=$1
    echo "Configuring Nginx for WebSocket and masking..."

    # Use a template to generate the Nginx configuration
    export DOMAIN WEBSOCKET_PATH
    envsubst < nginx-config.template > "$NGINX_CONFIG"

    # Enable the Nginx configuration
    sudo ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/xray
    sudo rm -f /etc/nginx/sites-enabled/default

    echo "Nginx configuration completed."
}

# Function to restart services
restart_services() {
    echo "Restarting Nginx and Xray..."
    sudo systemctl restart nginx
    sudo systemctl restart xray
    echo "Services restarted successfully."
}

# Main function to orchestrate the setup
main() {
    echo "Starting Xray, Nginx, and Let's Encrypt SSL setup..."

    # Get the domain name from the user
    read -p "Enter your subdomain (e.g., subdomain.example.com): " DOMAIN
    validate_domain "$DOMAIN"

    # Download templates from GitHub
    download_templates

    # Call functions in sequence
    install_dependencies
    install_xray
    setup_ssl "$DOMAIN"
    configure_xray "$DOMAIN"
    configure_nginx "$DOMAIN"
    restart_services

    echo "Setup completed successfully!"
    echo "Xray is running with VLESS + TLS and WebSocket on port 443."
    echo "You can access your server at https://$DOMAIN (Nginx is masking Xray)."
}

# Execute the main function
main
