#!/usr/bin/env bash
# =============================================================================
# niri-setup.sh — Niri (Wayland) façon CachyOS, adapté Debian 13 Trixie
# =============================================================================
# Réplique la configuration CachyOS (cachyos-niri-settings) avec adaptations :
#   waveterm, brave-origin (firefox), fuzzel (wofi), swaybg (swww),
#   Catppuccin Mocha (Nord), swaync (mako).
# Sources : github.com/CachyOS/cachyos-niri-settings
#           wiki.cachyos.org/configuration/desktop_environments/niri/
#
# Lancer SANS sudo (utilisateur normal) :
#   bash /opt/debiantrixie/scripts/niri-setup.sh
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*"; }

[[ $EUID -ne 0 ]] || { echo "Lancer SANS sudo (utilisateur normal)."; exit 1; }

# ── 1. Dépendances ────────────────────────────────────────────────────────────
log_section "Dépendances système"
sudo apt update
PKGS=(
  build-essential git curl wget pkg-config unzip clang
  libwayland-dev libxkbcommon-dev libgbm-dev libinput-dev libudev-dev
  libseat-dev libdisplay-info-dev libpango1.0-dev libglib2.0-dev libxml2-dev
  libpipewire-0.3-dev libspa-0.2-dev libdbus-1-dev libsystemd-dev libegl1-mesa-dev
  xdg-desktop-portal-gtk
  waybar fuzzel swaybg sway-notification-center
  swaylock playerctl pavucontrol
  fonts-noto-color-emoji
)
FAILED=()
for pkg in "${PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null && continue
  sudo apt install -y "$pkg" &>/dev/null \
    && log_ok "apt: $pkg" || { log_warn "apt: $pkg — skipped"; FAILED+=("$pkg"); }
done

# polkit : kde → gnome en fallback
if sudo apt install -y polkit-kde-agent-1 &>/dev/null; then
  log_ok "polkit-kde-agent-1"
elif sudo apt install -y policykit-1-gnome &>/dev/null; then
  log_ok "policykit-1-gnome (fallback)"
elif sudo apt install -y mate-polkit &>/dev/null; then
  log_ok "mate-polkit (fallback)"
else
  log_warn "Aucun polkit agent — élévation GUI désactivée"
fi

