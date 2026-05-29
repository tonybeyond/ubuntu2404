#!/usr/bin/env bash
# =============================================================================
# post-install.sh — Setup système Ubuntu 24.04
# =============================================================================
# Appelé automatiquement par autoinstall (late-commands, root, chroot).
# Peut aussi être lancé manuellement : sudo bash /opt/ubuntu2404/scripts/post-install.sh
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
TARGET_USER="${SUDO_USER:-tony}"
TARGET_HOME="/home/${TARGET_USER}"
REPO_DIR="/opt/ubuntu2404"
LOG_FILE="/var/log/ubuntu2404-setup.log"
ERROR_COUNT=0

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo "[$(date +'%H:%M:%S')] ·     $*" | tee -a "${LOG_FILE}"; }
log_ok()      { echo "[$(date +'%H:%M:%S')] ✓     $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo "[$(date +'%H:%M:%S')] ✗     $*" | tee -a "${LOG_FILE}" >&2; ((ERROR_COUNT++)) || true; }
log_section() { echo "" | tee -a "${LOG_FILE}"; echo "[$(date +'%H:%M:%S')] ════ $* ════" | tee -a "${LOG_FILE}"; }

is_installed() { dpkg -s "$1" &>/dev/null; }
apt_install() {
  for pkg in "$@"; do
    is_installed "$pkg" || apt install -y "$pkg" 2>>"${LOG_FILE}" \
      && log_ok "apt: $pkg" || log_error "apt: $pkg FAILED"
  done
}

[[ $EUID -eq 0 ]] || { echo "Requiert root (sudo)."; exit 1; }
mkdir -p "$(dirname "${LOG_FILE}")"
log_info "=== ubuntu2404 post-install — $(date) ==="
log_info "Utilisateur cible : ${TARGET_USER}"

# ── 1. APT update ─────────────────────────────────────────────────────────────
log_section "Mise à jour système"
apt update -q && apt upgrade -y || log_error "apt update/upgrade"

# ── 2. Suppression du bloat ───────────────────────────────────────────────────
log_section "Suppression bloat"
BLOAT=(gnome-games evolution cheese gnome-maps gnome-music gnome-sound-recorder
       rhythmbox gnome-weather gnome-clocks gnome-contacts gnome-characters)
for pkg in "${BLOAT[@]}"; do
  is_installed "$pkg" && apt remove -y "$pkg" && log_ok "Retiré : $pkg" || true
done
mapfile -t TB < <(apt list --installed 2>/dev/null | grep -i thunderbird | awk -F/ '{print $1}' || true)
mapfile -t LO < <(apt list --installed 2>/dev/null | grep -i libreoffice | awk -F/ '{print $1}' || true)
[[ ${#TB[@]} -gt 0 ]] && apt remove -y "${TB[@]}" || true
[[ ${#LO[@]} -gt 0 ]] && apt remove -y "${LO[@]}" || true
apt autoremove --purge -y && apt autoclean

# ── 3. Paquets principaux ─────────────────────────────────────────────────────
log_section "Paquets principaux"
apt_install \
  curl git wget build-essential unzip gnupg ca-certificates apt-transport-https \
  zsh fzf eza bat btop hyfetch nala vlc xclip flameshot \
  gnome-tweaks gnome-shell-extension-appindicator gnome-shell-extension-manager \
  gimagereader tesseract-ocr tesseract-ocr-fra tesseract-ocr-eng \
  gawk bash-completion node-typescript \
  ninja-build cmake gettext

# ── 4. Locale fr_CH ───────────────────────────────────────────────────────────
log_section "Locale"
if grep -q "# fr_CH.UTF" /etc/locale.gen 2>/dev/null; then
  sed -i 's/# fr_CH.UTF/fr_CH.UTF/' /etc/locale.gen
  locale-gen && log_ok "Locale fr_CH.UTF-8 activée"
fi

# ── 5. Ghostty ────────────────────────────────────────────────────────────────
log_section "Ghostty"
if ! command -v ghostty &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)" \
    && log_ok "Ghostty installé" || log_error "Ghostty install"
else
  log_ok "Ghostty déjà présent"
fi
mkdir -p "${TARGET_HOME}/.config/ghostty"
if [[ -f "${REPO_DIR}/configs/ghostty/config" ]]; then
  cp "${REPO_DIR}/configs/ghostty/config" "${TARGET_HOME}/.config/ghostty/config"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/ghostty"
  log_ok "Config Ghostty déployée"
fi

# ── 6. Brave browser ──────────────────────────────────────────────────────────
log_section "Brave Browser"
if ! command -v brave-browser &>/dev/null; then
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
  apt update -q && apt install -y brave-browser \
    && log_ok "Brave installé" || log_error "Brave install"
else
  log_ok "Brave déjà présent"
fi

# ── 7. Neovim (depuis source) ─────────────────────────────────────────────────
log_section "Neovim"
if ! command -v nvim &>/dev/null; then
  BUILD_DIR="/tmp/neovim-build"
  [[ -d "${BUILD_DIR}" ]] || \
    git clone https://github.com/neovim/neovim.git --branch=stable --depth=1 "${BUILD_DIR}"
  cd "${BUILD_DIR}"
  make CMAKE_BUILD_TYPE=RelWithDebInfo 2>>"${LOG_FILE}"
  cd build && cpack -G DEB
  DEB=$(find . -name 'nvim-linux*.deb' | head -n1)
  [[ -n "${DEB}" ]] && dpkg -i "${DEB}" && log_ok "Neovim installé" || log_error "Neovim build"
  cd /tmp
else
  log_ok "Neovim déjà présent"
fi
NVIM_CONF="${TARGET_HOME}/.config/nvim"
if [[ ! -d "${NVIM_CONF}" ]]; then
  sudo -u "${TARGET_USER}" git clone \
    https://github.com/nvim-lua/kickstart.nvim.git "${NVIM_CONF}" \
    && log_ok "kickstart.nvim déployé" || log_error "kickstart.nvim clone"
fi

# ── 8. Oh My Zsh + plugins ────────────────────────────────────────────────────
log_section "Oh My Zsh"
if [[ ! -d "${TARGET_HOME}/.oh-my-zsh" ]]; then
  sudo -u "${TARGET_USER}" HOME="${TARGET_HOME}" \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended && log_ok "Oh My Zsh installé" || log_error "Oh My Zsh install"
fi

ZSH_PLUGINS="${TARGET_HOME}/.oh-my-zsh/custom/plugins"
mkdir -p "${ZSH_PLUGINS}"
declare -A PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
  ["zsh-autocomplete"]="https://github.com/marlonrichert/zsh-autocomplete.git"
)
for name in "${!PLUGINS[@]}"; do
  [[ -d "${ZSH_PLUGINS}/${name}" ]] || \
    sudo -u "${TARGET_USER}" git clone "${PLUGINS[$name]}" "${ZSH_PLUGINS}/${name}" \
    && log_ok "Plugin: ${name}" || log_error "Plugin: ${name}"
done

# Déployer .zshrc (exa → eza corrigé)
if [[ -f "${REPO_DIR}/configs/zshrc" ]]; then
  sed 's/exa /eza /g; s/exa -/eza -/g' "${REPO_DIR}/configs/zshrc" > "${TARGET_HOME}/.zshrc"
  chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.zshrc"
  log_ok ".zshrc déployé"
fi
chsh -s "$(which zsh)" "${TARGET_USER}" && log_ok "zsh shell par défaut"

# ── 9. Citrix Workspace ───────────────────────────────────────────────────────
log_section "Citrix Workspace"
if [[ -x "${REPO_DIR}/scripts/citrix-setup.sh" ]]; then
  bash "${REPO_DIR}/scripts/citrix-setup.sh" && log_ok "Citrix installé" \
    || log_error "Citrix SKIPPED — lancer manuellement : bash /opt/ubuntu2404/scripts/citrix-setup.sh"
fi

# ── 10. Niri (Wayland WM, depuis source) ─────────────────────────────────────
log_section "Niri WM"
if ! command -v niri &>/dev/null; then
  if [[ -x "${REPO_DIR}/scripts/niri-setup.sh" ]]; then
    sudo -u "${TARGET_USER}" HOME="${TARGET_HOME}" \
      bash "${REPO_DIR}/scripts/niri-setup.sh" \
      && log_ok "Niri installé" \
      || log_error "Niri FAILED — relancer manuellement : bash /opt/ubuntu2404/scripts/niri-setup.sh"
  fi
else
  log_ok "Niri déjà présent"
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ubuntu2404 post-install — TERMINÉ                  ║"
printf "║  Erreurs : %-3d                                       ║\n" "${ERROR_COUNT}"
echo "║  Log : ${LOG_FILE}"
if [[ ${ERROR_COUNT} -eq 0 ]]; then
echo "║  Statut : ✓ Tout OK                                  ║"
else
echo "║  Statut : ⚠ Vérifier le log                         ║"
fi
echo "╚══════════════════════════════════════════════════════╝"
