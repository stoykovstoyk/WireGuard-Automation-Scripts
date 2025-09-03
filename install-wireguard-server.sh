#!/bin/bash

# WireGuard Server Installation Script
# Compatible with add-wireguard-clients.sh

set -e

# === CONFIGURATION ===
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"
SERVER_PRIVATE_KEY_FILE="$WG_DIR/server_private.key"
SERVER_PUBLIC_KEY_FILE="$WG_DIR/server_public.key"
SERVER_ENDPOINT_FILE="$WG_DIR/server_endpoint"

# Network configuration
VPN_NETWORK="10.0.0.0/24"
SERVER_IP="10.0.0.1"
WG_PORT="51820"
DNS_SERVER="8.8.8.8"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === FUNCTIONS ===

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use sudo."
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        log_error "Unable to detect OS. This script supports Ubuntu only."
        exit 1
    fi
    
    if [[ "$OS" != "Ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only. Detected: $OS"
        exit 1
    fi
    
    log_info "Detected OS: $OS $VERSION"
}

check_existing_installation() {
    if [[ -d "$WG_DIR" ]] && [[ -f "$WG_CONFIG" ]]; then
        log_warning "WireGuard installation already exists at $WG_DIR"
        read -p "Do you want to backup and overwrite the existing installation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Installation aborted by user."
            exit 1
        fi
        
        # Create backup
        BACKUP_DIR="$WG_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Creating backup at $BACKUP_DIR"
        cp -r "$WG_DIR" "$BACKUP_DIR"
        if [[ $? -eq 0 ]]; then
            log_success "Backup created successfully"
        else
            log_error "Failed to create backup"
            exit 1
        fi
    fi
}

install_dependencies() {
    log_info "Updating package list..."
    apt update -y
    
    log_info "Installing WireGuard and dependencies..."
    apt install -y wireguard qrencode ufw
    
    if [[ $? -eq 0 ]]; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies"
        exit 1
    fi
}

generate_server_keys() {
    log_info "Generating WireGuard server keys..."
    
    # Generate private key
    SERVER_PRIVATE_KEY=$(wg genkey)
    if [[ -z "$SERVER_PRIVATE_KEY" ]]; then
        log_error "Failed to generate server private key"
        exit 1
    fi
    
    # Generate public key
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
    if [[ -z "$SERVER_PUBLIC_KEY" ]]; then
        log_error "Failed to generate server public key"
        exit 1
    fi
    
    # Save keys to files
    echo "$SERVER_PRIVATE_KEY" > "$SERVER_PRIVATE_KEY_FILE"
    echo "$SERVER_PUBLIC_KEY" > "$SERVER_PUBLIC_KEY_FILE"
    
    # Set proper permissions
    chmod 600 "$SERVER_PRIVATE_KEY_FILE"
    chmod 644 "$SERVER_PUBLIC_KEY_FILE"
    
    log_success "Server keys generated and saved"
    log_info "Private key: $SERVER_PRIVATE_KEY_FILE"
    log_info "Public key: $SERVER_PUBLIC_KEY_FILE"
}

create_directory_structure() {
    log_info "Creating directory structure..."
    
    mkdir -p "$WG_DIR"
    mkdir -p "$CLIENTS_DIR"
    
    # Set proper permissions
    chmod 700 "$WG_DIR"
    chmod 755 "$CLIENTS_DIR"
    
    log_success "Directory structure created"
}

create_wireguard_config() {
    log_info "Creating WireGuard configuration file..."
    
    # Get the default network interface (excluding WireGuard interface)
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    cat > "$WG_CONFIG" << EOF
[Interface]
Address = $SERVER_IP/24
PrivateKey = $(cat "$SERVER_PRIVATE_KEY_FILE")
ListenPort = $WG_PORT
DNS = $DNS_SERVER

# Enable IP forwarding and NAT
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
EOF

    # Set proper permissions
    chmod 600 "$WG_CONFIG"
    
    log_success "WireGuard configuration created: $WG_CONFIG"
}

configure_ip_forwarding() {
    log_info "Configuring IP forwarding..."
    
    # Enable IP forwarding permanently
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    
    # Apply immediately
    sysctl -w net.ipv4.ip_forward=1
    
    log_success "IP forwarding enabled"
}

configure_firewall() {
    log_info "Configuring UFW firewall..."
    
    # Allow SSH (keep existing SSH connections)
    ufw allow OpenSSH
    
    # Allow WireGuard port
    ufw allow "$WG_PORT"/udp
    
    # Enable UFW if not already enabled
    if ! ufw status | grep -q "Status: active"; then
        log_info "Enabling UFW firewall..."
        ufw --force enable
    else
        log_info "UFW is already active"
    fi
    
    # Configure UFW to allow forwarding by modifying the rules file
    # This is necessary for WireGuard traffic to be forwarded
    UFW_DEFAULT_RULES="/etc/default/ufw"
    if [[ -f "$UFW_DEFAULT_RULES" ]]; then
        # Ensure forwarding is enabled
        sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT_RULES"
        sed -i 's/^DEFAULT_FORWARD_POLICY="REJECT"/DEFAULT_FORWARD_POLICY="ACCEPT"/' "$UFW_DEFAULT_RULES"
    fi
    
    # Reload UFW to apply the changes
    ufw reload
    
    log_success "Firewall configured successfully"
}

start_wireguard_service() {
    log_info "Starting WireGuard service..."

    # Check if interface already exists and stop it if necessary
    if wg show "$WG_INTERFACE" >/dev/null 2>&1; then
        log_info "Existing WireGuard interface found, stopping it first..."
        systemctl stop "wg-quick@$WG_INTERFACE" 2>/dev/null || true
        wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    fi

    # Enable and start the service
    systemctl enable "wg-quick@$WG_INTERFACE"
    systemctl start "wg-quick@$WG_INTERFACE"

    # Check status
    if systemctl is-active --quiet "wg-quick@$WG_INTERFACE"; then
        log_success "WireGuard service started successfully"
    else
        log_error "Failed to start WireGuard service"
        systemctl status "wg-quick@$WG_INTERFACE"
        exit 1
    fi
}

verify_installation() {
    log_info "Verifying installation..."
    
    # Check WireGuard status
    if ! wg show "$WG_INTERFACE" >/dev/null 2>&1; then
        log_error "WireGuard interface is not running"
        exit 1
    fi
    
    # Check configuration file
    if [[ ! -f "$WG_CONFIG" ]]; then
        log_error "Configuration file not found"
        exit 1
    fi
    
    # Check server keys
    if [[ ! -f "$SERVER_PRIVATE_KEY_FILE" ]] || [[ ! -f "$SERVER_PUBLIC_KEY_FILE" ]]; then
        log_error "Server keys not found"
        exit 1
    fi
    
    # Check interface IP
    if ! ip addr show "$WG_INTERFACE" | grep -q "$SERVER_IP"; then
        log_error "Server IP not configured on interface"
        exit 1
    fi
    
    log_success "Installation verified successfully"
}

get_server_ip() {
    # Get public IP address
    PUBLIC_IP=$(curl -s --connect-timeout 10 https://api.ipify.org || echo "unknown")
    
    # Get private IP address
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    
    log_info "Server IP addresses detected:"
    log_info "  Public IP: $PUBLIC_IP"
    log_info "  Private IP: $PRIVATE_IP"
    
    # Ask user which IP to use as endpoint
    echo ""
    echo "Which IP address should clients use to connect?"
    echo "1) Public IP: $PUBLIC_IP"
    echo "2) Private IP: $PRIVATE_IP"
    echo "3) Custom domain/IP"
    
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            if [[ "$PUBLIC_IP" == "unknown" ]]; then
                log_error "Public IP could not be detected. Please choose another option."
                get_server_ip
                return
            fi
            ENDPOINT="$PUBLIC_IP:$WG_PORT"
            ;;
        2)
            ENDPOINT="$PRIVATE_IP:$WG_PORT"
            ;;
        3)
            read -p "Enter custom endpoint (e.g., vpn.example.com:51820): " ENDPOINT
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac

    # Validate endpoint format
    if [[ ! "$ENDPOINT" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        log_error "Invalid endpoint format. Expected format: ip/domain:port"
        get_server_ip
        return
    fi

    # Create the endpoint file
    if echo "$ENDPOINT" > "$SERVER_ENDPOINT_FILE"; then
        log_success "Endpoint configured: $ENDPOINT"
        log_info "Endpoint saved to: $SERVER_ENDPOINT_FILE"
    else
        log_error "Failed to save endpoint to file"
        exit 1
    fi
}

generate_installation_summary() {
    log_info "Generating installation summary..."
    
    SERVER_PUBLIC_KEY=$(cat "$SERVER_PUBLIC_KEY_FILE")
    ENDPOINT=$(cat "$SERVER_ENDPOINT_FILE" 2>/dev/null || echo "not configured")
    
    echo ""
    echo "=========================================="
    echo "      WireGuard Server Installation"
    echo "=========================================="
    echo ""
    echo "🎉 Installation completed successfully!"
    echo ""
    echo "📋 Configuration Details:"
    echo "  Interface: $WG_INTERFACE"
    echo "  Server IP: $SERVER_IP"
    echo "  VPN Network: $VPN_NETWORK"
    echo "  Port: $WG_PORT"
    echo "  DNS: $DNS_SERVER"
    echo ""
    echo "🔑 Server Public Key:"
    echo "  $SERVER_PUBLIC_KEY"
    echo ""
    echo "🌐 Connection Endpoint:"
    echo "  $ENDPOINT"
    echo ""
    echo "📁 Configuration Files:"
    echo "  Main config: $WG_CONFIG"
    echo "  Server public key: $SERVER_PUBLIC_KEY_FILE"
    echo "  Clients directory: $CLIENTS_DIR"
    echo ""
    echo "🔧 Service Management:"
    echo "  Start:   systemctl start wg-quick@$WG_INTERFACE"
    echo "  Stop:    systemctl stop wg-quick@$WG_INTERFACE"
    echo "  Restart: systemctl restart wg-quick@$WG_INTERFACE"
    echo "  Status:  systemctl status wg-quick@$WG_INTERFACE"
    echo ""
    echo "📱 Next Steps:"
    echo "  1. Update your add-wireguard-clients.sh script with the endpoint above"
    echo "  2. Run add-wireguard-clients.sh to add clients"
    echo "  3. Share the server public key and endpoint with clients"
    echo ""
    echo "=========================================="
}

# === MAIN INSTALLATION PROCESS ===

main() {
    echo "=========================================="
    echo "    WireGuard Server Installation Script"
    echo "=========================================="
    echo ""
    
    # Step 1: System requirements check
    log_info "Step 1: Checking system requirements..."
    check_root
    detect_os
    check_existing_installation
    
    # Step 2: Install dependencies
    log_info "Step 2: Installing dependencies..."
    install_dependencies
    
    # Step 3: Create directory structure
    log_info "Step 3: Creating directory structure..."
    create_directory_structure

    # Step 4: Generate server keys
    log_info "Step 4: Generating server keys..."
    generate_server_keys
    
    # Step 5: Create WireGuard configuration
    log_info "Step 5: Creating WireGuard configuration..."
    create_wireguard_config

    # Step 6: Configure IP forwarding
    log_info "Step 6: Configuring IP forwarding..."
    configure_ip_forwarding

    # Step 7: Configure firewall
    log_info "Step 7: Configuring firewall..."
    configure_firewall

    # Step 8: Start WireGuard service
    log_info "Step 8: Starting WireGuard service..."
    start_wireguard_service

    # Step 9: Verify installation
    log_info "Step 9: Verifying installation..."
    verify_installation

    # Step 10: Get server IP and configure endpoint
    log_info "Step 10: Configuring connection endpoint..."
    get_server_ip

    # Step 11: Generate installation summary
    generate_installation_summary
    
    log_success "WireGuard server installation completed!"
}

# Run main function
main "$@"