[[ ${#FAILED[@]} -eq 0 ]] && log_ok "Dépendances OK" \
  || log_warn "Paquets manquants : ${FAILED[*]}"

# ── 2. xwayland-satellite ─────────────────────────────────────────────────────
log_section "xwayland-satellite (apps X11 : Citrix…)"
if command -v xwayland-satellite &>/dev/null; then
  log_ok "xwayland-satellite présent"
elif sudo apt install -y xwayland-satellite &>/dev/null; then
  log_ok "xwayland-satellite installé (apt)"
else
  log_info "Build depuis cargo (~5 min)…"
  for p in libxcb1-dev libxcb-cursor-dev libxcb-res0-dev xwayland; do
    sudo apt install -y "$p" &>/dev/null || true
  done
  source "${HOME}/.cargo/env" 2>/dev/null || true
  if command -v cargo &>/dev/null; then
    cargo install --git https://github.com/Supreeeme/xwayland-satellite --locked &>/dev/null \
      && sudo cp "${HOME}/.cargo/bin/xwayland-satellite" /usr/local/bin/ \
      && log_ok "xwayland-satellite buildé" \
      || log_warn "Build échoué — apps X11 non disponibles dans Niri"
  else
    log_warn "cargo absent — installer Rust d'abord (étape 3)"
  fi
fi

# ── 3. Rust ───────────────────────────────────────────────────────────────────
log_section "Rust toolchain"
if ! command -v cargo &>/dev/null && [[ ! -f "${HOME}/.cargo/env" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
source "${HOME}/.cargo/env" 2>/dev/null || true
command -v cargo &>/dev/null || { log_error "cargo introuvable"; exit 1; }
log_ok "Rust : $(rustc --version)"

# ── 4. Build Niri ─────────────────────────────────────────────────────────────
log_section "Build Niri (dernier tag stable)"
[[ -d "${HOME}/niri-src" ]] || git clone https://github.com/YaLTeR/niri.git "${HOME}/niri-src"
cd "${HOME}/niri-src"
git fetch --tags
LATEST_TAG=$(git tag --sort=-version:refname | head -n1)
[[ -n "${LATEST_TAG}" ]] && git checkout "${LATEST_TAG}" 2>/dev/null \
  && log_ok "Version : ${LATEST_TAG}" || { git pull; log_warn "Build depuis main"; }
cargo build --release
log_ok "Niri compilé"

# ── 5. Installation binaires + session ────────────────────────────────────────
log_section "Installation"
sudo install -m755 target/release/niri /usr/local/bin/niri
[[ -f resources/niri-session ]] && sudo install -m755 resources/niri-session /usr/local/bin/niri-session
sudo mkdir -p /usr/share/wayland-sessions
[[ -f resources/niri.desktop ]] && sudo cp resources/niri.desktop /usr/share/wayland-sessions/
sudo mkdir -p /usr/lib/systemd/user
[[ -f resources/niri.service ]] && \
  sed 's|/usr/bin/niri|/usr/local/bin/niri|g' resources/niri.service \
  | sudo tee /usr/lib/systemd/user/niri.service >/dev/null
[[ -f resources/niri-shutdown.target ]] && \
  sudo cp resources/niri-shutdown.target /usr/lib/systemd/user/
systemctl --user daemon-reload 2>/dev/null || true
log_ok "Niri → /usr/local/bin/niri"

# ── 6. Répertoires de configuration ───────────────────────────────────────────
log_section "Configuration (style CachyOS — Catppuccin Mocha)"
NIRI_DIR="${HOME}/.config/niri"
WAYBAR_DIR="${HOME}/.config/waybar"
FUZZEL_DIR="${HOME}/.config/fuzzel"
SWAYLOCK_DIR="${HOME}/.config/swaylock"
SCREENSHOTS_DIR="${HOME}/Pictures/Screenshots"

mkdir -p "${NIRI_DIR}" "${WAYBAR_DIR}/scripts" "${FUZZEL_DIR}" \
         "${SWAYLOCK_DIR}" "${SCREENSHOTS_DIR}"

# Backup config existante
[[ -f "${NIRI_DIR}/config.kdl" ]] && \
  cp "${NIRI_DIR}/config.kdl" "${NIRI_DIR}/config.kdl.bak-$(date +%Y%m%d-%H%M%S)"

# Détecter le polkit agent disponible
POLKIT_BIN=""
for candidate in \
  "/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1" \
  "/usr/lib/polkit-kde-authentication-agent-1" \
  "/usr/libexec/polkit-kde-authentication-agent-1" \
  "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1" \
  "/usr/lib/mate-polkit/polkit-mate-authentication-agent-1"; do
  [[ -x "${candidate}" ]] && POLKIT_BIN="${candidate}" && break
done
[[ -z "${POLKIT_BIN}" ]] && log_warn "polkit agent non trouvé — certaines opérations root échoueront" \
  || log_ok "polkit : ${POLKIT_BIN}"

# ── 7. config.kdl — CachyOS style, adapté Debian ─────────────────────────────
cat > "${NIRI_DIR}/config.kdl" << KDLEOF
// Niri — style CachyOS (cachyos-niri-settings), adapté Debian 13 Trixie
// Ref: github.com/CachyOS/cachyos-niri-settings
// Clavier : ch/fr | Terminal : waveterm | Browser : brave-origin | Launcher : fuzzel

// ────────────── Input ──────────────────────────────────────────────────────────
input {
    keyboard {
        xkb {
            layout "ch"
            variant "fr"
        }
        numlock                      // NumLock activé au démarrage (CachyOS)
    }
    touchpad {
        tap                          // Tap-to-click
        natural-scroll               // Défilement naturel (macOS-style)
    }
    focus-follows-mouse              // Focus suit la souris (CachyOS)
    workspace-auto-back-and-forth    // Workspace back & forth (CachyOS)
}

// ────────────── Outputs ────────────────────────────────────────────────────────
// Décommenter et adapter avec : niri msg outputs
/- output "DP-1" {
    mode "2560x1440@144"
    scale 1
}

// ────────────── Keybinds (complets, style CachyOS) ────────────────────────────
binds {
    // ─ Hotkey overlay ─
    Mod+Shift+Escape { show-hotkey-overlay; }

    // ─ Applications ─
    Mod+Return hotkey-overlay-title="Terminal : waveterm" {
        spawn "waveterm";
    }
    Mod+Space hotkey-overlay-title="Launcher : fuzzel" {
        spawn "fuzzel";
    }
    Mod+B hotkey-overlay-title="Browser : brave" {
        spawn "sh" "-c" "exec \$(command -v brave-origin || command -v brave-browser)";
    }
    Mod+E hotkey-overlay-title="Files : nautilus" {
        spawn "nautilus";
    }
    Mod+Alt+L hotkey-overlay-title="Lock screen : swaylock" {
        spawn "swaylock";
    }

    // ─ Audio (allow-when-locked : fonctionne même en veille) ─
    XF86AudioRaiseVolume allow-when-locked=true {
        spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+";
    }
    XF86AudioLowerVolume allow-when-locked=true {
        spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-";
    }
    XF86AudioMute allow-when-locked=true {
        spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
    }
    XF86AudioMicMute allow-when-locked=true {
        spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle";
    }
    XF86AudioNext  allow-when-locked=true { spawn "playerctl" "next"; }
    XF86AudioPrev  allow-when-locked=true { spawn "playerctl" "previous"; }
    XF86AudioPlay  allow-when-locked=true { spawn "playerctl" "play-pause"; }
    XF86AudioPause allow-when-locked=true { spawn "playerctl" "play-pause"; }

    // ─ Luminosité ─
    XF86MonBrightnessUp   { spawn "brightnessctl" "set" "10%+"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "10%-"; }

    // ─ Fenêtres ─
    Mod+Q { close-window; }

    // Navigation colonne/fenêtre (HJKL + flèches)
    Mod+Left  { focus-column-left; }
    Mod+H     { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+L     { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+K     { focus-window-up; }
    Mod+Down  { focus-window-down; }
    Mod+J     { focus-window-down; }

    // Déplacement (Ctrl+HJKL + flèches)
    Mod+Ctrl+Left  { move-column-left; }
    Mod+Ctrl+H     { move-column-left; }
    Mod+Ctrl+Right { move-column-right; }
    Mod+Ctrl+L     { move-column-right; }
    Mod+Ctrl+Up    { move-window-up; }
    Mod+Ctrl+K     { move-window-up; }
    Mod+Ctrl+Down  { move-window-down; }
    Mod+Ctrl+J     { move-window-down; }

    // Début / Fin de ligne
    Mod+Home      { focus-column-first; }
    Mod+End       { focus-column-last; }
    Mod+Ctrl+Home { move-column-to-first; }
    Mod+Ctrl+End  { move-column-to-last; }

    // ─ Moniteurs ─
    Mod+Shift+Left  { focus-monitor-left; }
    Mod+Shift+Right { focus-monitor-right; }
    Mod+Shift+Up    { focus-monitor-up; }
    Mod+Shift+Down  { focus-monitor-down; }

    Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
    Mod+Shift+Ctrl+Up    { move-column-to-monitor-up; }
    Mod+Shift+Ctrl+Down  { move-column-to-monitor-down; }

    // ─ Workspaces ─
    Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
    Mod+WheelScrollUp   cooldown-ms=150 { focus-workspace-up; }
    Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
    Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

    Mod+WheelScrollRight { focus-column-right; }
    Mod+WheelScrollLeft  { focus-column-left; }

    Mod+Page_Down       { focus-workspace-down; }
    Mod+Page_Up         { focus-workspace-up; }
    Mod+U               { focus-workspace-down; }
    Mod+I               { focus-workspace-up; }
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Mod+Ctrl+1 { move-column-to-workspace 1; }
    Mod+Ctrl+2 { move-column-to-workspace 2; }
    Mod+Ctrl+3 { move-column-to-workspace 3; }
    Mod+Ctrl+4 { move-column-to-workspace 4; }
    Mod+Ctrl+5 { move-column-to-workspace 5; }
    Mod+Ctrl+6 { move-column-to-workspace 6; }
    Mod+Ctrl+7 { move-column-to-workspace 7; }
    Mod+Ctrl+8 { move-column-to-workspace 8; }
    Mod+Ctrl+9 { move-column-to-workspace 9; }

    Mod+Tab { focus-workspace-previous; }

    // ─ Layout ─
    Mod+R       { switch-preset-column-width; }
    Mod+Ctrl+F  { expand-column-to-available-width; }
    Mod+C       { center-column; }
    Mod+Ctrl+C  { center-visible-columns; }
    Mod+Minus       { set-column-width "-10%"; }
    Mod+Equal       { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }

    // ─ Modes fenêtre ─
    Mod+T { toggle-window-floating; }
    Mod+F { fullscreen-window; }
    Mod+W { toggle-column-tabbed-display; }
    Mod+O repeat=false { toggle-overview; }

    // ─ Screenshots ─
    Ctrl+Shift+1 { screenshot; }
    Ctrl+Shift+2 { screenshot-screen; }
    Ctrl+Shift+3 { screenshot-window; }
    Print        { screenshot; }

    // ─ Système ─
    Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
    Ctrl+Alt+Delete { quit; }
    Mod+Shift+P { power-off-monitors; }
}

// ────────────── Démarrage ──────────────────────────────────────────────────────
spawn-at-startup "xwayland-satellite"
spawn-at-startup "swaync"
spawn-at-startup "sh" "-c" "pgrep -x waybar || exec waybar"
spawn-at-startup "swaybg" "-c" "#1e1e2e"

// ────────────── Options globales (CachyOS) ────────────────────────────────────
prefer-no-csd   // Désactiver les décorations client (CachyOS)
screenshot-path "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png"

hotkey-overlay {
    skip-at-startup  // Ne pas afficher l'overlay au premier démarrage (CachyOS)
}

// ────────────── Variables d'environnement (CachyOS) ───────────────────────────
environment {
    DISPLAY ":1"                            // XWayland display fixe (évite conflit SDDM)
    ELECTRON_OZONE_PLATFORM_HINT "auto"     // Electron apps en Wayland natif si dispo
    QT_QPA_PLATFORM "wayland"
    QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
    XDG_SESSION_TYPE "wayland"
    XDG_CURRENT_DESKTOP "niri"
}

// ────────────── Layout ─────────────────────────────────────────────────────────
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
        width 3
        active-color "#cba6f7"    // Catppuccin Mauve
        inactive-color "#45475a"  // Catppuccin Surface1
    }

    shadow {
        softness 30
        spread 5
        offset x=0 y=5
        color "#0007"
    }

    struts {}
}

// ────────────── Animations (spring physics, style CachyOS) ────────────────────
animations {
    workspace-switch {
        spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
    }
    window-open {
        duration-ms 200
        curve "ease-out-quad"
    }
    window-close {
        duration-ms 200
        curve "ease-out-cubic"
    }
    horizontal-view-movement {
        spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
    }
    window-movement {
        spring damping-ratio=1.0 stiffness=800 epsilon=0.0001
    }
    window-resize {
        spring damping-ratio=1.0 stiffness=1000 epsilon=0.0001
    }
    config-notification-open-close {
        spring damping-ratio=0.6 stiffness=1200 epsilon=0.001
    }
    screenshot-ui-open {
        duration-ms 300
        curve "ease-out-quad"
    }
    overview-open-close {
        spring damping-ratio=1.0 stiffness=900 epsilon=0.0001
    }
}

// ────────────── Window Rules (style CachyOS) ──────────────────────────────────
window-rule {
    // Firefox / Brave PiP → floating
    match app-id=r#"firefox$"# title="^Picture-in-Picture$"
    match app-id=r#"brave-browser$"# title="^Picture in picture$"
    open-floating true
}

window-rule {
    geometry-corner-radius 20   // Coins arrondis (20px, CachyOS)
    clip-to-geometry true
}

// Citrix / apps X11 → via XWayland
window-rule {
    match app-id=r#"wfica"#
    open-floating false
}
KDLEOF

log_ok "config.kdl généré (style CachyOS complet)"

# ── 8. swaylock (lock screen avec flou, style CachyOS/Catppuccin) ─────────────
cat > "${SWAYLOCK_DIR}/config" << 'EOF'
# swaylock — Catppuccin Mocha (inspiré config Nord CachyOS)
ignore-empty-password
disable-caps-lock-text
font=Hack Nerd Font Mono

screenshots
effect-blur=7x5
effect-vignette=0.5:0.5
indicator
indicator-radius=120
indicator-thickness=20
clock
timestr=%H:%M
datestr=%A, %d %B

# Catppuccin Mocha palette
ring-color=585b70
key-hl-color=cba6f7
line-color=1e1e2e
separator-color=313244
inside-color=1e1e2e
bs-hl-color=f38ba8
layout-bg-color=313244
layout-border-color=585b70
layout-text-color=cdd6f4
text-color=cdd6f4
ring-ver-color=89b4fa
inside-ver-color=1e1e2e
ring-wrong-color=f38ba8
inside-wrong-color=1e1e2e
EOF
log_ok "swaylock configuré (Catppuccin, flou de fond)"

# ── 9. Waybar (enrichi : systray, réseau, power menu) ────────────────────────
cat > "${WAYBAR_DIR}/config" << 'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 36,
    "margin-top": 10,
    "margin-left": 12,
    "margin-right": 12,

    "modules-left": ["niri/workspaces", "niri/window"],
    "modules-center": ["clock"],
    "modules-right": [
        "tray",
        "network",
        "cpu",
        "memory",
        "backlight",
        "pulseaudio",
        "battery",
        "custom/notification",
        "custom/power"
    ],

    "niri/workspaces": {
        "format": "{icon}",
        "format-icons": { "default": "○", "active": "●" }
    },
    "niri/window": {
        "format": "{}",
        "max-length": 40
    },
    "clock": {
        "format": "{:%H:%M  %a %d %b}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>",
        "calendar": { "mode": "year", "mode-mon-col": 3 }
    },
    "tray": {
        "icon-size": 16,
        "spacing": 8
    },
    "network": {
        "format-wifi": "󰤨 {signalStrength}%",
        "format-ethernet": "󰈀",
        "format-disconnected": "󰤭",
        "tooltip-format": "{ifname}: {ipaddr}\n{essid}",
        "on-click": "nm-connection-editor"
    },
    "cpu": {
        "format": " {usage}%",
        "interval": 5,
        "tooltip": false
    },
    "memory": {
        "format": " {percentage}%",
        "interval": 10
    },
    "backlight": {
        "format": "{icon} {percent}%",
        "format-icons": ["󰋙", "󰛩", "󰛨"]
    },
    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰝟",
        "format-icons": { "default": ["󰕿", "󰖀", "󰕾"] },
        "on-click": "pavucontrol",
        "scroll-step": 5
    },
    "battery": {
        "format": "{icon} {capacity}%",
        "format-charging": "󰂄 {capacity}%",
        "format-plugged": "󰚥 {capacity}%",
        "format-icons": ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"],
        "states": { "warning": 30, "critical": 15 }
    },
    "custom/notification": {
        "tooltip": false,
        "format": "󰂚",
        "on-click": "swaync-client -t -sw",
        "escape": true
    },
    "custom/power": {
        "tooltip": false,
        "format": "⏻",
        "on-click": "bash ~/.config/waybar/scripts/power-menu.sh"
    }
}
EOF

# Power menu script
cat > "${WAYBAR_DIR}/scripts/power-menu.sh" << 'EOF'
#!/usr/bin/env bash
# Power menu via fuzzel
CHOICE=$(printf "  Shutdown\n  Reboot\n󰍃  Logout\n󰒲  Suspend\n  Lock" \
  | fuzzel --dmenu --prompt "Power  " --lines 5 --width 20)
case "$CHOICE" in
  *Shutdown) systemctl poweroff ;;
  *Reboot)   systemctl reboot ;;
  *Logout)   niri msg action quit ;;
  *Suspend)  systemctl suspend ;;
  *Lock)     swaylock ;;
