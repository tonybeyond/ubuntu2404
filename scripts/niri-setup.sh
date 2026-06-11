#!/usr/bin/env bash
# =============================================================================
# niri-setup.sh — Niri (Wayland compositor) + Waybar + Fuzzel
# Compatible : Ubuntu 24.04 + Debian 13 Trixie (et RefreshOS 3)
# Build depuis source, dernier tag stable (~15-20 min).
# Lancer en tant qu'utilisateur normal (PAS sudo).
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -ne 0 ]] || { echo "Lancer sans sudo (en tant qu'utilisateur normal)."; exit 1; }

# ── 1. Dépendances système ────────────────────────────────────────────────────
log_section "Dépendances système"
sudo apt update

# Installation paquet par paquet : un paquet manquant ne bloque pas le reste
# (ex: policykit-1-gnome retiré de Debian Trixie)
PKGS=(
  build-essential git curl wget pkg-config unzip clang
  libwayland-dev libxkbcommon-dev libgbm-dev libinput-dev libudev-dev
  libseat-dev libdisplay-info-dev libpango1.0-dev libglib2.0-dev libxml2-dev
  libpipewire-0.3-dev libspa-0.2-dev libdbus-1-dev libsystemd-dev libegl1-mesa-dev
  xdg-desktop-portal-gtk xwayland
  waybar fuzzel swaybg sway-notification-center
  pavucontrol fonts-noto-color-emoji
)
FAILED_PKGS=()
for pkg in "${PKGS[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    continue
  elif sudo apt install -y "$pkg" &>/dev/null; then
    log_ok "apt: $pkg"
  else
    log_warn "apt: $pkg indisponible — skipped"
    FAILED_PKGS+=("$pkg")
  fi
done

# Polkit agent : policykit-1-gnome (Ubuntu) retiré de Debian Trixie → mate-polkit
if sudo apt install -y policykit-1-gnome &>/dev/null; then
  log_ok "Polkit agent : policykit-1-gnome"
elif sudo apt install -y mate-polkit &>/dev/null; then
  log_ok "Polkit agent : mate-polkit (Trixie)"
else
  log_warn "Aucun polkit agent installé — l'élévation GUI ne fonctionnera pas dans Niri"
fi

