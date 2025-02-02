#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

# Function to validate domain format
validate_domain() {
    if [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate path format
validate_path() {
    if [[ $1 =~ ^/[a-zA-Z0-9/_-]*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to optimize system performance
optimize_system() {
    # Create sysctl configuration file for optimizations
    cat > /etc/sysctl.d/98-xray-optimize.conf << EOF
# Max open files
fs.file-max = 1000000

# Max read buffer
net.core.rmem_max = 67108864

# Max write buffer
net.core.wmem_max = 67108864

# Default read buffer
net.core.rmem_default = 65536

# Default write buffer
net.core.wmem_default = 65536

# Max processor input queue
net.core.netdev_max_backlog = 4096

# Max backlog
net.core.somaxconn = 4096

# Resist SYN flood attacks
net.ipv4.tcp_syncookies = 1

# Reuse timewait sockets when safe
net.ipv4.tcp_tw_reuse = 1

# Turn off fast timewait sockets recycling
net.ipv4.tcp_tw_recycle = 0

# Short FIN timeout
net.ipv4.tcp_fin_timeout = 30

# Short keepalive time
net.ipv4.tcp_keepalive_time = 1200

# Outbound port range
net.ipv4.ip_local_port_range = 10000 65000

# Max SYN backlog
net.ipv4.tcp_max_syn_backlog = 4096

# Max timewait sockets held by system simultaneously
net.ipv4.tcp_max_tw_buckets = 5000

# Turn on TCP Fast Open
net.ipv4.tcp_fastopen = 3

# TCP receive buffer
net.ipv4.tcp_rmem = 4096 87380 67108864

# TCP write buffer
net.ipv4.tcp_wmem = 4096 65536 67108864

# Turn on path MTU discovery
net.ipv4.tcp_mtu_probing = 1

# Enable forward
net.ipv4.ip_forward = 1

# TCP congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/98-xray-optimize.conf

    # Enable BBR if not already enabled
    if ! lsmod | grep -q bbr; then
        modprobe tcp_bbr
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi

    # Optimize system limits
    cat > /etc/security/limits.d/98-xray.conf << EOF
* soft nofile 1000000
* hard nofile 1000000
* soft nproc 1000000
* hard nproc 1000000
EOF
}

# Get domain from user
while true; do
    read -p "Enter your domain/subdomain: " DOMAIN
    if validate_domain "$DOMAIN"; then
        break
    else
        echo "Invalid domain format. Please try again."
    fi
done

# Get websocket path from user
while true; do
    read -p "Enter websocket path (e.g., /websocket): " WSPATH
    if validate_path "$WSPATH"; then
        break
    else
        echo "Invalid path format. Please try again."
    fi
done

# Generate random UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
EMAIL="admin@${DOMAIN}"

# Install required packages
apt update
apt install -y curl socat certbot haveged

# Install Xray using official script
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Download config template
TEMPLATE_URL="https://github.com/0xlucyg/xrayconfig/raw/refs/heads/main/xray-config.json"  # Replace with your actual template URL
curl -o /usr/local/etc/xray/config.json.template "$TEMPLATE_URL"

# Replace placeholders in template
sed -i "s/%%DOMAIN%%/${DOMAIN}/g" /usr/local/etc/xray/config.json.template
sed -i "s/%%EMAIL%%/${EMAIL}/g" /usr/local/etc/xray/config.json.template
sed -i "s/%%WSPATH%%/${WSPATH}/g" /usr/local/etc/xray/config.json.template
sed -i "s/%%UUID%%/${UUID}/g" /usr/local/etc/xray/config.json.template

# Install SSL certificate
certbot certonly --standalone --non-interactive --agree-tos --email "${EMAIL}" -d "${DOMAIN}"

# Move configured template to final location
mv /usr/local/etc/xray/config.json.template /usr/local/etc/xray/config.json

# Set proper permissions
chown root:root /usr/local/etc/xray/config.json
chmod 644 /usr/local/etc/xray/config.json

# Apply system optimizations
optimize_system

# Create systemd override for Xray service
mkdir -p /etc/systemd/system/xray.service.d/
cat > /etc/systemd/system/xray.service.d/override.conf << EOF
[Service]
LimitNOFILE=1000000
LimitNPROC=1000000
EOF

# Reload systemd and restart Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# Enable and start haveged (entropy generator)
systemctl enable haveged
systemctl start haveged

# Print configuration details
echo "Installation completed!"
echo "Domain: ${DOMAIN}"
echo "UUID: ${UUID}"
echo "WebSocket Path: ${WSPATH}"
echo "Email: ${EMAIL}"
echo "SSL certificates are installed in /etc/letsencrypt/live/${DOMAIN}/"
echo "Xray configuration is at /usr/local/etc/xray/config.json"

# Print optimization status
echo -e "\nPerformance Optimizations:"
echo "✓ BBR congestion control enabled"
echo "✓ System limits optimized"
echo "✓ Network stack tuned"
echo "✓ TCP Fast Open enabled"
echo "✓ High entropy generation enabled"
echo "✓ Service limits increased"

# Check if BBR is actually enabled
if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
    echo "✓ BBR is active and running"
else
    echo "⚠ BBR is not running, you may need to reboot"
fi
