# WireGuard Automation Scripts

## Overview

This project provides automated Bash scripts for setting up and managing WireGuard VPN servers and clients. The scripts simplify the process of deploying secure VPN infrastructure with minimal manual configuration, making it easy to create and manage VPN networks for secure remote access.

### Purpose

The primary purpose of these scripts is to automate the complex setup and management of WireGuard VPNs, which are known for their speed, simplicity, and strong cryptography. By automating key generation, configuration, firewall setup, and client management, these scripts reduce the barrier to entry for deploying secure VPN solutions.

### Architecture

The project consists of two main components:

1. **Server Installation Script** (`install-wireguard-server.sh`): Handles complete server setup including dependencies, keys, configuration, and service management
2. **Client Management Script** (`add-wireguard-clients.sh`): Manages client addition, IP assignment, and configuration generation

The scripts work together to provide a complete VPN management solution with automated IP conflict detection, QR code generation for mobile clients, and robust error handling.

## Features

- **Automated Server Setup**: Complete WireGuard server installation with dependency management
- **Client Management**: Automated client addition with IP assignment and conflict detection
- **Security Features**: Automatic key generation, firewall configuration, and secure file permissions
- **Mobile Support**: QR code generation for easy mobile client configuration
- **Network Configuration**: Automatic IP forwarding, NAT setup, and firewall rules
- **Service Integration**: Systemd service management with status monitoring
- **Endpoint Detection**: Automatic detection of server public/private IPs for client connections
- **Error Handling**: Comprehensive validation and error checking throughout the process

## Prerequisites

- **Operating System**: Ubuntu Linux (18.04 or later recommended)
- **Privileges**: Root access (sudo) required for installation and configuration
- **Network**: Internet connection for package downloads and endpoint detection
- **Hardware**: Minimal requirements - works on most modern servers and VPS instances

## Dependencies

The scripts automatically install the following dependencies:

- **wireguard**: Core WireGuard VPN kernel module and tools
- **qrencode**: QR code generation for mobile clients
- **ufw**: Uncomplicated Firewall for firewall management
- **resolveconf**: DNS resolution configuration management
- **curl**: HTTP client for endpoint detection

## Installation

### Step 1: Download Scripts

Clone or download the scripts to your server:

```bash
git clone https://github.com/stoykovstoyk/WireGuard-Automation-Scripts.git
cd WireGuard-Automation-Scripts
```

### Step 2: Make Scripts Executable

```bash
chmod +x install-wireguard-server.sh
chmod +x add-wireguard-clients.sh
```

### Step 3: Run Server Installation

Execute the server installation script with root privileges:

```bash
sudo ./install-wireguard-server.sh
```

The script will guide you through the installation process, including:
- System compatibility check
- Dependency installation
- Key generation
- Configuration creation
- Firewall setup
- Service startup
- Endpoint configuration

## Usage

### Server Setup

The installation script performs a complete server setup:

```bash
sudo ./install-wireguard-server.sh
```

**What the script does:**
1. Checks system requirements and OS compatibility
2. Installs WireGuard and required dependencies
3. Generates server private and public keys
4. Creates WireGuard configuration file
5. Configures IP forwarding and NAT rules
6. Sets up firewall rules for VPN traffic
7. Enables and starts the WireGuard service
8. Detects server endpoint (public/private IP)
9. Provides installation summary with connection details

### Adding Clients

To add new VPN clients:

```bash
sudo ./add-wireguard-clients.sh
```

**Client addition process:**
1. Prompts for client name (e.g., "alice", "mobile-device")
2. Automatically suggests next available IP address
3. Allows custom IP assignment with validation
4. Generates unique client keys
5. Creates client configuration file
6. Updates server configuration with new peer
7. Restarts WireGuard service to apply changes
8. Optionally generates QR code for mobile clients

### Example Usage

```bash
# Install server
sudo ./install-wireguard-server.sh

# Add first client
sudo ./add-wireguard-clients.sh
# Enter client name: alice
# Enter client IP: [press enter for 10.0.0.2]
# Generate QR code: y

# Add second client
sudo ./add-wireguard-clients.sh
# Enter client name: bob
# Enter client IP: [press enter for 10.0.0.3]
# Generate QR code: n
```

### Service Management

```bash
# Check VPN status
sudo wg show wg0

# View connected clients
sudo wg show wg0 peers

# Check service status
sudo systemctl status wg-quick@wg0

# Restart VPN service
sudo systemctl restart wg-quick@wg0

# View service logs
sudo journalctl -u wg-quick@wg0 -f
```

## Configuration

### Default Settings

| Setting | Default Value | Description |
|---------|---------------|-------------|
| Interface | wg0 | WireGuard interface name |
| Port | 51820 | UDP port for VPN traffic |
| Network | 10.0.0.0/24 | VPN network range |
| Server IP | 10.0.0.1 | Server's VPN IP address |
| DNS | 8.8.8.8 | DNS server for clients |
| Config Directory | /etc/wireguard | Configuration files location |

