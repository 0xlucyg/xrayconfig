#!/bin/bash

# Configuration
config_url="https://raw.githubusercontent.com/0xlucyg/xrayconfig/refs/heads/main/xray/config.json"

# Function to generate a random UUID
generate_uuid() {
    uuidgen
}

# Function to check if a string is a valid domain name
is_valid_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a string is a valid email address
is_valid_email() {
    local email="$1"
    if [[ "$email" =~ ^[[:alnum:]][a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get user input for DOMAIN, EMAIL, and PASSWORD
get_user_input() {
    local valid_input=false
    local domain
    local email
    local password

    while ! $valid_input; do
        read -p "Enter DOMAIN: " domain
        read -p "Enter EMAIL: " email
        read -s -p "Enter Trojan PASSWORD: " password
        echo ""

        if is_valid_domain "$domain" && is_valid_email "$email" && [[ -n "$password" ]]; then
            valid_input=true
        else
            echo "Invalid DOMAIN, EMAIL, or PASSWORD. Please try again."
        fi
    done

    echo "DOMAIN: $domain"
    echo "EMAIL: $email"
    echo "PASSWORD: $password" #Echo Password after input for sed command
}

# Function to obtain SSL certificates from Let's Encrypt using standalone method
get_letsencrypt_ssl() {
    local domain="$1"
    local email="$2"

    sudo apt update
    sudo apt install -y certbot

    if systemctl is-active --quiet xray; then
        sudo systemctl stop xray
        xray_was_running=true
    else
        xray_was_running=false
    fi

    if ! certbot certonly --standalone -d "$domain" --email "$email" --agree-tos --no-eff-email --non-interactive --force-renewal; then
        echo "Error obtaining Let's Encrypt certificate. Please check your domain and DNS settings. Make sure port 80 is open."
        if [[ "$xray_was_running" == true ]]; then
            sudo systemctl start xray
        fi
        return 1
    fi

    if [[ "$xray_was_running" == true ]]; then
        sudo systemctl start xray
    fi
    return 0
}

# Function to install dependencies
install_dependencies() {
    sudo apt update
    sudo apt install -y uuid-runtime jq certbot
    if [[ "$use_dns_auth" == "true" ]]; then
        sudo apt install -y python3-certbot-dns-cloudflare
    fi
}

# Function to download and install Xray
install_xray() {
    curl -L https://raw.githubusercontent.com/XTLS/Xray-install/refs/heads/main/install-release.sh -o install-xray.sh
    chmod +x install-xray.sh
    ./install-xray.sh
}

# Function to create and move configuration file
configure_xray() {
    # Download config.json from GitHub raw URL
    curl -L "$config_url" -o config.json

    generated_uuid=$(generate_uuid)

    get_user_input

    if ! get_letsencrypt_ssl "$domain" "$email"; then
        echo "SSL certificate acquisition failed. Exiting."
        return 1
    fi

    sed -i "s/%UUID%/${generated_uuid}/g" config.json
    sed -i "s/%DOMAIN%/${domain}/g" config.json
    sed -i "s/%EMAIL%/${email}/g" config.json
    sed -i "s/%PASSWORD%/${password}/g" config.json

    sudo mv config.json /usr/local/etc/xray/config.json
}

# Function to start and enable Xray service
start_xray_service() {
    sudo systemctl daemon-reload
    sudo systemctl enable --now xray
}

# Function to check Xray status and version
check_xray() {
    echo "Checking Xray service status..."
    sudo systemctl status xray

    echo "Checking Xray version..."
    xray -v
}

# Function to extract information from config.json
get_config_info() {
    local vless_port=$(jq -r '.inbounds[0].port' /usr/local/etc/xray/config.json)
    local vless_ws_path=$(jq -r '.inbounds[1].streamSettings.wsSettings.path' /usr/local/etc/xray/config.json)
    local trojan_port=$(jq -r '.inbounds[2].port' /usr/local/etc/xray/config.json)
    local trojan_password=$(jq -r '.inbounds[2].settings.clients[0].password' /usr/local/etc/xray/config.json)

    echo "Domain: $domain"
    echo "Vless Port: $vless_port"
    echo "UUID: $generated_uuid"
    echo "WS Path: $vless_ws_path"
    echo "Trojan Port: $trojan_port"
    echo "Trojan Password: $trojan_password"
}

# Main function to execute all steps
main() {
    use_dns_auth="false" # Set to "true" if using DNS authentication
    install_dependencies
    install_xray
    configure_xray || return 1
    start_xray_service
    check_xray
    get_config_info

    echo "Xray installation and configuration complete!"
}

# Execute the main function
main
