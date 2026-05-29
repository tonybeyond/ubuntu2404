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
UBUNTU_VERSION="24.04.2"
UBUNTU_ISO="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
UBUNTU_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/${UBUNTU_ISO}"
SHA256_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/SHA256SUMS"
OUTPUT_ISO="ubuntu-${UBUNTU_VERSION}-autoinstall.iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
WORK_DIR="/tmp/ubuntu-autoinstall-work"
WRITE_USB=false

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
      log_ok "${tool} présent ($(${tool} --version 2>&1 | head -1))"
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
    else die "Gestionnaire de paquets non reconnu. Installer manuellement : ${missing[*]}"
    fi
  fi
  log_ok "Dépendances OK (xorriso $(xorriso --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo '?'))"
}

[[ "${OS_TYPE}" == "macos" ]] && install_deps_macos || install_deps_linux

# ── Télécharger l'ISO Ubuntu ──────────────────────────────────────────────────
log_section "ISO Ubuntu ${UBUNTU_VERSION}"
ISO_PATH="${HOME}/Downloads/${UBUNTU_ISO}"

if [[ -f "${ISO_PATH}" ]]; then
  log_ok "ISO déjà présent : ${ISO_PATH}"
else
  log_info "Téléchargement (~5.9 Go)..."
  log_info "URL : ${UBUNTU_URL}"
  mkdir -p "${HOME}/Downloads"
  wget --progress=bar:force -O "${ISO_PATH}.part" "${UBUNTU_URL}" \
    && mv "${ISO_PATH}.part" "${ISO_PATH}" \
    || die "Téléchargement échoué"
  log_ok "ISO téléchargé"
fi

# ── Vérifier le SHA-256 ───────────────────────────────────────────────────────
log_section "Vérification checksum"
log_info "Récupération SHA256SUMS officiel Ubuntu..."
SHA256_FILE="/tmp/ubuntu-sha256sums"
wget -q -O "${SHA256_FILE}" "${SHA256_URL}" || die "Impossible de récupérer SHA256SUMS"

EXPECTED_SHA=$(grep " ${UBUNTU_ISO}$" "${SHA256_FILE}" | awk '{print $1}')
[[ -n "${EXPECTED_SHA}" ]] || die "Checksum pour ${UBUNTU_ISO} introuvable"

log_info "Calcul du SHA-256 (peut prendre ~30s)..."
if [[ "${OS_TYPE}" == "macos" ]]; then
  ACTUAL_SHA=$(shasum -a 256 "${ISO_PATH}" | awk '{print $1}')
else
  ACTUAL_SHA=$(sha256sum "${ISO_PATH}" | awk '{print $1}')
fi

if [[ "${ACTUAL_SHA}" == "${EXPECTED_SHA}" ]]; then
  log_ok "Checksum OK : ${EXPECTED_SHA:0:16}..."
else
  log_error "Checksum INCORRECT — ISO corrompu ou mauvaise version"
  rm -f "${ISO_PATH}"
  die "Fichier supprimé. Relancer pour re-télécharger."
fi

# ── Préparer le workspace ─────────────────────────────────────────────────────
log_section "Préparation workspace"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# Extraire grub.cfg de l'ISO (sans tout extraire)
log_info "Extraction de grub.cfg..."
xorriso -osirrox on \
  -indev "${ISO_PATH}" \
  -extract /boot/grub/grub.cfg "${WORK_DIR}/grub_orig.cfg" \
  > /dev/null 2>&1 \
  || die "Impossible d'extraire grub.cfg depuis l'ISO"
log_ok "grub.cfg extrait"

# ── Patcher le grub.cfg ───────────────────────────────────────────────────────
log_section "Modification GRUB"

# Réduire le timeout et injecter les params autoinstall
awk '
  /set timeout=[0-9]/ { sub(/set timeout=[0-9]*/, "set timeout=3") }
  /\/casper\/vmlinuz/ && !/autoinstall/ {
    sub(/\/casper\/vmlinuz/, "/casper/vmlinuz autoinstall \"ds=nocloud;s=/cdrom/autoinstall/\"")
  }
  { print }
' "${WORK_DIR}/grub_orig.cfg" > "${WORK_DIR}/grub_patched.cfg"

if grep -q "autoinstall" "${WORK_DIR}/grub_patched.cfg"; then
  log_ok "GRUB patché (autoinstall + timeout=3s)"
else
  log_warn "Pattern vmlinuz non trouvé — vérifier ${WORK_DIR}/grub_patched.cfg"
fi

