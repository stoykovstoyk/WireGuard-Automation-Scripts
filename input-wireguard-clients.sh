#!/bin/bash

# === CONFIG ===
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"
SERVER_PUBLIC_KEY_FILE="$WG_DIR/server_public.key"
SERVER_ENDPOINT_FILE="$WG_DIR/server_endpoint"
# ==============

set -e

# === FUNCTIONS ===

load_config() {
    # Check if config file exists
    if [[ ! -f "$WG_CONFIG" ]]; then
        echo "[ERROR] WireGuard configuration file not found: $WG_CONFIG"
        echo "Please run the server installation script first."
        exit 1
    fi

    # Load server public key
    if [[ ! -f "$SERVER_PUBLIC_KEY_FILE" ]]; then
        echo "[ERROR] Server public key file not found: $SERVER_PUBLIC_KEY_FILE"
        exit 1
    fi
    SERVER_PUBLIC_KEY=$(cat "$SERVER_PUBLIC_KEY_FILE")

    # Load server endpoint
    if [[ -f "$SERVER_ENDPOINT_FILE" ]]; then
        SERVER_ENDPOINT=$(cat "$SERVER_ENDPOINT_FILE")
    else
        # Fallback to common endpoint if file doesn't exist
        SERVER_ENDPOINT="your.server.ip.or.domain:51820"
        echo "[WARNING] Server endpoint file not found, using default: $SERVER_ENDPOINT"
        echo "Please update the endpoint in the generated client config file."
    fi

    # Extract server IP from WireGuard config (more robust pattern matching)
    SERVER_IP=$(grep -E "^[[:space:]]*Address[[:space:]]*=" "$WG_CONFIG" | sed 's/.*= *//' | cut -d'/' -f1 | tr -d ' ')
    if [[ -z "$SERVER_IP" ]]; then
        echo "[ERROR] Could not extract server IP from config file"
        exit 1
    fi

    # Extract DNS server from WireGuard config
    DNS_SERVER=$(grep -E "^[[:space:]]*DNS[[:space:]]*=" "$WG_CONFIG" | sed 's/.*= *//' | tr -d ' ')
    if [[ -z "$DNS_SERVER" ]]; then
        # Fallback to common DNS servers if not found in config
        DNS_SERVER="8.8.8.8"
        echo "[WARNING] DNS server not found in config, using default: $DNS_SERVER"
    fi

    # Extract VPN network from server IP (get the CIDR notation)
    SERVER_IP_CIDR=$(grep -E "^[[:space:]]*Address[[:space:]]*=" "$WG_CONFIG" | sed 's/.*= *//' | tr -d ' ')
    if [[ -z "$SERVER_IP_CIDR" ]]; then
        VPN_NETWORK="10.0.0.0/24"
        echo "[WARNING] Could not extract VPN network from config, using default: $VPN_NETWORK"
    else
        # Extract network prefix from CIDR (e.g., 10.0.0.1/24 -> 10.0.0.0/24)
        NETWORK_PART=$(echo "$SERVER_IP_CIDR" | cut -d'/' -f1)
        SUBNET_MASK=$(echo "$SERVER_IP_CIDR" | cut -d'/' -f2)
        # Calculate network address (simplified for /24 networks)
        if [[ "$SUBNET_MASK" == "24" ]]; then
            NETWORK_PREFIX=$(echo "$NETWORK_PART" | cut -d'.' -f1-3)
            VPN_NETWORK="${NETWORK_PREFIX}.0/${SUBNET_MASK}"
        else
            VPN_NETWORK="10.0.0.0/24"
            echo "[WARNING] Unsupported subnet mask $SUBNET_MASK, using default: $VPN_NETWORK"
        fi
    fi

    # Debug output
    echo "[DEBUG] Server IP: $SERVER_IP"
    echo "[DEBUG] DNS Server: $DNS_SERVER"
    echo "[DEBUG] VPN Network: $VPN_NETWORK"
}

get_existing_client_ips() {
    if [[ ! -f "$WG_CONFIG" ]]; then
        echo ""
        return
    fi

    # Extract network prefix from VPN network (e.g., 10.0.0.0/24 -> 10.0.0)
    local network_prefix=$(echo "$VPN_NETWORK" | cut -d'/' -f1 | cut -d'.' -f1-3)
    if [[ -z "$network_prefix" ]]; then
        network_prefix="10.0.0"  # fallback
    fi

    # Extract AllowedIPs entries and filter for VPN network
    # Look for lines like "AllowedIPs = 10.0.0.2/32"
    grep -E "^[[:space:]]*AllowedIPs[[:space:]]*=" "$WG_CONFIG" | \
    sed 's/.*= *//' | \
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
    grep -E "^${network_prefix}\.[0-9]+$" || echo ""
}

