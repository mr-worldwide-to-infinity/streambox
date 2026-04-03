#!/usr/bin/env bash
set -euo pipefail

# Streambox Spotify Connect setup for Raspberry Pi Zero W (ARMv6)
# Installs a lightweight headless Spotify Connect receiver using librespot-java
# and configures systemd autostart.

APP_USER="streambox"
APP_GROUP="audio"
APP_DIR="/opt/streambox-spotify"
CONFIG_DIR="/etc/streambox-spotify"
CACHE_DIR="/var/cache/streambox-spotify"
SERVICE_NAME="streambox-spotify.service"
HOSTNAME_TARGET="streambox"
DEVICE_NAME="streambox"
DEVICE_TYPE="SPEAKER"
LIBRESPOT_VERSION="1.6.5"
JAR_NAME="librespot-player-${LIBRESPOT_VERSION}.jar"
JAR_URL="https://repo1.maven.org/maven2/xyz/gianlu/librespot/librespot-player/${LIBRESPOT_VERSION}/${JAR_NAME}"

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run dit script met sudo of als root."
    exit 1
  fi
}

require_user() {
  if ! id -u "${APP_USER}" >/dev/null 2>&1; then
    echo "Gebruiker '${APP_USER}' bestaat niet. Maak eerst een gebruiker met die naam aan."
    echo "Voorbeeld op een verse Pi OS install: sudo adduser ${APP_USER}"
    exit 1
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    avahi-daemon \
    alsa-utils \
    curl \
    ca-certificates
}

set_hostname_if_needed() {
  local current
  current="$(hostnamectl --static status 2>/dev/null || hostname)"
  if [[ "${current}" != "${HOSTNAME_TARGET}" ]]; then
    hostnamectl set-hostname "${HOSTNAME_TARGET}" || true
    echo "127.0.1.1 ${HOSTNAME_TARGET}" > /etc/hosts.d/streambox-hostname.tmp
    if grep -q '^127.0.1.1' /etc/hosts; then
      sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${HOSTNAME_TARGET}/" /etc/hosts
    else
      cat /etc/hosts.d/streambox-hostname.tmp >> /etc/hosts
    fi
    rm -f /etc/hosts.d/streambox-hostname.tmp 2>/dev/null || true
  fi
}

create_dirs() {
  mkdir -p "${APP_DIR}" "${CONFIG_DIR}" "${CACHE_DIR}"
  chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}" "${CACHE_DIR}"
  chmod 755 "${APP_DIR}" "${CONFIG_DIR}" "${CACHE_DIR}"
}

download_player() {
  if [[ ! -f "${APP_DIR}/${JAR_NAME}" ]]; then
    curl -L --fail --retry 3 -o "${APP_DIR}/${JAR_NAME}" "${JAR_URL}"
  fi
  ln -sf "${APP_DIR}/${JAR_NAME}" "${APP_DIR}/librespot-player.jar"
  chown -h "${APP_USER}:${APP_GROUP}" "${APP_DIR}/librespot-player.jar"
  chown "${APP_USER}:${APP_GROUP}" "${APP_DIR}/${JAR_NAME}"
}

write_config() {
  cat > "${CONFIG_DIR}/config.toml" <<CFG
# Streambox Spotify Connect configuratie
# Verander deviceName als je een andere naam in de Spotify app wilt zien.

deviceName = "${DEVICE_NAME}"
deviceType = "${DEVICE_TYPE}"
preferredLocale = "nl"
logLevel = "INFO"

[auth]
strategy = "ZEROCONF"
storeCredentials = true
credentialsFile = "${CACHE_DIR}/credentials.json"

[zeroconf]
listenPort = -1
listenAll = true
interfaces = "wlan0"

[cache]
enabled = true
dir = "${CACHE_DIR}"
doCleanUp = true

[preload]
enabled = true

[time]
synchronizationMethod = "NTP"
manualCorrection = 0

[player]
autoplayEnabled = true
preferredAudioQuality = "HIGH"
enableNormalisation = true
normalisationPregain = 0.0
initialVolume = 49152
volumeSteps = 64
logAvailableMixers = true
mixerSearchKeywords = "Headphone;PCM;Master"
crossfadeDuration = 0
output = "MIXER"
releaseLineDelay = 20
pipe = ""
retryOnChunkError = true
metadataPipe = ""
CFG
  chmod 644 "${CONFIG_DIR}/config.toml"
}

write_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}" <<UNIT
[Unit]
Description=Streambox Spotify Connect Receiver
Wants=network-online.target avahi-daemon.service
After=network-online.target avahi-daemon.service sound.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
Environment=HOME=/home/${APP_USER}
Environment=JAVA_TOOL_OPTIONS=-Djava.awt.headless=true
ExecStart=/usr/bin/java -jar ${APP_DIR}/librespot-player.jar --conf-file=${CONFIG_DIR}/config.toml
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=false
PrivateTmp=true
ReadWritePaths=${CACHE_DIR} ${APP_DIR}

[Install]
WantedBy=multi-user.target
UNIT
}

configure_audio() {
  # Zet analoge output aan op Pi's die standaard op auto/HDMI staan.
  if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_audio 1 || true
  fi

  # Zet volume iets bruikbaarder. Geen magie, slechts schadebeperking.
  su -s /bin/bash -c 'amixer sset PCM 90% unmute || true' "${APP_USER}" || true
  su -s /bin/bash -c 'amixer sset Master 90% unmute || true' "${APP_USER}" || true
}

enable_services() {
  systemctl daemon-reload
  systemctl enable avahi-daemon
  systemctl enable "${SERVICE_NAME}"
  systemctl restart avahi-daemon
  systemctl restart "${SERVICE_NAME}"
}

print_done() {
  cat <<MSG

Klaar.

Belangrijk:
1. Herstart de Pi een keer: sudo reboot
2. Open daarna Spotify op je telefoon.
3. Tik op 'Beschikbare apparaten' en kies '${DEVICE_NAME}'.

Handige commando's:
- Status bekijken: sudo systemctl status ${SERVICE_NAME}
- Logs bekijken:   journalctl -u ${SERVICE_NAME} -f
- Config wijzigen: sudo nano ${CONFIG_DIR}/config.toml

Als '${DEVICE_NAME}' niet verschijnt:
- Controleer of telefoon en Pi op hetzelfde netwerk zitten
- Controleer of avahi draait: systemctl status avahi-daemon
- Controleer audiolevels met: alsamixer
MSG
}

ensure_root
require_user
install_packages
set_hostname_if_needed
create_dirs
download_player
write_config
write_service
configure_audio
enable_services
print_done
