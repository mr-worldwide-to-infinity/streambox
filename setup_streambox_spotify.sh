#!/usr/bin/env bash
set -euo pipefail

APP_USER="streambox"
HOSTNAME_TARGET="streambox"

APP_DIR="/opt/streambox-spotify"
CONFIG_FILE="${APP_DIR}/config.toml"
CACHE_DIR="${APP_DIR}/cache"
JAR_FILE="${APP_DIR}/librespot-player.jar"
SERVICE_FILE="/etc/systemd/system/streambox-spotify.service"

LIBRESPOT_URL="https://github.com/librespot-org/librespot-java/releases/download/v1.6.5/librespot-player-1.6.5.jar"

log() {
  echo "[INFO] $*"
}

err() {
  echo "[ERROR] $*" >&2
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run dit script met sudo of als root."
    exit 1
  fi
}

check_user_exists() {
  if ! id "${APP_USER}" >/dev/null 2>&1; then
    err "Gebruiker '${APP_USER}' bestaat niet."
    exit 1
  fi
}

remove_broken_spocon_repo() {
  log "Oude SpoCon repo verwijderen..."
  rm -f /etc/apt/sources.list.d/spocon.list
  apt-get update
}

install_packages() {
  log "Benodigde pakketten installeren..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ca-certificates \
    openjdk-17-jre-headless \
    avahi-daemon \
    alsa-utils
}

fix_hostname() {
  log "Hostname instellen op ${HOSTNAME_TARGET}..."
  echo "${HOSTNAME_TARGET}" > /etc/hostname

  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${HOSTNAME_TARGET}/" /etc/hosts
  else
    echo "127.0.1.1 ${HOSTNAME_TARGET}" >> /etc/hosts
  fi

  hostname "${HOSTNAME_TARGET}" || true
}

create_dirs() {
  log "Mappen aanmaken..."
  mkdir -p "${APP_DIR}"
  mkdir -p "${CACHE_DIR}"
  chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
  chmod 755 "${APP_DIR}"
}

download_librespot() {
  log "librespot-player downloaden..."
  curl -L "${LIBRESPOT_URL}" -o "${JAR_FILE}"

  if [[ ! -s "${JAR_FILE}" ]]; then
    err "Download van librespot-player mislukt."
    exit 1
  fi

  chown "${APP_USER}:${APP_USER}" "${JAR_FILE}"
  chmod 644 "${JAR_FILE}"
}

write_config() {
  log "Config schrijven..."
  cat > "${CONFIG_FILE}" <<'EOF'
deviceName = "streambox"
deviceType = "SPEAKER"
preferredLocale = "nl"

[auth]
strategy = "ZEROCONF"

[zeroconf]
listenPort = -1
listenAll = true
interfaces = ""

[cache]
enabled = true
dir = "/opt/streambox-spotify/cache"
doCleanUp = true

[preload]
enabled = true

[time]
synchronizationMethod = "NTP"
manualCorrection = 0

[player]
autoplayEnabled = true
preferredAudioQuality = "VORBIS_160"
enableNormalisation = true
normalisationPregain = 0.0
initialVolume = 45000
logAvailableMixers = true
mixerSearchKeywords = ""
crossfadeDuration = 0
output = "MIXER"
releaseLineDelay = 20
pipe = ""
EOF

  chown "${APP_USER}:${APP_USER}" "${CONFIG_FILE}"
  chmod 664 "${CONFIG_FILE}"
}

write_service() {
  log "systemd service schrijven..."
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Streambox Spotify Connect
After=network-online.target avahi-daemon.service sound.target
Wants=network-online.target avahi-daemon.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment=HOME=/home/${APP_USER}
ExecStart=/usr/bin/java -jar ${JAR_FILE} --conf-file=${CONFIG_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "${SERVICE_FILE}"
}

enable_service() {
  log "Services activeren..."
  systemctl daemon-reload
  systemctl enable avahi-daemon
  systemctl restart avahi-daemon
  systemctl enable streambox-spotify.service
  systemctl restart streambox-spotify.service
}

show_status() {
  echo
  log "Klaar."
  echo "Controleer met:"
  echo "  systemctl status streambox-spotify.service --no-pager"
  echo "  journalctl -u streambox-spotify.service -n 100 --no-pager"
  echo
  echo "Live log bekijken tijdens verbinden:"
  echo "  journalctl -u streambox-spotify.service -f --no-pager"
  echo
  echo "Herstart daarna de Pi:"
  echo "  sudo reboot"
}

main() {
  require_root
  check_user_exists
  remove_broken_spocon_repo
  install_packages
  fix_hostname
  create_dirs
  download_librespot
  write_config
  write_service
  enable_service
  show_status
}

main "$@"