esac
EOF
chmod +x "${WAYBAR_DIR}/scripts/power-menu.sh"

# ── 10. Waybar style.css (Catppuccin Mocha) ───────────────────────────────────
cat > "${WAYBAR_DIR}/style.css" << 'EOF'
* {
    border: none;
    font-family: "Hack Nerd Font Mono", "Symbols Nerd Font", sans-serif;
    font-size: 13px;
    font-weight: bold;
}

window#waybar {
    background: transparent;
}

/* ── Modules de base ─────────────────────────────────── */
.modules-left,
.modules-center,
.modules-right {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 2px 12px;
    border: 1px solid #45475a;
    color: #cdd6f4;
    margin: 0 4px;
}

/* ── Workspaces ─────────────────────────────────────── */
#workspaces button {
    color: #7f849c;
    padding: 0 8px;
    font-size: 15px;
    border-radius: 0;
    background: transparent;
}
#workspaces button.active {
    color: #1e1e2e;
    background: #cba6f7;
    border-radius: 8px;
    padding: 0 10px;
    min-width: 20px;
}
#workspaces button:hover {
    background: #313244;
    color: #cdd6f4;
}

/* ── Titre fenêtre ──────────────────────────────────── */
#window {
    color: #a6adc8;
    font-weight: normal;
    font-size: 12px;
}

