#!/bin/bash

# This script requires an external hard disk to be connected.
echo "This script requires an external hard disk to be connected."

# Create Docker group if it doesn't exist
if ! getent group docker > /dev/null; then
  echo "Creating Docker group..."
  sudo groupadd docker
fi

# Add the current user to the Docker group if not already added
if ! groups $(whoami) | grep -q '\bdocker\b'; then
  echo "Adding the current user to the Docker group..."
  sudo usermod -aG docker $(whoami)
  echo "Please log out and log back in to apply Docker group changes, then re-run this script."
  exit 1
else
  echo "User is already in the Docker group."
fi

# ===========================
# Collect all answers upfront
# ===========================

# Ask if this is the first installation
echo "Is this the first installation? (y/n)"
read first_install_choice

# Ask if the user wants to configure Zigbee2MQTT
echo "Would you like to configure Zigbee2MQTT? (y/n)"
read zigbee2mqtt_choice

if [ "$zigbee2mqtt_choice" = "y" ]; then
  echo "Are you using slzb-06m.local for Zigbee2MQTT? (y/n)"
  read use_slzb_local
fi

if [ "$first_install_choice" = "y" ]; then
  # 1. Ask if the user wants to update the system
  echo "Would you like to update the system? (y/n) (Recommended to do this at least the first time)"
  read update_choice

  # 2. Ask if Docker should be installed
  echo "Would you like to install Docker? (y/n)"
  read docker_install_choice

  # 3. Ask if Docker Compose should be installed
  echo "Would you like to install Docker Compose? (y/n)"
  read docker_compose_install_choice
fi

# 4. Ask if Portainer should be installed
echo "Would you like to install Portainer for Docker monitoring? (y/n)"
read portainer_install_choice

# 5. Ask for the external hard disk mount point
echo "Listing available disks and partitions:"
sudo lsblk
read -p "Enter the mount point for the external hard disk to use in Docker Compose (default: /media/$(whoami)/TOSHIBA\ EXT), or press Enter to use default: " external_hd_mount_point

# Set default mount point if not provided
if [ -z "$external_hd_mount_point" ]; then
  external_hd_mount_point="/media/$(whoami)/TOSHIBA\ EXT"
fi

echo "Using $external_hd_mount_point as the external hard disk for Docker Compose volumes."

# ===========================
# Execute actions based on user input
# ===========================

if [ "$first_install_choice" = "y" ]; then
  # Optional: Update the system
  if [ "$update_choice" = "y" ]; then
    echo "Updating the system..."
    sudo apt update && sudo apt upgrade -y
  else
    echo "System update skipped."
  fi

  # Install Docker if requested
  if [ "$docker_install_choice" = "y" ]; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
  else
    echo "Docker installation skipped."
  fi

  # Install Docker Compose if requested
  if [ "$docker_compose_install_choice" = "y" ]; then
    echo "Installing Docker Compose..."
    sudo apt install -y docker-compose
  else
    echo "Docker Compose installation skipped."
  fi
fi

# Check if the necessary directories exist on the external hard disk and create them if they don't
if [ -n "$external_hd_mount_point" ]; then
  if [ ! -d "$external_hd_mount_point/download/torrent/torrent-inprogress" ]; then
    echo "Creating directory $external_hd_mount_point/download/torrent/torrent-inprogress"
    mkdir -p "$external_hd_mount_point/download/torrent/torrent-inprogress"
  fi
  if [ ! -d "$external_hd_mount_point/download/torrent/torrent-complete" ]; then
    echo "Creating directory $external_hd_mount_point/download/torrent/torrent-complete"
    mkdir -p "$external_hd_mount_point/download/torrent/torrent-complete"
  fi
  if [ ! -d "$external_hd_mount_point/download/torrent/watch" ]; then
    echo "Creating directory $external_hd_mount_point/download/torrent/watch"
    mkdir -p "$external_hd_mount_point/download/torrent/watch"
  fi
  if [ ! -d "$external_hd_mount_point/multimedia/movies" ]; then
    echo "Creating directory $external_hd_mount_point/multimedia/movies"
    mkdir -p "$external_hd_mount_point/multimedia/movies"
  fi
fi

# Create directories for persistent volumes
mkdir -p homeassistant mosquitto/config mosquitto/data mosquitto/log transmission/config transmission/downloads transmission/watch minidlna/media minidlna/config

# Create a default Mosquitto configuration file
sudo bash -c 'cat > mosquitto/config/mosquitto.conf <<EOL
listener 1883
allow_anonymous true
EOL'

# Create a default MiniDLNA configuration file
bash -c 'cat > minidlna/config/minidlna.conf <<EOL
media_dir=/media
friendly_name=MyDLNA
notify_interval=30
serial=12345678
presentation_url=http://raspberrypi:8200
inotify=yes
EOL'

# ===========================
# Zigbee2MQTT Configuration
# ===========================

