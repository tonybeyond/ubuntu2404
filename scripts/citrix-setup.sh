#!/usr/bin/env bash
# =============================================================================
# citrix-setup.sh — Citrix Workspace App pour Linux (x86_64)
# =============================================================================
# Version actuelle : 2601 (release : 5 mars 2026)
# SHA-256 .deb     : 7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a
#
# ⚠️  TÉLÉCHARGEMENT MANUEL REQUIS (EULA Citrix)
#   1. Ouvrir : https://www.citrix.com/downloads/workspace-app/linux/
#   2. Télécharger "Full Package (Self-Service) — x86_64 .deb"
#   3. Placer le fichier dans ~/Downloads/
#   4. Lancer : sudo bash scripts/citrix-setup.sh
# =============================================================================

set -euo pipefail

CITRIX_VERSION="2601"
CITRIX_SHA256="7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a"
DOWNLOADS="${HOME:-/root}/Downloads"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()  { echo "[$(date +'%H:%M:%S')] ·     $*"; }
log_ok()    { echo "[$(date +'%H:%M:%S')] ✓     $*"; }
log_error() { echo "[$(date +'%H:%M:%S')] ✗     $*" >&2; }

[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

# ── Trouver le .deb ───────────────────────────────────────────────────────────
find_deb() {
  local found
  for dir in "${SCRIPT_DIR}" "${DOWNLOADS}" /tmp; do
    found=$(find "${dir}" -maxdepth 1 -name "icaclient_*.deb" 2>/dev/null | head -n1 || true)
    [[ -n "${found}" ]] && echo "${found}" && return 0
  done
  return 1
}

log_info "Citrix Workspace App ${CITRIX_VERSION} — installation"

DEB_PATH=$(find_deb) || {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  Fichier Citrix .deb introuvable                                ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  1. Ouvrir dans un navigateur :                                 ║"
  echo "║     https://www.citrix.com/downloads/workspace-app/linux/       ║"
  echo "║  2. Télécharger : Full Package (Self-Service) x86_64 .deb       ║"
  printf "║     SHA-256 : %.55s ║\n" "${CITRIX_SHA256}..."
  echo "║  3. Placer dans : ~/Downloads/                                  ║"
  echo "║  4. Relancer : sudo bash scripts/citrix-setup.sh                ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  exit 1
}

log_info "Fichier trouvé : ${DEB_PATH}"

# ── Vérification SHA-256 ──────────────────────────────────────────────────────
log_info "Vérification du checksum..."
ACTUAL_SHA=$(sha256sum "${DEB_PATH}" | awk '{print $1}')
if [[ "${ACTUAL_SHA}" == "${CITRIX_SHA256}" ]]; then
  log_ok "Checksum OK"
else
  log_error "Checksum INCORRECT !"
  echo "  Attendu : ${CITRIX_SHA256}"
  echo "  Obtenu  : ${ACTUAL_SHA}"
  echo "  → Fichier corrompu ou mauvaise version. Re-télécharger."
  exit 1
fi

# ── Dépendances ───────────────────────────────────────────────────────────────
log_info "Installation des dépendances..."
apt update -q
apt install -y \
  libc6 libglib2.0-0 libgtk2.0-0 libstdc++6 \
  libcanberra-gtk-module libcanberra-gtk3-module \
  libcurl4 libssl3 libpulse0 libxmu6 2>/dev/null || true

# libwebkit2gtk-4.0-37 est optionnel (Self-Service UI)
apt install -y libwebkit2gtk-4.0-37 2>/dev/null \
  || apt install -y libwebkit2gtk-4.1-0 2>/dev/null \
  || log_info "libwebkit non disponible — Self-Service UI limitée (OK pour ICA)"

log_ok "Dépendances installées"

# ── Pré-acceptation EULA (non-interactive) ────────────────────────────────────
log_info "Acceptation EULA (debconf)..."
echo "icaclient icaclient/accepteula boolean true" | debconf-set-selections

# ── Installation ──────────────────────────────────────────────────────────────
log_info "Installation du package Citrix..."
dpkg -i "${DEB_PATH}" || apt install -f -y || {
  log_error "Installation échouée"
  exit 1
}
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
  log_ok "Citrix Workspace App prêt → /opt/Citrix/ICAClient/selfservice"
elif [[ -x "/opt/Citrix/ICAClient/wfica" ]]; then
  log_ok "Citrix ICA client prêt → /opt/Citrix/ICAClient/wfica"
else
  log_error "Binaire non trouvé — vérifier l'installation"
fi

echo ""
echo "✓ Citrix Workspace App ${CITRIX_VERSION} installé."
echo "  Lancer depuis le menu ou : /opt/Citrix/ICAClient/selfservice"