/* ── Modules colorés ────────────────────────────────── */
#clock          { color: #cba6f7; }
#cpu            { color: #89b4fa; }
#memory         { color: #a6e3a1; }
#pulseaudio     { color: #f9e2af; }
#pulseaudio.muted { color: #585b70; }
#battery        { color: #fab387; }
#battery.charging { color: #a6e3a1; }
#battery.warning:not(.charging) { color: #f9e2af; }
#battery.critical:not(.charging) { color: #f38ba8; animation-name: blink; }
#network        { color: #89dceb; }
#network.disconnected { color: #585b70; }
#backlight      { color: #f9e2af; }
#tray           { padding: 0 4px; }
#custom-power   { color: #f38ba8; padding: 0 8px; }
#custom-notification { color: #cba6f7; padding: 0 6px; }

@keyframes blink {
    to { color: #1e1e2e; background: #f38ba8; border-radius: 8px; }
}
EOF

log_ok "Waybar config (modules enrichis + power menu)"

# ── 11. Fuzzel (aligné Catppuccin) ────────────────────────────────────────────
cat > "${FUZZEL_DIR}/fuzzel.ini" << 'EOF'
[main]
font=Hack Nerd Font Mono:size=13
prompt=❯ 
terminal=waveterm
width=42
horizontal-pad=40
vertical-pad=20
inner-pad=10
lines=8
line-height=24

[colors]
background=1e1e2edd
text=cdd6f4ff
match=cba6f7ff
selection=585b70ff
selection-text=cdd6f4ff
border=cba6f7ff
EOF

# ── 12. Systemd units : masquer les doublons ───────────────────────────────────
systemctl --user mask waybar.service 2>/dev/null || true
systemctl --user mask sway-notification-center.service 2>/dev/null || true
log_ok "Units systemd waybar/swaync masquées (anti-doublon)"

# ── 13. Validation config.kdl ────────────────────────────────────────────────
log_section "Validation"
if /usr/local/bin/niri validate --config "${NIRI_DIR}/config.kdl" 2>/dev/null; then
  log_ok "config.kdl valide"
else
  log_warn "niri validate a signalé un problème :"
  /usr/local/bin/niri validate --config "${NIRI_DIR}/config.kdl" 2>&1 | head -20 || true
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗\n"
printf "║  Niri (style CachyOS) configuré ✓                        ║\n"
printf "╠══════════════════════════════════════════════════════════╣\n"
printf "║  1. sudo reboot (ou relogin → sélectionner Niri)         ║\n"
printf "╠══════════════════════════════════════════════════════════╣\n"
printf "║  Keybinds principaux :                                   ║\n"
printf "║  Super+Enter      Terminal (WaveTerm)                    ║\n"
printf "║  Super+Space      Launcher (Fuzzel)                      ║\n"
printf "║  Super+B          Brave browser                          ║\n"
printf "║  Super+HJKL/↑↓←→  Navigation                            ║\n"
printf "║  Super+Ctrl+↑↓←→  Déplacer fenêtre                      ║\n"
printf "║  Super+Shift+↑↓←→ Moniteur                              ║\n"
printf "║  Super+1..9       Workspace direct                       ║\n"
printf "║  Super+U/I / PgDn/PgUp  Workspace bas/haut              ║\n"
printf "║  Super+T          Float/tile toggle                      ║\n"
printf "║  Super+F          Fullscreen                             ║\n"
printf "║  Super+W          Tabbed display toggle                  ║\n"
printf "║  Super+O          Overview mode                          ║\n"
printf "║  Super+C          Centrer colonne                        ║\n"
printf "║  Super+Alt+L      Verrouiller (swaylock + blur)          ║\n"
printf "║  Ctrl+Shift+1/2/3 Screenshot selection/screen/window    ║\n"
printf "║  Ctrl+Alt+Delete  Quitter Niri                          ║\n"
printf "╠══════════════════════════════════════════════════════════╣\n"
printf "║  Wallpaper perso : modifier swaybg dans config.kdl       ║\n"
printf "║  Sortie moniteur : niri msg outputs → décommenter block  ║\n"
printf "╚══════════════════════════════════════════════════════════╝${NC}\n"
