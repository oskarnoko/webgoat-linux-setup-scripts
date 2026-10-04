# webgoat-linux-setup-scripts

Automated setup scripts to quickly deploy a WebGoat server inside a Docker container with custom firewall rules. Perfect for users who want a guided, hassle-free installation instead of configuring everything manually.

### Features
* **Automated Dependencies:** Checks for and installs Docker, then pulls the WebGoat image.
* **Optional Wi-Fi Access Point:** Broadcasts an AP for nearby devices to connect to WebGoat.
* **Smart Routing:** Prioritizes Ethernet over Wi-Fi for internet traffic, allowing AP-connected devices to reach both WebGoat and the external internet.
* **Persistent Firewall Rules:** Automatically configures and saves your iptables.

## Installation

Download and run the setup script for your specific Linux distribution. 

### Debian
```bash
curl -O https://raw.githubusercontent.com/oskarnoko/webgoat-linux-setup-scripts/main/webgoat-debian-setup-script.sh
chmod +x webgoat-debian-setup-script.sh
sudo sh webgoat-debian-setup-script.sh
```

### Ubuntu
```bash
curl -O https://raw.githubusercontent.com/oskarnoko/webgoat-linux-setup-scripts/main/webgoat-ubuntu-setup-script.sh
chmod +x webgoat-ubuntu-setup-script.sh
sudo sh webgoat-ubuntu-setup-script.sh
```

## Disclaimer
This repository is simply a helper tool for installing Docker and WebGoat, as well as setting it up as an Access Point. While I wrote the scripts, I do not own the software they install and have no control over their external repositories. I am not liable for any third-party issues, including the fetching of incorrect or malicious images. Please review the scripts before running them. Use at your own risk.
