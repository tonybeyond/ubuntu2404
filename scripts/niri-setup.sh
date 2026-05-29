#!/usr/bin/env bash
# =============================================================================
# niri-setup.sh — Niri (Wayland compositor) + environnement complet
# Basé sur niri2.sh — mise à jour Brave + robustesse
# Build depuis source (~20 min). Lancer en tant qu'utilisateur normal.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
BOLD='\033[1m'; NC='\033[0m'

log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -ne 0 ]] || { echo "Lancer sans sudo (en tant qu'utilisateur normal)."; exit 1; }

# ── 1. Dépendances système ────────────────────────────────────────────────────
log_section "Dépendances système"
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  build-essential git curl wget pkg-config unzip clang \
  libwayland-dev libxkbcommon-dev libgbm-dev libinput-dev libudev-dev \
  libseat-dev libdisplay-info-dev libpango1.0-dev libglib2.0-dev libxml2-dev \
  libpipewire-0.3-dev libspa-0.2-dev libdbus-1-dev libsystemd-dev libegl1-mesa-dev \
  xdg-desktop-portal-gnome policykit-1-gnome \
  waybar fuzzel swaybg sway-notification-center \
  fonts-noto-color-emoji
log_ok "Dépendances installées"

# ── 2. Rust ───────────────────────────────────────────────────────────────────
log_section "Rust toolchain"
if ! command -v cargo &>/dev/null; then
  log_info "Installation de Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "${HOME}/.cargo/env"
  log_ok "Rust installé"
else
  log_ok "Rust $(rustc --version) déjà présent"
  rustup update stable
fi

# ── 3. Build Niri ─────────────────────────────────────────────────────────────
log_section "Build Niri depuis source (~15-20 min)"
if [[ ! -d "${HOME}/niri-src" ]]; then
  git clone https://github.com/YaLTeR/niri.git "${HOME}/niri-src"
fi
cd "${HOME}/niri-src"
git pull
source "${HOME}/.cargo/env"
cargo build --release
log_ok "Niri compilé"

# Installer les binaires et fichiers de session
sudo cp target/release/niri /usr/local/bin/
sudo cp resources/niri.desktop /usr/share/wayland-sessions/ 2>/dev/null || true
sudo cp resources/niri-session /usr/local/bin/ 2>/dev/null || true
sudo cp resources/niri.service /usr/lib/systemd/user/ 2>/dev/null || true
sudo cp resources/niri-shutdown.target /usr/lib/systemd/user/ 2>/dev/null || true
sudo chmod +x /usr/local/bin/niri*
systemctl --user daemon-reload 2>/dev/null || true
log_ok "Niri installé → /usr/local/bin/niri"

# ── 4. Configs ────────────────────────────────────────────────────────────────
log_section "Configuration Niri + Waybar"

NIRI_DIR="${HOME}/.config/niri"
WAYBAR_DIR="${HOME}/.config/waybar"
FUZZEL_DIR="${HOME}/.config/fuzzel"
SWAYNC_DIR="${HOME}/.config/swaync"
mkdir -p "${NIRI_DIR}" "${WAYBAR_DIR}" "${FUZZEL_DIR}" "${SWAYNC_DIR}"

# ── niri/config.kdl ──────────────────────────────────────────────────────────
cat > "${NIRI_DIR}/config.kdl" << 'KDL'
// Niri — Tony's config
// Clavier ch/fr · Super+HJKL navigation · Ghostty · Brave

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
    focus-ring { off }
    border {
        on
        width 2
        active-gradient from="#89b4fa" to="#cba6f7" angle=45
        inactive-color "#585b70"
    }
}

// Démarrage automatique
spawn-at-startup "waybar"
spawn-at-startup "swaync"
spawn-at-startup "swaybg" "-c" "#1e1e2e"

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

    // Scroll infini
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

# ── 5. Résumé ─────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗\n"
printf "║  Niri installé ✓                                 ║\n"
printf "╠══════════════════════════════════════════════════╣\n"
printf "║  1. Redémarrer : sudo reboot                     ║\n"
printf "║  2. Login → icône engrenage → sélectionner Niri  ║\n"
printf "╠══════════════════════════════════════════════════╣\n"
printf "║  Keybinds :                                      ║\n"
printf "║  Super+Enter  Terminal (Ghostty)                 ║\n"
printf "║  Super+Space  Launcher (Fuzzel)                  ║\n"
printf "║  Super+W      Navigateur (Brave)                 ║\n"
printf "║  Super+HJKL   Navigation Vim                     ║\n"
printf "║  Super+Q      Fermer fenêtre                     ║\n"
printf "╚══════════════════════════════════════════════════╝${NC}\n"
