#!/bin/bash

# ==============================================================================
# Setup Script for using Raspi as Access Point that has WebGoat running in isolated environment
# ==============================================================================

# Ensure the script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script as root (e.g., sudo sh ./webgoat-debian-setup-script.sh)"
  exit 1
fi

echo "\n\n"
echo "======================================================"
echo "               Setting Network priority               "
echo "======================================================"
echo ""

# Isolate the exact connection profile names by filtering for their connection type
ETH_CONN=$(nmcli -t -f NAME,TYPE connection show | grep 802-3-ethernet | head -n1 | cut -d: -f1)
WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show | grep 802-11-wireless | head -n1 | cut -d: -f1)

# Apply Ethernet Metrics
if [ -z "$ETH_CONN" ]; then
    echo "No Ethernet connection profile found."
else
    echo "Setting priority for Ethernet ('$ETH_CONN') to metric 100..."
    nmcli connection modify "$ETH_CONN" ipv4.route-metric 100 ipv6.route-metric 100
    nmcli connection up "$ETH_CONN" > /dev/null
fi

# Apply Wi-Fi Metrics
if [ -z "$WIFI_CONN" ]; then
    echo "No Wi-Fi connection profile found."
else
    echo "Setting priority for Wi-Fi ('$WIFI_CONN') to metric 200..."
    nmcli connection modify "$WIFI_CONN" ipv4.route-metric 200 ipv6.route-metric 200
    nmcli connection up "$WIFI_CONN" > /dev/null
fi

echo "\n\n"
echo "======================================================"
echo "         Checking and Installing Dependencies         "
echo "======================================================"
echo ""

# ---------------------------------------------------------
# Check if Docker is installed, if not -> install
# ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Installing Docker..."

    sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-doc podman-docker containerd runc | cut -f1)
    
    # Update package list and install Docker (Debian/Ubuntu specific)

    # Add Docker's official GPG key:
    sudo apt update
    sudo apt install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update

    sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

elif ! docker info >/dev/null 2>&1; then
  echo "Docker is installed, but the daemon is not running. Starting it now..."
  sudo systemctl start docker
else
  echo "Docker is installed and running!"
fi

# ---------------------------------------------------------
# pull the latest WebGoat image
# ---------------------------------------------------------
echo "Pulling or updating WebGoat..."
sudo docker image pull webgoat/webgoat



echo "\n\n"
echo "======================================================"
echo "     Raspberry Pi Isolated WebGoat Network Setup      "
echo "======================================================"
echo ""

# ---------------------------------------------------------
# 1. Gather User Variables
# ---------------------------------------------------------
read -p "Enter desired Wi-Fi Network Name (SSID) [Default: WebGoat_Net]: " SSID
SSID=${SSID:-WebGoat_Net}

read -p "Enter Wi-Fi Password (min 8 chars) [Default: secr3tpass]: " PASSWORD
PASSWORD=${PASSWORD:-secr3tpass}

read -p "Enter the Raspberry Pi's local IP for this network (e.g., 10.42.0.1 or 192.168.50.1) [Default: 10.42.0.1]: " PI_IP
PI_IP=${PI_IP:-10.42.0.1}

SUBNET="${PI_IP}/24"

# ---------------------------------------------------------
# 2. Prepare the Environment
# ---------------------------------------------------------
echo "\n[*] Unblocking Wi-Fi radio..."
rfkill unblock wlan

# Clean up any previous connection named 'isolated_ap' to avoid conflicts
if nmcli connection show | grep -q "isolated_ap"; then
    echo "[*] Removing old 'isolated_ap' configuration..."
    nmcli connection delete isolated_ap > /dev/null
fi

# ---------------------------------------------------------
# 3. Configure the Wi-Fi Access Point
# ---------------------------------------------------------
echo "[*] Creating the new Wi-Fi Access Point ($SSID)..."
# Create the base Wi-Fi connection
nmcli connection add type wifi ifname wlan0 con-name isolated_ap autoconnect yes ssid "$SSID" > /dev/null

