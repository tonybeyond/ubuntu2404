#!/usr/bin/env bash
# =============================================================================
# create-iso.sh — Crée un ISO Ubuntu 24.04 avec autoinstall intégré
# Compatible : macOS (Intel/Apple Silicon) + Linux (x86_64)
#
# Usage :
#   bash scripts/create-iso.sh              # Crée l'ISO uniquement
#   bash scripts/create-iso.sh --usb        # Crée l'ISO + écrit sur USB
#   bash scripts/create-iso.sh --help
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
UBUNTU_VERSION="24.04.4"
UBUNTU_ISO="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
UBUNTU_BASE_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}"
UBUNTU_URL="${UBUNTU_BASE_URL}/${UBUNTU_ISO}"
SHA256_URL="${UBUNTU_BASE_URL}/SHA256SUMS"
OUTPUT_ISO="ubuntu-${UBUNTU_VERSION}-autoinstall.iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
WORK_DIR="/tmp/ubuntu-autoinstall-work"
WRITE_USB=false

# wget avec timeout et retry (évite les blocages réseau)
WGET="wget --timeout=30 --tries=2 --dns-timeout=10 --connect-timeout=15"

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }
die()         { log_error "$*"; exit 1; }

# ── Aide ──────────────────────────────────────────────────────────────────────
usage() {
  cat << EOF
${BOLD}create-iso.sh${NC} — ISO Ubuntu 24.04 autoinstall

Usage:
  bash scripts/create-iso.sh [OPTIONS]

Options:
  --usb       Écrire l'ISO sur une clé USB après création
  --help      Afficher cette aide

Ce script :
  1. Détecte macOS ou Linux et installe les outils requis
  2. Télécharge Ubuntu ${UBUNTU_VERSION} Desktop (AMD64)
  3. Vérifie le checksum SHA-256 officiel Ubuntu
  4. Intègre autoinstall/user-data + meta-data dans l'ISO
  5. Modifie GRUB pour démarrer en autoinstall automatiquement
  6. (Optionnel) Écrit l'ISO sur une clé USB

⚠  Remplacer le hash de mot de passe dans autoinstall/user-data avant usage !

EOF
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage
[[ "${1:-}" == "--usb"  ]] && WRITE_USB=true

# ── Détecter l'OS ─────────────────────────────────────────────────────────────
log_section "Détection de l'environnement"
OS_TYPE=""
if [[ "$(uname)" == "Darwin" ]]; then
  OS_TYPE="macos"
  ARCH=$(uname -m)
  log_ok "macOS détecté (${ARCH})"
elif [[ "$(uname)" == "Linux" ]]; then
  OS_TYPE="linux"
  log_ok "Linux détecté ($(uname -m))"
else
  die "OS non supporté : $(uname)"
fi

# ── Vérifier les fichiers source ──────────────────────────────────────────────
log_section "Vérification des fichiers source"
[[ -f "${REPO_DIR}/autoinstall/user-data" ]] \
  || die "autoinstall/user-data introuvable. Lancer depuis la racine du repo."
[[ -f "${REPO_DIR}/autoinstall/meta-data" ]] \
  || die "autoinstall/meta-data introuvable."

if grep -q "PLEASE_REPLACE_WITH_REAL_HASH" "${REPO_DIR}/autoinstall/user-data"; then
  log_warn "Le hash du mot de passe dans autoinstall/user-data n'a pas été remplacé !"
  log_warn "Générer un hash : echo 'tonpass' | openssl passwd -6 -stdin"
  printf "  Continuer quand même ? [y/N] "
  read -r answer
  [[ "${answer}" =~ ^[Yy]$ ]] || { log_info "Annulé."; exit 0; }
fi
log_ok "Fichiers autoinstall présents"

# ── Installer les dépendances ─────────────────────────────────────────────────
log_section "Dépendances"
install_deps_macos() {
  if ! command -v brew &>/dev/null; then
    log_info "Installation de Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ "${ARCH}" == "arm64" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    log_ok "Homebrew installé"
  else
    log_ok "Homebrew présent"
  fi
  for tool in xorriso wget; do
    if ! command -v "${tool}" &>/dev/null; then
      log_info "Installation de ${tool}..."
      brew install "${tool}" && log_ok "${tool} installé"
    else
      log_ok "${tool} présent"
    fi
  done
}

install_deps_linux() {
  local missing=()
  command -v xorriso &>/dev/null || missing+=("xorriso")
  command -v wget    &>/dev/null || missing+=("wget")
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_info "Installation : ${missing[*]}"
    if   command -v apt-get &>/dev/null; then sudo apt-get install -y "${missing[@]}"
    elif command -v dnf     &>/dev/null; then sudo dnf install -y "${missing[@]}"
    elif command -v pacman  &>/dev/null; then sudo pacman -S --noconfirm "${missing[@]}"
    else die "Gestionnaire de paquets inconnu. Installer manuellement : ${missing[*]}"
    fi
  fi
  log_ok "Dépendances OK"
}

[[ "${OS_TYPE}" == "macos" ]] && install_deps_macos || install_deps_linux

# ── Gérer l'ISO source ────────────────────────────────────────────────────────
log_section "ISO Ubuntu ${UBUNTU_VERSION}"
ISO_PATH="${HOME}/Downloads/${UBUNTU_ISO}"

# Chercher un ISO 24.04.x existant (y compris des versions antérieures)
EXISTING_ISO=""
if [[ -f "${ISO_PATH}" ]]; then
  EXISTING_ISO="${ISO_PATH}"
else
  # Chercher n'importe quel ISO 24.04.x déjà téléchargé
  EXISTING_ISO=$(find "${HOME}/Downloads" -maxdepth 1 \
    -name "ubuntu-24.04.*-desktop-amd64.iso" 2>/dev/null \
    | sort -V | tail -1 || true)
fi

if [[ -n "${EXISTING_ISO}" && "${EXISTING_ISO}" != "${ISO_PATH}" ]]; then
  log_warn "ISO existant trouvé : $(basename "${EXISTING_ISO}")"
  log_warn "La version cible est : ${UBUNTU_ISO}"
  printf "  Utiliser l'ISO existant plutôt que télécharger 24.04.4 ? [Y/n] "
  read -r use_existing
  if [[ ! "${use_existing}" =~ ^[Nn]$ ]]; then
    ISO_PATH="${EXISTING_ISO}"
    # Extraire la version depuis le nom de fichier
    UBUNTU_VERSION=$(basename "${ISO_PATH}" | grep -oE '24\.[0-9]+\.[0-9]+')
    SHA256_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/SHA256SUMS"
    UBUNTU_ISO=$(basename "${ISO_PATH}")
    OUTPUT_ISO="ubuntu-${UBUNTU_VERSION}-autoinstall.iso"
    log_ok "Utilisation de : $(basename "${ISO_PATH}")"
  fi
fi

if [[ ! -f "${ISO_PATH}" ]]; then
  log_info "Téléchargement Ubuntu ${UBUNTU_VERSION} (~5.9 Go)..."
  log_info "URL : ${UBUNTU_URL}"
  mkdir -p "${HOME}/Downloads"
  ${WGET} --progress=bar:force -O "${ISO_PATH}.part" "${UBUNTU_URL}" \
    && mv "${ISO_PATH}.part" "${ISO_PATH}" \
    || die "Téléchargement échoué"
  log_ok "ISO téléchargé"
else
  log_ok "ISO présent : ${ISO_PATH}"
fi

# ── Vérifier le SHA-256 ───────────────────────────────────────────────────────
log_section "Vérification checksum"
SHA256_FILE="/tmp/ubuntu-sha256sums-${UBUNTU_VERSION}"

# Essayer d'abord releases.ubuntu.com, puis old-releases en fallback
log_info "Récupération SHA256SUMS (${UBUNTU_VERSION})..."
if ! ${WGET} -q -O "${SHA256_FILE}" "${SHA256_URL}" 2>/dev/null; then
  log_warn "releases.ubuntu.com indisponible, essai sur old-releases..."
  ${WGET} -q -O "${SHA256_FILE}" \
    "https://old-releases.ubuntu.com/releases/${UBUNTU_VERSION}/SHA256SUMS" \
    || die "Impossible de récupérer SHA256SUMS depuis les deux sources"
fi

EXPECTED_SHA=$(grep " ${UBUNTU_ISO}$" "${SHA256_FILE}" | awk '{print $1}' || true)
if [[ -z "${EXPECTED_SHA}" ]]; then
  # Essai avec ./ prefix (format alternatif)
  EXPECTED_SHA=$(grep "${UBUNTU_ISO}" "${SHA256_FILE}" | awk '{print $1}' || true)
fi
[[ -n "${EXPECTED_SHA}" ]] || die "Checksum pour ${UBUNTU_ISO} introuvable dans SHA256SUMS"

log_info "Calcul du SHA-256 (peut prendre ~30s)..."
if [[ "${OS_TYPE}" == "macos" ]]; then
  ACTUAL_SHA=$(shasum -a 256 "${ISO_PATH}" | awk '{print $1}')
else
  ACTUAL_SHA=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
fi

if [[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]]; then
  log_ok "Checksum OK : ${EXPECTED_SHA:0:20}..."
else
  log_error "Checksum INCORRECT — ISO corrompu ou mauvaise version"
  die "Supprimer ${ISO_PATH} et relancer pour re-télécharger."
fi

# ── Préparer le workspace ─────────────────────────────────────────────────────
log_section "Préparation workspace"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

log_info "Extraction de grub.cfg depuis l'ISO..."
xorriso -osirrox on \
  -indev "${ISO_PATH}" \
  -extract /boot/grub/grub.cfg "${WORK_DIR}/grub_orig.cfg" \
  > /dev/null 2>&1 \
  || die "Impossible d'extraire grub.cfg — ISO incompatible ?"
log_ok "grub.cfg extrait"

# ── Patcher le grub.cfg ───────────────────────────────────────────────────────
log_section "Modification GRUB"
awk '
  /set timeout=[0-9]/ { sub(/set timeout=[0-9]*/, "set timeout=3") }
  /\/casper\/vmlinuz/ && !/autoinstall/ {
    sub(/\/casper\/vmlinuz/, "/casper/vmlinuz autoinstall \"ds=nocloud;s=/cdrom/autoinstall/\"")
  }
  { print }
' "${WORK_DIR}/grub_orig.cfg" > "${WORK_DIR}/grub_patched.cfg"

if grep -q "autoinstall" "${WORK_DIR}/grub_patched.cfg"; then
  log_ok "GRUB patché (autoinstall injecté, timeout → 3s)"
else
  log_warn "Pattern vmlinuz non trouvé — autoinstall ne démarrera pas automatiquement"
  log_warn "Vérifier : ${WORK_DIR}/grub_patched.cfg"
fi

# ── Construire l'ISO autoinstall ──────────────────────────────────────────────
log_section "Construction de l'ISO autoinstall"
OUTPUT_PATH="${HOME}/Downloads/${OUTPUT_ISO}"
rm -f "${OUTPUT_PATH}"

# Préparer les fichiers à injecter
INJECT_DIR="${WORK_DIR}/inject"
mkdir -p "${INJECT_DIR}/autoinstall"
cp "${REPO_DIR}/autoinstall/user-data" "${INJECT_DIR}/autoinstall/user-data"
cp "${REPO_DIR}/autoinstall/meta-data" "${INJECT_DIR}/autoinstall/meta-data"

log_info "Création de l'ISO (~même taille que l'original, 2-5 min)..."

# xorriso -indev/-outdev : crée un nouvel ISO basé sur l'original avec modifications
# -overwrite on         : autorise l'écrasement des fichiers existants (grub.cfg)
# -map dir /dir         : injecte un dossier dans l'ISO
# -map file /path       : injecte/remplace un fichier
# -boot_image any replay: préserve TOUTE la structure boot (BIOS MBR + UEFI EFI)
xorriso \
  -indev  "${ISO_PATH}" \
  -outdev "${OUTPUT_PATH}" \
  -overwrite on \
  -map "${INJECT_DIR}/autoinstall" /autoinstall \
  -map "${WORK_DIR}/grub_patched.cfg" /boot/grub/grub.cfg \
  -boot_image any replay \
  2>&1 | grep -Ev "^(xorriso|$)" | tail -8 \
  && log_ok "ISO construit" \
  || die "Construction ISO échouée — voir les messages ci-dessus"

rm -rf "${WORK_DIR}"

ISO_SIZE=$(du -sh "${OUTPUT_PATH}" | cut -f1)
printf "\n${GREEN}${BOLD}  ✓ ISO autoinstall prêt !${NC}\n\n"
echo "  Fichier : ${OUTPUT_PATH}"
echo "  Taille  : ${ISO_SIZE}"
echo "  Contenu : /autoinstall/{user-data,meta-data} · grub patché (timeout 3s)"
echo ""

# ── Sans --usb : instructions manuelles ──────────────────────────────────────
if [[ "${WRITE_USB}" == false ]]; then
  echo "  Pour écrire sur clé USB :"
  if [[ "${OS_TYPE}" == "macos" ]]; then
    echo "    diskutil list                             # Identifier la clé (ex: /dev/disk2)"
    echo "    diskutil unmountDisk /dev/diskN"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/rdiskN bs=1m"
    echo "    diskutil eject /dev/diskN"
  else
    echo "    lsblk                                     # Identifier la clé (ex: /dev/sdb)"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/sdX bs=4M status=progress oflag=sync"
  fi
  echo ""
  echo "  Ou : bash scripts/create-iso.sh --usb"
  exit 0
fi

# ── Mode --usb ────────────────────────────────────────────────────────────────
log_section "Écriture sur clé USB"
log_warn "⚠  Cette opération EFFACE le contenu de la clé USB sélectionnée !"
echo ""

if [[ "${OS_TYPE}" == "macos" ]]; then
  echo "  Périphériques externes :"
  diskutil list external physical 2>/dev/null | grep -E "^/dev|GB|MB" | sed 's/^/    /' || true
  echo ""
  printf "  Numéro de disque (ex: 2 pour /dev/disk2) : "
  read -r DISK_NUM
  USB_DEVICE="/dev/disk${DISK_NUM}"
  USB_RAW="/dev/rdisk${DISK_NUM}"
else
  echo "  Périphériques :"
  lsblk -d -p -o NAME,SIZE,TYPE,TRAN 2>/dev/null | sed 's/^/    /' || true
  echo ""
  printf "  Chemin de la clé USB (ex: /dev/sdb) : "
  read -r USB_DEVICE
  USB_RAW="${USB_DEVICE}"
fi

echo ""
log_warn "CIBLE  : ${USB_DEVICE}"
log_warn "SOURCE : ${OUTPUT_PATH}"
echo ""
printf "${RED}${BOLD}  CONFIRMER ? Tout le contenu sera perdu. [oui/NON] : ${NC}"
read -r confirm
[[ "${confirm}" == "oui" ]] || { log_info "Annulé."; exit 0; }

if [[ "${OS_TYPE}" == "macos" ]]; then
  log_info "Démontage de ${USB_DEVICE}..."
  diskutil unmountDisk "${USB_DEVICE}"
  log_info "Écriture (5-15 min selon la clé)..."
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=1m
  sync
  diskutil eject "${USB_DEVICE}"
else
  log_info "Écriture (5-15 min selon la clé)..."
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=4M status=progress oflag=sync
  sync
fi

printf "\n${GREEN}${BOLD}  ✓ Clé USB prête.${NC}\n\n"
echo "  1. Insérer la clé dans la machine cible"
echo "  2. Démarrer depuis la clé (F12 / F2 / DEL selon BIOS/UEFI)"
echo "  3. Installation automatique (~15-20 min)"
echo "  4. Reboot → machine prête"
