#!/usr/bin/env bash
set -euo pipefail

APP_USER="streambox"
HOSTNAME_TARGET="streambox"
SPOCON_CONFIG="/opt/spocon/config.toml"
SPOCON_SERVICE="spocon.service"

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

install_base_packages() {
  log "Basispakketten installeren..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    ca-certificates \
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

install_spocon() {
  log "SpoCon installeren via officiële installer..."
  curl -sL https://spocon.github.io/spocon/install.sh | sh
}

write_spocon_config() {
  log "SpoCon config schrijven..."

  mkdir -p /opt/spocon

  cat > "${SPOCON_CONFIG}" <<'EOF'
deviceName = "streambox"
deviceType = "SPEAKER"
preferredLocale = "nl"

[audio]
output = "ALSA"
backend = "STDOUT"
alsaDevice = "default"
mixer = "software"
initialVolume = 70
volumeSteps = 64
bitrate = 160

[auth]
strategy = "ZEROCONF"

[zeroconf]
enabled = true
listenAll = true
EOF

  chmod 644 "${SPOCON_CONFIG}"
}

fix_permissions() {
  if id spocon >/dev/null 2>&1; then
    chown -R spocon:spocon /opt/spocon || true
  fi
}

enable_services() {
  log "Services activeren..."
  systemctl daemon-reload
  systemctl enable avahi-daemon
  systemctl restart avahi-daemon
  systemctl enable "${SPOCON_SERVICE}"
  systemctl restart "${SPOCON_SERVICE}"
}

show_status() {
  echo
  log "Klaar."
  echo
  echo "Controleer:"
  echo "  systemctl status ${SPOCON_SERVICE} --no-pager"
  echo "  journalctl -u ${SPOCON_SERVICE} -n 100 --no-pager"
  echo "  hostname"
  echo "  grep 127.0.1.1 /etc/hosts"
  echo
  echo "Na reboot moet Spotify Connect apparaat 'streambox' zichtbaar zijn op je telefoon."
}

main() {
  require_root
  check_user_exists
  install_base_packages
  set_hostname_if_needed
  install_spocon
  write_spocon_config
  fix_permissions
  enable_services
  show_status
}

main "$@"