[[ ${#FAILED_PKGS[@]} -eq 0 ]] && log_ok "Toutes les dépendances installées" \
  || log_warn "Paquets manquants : ${FAILED_PKGS[*]}"

# ── xwayland-satellite : OBLIGATOIRE pour les apps X11 (Citrix, etc.) ─────────
# Niri n'embarque pas XWayland — sans satellite, aucune app X11 ne se lance.
# Niri >= 25.08 le détecte et le lance automatiquement s'il est dans le PATH.
log_section "xwayland-satellite (support apps X11 : Citrix...)"
if command -v xwayland-satellite &>/dev/null; then
  log_ok "xwayland-satellite déjà présent"
elif sudo apt install -y xwayland-satellite &>/dev/null; then
  log_ok "xwayland-satellite installé (apt)"
else
  log_info "Paquet apt absent — build cargo (~5 min)..."
  # Dépendances de build
  for p in libxcb1-dev libxcb-cursor-dev libxcb-res0-dev; do
    sudo apt install -y "$p" &>/dev/null || true
  done
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env" 2>/dev/null || true
  if command -v cargo &>/dev/null; then
    cargo install --git https://github.com/Supreeeme/xwayland-satellite \
      --locked 2>/dev/null \
      && sudo cp "${HOME}/.cargo/bin/xwayland-satellite" /usr/local/bin/ \
      && log_ok "xwayland-satellite buildé → /usr/local/bin" \
      || log_warn "Build xwayland-satellite échoué — les apps X11 (Citrix) ne marcheront pas dans Niri"
  else
    log_warn "cargo absent à ce stade — relancer le script après l'étape Rust"
  fi
fi

# ── 2. Rust ───────────────────────────────────────────────────────────────────
log_section "Rust toolchain"
if ! command -v cargo &>/dev/null && [[ ! -f "${HOME}/.cargo/env" ]]; then
  log_info "Installation de Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  log_ok "Rust installé"
fi
# shellcheck disable=SC1091
source "${HOME}/.cargo/env" 2>/dev/null || true
command -v cargo &>/dev/null || { log_error "cargo introuvable après install Rust"; exit 1; }
log_ok "Rust : $(rustc --version)"

# ── 3. Build Niri (dernier tag stable, pas main) ──────────────────────────────
log_section "Build Niri depuis source (~15-20 min)"
if [[ ! -d "${HOME}/niri-src" ]]; then
  git clone https://github.com/YaLTeR/niri.git "${HOME}/niri-src"
fi
cd "${HOME}/niri-src"
git fetch --tags

# Checkout du dernier tag stable — main peut être cassé
LATEST_TAG=$(git tag --sort=-version:refname | head -n1)
if [[ -n "${LATEST_TAG}" ]]; then
  git checkout "${LATEST_TAG}" 2>/dev/null
  log_ok "Version : ${LATEST_TAG} (dernier tag stable)"
else
  log_warn "Aucun tag trouvé — build depuis main"
  git pull
fi

cargo build --release
log_ok "Niri compilé"

# ── 4. Installation des binaires + fichiers de session ───────────────────────
log_section "Installation"
sudo cp target/release/niri /usr/local/bin/
sudo cp resources/niri-session /usr/local/bin/ 2>/dev/null || true
sudo chmod +x /usr/local/bin/niri /usr/local/bin/niri-session 2>/dev/null || true

# niri.desktop : session GDM/SDDM
sudo mkdir -p /usr/share/wayland-sessions
sudo cp resources/niri.desktop /usr/share/wayland-sessions/ 2>/dev/null || true

# ⚠ FIX CRITIQUE : niri.service upstream pointe /usr/bin/niri
# mais on installe dans /usr/local/bin → la session échouerait au démarrage
sudo mkdir -p /usr/lib/systemd/user
if [[ -f resources/niri.service ]]; then
  sed 's|/usr/bin/niri|/usr/local/bin/niri|g' resources/niri.service \
    | sudo tee /usr/lib/systemd/user/niri.service >/dev/null
  log_ok "niri.service installé (ExecStart corrigé → /usr/local/bin)"
fi
sudo cp resources/niri-shutdown.target /usr/lib/systemd/user/ 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true
log_ok "Niri installé → /usr/local/bin/niri"

# ── 5. Configs ────────────────────────────────────────────────────────────────
log_section "Configuration Niri + Waybar + Fuzzel"

NIRI_DIR="${HOME}/.config/niri"
WAYBAR_DIR="${HOME}/.config/waybar"
FUZZEL_DIR="${HOME}/.config/fuzzel"
mkdir -p "${NIRI_DIR}" "${WAYBAR_DIR}" "${FUZZEL_DIR}"

# Backup d'une config existante
[[ -f "${NIRI_DIR}/config.kdl" ]] \
  && cp "${NIRI_DIR}/config.kdl" "${NIRI_DIR}/config.kdl.bak-$(date +%Y%m%d-%H%M%S)"

# ── niri/config.kdl ──────────────────────────────────────────────────────────
# Syntaxe KDL valide : nodes terminés par ; ou newline.
# border : la présence de la section l'active (pas de node "on").
cat > "${NIRI_DIR}/config.kdl" << 'KDL'
// Niri — config générée par niri-setup.sh
// Clavier ch/fr · Super+HJKL · Ghostty · Brave · Catppuccin Mocha

input {
    keyboard {
        xkb {
            layout "ch"
            variant "fr"
        }
    }
    touchpad {
        tap
        natural-scroll
    }
}

layout {
    gaps 16
    center-focused-column "never"
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
    default-column-width { proportion 0.5; }
    focus-ring {
        off
    }
    border {
        width 2
        active-gradient from="#89b4fa" to="#cba6f7" angle=45
        inactive-color "#585b70"
    }
}

// Guards pgrep : évite les doublons si une unit systemd lance déjà ces services
spawn-at-startup "sh" "-c" "pgrep -x waybar || exec waybar"
spawn-at-startup "sh" "-c" "pgrep -x swaync || exec swaync"
spawn-at-startup "sh" "-c" "pgrep -x swaybg || exec swaybg -c '#1e1e2e'"

binds {
    Mod+Shift+Slash { show-hotkey-overlay; }

    // Applications
    Mod+Return { spawn "ghostty"; }
    Mod+Space  { spawn "fuzzel"; }
    Mod+W      { spawn "brave-browser"; }
    Print      { screenshot; }

    // Session
    Mod+Q       { close-window; }
    Mod+Shift+E { quit; }

    // Navigation Vim
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    // Déplacement
    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }

    // Largeur de colonne
    Mod+R     { switch-preset-column-width; }
    Mod+F     { maximize-column; }
    Mod+Shift+F { fullscreen-window; }

    // Scroll
    Mod+WheelScrollDown { focus-column-right; }
    Mod+WheelScrollUp   { focus-column-left; }
}
KDL

# ── waybar/config ─────────────────────────────────────────────────────────────
cat > "${WAYBAR_DIR}/config" << 'JSON'
{
    "layer": "top",
    "position": "top",
    "height": 34,
    "margin-top": 10,
    "margin-left": 10,
    "margin-right": 10,
    "modules-left": ["niri/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["cpu", "memory", "pulseaudio", "battery", "custom/notification"],
    "niri/workspaces": {
        "format": "{icon}",
        "format-icons": { "default": "", "active": "" }
    },
    "clock":   { "format": "{:%H:%M  %a %d %b}" },
    "cpu":     { "format": " {usage}%", "interval": 5 },
    "memory":  { "format": " {}%",     "interval": 10 },
    "pulseaudio": { "format": " {volume}%", "on-click": "pavucontrol" },
    "battery": { "format": " {capacity}%" },
    "custom/notification": {
        "tooltip": false,
        "format": "",
        "on-click": "swaync-client -t -sw"
    }
}
JSON

# ── waybar/style.css ──────────────────────────────────────────────────────────
cat > "${WAYBAR_DIR}/style.css" << 'CSS'
* {
    border: none;
    font-family: "Hack Nerd Font Mono", "Symbols Nerd Font", sans-serif;
    font-size: 13px;
    font-weight: bold;
}
window#waybar { background: transparent; }
.modules-left, .modules-center, .modules-right {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 2px 12px;
    border: 1px solid #45475a;
    color: #cdd6f4;
    margin: 0 4px;
}
#clock     { color: #cba6f7; }
#cpu       { color: #89b4fa; }
#memory    { color: #a6e3a1; }
#pulseaudio{ color: #f9e2af; }
#battery   { color: #fab387; }
#workspaces button         { color: #585b70; padding: 0 6px; }
#workspaces button.active  { color: #cba6f7; }
#workspaces button:hover   { background: #313244; }
CSS

# ── fuzzel/fuzzel.ini ─────────────────────────────────────────────────────────
cat > "${FUZZEL_DIR}/fuzzel.ini" << 'INI'
[main]
font=Hack Nerd Font Mono:size=13
prompt=❯ 
terminal=ghostty
width=42
horizontal-pad=40
vertical-pad=20
inner-pad=10

[colors]
background=1e1e2edd
text=cdd6f4ff
match=cba6f7ff
selection=585b70ff
selection-text=cdd6f4ff
border=cba6f7ff
INI

log_ok "Configs Niri, Waybar, Fuzzel générées"

# Masquer les units systemd user waybar/swaync : elles seraient lancées par
# graphical-session.target en plus de notre spawn-at-startup → barre en double
systemctl --user mask waybar.service 2>/dev/null || true
systemctl --user mask sway-notification-center.service 2>/dev/null || true
log_ok "Units systemd waybar/swaync masquées (anti-doublon)"

# ── 6. Validation de la config ────────────────────────────────────────────────
log_section "Validation"
if /usr/local/bin/niri validate 2>/dev/null; then
  log_ok "config.kdl valide (niri validate)"
else
  log_warn "niri validate a signalé un problème — vérifier ~/.config/niri/config.kdl"
  /usr/local/bin/niri validate || true
fi

# ── 7. Résumé ─────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗\n"
printf "║  Niri installé ✓                                 ║\n"
printf "╠══════════════════════════════════════════════════╣\n"
printf "║  1. Redémarrer : sudo reboot                     ║\n"
printf "║  2. Écran de login → sélectionner session Niri   ║\n"
printf "╠══════════════════════════════════════════════════╣\n"
printf "║  Keybinds :                                      ║\n"
printf "║  Super+Enter  Terminal (Ghostty)                 ║\n"
printf "║  Super+Space  Launcher (Fuzzel)                  ║\n"
printf "║  Super+W      Navigateur (Brave)                 ║\n"
printf "║  Super+HJKL   Navigation Vim                     ║\n"
printf "║  Super+R      Cycle largeur colonne              ║\n"
printf "║  Super+Q      Fermer fenêtre                     ║\n"
printf "║  Super+Shift+/  Aide raccourcis                  ║\n"
printf "╚══════════════════════════════════════════════════╝${NC}\n"