# Modify the connection to act as an Access Point, set the IP, and set the password
nmcli connection modify isolated_ap \
    802-11-wireless.mode ap \
    ipv4.method shared \
    ipv4.addresses "$SUBNET" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$PASSWORD"

echo "[*] Starting the Wi-Fi network..."
nmcli connection up isolated_ap


# ---------------------------------------------------------
# 4. Configure Docker & WebGoat
# ---------------------------------------------------------

if docker ps -a --format '{{.Names}}' | grep -Eq "^webgoat$"; then
    echo "[*] Removing existing 'webgoat' Docker container..."
    docker rm -f webgoat > /dev/null
fi

echo "[*] Pulling and starting WebGoat bound strictly to $PI_IP..."
docker run -d \
    --name webgoat \
    --restart unless-stopped \
    -p "${PI_IP}:8080:8080" \
    -p "${PI_IP}:9090:9090" \
    webgoat/webgoat

# ---------------------------------------------------------
# 5. Network Isolation (Firewall)
# ---------------------------------------------------------
echo ""
read -p "Do you want to block internet access for devices connected to this Wi-Fi? (y/n) [Default: y]: " BLOCK_NET
BLOCK_NET=${BLOCK_NET:-y}

if [ "$BLOCK_NET" = "y" ] || [ "$BLOCK_NET" = "Y" ]; then
    read -p "Enter one specific IP address to allow outside connection (leave blank to allow none): " ALLOWED_IP
    
    echo "[*] Applying firewall rules to isolate Wi-Fi clients from the internet..."
    iptables -I FORWARD -i wlan0 -j DROP
    # Check if the ALLOWED_IP variable is empty
    if [ -z "$ALLOWED_IP" ]; then
        echo "[*] No IP provided. Applying strict firewall rules (Total internet block)..."
    else
        echo "[*] Applying firewall rules to isolate Wi-Fi clients, allowing ONLY $ALLOWED_IP..."
        
        iptables -I FORWARD -i wlan0 -s "$ALLOWED_IP" -j ACCEPT
        
        iptables -I FORWARD -i eth0 -o wlan0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    fi
fi

echo "[*] Opening ports 8080 and 9090 in FORWARD chain for WebGoat access..."

# Allow ANY Wi-Fi client to forward traffic to the WebGoat ports (Docker/VM bypass)
iptables -I FORWARD -i wlan0 -p tcp --dport 8080 -j ACCEPT
iptables -I FORWARD -i wlan0 -p tcp --dport 9090 -j ACCEPT

# ---------------------------------------------------------
# 6. SAVE RULES (Persistent Setup)
# ---------------------------------------------------------
read -p "Do you want to save these rules permanently? (y/n) [Default: n]: " SAVE_RULES
SAVE_RULES=${SAVE_RULES:-n}

if [ "$SAVE_RULES" = "y" ] || [ "$SAVE_RULES" = "Y" ]; then
    # Check if the save command actually exists on the system
    if command -v netfilter-persistent >/dev/null 2>&1; then
        echo "[*] Saving firewall rules permanently..."
        netfilter-persistent save
    else
        echo "[*] Installing iptables-persistent..."
        echo "[*] Keep pressing yes if you want to save the firewall rules permanently (saved after reboot)."
        sudo apt update
        sudo apt install iptables-persistent
    fi
else
    echo "[*] Firewall rules applied temporarily (will reset on reboot)."
fi


# ---------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------
echo "\n\n"
echo "======================================================"
echo "                   Setup Complete!                    "
echo "======================================================"
echo ""
echo "Wi-Fi Network Name:  $SSID"
echo "Wi-Fi Password:      $PASSWORD"
echo "WebGoat Server URL:  http://${PI_IP}:8080/WebGoat"
echo "WebGoat WebWolf:     http://${PI_IP}:9090/WebWolf"
echo "------------------------------------------------------"
echo "Note: The server is invisible to your main network."
echo "You can still SSH/Screen Share into the Pi via your main network IP."
echo ""