# ── Construire l'ISO autoinstall ──────────────────────────────────────────────
log_section "Construction de l'ISO autoinstall"
OUTPUT_PATH="${HOME}/Downloads/${OUTPUT_ISO}"
rm -f "${OUTPUT_PATH}"

# Préparer les fichiers à injecter dans une arborescence temporaire
# Structure : refléter les chemins ISO pour un mapping propre
INJECT_DIR="${WORK_DIR}/inject"
mkdir -p "${INJECT_DIR}/autoinstall"

cp "${REPO_DIR}/autoinstall/user-data" "${INJECT_DIR}/autoinstall/user-data"
cp "${REPO_DIR}/autoinstall/meta-data" "${INJECT_DIR}/autoinstall/meta-data"

log_info "Création de l'ISO (~même taille que l'original, peut prendre 2-5 min)..."

# xorriso -indev/-outdev : crée un nouvel ISO basé sur l'original avec modifications
# -overwrite on         : autorise l'écrasement de fichiers existants (grub.cfg)
# -map dir /dir         : ajoute/remplace un répertoire entier dans l'ISO
# -map file /path/file  : ajoute/remplace un fichier spécifique
# -boot_image any replay : préserve TOUTE la structure de boot (BIOS MBR + UEFI EFI)
xorriso \
  -indev "${ISO_PATH}" \
  -outdev "${OUTPUT_PATH}" \
  -overwrite on \
  -map "${INJECT_DIR}/autoinstall" /autoinstall \
  -map "${WORK_DIR}/grub_patched.cfg" /boot/grub/grub.cfg \
  -boot_image any replay \
  2>&1 | grep -v "^xorriso" | grep -v "^$" | tail -8 \
  && log_ok "ISO créé avec succès" \
  || die "Création ISO échouée — voir les messages ci-dessus"

# Nettoyer
rm -rf "${WORK_DIR}"

ISO_SIZE=$(du -sh "${OUTPUT_PATH}" | cut -f1)
printf "\n${GREEN}${BOLD}  ✓ ISO autoinstall prêt !${NC}\n\n"
echo "  Fichier : ${OUTPUT_PATH}"
echo "  Taille  : ${ISO_SIZE}"
echo "  Contenu : autoinstall/user-data · meta-data · grub patché (timeout 3s)"
echo ""

# ── Écriture USB ──────────────────────────────────────────────────────────────
if [[ "${WRITE_USB}" == false ]]; then
  echo "  Pour écrire sur clé USB :"
  if [[ "${OS_TYPE}" == "macos" ]]; then
    echo "    diskutil list                     # Repérer la clé (ex: /dev/disk2)"
    echo "    diskutil unmountDisk /dev/diskN"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/rdiskN bs=1m status=progress"
    echo "    diskutil eject /dev/diskN"
  else
    echo "    lsblk                             # Repérer la clé (ex: /dev/sdb)"
    echo "    sudo dd if=\"${OUTPUT_PATH}\" of=/dev/sdX bs=4M status=progress oflag=sync"
  fi
  echo ""
  echo "  Ou relancer avec --usb : bash scripts/create-iso.sh --usb"
  exit 0
fi

# ── Mode --usb ────────────────────────────────────────────────────────────────
log_section "Écriture sur clé USB"
log_warn "⚠  Cette opération EFFACE DÉFINITIVEMENT le contenu de la clé USB !"
echo ""

if [[ "${OS_TYPE}" == "macos" ]]; then
  echo "  Périphériques externes détectés :"
  diskutil list external physical | grep -E "^/dev|GB|MB" | sed 's/^/    /'
  echo ""
  printf "  Numéro de disque (ex: 2 pour /dev/disk2) : "
  read -r DISK_NUM
  USB_DEVICE="/dev/disk${DISK_NUM}"
  USB_RAW="/dev/rdisk${DISK_NUM}"
else
  echo "  Périphériques disponibles :"
  lsblk -d -p -o NAME,SIZE,TYPE,TRAN 2>/dev/null | sed 's/^/    /'
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
  log_info "Écriture (peut prendre 5-15 min selon la clé)..."
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=1m
  sync
  diskutil eject "${USB_DEVICE}"
else
  log_info "Écriture (peut prendre 5-15 min selon la clé)..."
  sudo dd if="${OUTPUT_PATH}" of="${USB_RAW}" bs=4M status=progress oflag=sync
  sync
fi

printf "\n${GREEN}${BOLD}  ✓ Clé USB prête !${NC}\n\n"
echo "  1. Insérer la clé dans la machine cible"
echo "  2. Démarrer depuis la clé (F12 / F2 / DEL selon BIOS/UEFI)"
echo "  3. L'installation démarre automatiquement (~10-20 min)"
echo "  4. La machine redémarre et est prête"