find_next_available_ip() {
    local existing_ips=$(get_existing_client_ips)

    # Extract network prefix from VPN network (e.g., 10.0.0.0/24 -> 10.0.0)
    local network_prefix=$(echo "$VPN_NETWORK" | cut -d'/' -f1 | cut -d'.' -f1-3)
    if [[ -z "$network_prefix" ]]; then
        network_prefix="10.0.0"  # fallback
    fi

    local next_ip=2

    if [[ -z "$existing_ips" ]]; then
        echo "${network_prefix}.${next_ip}"
        return
    fi

    # Find the highest IP number used
    local max_ip=1
    local used_ips=()

    # Read existing IPs into array and find max
    while IFS= read -r ip; do
        if [[ -n "$ip" ]]; then
            local ip_num=$(echo "$ip" | cut -d'.' -f4)
            if [[ $ip_num =~ ^[0-9]+$ ]]; then
                used_ips+=($ip_num)
                if [[ $ip_num -gt $max_ip ]]; then
                    max_ip=$ip_num
                fi
            fi
        fi
    done <<< "$existing_ips"

    # Find the next available IP starting from 2 (avoid server IP at .1)
    next_ip=2
    while [[ $next_ip -le 254 ]]; do
        local is_used=0
        for used_ip in "${used_ips[@]}"; do
            if [[ $used_ip -eq $next_ip ]]; then
                is_used=1
                break
            fi
        done

        if [[ $is_used -eq 0 ]]; then
            echo "${network_prefix}.${next_ip}"
            return
        fi

        ((next_ip++))
    done

    # If we get here, no available IPs found
    echo "[ERROR] No more available IPs in the VPN network $VPN_NETWORK" >&2
    echo "All IPs from ${network_prefix}.2 to ${network_prefix}.254 are in use" >&2
    exit 1
}

validate_ip() {
    local ip=$1

    # Check if IP matches expected format
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Invalid IP format: $ip"
        return 1
    fi

    # Check if IP is in the correct range
    local ip_num=$(echo "$ip" | cut -d'.' -f4)
    if [[ $ip_num -lt 1 ]] || [[ $ip_num -ge 255 ]]; then
        echo "[ERROR] IP number must be between 1 and 254: $ip"
        return 1
    fi

    # Check if IP is in VPN network
    local network_prefix=$(echo "$VPN_NETWORK" | cut -d'/' -f1 | cut -d'.' -f1-3)
    if [[ ! $ip =~ ^${network_prefix}\.[0-9]+$ ]]; then
        echo "[ERROR] IP must be in VPN network $VPN_NETWORK: $ip"
        return 1
    fi

    # Check if IP conflicts with server IP
    if [[ "$ip" == "$SERVER_IP" ]]; then
        echo "[ERROR] IP conflicts with server IP: $ip"
        return 1
    fi

    return 0
}

is_ip_available() {
    local ip=$1
    local existing_ips=$(get_existing_client_ips)

    while IFS= read -r existing_ip; do
        if [[ "$existing_ip" == "$ip" ]]; then
            return 1
        fi
    done <<< "$existing_ips"

    return 0
}

sanitize_email() {
    local email=$1
    # Replace @ with -
    echo "${email//@/-}"
}

validate_email() {
    local email=$1
    # Basic email validation: contains @ and .
    if [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        return 1
    fi
    return 0
}

send_wireguard_email() {
    local recipient=$1
    local config_file=$2
    local client_name=$3

    # Create temporary email file
    local email_file=$(mktemp)
    local config_content=$(cat "$config_file")

    cat > "$email_file" << EOF
To: $recipient
Subject: $EMAIL_SUBJECT
From: $FROM_EMAIL

Dear ${recipient%%@*},

Your WireGuard VPN configuration has been created. Below is your client configuration file.

Please save this email and use the configuration below to connect to the VPN.

Configuration for $client_name:

$config_content

Installation Instructions:

1. Download and install WireGuard for your platform:
   - Windows: https://download.wireguard.com/windows-client/wireguard-installer.exe
   - macOS: Download from App Store or use brew install wireguard-tools
   - Linux: sudo apt install wireguard (Ubuntu/Debian)
   - Android/iOS: Download from respective app stores

2. Create a new tunnel in WireGuard and paste the configuration above

3. Connect to the VPN

If you encounter any issues, please contact your system administrator.

Best regards,
VPN Administrator
EOF

    # Send email using curl
    if curl --silent --ssl-reqd --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
        --user "$SMTP_USER:$SMTP_PASS" \
        --mail-from "$FROM_EMAIL" \
        --mail-rcpt "$recipient" \
        --upload-file "$email_file"; then
        echo "[SUCCESS] Email sent to $recipient"
        rm "$email_file"
        return 0
    else
        echo "[ERROR] Failed to send email to $recipient"
        rm "$email_file"
        return 1
    fi
}

echo "=== WireGuard Bulk Client Generator ==="

# Parse arguments
INPUT_FILE=""
SEND_EMAIL=false
SMTP_SERVER=""
SMTP_PORT=587
FROM_EMAIL=""
EMAIL_SUBJECT="Your WireGuard VPN Configuration"

while [[ $# -gt 0 ]]; do
    case $1 in
        --input-file)
            INPUT_FILE="$2"
            shift 2
            ;;
        --send-email)
            SEND_EMAIL=true
            shift
            ;;
        --smtp-server)
            SMTP_SERVER="$2"
            shift 2
            ;;
        --smtp-port)
            SMTP_PORT="$2"
            shift 2
            ;;
        --from-email)
            FROM_EMAIL="$2"
            shift 2
            ;;
        --email-subject)
            EMAIL_SUBJECT="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown option: $1"
            echo "Usage: $0 --input-file <file> [--send-email --smtp-server <server> --smtp-port <port> --from-email <email> --email-subject <subject>]"
            exit 1
            ;;
    esac