if [ "$zigbee2mqtt_choice" = "y" ]; then
  # Create directory for Zigbee2MQTT persistent data
  mkdir -p zigbee2mqtt/data

  if [ "$use_slzb_local" = "y" ]; then
    # Attempt to resolve the IP address of slzb-06m.local
    # This step is necessary because Zigbee2MQTT requires a stable IP address rather than relying on mDNS (which might not work reliably in Docker).
    slzb_ip=$(ping -c 1 slzb-06m.local | awk -F'[()]' '/PING/{print $2}')
    if [ -z "$slzb_ip" ]; then
      echo "Failed to resolve slzb-06m.local. Please make sure the device is online and try again."
      exit 1
    else
      echo "Resolved slzb-06m.local to IP: $slzb_ip"
    fi
  else
    read -p "Enter the IP address for the Zigbee2MQTT dongle: " slzb_ip
  fi

  # Create the Zigbee2MQTT configuration file
  cat > zigbee2mqtt/data/configuration.yaml <<EOL
mqtt:
  base_topic: zigbee2mqtt
  server: "mqtt://localhost:1883"  # Address of the MQTT broker (use localhost in host network mode) (Mosquitto in this case)

serial:
  port: "tcp://${slzb_ip}:6638"  # Using resolved IP address of the Zigbee dongle
  baudrate: 115200                   # Baudrate for communication with the dongle
  adapter: ezsp                      # Type of adapter; SLZB-06M uses the EZSP protocol

advanced:
  disable_led: false                 # Keeps the green LED on (set to true to disable)
  transmit_power: 20                 # Set transmit power to maximum (20 dBm)

frontend:
  port: 8080                         # (Optional) Enable the Zigbee2MQTT web frontend on this port

homeassistant: false                 # Disable automatic integration with Home Assistant
permit_join: false                   # Prevent devices from automatically joining the Zigbee network
EOL
fi

# Set UID and GID environment variables for Docker Compose
export UID=$(id -u)
export GID=$(id -g)

# Create the docker-compose.yml file
cat > docker-compose.yml <<EOL
version: '3'

services:
  homeassistant:
    container_name: homeassistant
    image: ghcr.io/home-assistant/home-assistant:stable
    user: "\${UID}:\${GID}"
    volumes:
      - ./homeassistant:/config
      - /run/dbus:/run/dbus:ro
    environment:
      - TZ=Europe/Rome
    network_mode: host
    restart: unless-stopped

  mosquitto:
    container_name: mosquitto
    image: eclipse-mosquitto
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log
    ports:
      - "1883:1883"
      - "9001:9001"
    restart: unless-stopped
EOL

if [ "$zigbee2mqtt_choice" = "y" ]; then
  cat >> docker-compose.yml <<EOL

  zigbee2mqtt:
    container_name: zigbee2mqtt
    image: koenkk/zigbee2mqtt
    volumes:
      - ./zigbee2mqtt/data:/app/data
    environment:
      - TZ=Europe/Rome
    network_mode: host
    restart: unless-stopped
EOL
fi

cat >> docker-compose.yml <<EOL

  transmission:
    container_name: transmission
    image: linuxserver/transmission
    user: "\${UID}:\${GID}"
    ports:
      - "9091:9091"
    volumes:
      - ./transmission/config:/config
      - $external_hd_mount_point/download/torrent/torrent-inprogress:/torrent-inprogress
      - $external_hd_mount_point/download/torrent/torrent-complete:/torrent-complete
      - $external_hd_mount_point/download/torrent/watch:/watch
      - $external_hd_mount_point/multimedia/movies:/torrent-complete/movies
      - $external_hd_mount_point/multimedia/movies:/torrent-complete/show
    environment:
      - TZ=Europe/Rome
      - TRANSMISSION_INCOMPLETE_DIR=/torrent-inprogress
      - TRANSMISSION_DOWNLOAD_DIR=/torrent-complete
      - TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true
      - TRANSMISSION_RPC_USERNAME=paolotti
      - TRANSMISSION_RPC_PASSWORD=torrent_pass_123
    restart: unless-stopped

  minidlna:
    container_name: minidlna
    image: vladgh/minidlna
    network_mode: host
    environment:
      - MINIDLNA_MEDIA_DIR=/media
      - MINIDLNA_FRIENDLY_NAME=MyDLNA
      - MINIDLNA_INOTIFY=yes
    volumes:
      - $external_hd_mount_point/multimedia/:/media
    restart: unless-stopped
EOL

# Optionally add Portainer to the docker-compose file
if [ "$portainer_install_choice" = "y" ]; then
  cat >> docker-compose.yml <<EOL

  portainer:
    container_name: portainer
    image: portainer/portainer-ce
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./portainer/data:/data
    ports:
      - "9000:9000"
    restart: unless-stopped
EOL
fi

# Start the containers with Docker Compose
if command -v docker-compose &> /dev/null; then
  docker-compose up -d
elif command -v docker compose &> /dev/null; then
  docker compose up -d
else
  echo "Docker Compose is not installed correctly. Please check your installation."
  exit 1
fi

# Completion message
echo "Setup complete! Docker and Docker Compose have been configured and the containers are running."
