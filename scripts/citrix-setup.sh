#!/usr/bin/env bash
# =============================================================================
# citrix-setup.sh — Citrix Workspace App pour Linux (x86_64)
# =============================================================================
# Version référence : 2601 / 26.01.x (release : mars 2026)
# SHA-256 référence : 7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a
#
# ⚠  TÉLÉCHARGEMENT MANUEL REQUIS (EULA Citrix)
#   1. Ouvrir : https://www.citrix.com/downloads/workspace-app/linux/
#   2. Télécharger "Full Package (Self-Service) — x86_64 .deb"
#   3. Placer le fichier dans ~/Downloads/
#   4. Lancer : sudo bash scripts/citrix-setup.sh
# =============================================================================

set -euo pipefail

CITRIX_SHA256_REF="7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()  { echo "[$(date +'%H:%M:%S')] ·     $*"; }
log_ok()    { echo "[$(date +'%H:%M:%S')] ✓     $*"; }
log_warn()  { echo "[$(date +'%H:%M:%S')] ⚠     $*"; }
log_error() { echo "[$(date +'%H:%M:%S')] ✗     $*" >&2; }

[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

# ── Détecter le VRAI utilisateur (pas root) ───────────────────────────────────
# Avec sudo : $HOME = /root, mais le .deb est dans le home de l'utilisateur réel
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -n "${REAL_USER}" && "${REAL_USER}" != "root" ]]; then
  REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
else
  REAL_HOME="/root"
fi

# ── Trouver le .deb (home utilisateur, root, script dir, /tmp) ───────────────
find_deb() {
  local found
  for dir in "${REAL_HOME}/Downloads" "/root/Downloads" "${SCRIPT_DIR}" "/tmp"; do
    found=$(find "${dir}" -maxdepth 1 -name "icaclient_*.deb" 2>/dev/null | sort -V | tail -n1 || true)
    [[ -n "${found}" ]] && echo "${found}" && return 0
  done
  return 1
}

log_info "Citrix Workspace App — installation"
log_info "Recherche du .deb (utilisateur : ${REAL_USER:-root})..."

DEB_PATH=$(find_deb) || {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  Fichier Citrix .deb introuvable                                ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  Emplacements cherchés :                                        ║"
  printf "║   • %-60s ║\n" "${REAL_HOME}/Downloads"
  echo "║   • /root/Downloads · répertoire du script · /tmp               ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  1. https://www.citrix.com/downloads/workspace-app/linux/       ║"
  echo "║  2. Télécharger : Full Package (Self-Service) x86_64 .deb       ║"
  echo "║  3. Placer dans : ~/Downloads/                                  ║"
  echo "║  4. Relancer : sudo bash scripts/citrix-setup.sh                ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  exit 1
}

log_ok "Fichier trouvé : ${DEB_PATH}"

# ── Vérification SHA-256 (informatif, non-bloquant) ──────────────────────────
# Le hash de référence correspond à la version 2601 — il devient obsolète à
# chaque release Citrix. En cas de mismatch, on demande confirmation.
log_info "Vérification du checksum..."
ACTUAL_SHA=$(sha256sum "${DEB_PATH}" | awk '{print $1}')
if [[ "${ACTUAL_SHA}" == "${CITRIX_SHA256_REF}" ]]; then
  log_ok "Checksum identique à la version de référence (2601)"
else
  log_warn "Checksum différent de la version de référence."
  log_warn "  Référence (2601) : ${CITRIX_SHA256_REF}"
  log_warn "  Fichier local    : ${ACTUAL_SHA}"
  log_warn "  → Normal si vous avez téléchargé une version plus récente."
  log_warn "  → Vérifiez le checksum sur la page de téléchargement Citrix."
  printf "  Continuer l'installation ? [Y/n] "
  read -r answer </dev/tty
  [[ ! "${answer}" =~ ^[Nn]$ ]] || { log_info "Annulé."; exit 0; }
fi

# ── Dépendances ───────────────────────────────────────────────────────────────
log_info "Installation des dépendances..."
apt update -q
apt install -y \
  libc6 libglib2.0-0 libgtk2.0-0 libstdc++6 \
  libcanberra-gtk-module libcanberra-gtk3-module \
  libcurl4 libssl3 libpulse0 libxmu6 2>/dev/null || true

# libasound2 : nom différent selon la version Debian/Ubuntu (t64 sur Trixie/Noble)
apt install -y libasound2t64 2>/dev/null \
  || apt install -y libasound2 2>/dev/null || true

# libwebkit2gtk : optionnel (Self-Service UI), noms variables
apt install -y libwebkit2gtk-4.1-0 2>/dev/null \
  || apt install -y libwebkit2gtk-4.0-37 2>/dev/null \
  || log_info "libwebkit indisponible — Self-Service UI limitée (OK pour ICA)"

log_ok "Dépendances installées"

# ── Pré-acceptation EULA (non-interactive) ────────────────────────────────────
log_info "Acceptation EULA (debconf)..."
echo "icaclient icaclient/accepteula boolean true" | debconf-set-selections

# ── Installation ──────────────────────────────────────────────────────────────
log_info "Installation du package Citrix..."
if ! dpkg -i "${DEB_PATH}" 2>/dev/null; then
  apt install -f -y || { log_error "Installation échouée"; exit 1; }
fi
log_ok "Citrix Workspace App installé"

# ── Fix certificats SSL ───────────────────────────────────────────────────────
log_info "Liaison des certificats SSL..."
CITRIX_CERTS="/opt/Citrix/ICAClient/keystore/cacerts"
if [[ -d "${CITRIX_CERTS}" ]]; then
  ln -sf /etc/ssl/certs/ca-certificates.crt "${CITRIX_CERTS}/ca-certificates.crt" 2>/dev/null || true
  log_ok "Certificats SSL liés"
fi

# ── Vérification finale ───────────────────────────────────────────────────────
if [[ -x "/opt/Citrix/ICAClient/selfservice" ]]; then
  log_ok "Prêt → /opt/Citrix/ICAClient/selfservice"
elif [[ -x "/opt/Citrix/ICAClient/wfica" ]]; then
  log_ok "Prêt → /opt/Citrix/ICAClient/wfica"
else
  log_error "Binaire non trouvé — vérifier l'installation"
fi

echo ""
echo "✓ Citrix Workspace App installé ($(basename "${DEB_PATH}"))"
echo "  Lancer depuis le menu ou : /opt/Citrix/ICAClient/selfservice"