done

# Validate input file
if [[ -z "$INPUT_FILE" ]]; then
    echo "[ERROR] Input file not specified. Use --input-file <file>"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "[ERROR] Input file not found: $INPUT_FILE"
    exit 1
fi

if [[ ! -r "$INPUT_FILE" ]]; then
    echo "[ERROR] Input file not readable: $INPUT_FILE"
    exit 1
fi

# Load configuration from files
load_config

# Prepare client folder
mkdir -p "$CLIENTS_DIR"

# Arrays to track created clients
created_clients=()
created_configs=()
created_emails=()

# Process each email in the input file
while IFS= read -r email; do
    # Skip empty lines
    if [[ -z "$email" ]]; then
        continue
    fi

    # Validate email
    if ! validate_email "$email"; then
        echo "[ERROR] Invalid email format: $email"
        continue
    fi

    # Sanitize email to client name
    CLIENT_NAME=$(sanitize_email "$email")

    # Check if client already exists
    if [[ -f "$CLIENTS_DIR/${CLIENT_NAME}.conf" ]]; then
        echo "[WARNING] Client '$CLIENT_NAME' already exists, skipping"
        continue
    fi

    # Get next available IP
    CLIENT_IP=$(find_next_available_ip)

    # Validate the IP
    if ! validate_ip "$CLIENT_IP"; then
        echo "[ERROR] Failed to assign valid IP for $CLIENT_NAME"
        continue
    fi

    # Check if IP is available
    if ! is_ip_available "$CLIENT_IP"; then
        echo "[ERROR] IP address $CLIENT_IP is already in use for $CLIENT_NAME"
        continue
    fi

    # Generate client keys
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

    # Create client config file
    CLIENT_CONF="$CLIENTS_DIR/${CLIENT_NAME}.conf"

    cat > "$CLIENT_CONF" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = $DNS_SERVER

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Check if client already exists in server config
    if grep -q "$CLIENT_PUBLIC_KEY" "$WG_CONFIG"; then
        echo "[WARNING] Client $CLIENT_NAME already exists in WireGuard config, skipping"
        continue
    fi

    # Add client to server config
    echo "" >> "$WG_CONFIG"
    echo "# $CLIENT_NAME" >> "$WG_CONFIG"
    echo "[Peer]" >> "$WG_CONFIG"
    echo "PublicKey = $CLIENT_PUBLIC_KEY" >> "$WG_CONFIG"
    echo "AllowedIPs = $CLIENT_IP/32" >> "$WG_CONFIG"

    # Track created clients
    created_clients+=("$CLIENT_NAME")
    created_configs+=("$CLIENT_CONF")
    created_emails+=("$email")

    echo "[+] Created client: $CLIENT_NAME with IP: $CLIENT_IP"

done < "$INPUT_FILE"

# Restart WireGuard interface if any clients were added
if [[ ${#created_clients[@]} -gt 0 ]]; then
    echo "[*] Restarting WireGuard to apply changes..."
    systemctl restart "wg-quick@$WG_INTERFACE"
else
    echo "[INFO] No new clients were created"
    exit 0
fi

# Send emails if requested
if [[ "$SEND_EMAIL" == true ]]; then
    # Validate SMTP parameters
    if [[ -z "$SMTP_SERVER" ]]; then
        echo "[ERROR] SMTP server not specified. Use --smtp-server"
        exit 1
    fi
    if [[ -z "$FROM_EMAIL" ]]; then
        echo "[ERROR] From email not specified. Use --from-email"
        exit 1
    fi
    if [[ -z "${SMTP_USER:-}" ]] || [[ -z "${SMTP_PASS:-}" ]]; then
        echo "[ERROR] SMTP credentials not found. Set SMTP_USER and SMTP_PASS environment variables"
        exit 1
    fi

    # Send emails
    echo "[*] Sending configuration emails..."
    email_success_count=0
    for i in "${!created_clients[@]}"; do
        client_email="${created_emails[$i]}"
        client_config="${created_configs[$i]}"
        client_name="${created_clients[$i]}"
        echo "[*] Sending email to $client_email for $client_name"
        if send_wireguard_email "$client_email" "$client_config" "$client_name"; then
            ((email_success_count++))
        fi
    done
    echo "[INFO] Email sending complete: $email_success_count/${#created_clients[@]} emails sent successfully"
fi

# Output Summary
echo ""
echo "✅ Successfully created ${#created_clients[@]} client(s):"
for i in "${!created_clients[@]}"; do
    echo "➡ ${created_clients[$i]}: ${created_configs[$i]}"
done
echo ""