### Customization

To modify default settings, edit the configuration variables at the top of the scripts:

```bash
# In install-wireguard-server.sh
WG_INTERFACE="wg0"
WG_PORT="51820"
VPN_NETWORK="10.0.0.0/24"
SERVER_IP="10.0.0.1"
DNS_SERVER="8.8.8.8"
```

```bash
# In add-wireguard-clients.sh
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
```

### Advanced Configuration

- **Custom Network Ranges**: Modify `VPN_NETWORK` for different IP ranges
- **Multiple Interfaces**: Change `WG_INTERFACE` for multiple VPNs
- **Custom Ports**: Update `WG_PORT` if 51820 is unavailable
- **DNS Configuration**: Change `DNS_SERVER` for custom DNS

## Testing

### Installation Verification

After running the server installation script, verify the setup:

```bash
# Check WireGuard interface
sudo wg show wg0

# Verify interface IP
sudo ip addr show wg0

# Check service status
sudo systemctl is-active wg-quick@wg0

# Test IP forwarding
sysctl net.ipv4.ip_forward
```

### Client Testing

1. **Generate client config** using `add-wireguard-clients.sh`
2. **Import config** into WireGuard client application
3. **Connect to VPN**
4. **Test connectivity**:
   ```bash
   # Ping server
   ping 10.0.0.1

   # Test internet access
   curl ifconfig.me

   # Verify VPN IP
   curl ifconfig.me/ip
   ```

### Troubleshooting Tests

```bash
# Check firewall
# Check firewall rules
   sudo ufw status

   # Check WireGuard logs
   sudo journalctl -u wg-quick@wg0 --no-pager -n 50
   ```

### Performance Testing

```bash
# Test VPN throughput
iperf3 -s  # On server
iperf3 -c SERVER_IP  # On client

# Monitor VPN traffic
sudo wg show wg0 transfer
```

## Contributing

We welcome contributions to improve these WireGuard automation scripts. Please follow these guidelines:

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly on a clean Ubuntu system
5. Submit a pull request

### Code Standards

- **Shell Scripting**: Follow Bash best practices
- **Error Handling**: Use `set -e` and proper error checking
- **Documentation**: Comment complex logic and functions
- **Security**: Validate inputs and use secure practices
- **Compatibility**: Test on multiple Ubuntu versions

### Testing Requirements

- Test on fresh Ubuntu installations
- Verify both server and client scripts work together
- Test error scenarios and edge cases
- Ensure firewall and service configurations are correct

### Reporting Issues

When reporting bugs or requesting features:

1. Use the issue templates
2. Include your Ubuntu version and system details
3. Provide script output and error messages
4. Describe expected vs. actual behavior
5. Include steps to reproduce the issue

## License

This project is licensed under the MIT License.

```
MIT License

Copyright (c) 2025 WireGuard-Automation-Scripts

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Known Issues and Troubleshooting

### Common Issues

1. **Port Already in Use**
   - Error: "Address already in use"
   - Solution: Change `WG_PORT` in the script or check what's using the port

2. **Firewall Blocking Traffic**
   - Symptom: Clients can't connect
   - Solution: Verify UFW rules and ensure port 51820/UDP is open

3. **IP Forwarding Not Working**
   - Symptom: No internet access through VPN
   - Solution: Check `sysctl net.ipv4.ip_forward` and restart service

4. **Service Won't Start**
   - Symptom: `systemctl status wg-quick@wg0` shows failed
   - Solution: Check logs with `journalctl -u wg-quick@wg0`

### Troubleshooting Steps

1. **Check System Logs**
   ```bash
   sudo journalctl -u wg-quick@wg0 -f
   ```

2. **Verify Configuration**
   ```bash
   sudo wg show wg0
   sudo cat /etc/wireguard/wg0.conf
   ```

3. **Test Network Connectivity**
   ```bash
   sudo tcpdump -i wg0
   sudo iptables -L -n -v
   ```

4. **Restart Services**
   ```bash
   sudo systemctl restart wg-quick@wg0
   sudo systemctl restart ufw
   ```

### Getting Help

- Check the [WireGuard documentation](https://www.wireguard.com/)
- Review Ubuntu-specific WireGuard guides
- Search existing issues in this repository
- Create a new issue with detailed information

## Security Considerations

- **Key Management**: Keys are generated securely using WireGuard's built-in tools
- **File Permissions**: Configuration files have restrictive permissions (600)
- **Firewall**: Automatic UFW configuration blocks unauthorized access
- **IP Validation**: Scripts validate IP addresses to prevent conflicts
- **Input Sanitization**: User inputs are validated before processing

## Acknowledgments

- WireGuard project for the excellent VPN protocol
- Ubuntu community for system integration guidance
- Open source contributors who maintain WireGuard tools

---

**Note**: These scripts are provided as-is for educational and operational use. Always test in a development environment before deploying to production systems.