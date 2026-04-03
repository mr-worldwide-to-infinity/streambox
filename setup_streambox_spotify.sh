#!/usr/bin/env bash
set -euo pipefail

APP_USER="streambox"
HOSTNAME_TARGET="streambox"
APP_DIR="/opt/streambox-spotify"
CONFIG_DIR="/etc/streambox-spotify"
SERVICE_NAME="streambox-spotify.service"
BIN_PATH="/usr/local/bin/librespot-player"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_PATH="${CONFIG_DIR}/config.toml"

LIBRESPOT_URL="https://github.com/librespot-org/librespot-java/releases/download/v1.6.3/librespot-player-1.6.3_linux_armhf.deb"
TMP_DEB="/tmp/librespot-player.deb"

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
    err "Gebruiker '${APP_USER}' bestaat niet. Maak deze eerst aan."
    exit 1
  fi
}

install_packages() {
  log "Pakketten installeren..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ca-certificates \
    openjdk-17-jre-headless \
    avahi-daemon \
    alsa-utils
}

set_hostname_if_needed() {
  log "Hostname instellen op ${HOSTNAME_TARGET}..."
  echo "${HOSTNAME_TARGET}" > /etc/hostname

  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${HOSTNAME_TARGET}/" /etc/hosts
  else
    echo "127.0.1.1 ${HOSTNAME_TARGET}" >> /etc/hosts
  fi

  hostname "${HOSTNAME_TARGET}" || true
}

download_and_install_librespot() {
  log "librespot-player downloaden..."
  rm -f "${TMP_DEB}"
  curl -L "${LIBRESPOT_URL}" -o "${TMP_DEB}"

  log "librespot-player installeren..."
  dpkg -i "${TMP_DEB}" || apt-get install -f -y

  if [[ ! -f "/usr/bin/librespot-player" ]]; then
    err "librespot-player niet gevonden na installatie."
    exit 1
  fi

  cp /usr/bin/librespot-player "${BIN_PATH}"
  chmod 755 "${BIN_PATH}"
}

create_directories() {
  log "Mappen aanmaken..."
  mkdir -p "${APP_DIR}"
  mkdir -p "${CONFIG_DIR}"
  chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
}

write_config() {
  log "Config schrijven naar ${CONFIG_PATH}..."
  cat > "${CONFIG_PATH}" <<EOF
deviceName = "streambox"
deviceType = "SPEAKER"
audioOutput = "ALSA"
audioDevice = "default"
mixer = "software"
initialVolume = 70
bitrate = 160
volumeSteps = 64
zeroconfEnabled = true
EOF

  chmod 644 "${CONFIG_PATH}"
}

write_service() {
  log "systemd service schrijven..."
  cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Streambox Spotify Connect
After=network-online.target sound.target avahi-daemon.service
Wants=network-online.target avahi-daemon.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
ExecStart=${BIN_PATH} --conf-file ${CONFIG_PATH}
Restart=always
RestartSec=5
WorkingDirectory=${APP_DIR}
Environment=HOME=/home/${APP_USER}
Environment=USER=${APP_USER}

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "${SERVICE_PATH}"
}

enable_services() {
  log "Services activeren..."
  systemctl daemon-reload
  systemctl enable avahi-daemon
  systemctl restart avahi-daemon
  systemctl enable "${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"
}

show_status() {
  echo
  log "Klaar."
  echo "Controleer status met:"
  echo "  systemctl status ${SERVICE_NAME}"
  echo
  echo "Na een reboot zou Spotify Connect apparaat 'streambox' zichtbaar moeten zijn op je telefoon."
  echo
  echo "Handige checks:"
  echo "  hostname"
  echo "  cat /etc/hostname"
  echo "  grep 127.0.1.1 /etc/hosts"
  echo "  journalctl -u ${SERVICE_NAME} -n 100 --no-pager"
}

main() {
  require_root
  check_user_exists
  install_packages
  set_hostname_if_needed
  download_and_install_librespot
  create_directories
  write_config
  write_service
  enable_services
  show_status
}

main "$@"