#!/bin/bash

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

# Function to configure Xray with VLESS + XTLS and WebSocket on port 443
configure_xray() {
    local DOMAIN=$1
    echo "Configuring Xray with VLESS + XTLS and WebSocket on port 443..."

    XRAY_CONFIG="/usr/local/etc/xray/config.json"
    sudo mkdir -p /usr/local/etc/xray
    sudo cat > $XRAY_CONFIG <<EOF
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "dcd099af-57bc-4dbc-b404-79851facfb36", // Fixed UUID
            "flow": "xtls-rprx-direct"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "path": "/vless-ws", // WebSocket path
            "dest": "@vless_ws", // Unix socket for WebSocket
            "xver": 1
          },
          {
            "dest": 80,           // Fallback to Nginx for other traffic
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ]
        }
      },
      "tag": "inbound-vless" // Tag for this inbound
    },
    {
      "listen": "@vless_ws", // Unix socket listener for WebSocket
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "dcd099af-57bc-4dbc-b404-79851facfb36" // Fixed UUID
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless-ws"
        }
      },
      "tag": "inbound-ws" // Tag for this inbound
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct" // Outbound for direct traffic
    },
    {
      "protocol": "blackhole",
      "tag": "blocked" // Outbound for blocked traffic
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["inbound-vless"], // Route traffic from "inbound-vless"
        "outboundTag": "direct"          // to the "direct" outbound
      },
      {
        "type": "field",
        "inboundTag": ["inbound-ws"],    // Route traffic from "inbound-ws"
        "outboundTag": "direct"          // to the "direct" outbound
      },
      {
        "type": "field",
        "ip": ["geoip:private"],         // Block private IP ranges
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads"], // Block ads
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    echo "Xray configuration completed."
}

# Function to set up Let's Encrypt SSL
setup_ssl() {
    local DOMAIN=$1
    echo "Setting up Let's Encrypt SSL for $DOMAIN..."
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    echo "SSL certificate generated successfully."
}

# Function to configure Nginx for WebSocket and masking
configure_nginx() {
    local DOMAIN=$1
    echo "Configuring Nginx for WebSocket and masking..."

    sudo cat > /etc/nginx/sites-available/xray <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        return 200 'Welcome to $DOMAIN';
        add_header Content-Type text/plain;
    }

    location /vless-ws {
        proxy_pass http://unix:/tmp/vless_ws.sock;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Enable the Nginx configuration
    sudo ln -sf /etc/nginx/sites-available/xray /etc/nginx/sites-enabled/xray
    sudo rm /etc/nginx/sites-enabled/default

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
    read -p "Enter your domain name (e.g., example.com): " DOMAIN

    # Call functions in sequence
    install_dependencies
    install_xray
    setup_ssl "$DOMAIN"
    configure_xray "$DOMAIN"
    configure_nginx "$DOMAIN"
    restart_services

    echo "Setup completed successfully!"
    echo "Xray is running with VLESS + XTLS and WebSocket on port 443."
    echo "You can access your server at https://$DOMAIN (Nginx is masking Xray)."
}

# Execute the main function
main