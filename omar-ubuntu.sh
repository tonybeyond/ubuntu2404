#!/bin/bash
# Omarchy-style Hyprland Setup for Ubuntu 24.04
# This script installs and configures a similar workflow to Omarchy

set -eEo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[*]${NC} ${1}"
}

log_success() {
    echo -e "${GREEN}[+]${NC} ${1}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} ${1}"
}

log_error() {
    echo -e "${RED}[!]${NC} ${1}"
}

# Check if running on Ubuntu 24.04
check_system() {
    log_info "Checking system requirements..."

    if ! command -v lsb_release &> /dev/null; then
        log_error "lsb_release not found. Please install lsb-core."
        exit 1
    fi

    local distro=$(lsb_release -is 2>/dev/null || echo "")
    local version=$(lsb_release -rs 2>/dev/null || echo "")

    if [[ "$distro" != "Ubuntu" ]]; then
        log_warning "This script is designed for Ubuntu 24.04"
        log_warning "Detected: $distro $version"
        read -p "Continue anyway? (y/N) " -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    if [[ "$version" != "24.04" ]]; then
        log_warning "This script is optimized for Ubuntu 24.04"
        log_warning "Detected: Ubuntu $version"
        read -p "Continue anyway? (y/N) " -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # Check if running as root (should NOT be root)
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root!"
        exit 1
    fi

    log_success "System check passed: Ubuntu $version"
}

# Enable required repositories
enable_repositories() {
    log_info "Enabling required repositories..."

    # Enable Universe repository (required for most packages)
    if ! grep -q "^universe" /etc/apt/sources.list 2>/dev/null; then
        sudo add-apt-repository universe -y
    fi

    # Enable Multiverse repository (for some proprietary software)
    if ! grep -q "^multiverse" /etc/apt/sources.list 2>/dev/null; then
        sudo add-apt-repository multiverse -y
    fi

    # Enable Restricted repository
    if ! grep -q "^restricted" /etc/apt/sources.list 2>/dev/null; then
        sudo add-apt-repository restricted -y
    fi

    # Add Hyprland PPA
    log_info "Adding Hyprland PPA..."
    sudo apt install -y software-properties-common gnupg
    sudo add-apt-repository ppa:hyprland/team -y

    # Update package list
    log_info "Updating package list..."
    sudo apt update
}

# Install base system packages
install_base_packages() {
    log_info "Installing base system packages..."

    # Core utilities
    local base_packages=(
        # System utilities
        "build-essential" "git" "curl" "wget" "curl" "jq" "yq" "jq"
        "fastfetch" "btop" "htop" "nvtop"
        "bat" "exa" "eza" "dust" "fd-find" "ripgrep" "fzf"
        "alacritty" "kitty" "ghostty" "termite"
        "cliphist" "wl-clipboard" "xclip"
        "swaybg" "swayosd" "mako" "dunst"
        "grim" "slurp" "satty" "wl-copy"
        "playerctl" "pamixer" "volume-control"
        "brightnessctl" "xbacklight"
        "bluez" "blueman" "pulseaudio" "pipewire" "wireplumber"
        "network-manager" "network-manager-gnome"
        "nm-applet" "wpasupplicant" "iwd"
        "bluez-tools"
        # Hyprland dependencies
        "waybar" "walker" "uwsm"
        "hyprpicker" "hyprsunset" "hypridle" "hyprlock"
        "qt6-wayland" "qt5-wayland"
        "xwayland" "xwayland-satellite"
        # File management
        "nautilus" "nemo" "thunar"
        "imv" "slurp" "grim"
        # Theming
        "gtk2-engines-pixbuf" "gtk3-engines-briquet"
        "icon-themes" "cursors"
        "adwaita-icon-theme" "gtk4-theme"
        # Fonts
        "fonts-noto" "fonts-noto-color-emoji"
        "fonts-firacode" "fonts-dejavu"
        "fonts-cascadia-code" "fonts-cascadia-mono-nerd"
        "ttf-ia-writer-dual" "ttf-jetbrains-mono"
        "fonts-roboto" "fonts-roboto-mono"
        "fonts-liberation" "fonts-liberation2"
    )

    # Remove duplicates and install
    sudo apt install -y $(printf "%s\n" "${base_packages[@]}" | sort -u)
}

# Install additional useful packages
install_additional_packages() {
    log_info "Installing additional packages..."

    local additional_packages=(
        # Browsers
        "firefox" "chromium-browser" "brave-browser"
        # Office
        "libreoffice" "onlyoffice-desktopeditors"
        # Communication
        "signal-desktop" "discord" "teams"
        # Development
        "code" "cursor" "pycharm-community" "rubymine"
        "docker.io" "docker-compose" "podman"
        "nodejs" "npm" "nvm" "yarn"
        "python3" "python3-pip" "python3-venv"
        "ruby-full" "rbenv" "ruby-dev"
        "golang" "golang-go" "golang-ginkgo"
        "php" "php-cli" "php-mysql"
        "rustc" "cargo" "rustup"
        # Media
        "mpv" "vlc" "audacity" "obs-studio"
        "gimp" "inkscape" "kdenlive"
        "shotcut" "blender"
        # Productivity
        "keepassxc" "bitwarden" "1password"
        "typora" "libreoffice"
        "xournalpp" "zettlr"
        "calibre" "zotero"
        # Other
        "neovim" "vim" "nano"
        "lazygit" "tig" "git-delta"
        "postgresql" "mysql-client" "sqlite3"
        "redis-tools" "mongodb-tools"
        "nmap" "wireshark" "net-tools"
        "dnsutils" "iputils-ping" "traceroute"
    )

    # Some packages may not exist in Ubuntu repos, handle them specially
    log_info "Installing common development tools..."

    # Install Node.js via NodeSource if not available
    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js via NodeSource..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt install -y nodejs
    fi

    # Install Git
    if ! command -v git &> /dev/null; then
        sudo apt install -y git
    fi

    # Install Docker
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        sudo apt install -y docker.io docker-compose
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker $USER
    fi

    # Install VS Code
    if ! command -v code &> /dev/null; then
        log_info "Installing VS Code..."
        sudo apt install -y wget gnupg apt-transport-https
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.code.el7.prod.code.visualstudio.com/repos/stable/$([ $(uname -m) = 'x86_64' ] && echo 'debian' || echo 'debian-arm64') jammy main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        sudo apt update
        sudo apt install -y code
        rm -f packages.microsoft.gpg
    fi

    log_success "Additional packages installed"
}

# Install Hyprland and related packages
install_hyprland() {
    log_info "Installing Hyprland and related packages..."

    # Hyprland main packages
    local hypr_packages=(
        "hyprland"
        "hyprland-protocols"
        "hyprland-website"
        "hyprpicker"
        "hyprsunset"
        "hypridle"
        "hyprlock"
        "waybar"
        "walker"
        "uwsm"
        "xdg-desktop-portal-hyprland"
        "xdg-desktop-portal-gtk"
        "qml6-module-org-kde-blur"
        "qml6-module-org-kde-windoweffects"
    )

    # Install Hyprland packages
    sudo apt install -y $(printf "%s\n" "${hypr_packages[@]}" | sort -u)

    log_success "Hyprland installed"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."

    mkdir -p ~/.config/hypr
    mkdir -p ~/.config/waybar
    mkdir -p ~/.config/walker
    mkdir -p ~/.config/swayosd
    mkdir -p ~/.config/mako
    mkdir -p ~/.config/uwsm
    mkdir -p ~/.local/bin
    mkdir -p ~/.local/share/fonts
    mkdir -p ~/.local/state/omarchy/toggles

    log_success "Directories created"
}

# Install OMarchy-style tools and scripts
install_omarchy_tools() {
    log_info "Installing Omarchy-style tools..."

    # Install Walker (dmenu replacement)
    if ! command -v walker &> /dev/null; then
        log_info "Installing Walker..."
        sudo apt install -y walker || {
            log_warning "Walker not available in repos, installing via pip..."
            pip3 install --user walker-dmenu || log_warning "Could not install Walker"
        }
    fi

    # Install Omarchy Theme installer
    if ! command -v omarchy-theme-set &> /dev/null; then
        log_info "Setting up theme management..."
        # Create wrapper script for theme management
        cat > ~/.local/bin/omarchy-theme-set << 'EOF'
#!/bin/bash
# Theme management wrapper for Ubuntu
set -e

case "${1:-}" in
    list)
        echo "Default"
        echo "Nord"
        echo "Gruvbox"
        echo "Dracula"
        echo "OneDark"
        echo "Selenized"
        ;;
    set)
        theme="${2:-Default}"
        case "$theme" in
            Nord)
                gsettings set org.gnome.desktop.interface theme "Nord"
                gsettings set org.gnome.desktop.interface icon-theme "Nord"
                ;;
            Gruvbox)
                gsettings set org.gnome.desktop.interface theme "gruvbox-dark"
                ;;
            Dracula)
                gsettings set org.gnome.desktop.interface theme "Dracula"
                ;;
            OneDark)
                gsettings set org.gnome.desktop.interface theme "OneDark"
                ;;
            *)
                gsettings set org.gnome.desktop.interface theme "Adwaita"
                ;;
        esac
        ;;
    *)
        echo "Usage: omarchy-theme-set [list|set <theme>]"
        ;;
esac
EOF
        chmod +x ~/.local/bin/omarchy-theme-set
    fi

    # Install Font manager
    if ! command -v omarchy-font-set &> /dev/null; then
        cat > ~/.local/bin/omarchy-font-set << 'EOF'
#!/bin/bash
# Font management wrapper for Ubuntu
set -e

case "${1:-}" in
    list)
        fc-list | cut -d: -f1 | sort -u
        ;;
    set)
        font="${2:-}"
        if [ -n "$font" ]; then
            gsettings set org.gnome.desktop.interface font-name "$font"
            gsettings set org.gnome.desktop.interface monospace-font-name "${font} 10"
            log_success "Font set to: $font"
        fi
        ;;
    *)
        echo "Usage: omarchy-font-set [list|set <font>]"
        ;;
esac
EOF
        chmod +x ~/.local/bin/omarchy-font-set
    fi

    log_success "Omarchy tools installed"
}

# Install Neovim with LazyVim
install_neovim() {
    log_info "Installing Neovim with LazyVim..."

    # Install Neovim
    if ! command -v nvim &> /dev/null; then
        log_info "Installing Neovim..."
        sudo apt install -y neovim
    fi

    # Install dependencies
    sudo apt install -y nodejs npm python3-pip rustc cargo

    # Install LazyVim
    if [ ! -d ~/.config/nvim ]; then
        log_info "Installing LazyVim..."
        git clone https://github.com/LazyVim/starter.git ~/.config/nvim
    fi

    # Install treesitter
    if ! command -v nvim &> /dev/null; then
        sudo apt install -y nodejs npm
        npm install -g treesitter-cli
    fi

    log_success "Neovim with LazyVim installed"
}

# Install terminal tools
install_terminal_tools() {
    log_info "Installing terminal tools..."

    # Install zoxide (better cd)
    if ! command -v zoxide &> /dev/null; then
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    fi

    # Install starship prompt
    if ! command -v starship &> /dev/null; then
        curl -sS https://starship.rs/install.sh | sh
    fi

    # Install tldr
    if ! command -v tldr &> /dev/null; then
        sudo npm install -g tldr
    fi

    # Install exa (better ls)
    if ! command -v exa &> /dev/null; then
        sudo apt install -y exa
    fi

    # Install bat (better cat)
    if ! command -v bat &> /dev/null; then
        sudo apt install -y bat
    fi

    log_success "Terminal tools installed"
}

# Configure Hyprland
configure_hyprland() {
    log_info "Configuring Hyprland..."

    # Create main hyprland.conf
    cat > ~/.config/hypr/hyprland.conf << 'EOFCONFIG'
# Hyprland configuration for Ubuntu Omarchy-style setup
# Learn more: https://wiki.hyprland.org/Configuring/

# Use defaults for core settings
source = ~/.config/hypr/default/autostart.conf
source = ~/.config/hypr/default/bindings.conf
source = ~/.config/hypr/default/looknfeel.conf
source = ~/.config/hypr/default/input.conf
source = ~/.config/hypr/default/monitors.conf

# Personal overrides (create these for custom settings)
# source = ~/.config/hypr/overrides.conf
EOFCONFIG

    # Create default directory structure
    mkdir -p ~/.config/hypr/default

    # Create autostart.conf
    cat > ~/.config/hypr/default/autostart.conf << 'EOF'
# Autostart applications
# Run at Hyprland startup

# Start background services
systemctl --user start wireplumber &
systemctl --user start pipewire &

# Start desktop utilities
mako &
waybar &
swaybg --mode fill &
swayosd &
hyprsunset &

# Set wallpaper (change path as needed)
# swaybg -c 1a1a2e &

# Start compositor effects
# hypridle &

# Launch walker daemon for app launching
walker -d &
EOF

    # Create bindings.conf
    cat > ~/.config/hypr/default/bindings.conf << 'EOF'
# Application bindings
bind = SUPER, RETURN, exec, uwsm-app -- kitty
bind = SUPER SHIFT, RETURN, exec, uwsm-app -- firefox
bind = SUPER SHIFT, F, exec, uwsm-app -- nautilus
bind = SUPER SHIFT, B, exec, uwsm-app -- brave-browser
bind = SUPER SHIFT, M, exec, uwsm-app -- spotify
bind = SUPER SHIFT, N, exec, uwsm-app -- neovim
bind = SUPER SHIFT, D, exec, uwsm-app -- discord
bind = SUPER SHIFT, G, exec, uwsm-app -- signal-desktop
bind = SUPER SHIFT, W, exec, uwsm-app -- code
bind = SUPER SHIFT, SLASH, exec, uwsm-app -- 1password

# Web app bindings
bind = SUPER SHIFT, A, exec, uwsm-app -- "https://chatgpt.com"
bind = SUPER SHIFT, C, exec, uwsm-app -- "https://app.hey.com/calendar/weeks/"
bind = SUPER SHIFT, E, exec, uwsm-app -- "https://app.hey.com"
bind = SUPER SHIFT, Y, exec, uwsm-app -- "https://youtube.com/"

# System bindings
bind = SUPER, Q, killactive, class:.*
bind = SUPER SHIFT, Q, exec, systemctl poweroff
bind = SUPER SHIFT, R, exec, systemctl reboot
bind = SUPER, S, exec, Walker -p "Launch..." --width 400
bind = SUPER, SPACE, exec, Walker -p "Menu..."

# Volume controls
bind = ,XF86AudioLowerVolume, exec, pulsemixer --volume -5
bind = ,XF86AudioRaiseVolume, exec, pulsemixer --volume +5
bind = ,XF86AudioMute, exec, pulsemixer --toggle-mute
bind = ,XF86AudioMicMute, exec, pulsemixer --toggle-mute -i

# Brightness controls
bind = ,XF86MonBrightnessUp, exec, brightnessctl set +10%
bind = ,XF86MonBrightnessDown, exec, brightnessctl set 10%-

# Screenshot
bind = , Print, exec, grim - | wl-copy
bind = SHIFT, Print, exec, grim -g "$(slurp)" - | wl-copy
bind = ALT, Print, exec, grim - | tee ~/screenshots/$(date +%s).png | wl-copy

# Workspace switching
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER, 5, workspace, 5
bind = SUPER, 6, workspace, 6
bind = SUPER, 7, workspace, 7
bind = SUPER, 8, workspace, 8
bind = SUPER, 9, workspace, 9
bind = SUPER, 0, workspace, 10

# Window movement
bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3
bind = SUPER SHIFT, 4, movetoworkspace, 4
bind = SUPER SHIFT, 5, movetoworkspace, 5
bind = SUPER SHIFT, 6, movetoworkspace, 6
bind = SUPER SHIFT, 7, movetoworkspace, 7
bind = SUPER SHIFT, 8, movetoworkspace, 8
bind = SUPER SHIFT, 9, movetoworkspace, 9
bind = SUPER SHIFT, 0, movetoworkspace, 10

# Tiling
bind = SUPER, H, movefocus, l
bind = SUPER, L, movefocus, r
bind = SUPER, K, movefocus, u
bind = SUPER, J, movefocus, d

# Resize
bind = SUPER SHIFT, H, resize, -50 0
bind = SUPER SHIFT, L, resize, 50 0
bind = SUPER SHIFT, K, resize, 0 -50
bind = SUPER SHIFT, J, resize, 0 50

# Lock screen
bind = SUPER, L, exec, hyprlock
EOF

    # Create looknfeel.conf
    cat > ~/.config/hypr/default/looknfeel.conf << 'EOF'
# Visual appearance settings

# https://wiki.hyprland.org/Configuring/Variables/#general
general {
    # Gaps between windows
    gaps_in = 5
    gaps_out = 10

    # Border settings
    border_size = 2
    col.border = rgba(30 30 46 a0)
    col.active_border = rgba(94 129 172 a0)

    # Rounding
    rounding = 8

    # Layout (master or dwindle)
    layout = master
}

# https://wiki.hyprland.org/Configuring/Variables/#decoration
decoration {
    # Round corners
    rounding = 8

    # Dim inactive windows
    dim_inactive = true
    dim_strength = 0.3

    # Blur
    blur {
        enabled = true
        size = 5
        passes = 2
        vibrancy = 0.2
    }
}

# Animations
animations {
    enabled = true

    # Animation settings
    bezier = myBezier, 0.05, 0.9, 0.1, 1.0

    animation = windows, 1, 5, myBezier
    animation = windowsOut, 1, 5, default, popin 80%
    animation = border, 1, 10, default
    animation = corner, 1, 10, default
    animation = crashopen, 1, 5, default
    animation = crashclose, 1, 5, default
    animation = fade, 1, 10, default
    animation = workspaces, 1, 6, default
}

# Dwindle layout (tiling)
dwindle {
    # Master layout instead of dwindle
    # layout = master

    # Split width ratio
    split_width_percent = 0.5
}
EOF

    # Create input.conf
    cat > ~/.config/hypr/default/input.conf << 'EOF'
# Input device configuration

[input]
    kb_layout = us
    kb_variant =
    kb_options = compose:caps
    repeat_rate = 40
    repeat_delay = 600
    numlock_by_default = true

    # Scroll factor for touchpad
    scroll_factor = 0.4

    # Touchpad settings
    [input:touchpad]
        natural_scroll = true
        disable_while_typing = true
        clickfinger_behavior = true
        dwt = true
        middle_emulation = true

# Window rules for scroll factors
windowrule = match:class (Alacritty|kitty|ghostty), scroll_touchpad 1.5
EOF

    # Create monitors.conf
    cat > ~/.config/hypr/default/monitors.conf << 'EOF'
# Monitor configuration
# Use: hyprctl monitors to see available outputs

# Default: auto-detect and use preferred resolution
# Format: monitor = <output>, <resolution>, <position>, <scale>

# For retina-class 2x displays (13" 2.8K, 27" 5K, 32" 6K)
# env = GDK_SCALE,2
# monitor=,preferred,auto,auto

# For 27" or 32" 4K monitors (fractional scaling)
# env = GDK_SCALE,1.75
# monitor=,preferred,auto,1.6

# For 1080p or 1440p displays
# env = GDK_SCALE,1
# monitor=,preferred,auto,1

# Example multi-monitor setup
# monitor = DP-1, 2560x1440@144, auto, 1
# monitor = HDMI-A-1, 1920x1080@60, 2560x0, 1
EOF

    log_success "Hyprland configured"
}

# Configure Waybar
configure_waybar() {
    log_info "Configuring Waybar..."

    mkdir -p ~/.config/waybar

    cat > ~/.config/waybar/config.jsonc << 'EOF'
{
    "layer": "top",
    "height": 32,
    "margin": "0 0 0 0",
    "spacing": 10,

    "modules-left": [
        "hyprland/workspaces",
        "hyprland/window"
    ],

    "modules-center": [
        "clock"
    ],

    "modules-right": [
        "pulseaudio",
        "network",
        "cpu",
        "memory",
        "temperature",
        "battery",
        "tray"
    ],

    "hyprland/workspaces": {
        "format": "{icon}",
        "on-click": "activate",
        "on-click-right": "close",
        "sort-by": "number",
        "format-icons": {
            "1": "󰲠",
            "2": "󰲠",
            "3": "󰲠",
            "4": "󰲠",
            "5": "󰲠",
            "6": "󰲠",
            "7": "󰲠",
            "8": "󰲠",
            "9": "󰲠",
            "10": "󰲠",
            "active": "󰲠",
            "default": "󰲠"
        },
        "persistent-workspaces": "*"
    },

    "hyprland/window": {
        "max-char-len": 80
    },

    "clock": {
        "format": "{:%a %b %d  %I:%M %p}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>",
        "on-click-right": "mode",
        "format-alt": "{:%Y-%m-%d}"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-icons": {
            "headphone": "󰋋",
            "headset": "󰄋",
            "speaker": "�speaker",
            "handset": "󰄋",
            "phone": "󰄋",
            "video": "󰄋",
            "anonymous": "󰄋",
            "default": "�speaker"
        },
        "smooth-scrolling-threshold": 1,
        "smooth-scrolling-threshold-assets": 1,
        "on-click-right": "mute"
    },

    "network": {
        "format-wifi": "󰤨 {essid}",
        "format-ethernet": "󰤭 {ifname}",
        "format-disabled": "󰤭",
        "format-linked": "󰤭 {ifname}",
        "format-disconnected": "󰤭",
        "tooltip-format-wifi": "{essid} ({signalStrength}%) 󰤨",
        "on-click-right": "nm-connection-editor"
    },

    "cpu": {
        "format": "󰢮 {usage}%",
        "tooltip-format": "󰢮 {usage}%\nCore usage: {load_times}",
        "smooth-scrolling-threshold": 1
    },

    "memory": {
        "format": "󰢠 {used:0.1f}G/{total:0.1f}G",
        "tooltip-format": "󰢠 {used:0.1f}G/{total:0.1f}G"
    },

    "temperature": {
        "critical-threshold": 80,
        "format": "󰔏 {temperatureC}°C",
        "tooltip-format": "󰔏 {temperatureC}°C ({temperatureF}°F)"
    },

    "battery": {
        "format": "{icon} {capacity}%",
        "format-icons": ["󰢜", "󰄠", "󰢝", "󰢞", "󰢟", "󰢠"],
        "format-charging": "󰢜 {capacity}%",
        "format-discharging": "{icon} {capacity}%",
        "format-full": "󰢝 {capacity}%",
        "format-good": "󰄠 {capacity}%",
        "format-low": "󰢟 {capacity}%",
        "format-critical": "󰢜 {capacity}%",
        "tooltip-format": "{status} {capacity}%",
        "on-click-right": "mate-power-preferences"
    },

    "tray": {
        "icon-size": 24,
        "spacing": 10
    }
}
EOF

    cat > ~/.config/waybar/config.css << 'EOF'
* {
    font-family: "JetBrains Mono Nerd Font", "Noto Sans", sans-serif;
    font-size: 14px;
    min-height: 0;
}

window#waybar {
    background-color: rgba(15, 15, 20, 0.9);
    color: #cdd6f4;
    border-radius: 10px;
    margin: 5px;
    border: 1px solid rgba(58, 58, 68, 0.5);
}

#workspaces {
    background-color: transparent;
    padding: 0 8px;
}

#workspaces button {
    background-color: transparent;
    color: #89b4fa;
    border-radius: 5px;
    padding: 0 6px;
    margin: 0 2px;
}

#workspaces button.active {
    background-color: #89b4fa;
    color: #1e1e2e;
}

#workspaces button:hover {
    background-color: rgba(137, 180, 250, 0.2);
}

#window {
    background-color: transparent;
    padding: 0 10px;
}

#clock {
    background-color: transparent;
    padding: 0 15px;
}

#pulseaudio {
    background-color: transparent;
    padding: 0 10px;
}

#network {
    background-color: transparent;
    padding: 0 10px;
}

#cpu {
    background-color: transparent;
    padding: 0 10px;
}

#memory {
    background-color: transparent;
    padding: 0 10px;
}

#temperature {
    background-color: transparent;
    padding: 0 10px;
}

#battery {
    background-color: transparent;
    padding: 0 10px;
}

#battery.critical {
    color: #f38ba8;
}

#tray {
    background-color: transparent;
    padding: 0 10px;
}

.tooltip {
    background-color: #1e1e2e;
    border-radius: 5px;
    padding: 5px 10px;
    color: #cdd6f4;
}
EOF

    log_success "Waybar configured"
}

# Configure Walker
configure_walker() {
    log_info "Configuring Walker..."

    mkdir -p ~/.config/walker

    cat > ~/.config/walker/config.toml << 'EOF'
# Walker configuration

# Window settings
[window]
width = 300
minheight = 1
maxheight = 600
background = "#1e1e2e"
text = "#cdd6f4"
selected = "#89b4fa"
selected_text = "#1e1e2e"
border = "#313244"
border_radius = 5

# Input settings
[input]
case_sensitive = false
filter_timeout = 100
show_preview = true

# Preview settings
[preview]
enabled = true
width_percent = 50
position = "right"

# Font settings
[font]
name = "JetBrains Mono Nerd Font"
size = 14
weight = "Medium"

# Icon settings
[icons]
enabled = true
family = "JetBrains Mono Nerd Font"

# Default command
[default]
command = "exec"
terminal = "kitty"
browser = "firefox"
EOF

    log_success "Walker configured"
}

# Configure SwayOSD
configure_swayosd() {
    log_info "Configuring SwayOSD..."

    mkdir -p ~/.config/swayosd

    cat > ~/.config/swayosd/config.toml << 'EOF'
# SwayOSD configuration

[general]
# Show OSD when volume/brightness changes
show_osd = true
show_icon = true
icon_path = "/usr/share/icons"
theme = "Adwaita"

[display]
# Position and appearance
display = "all"
position = "top"
horizontal_offset = 0
vertical_offset = 50
width = 300
height = 50
margin = 10
padding = 10
border_radius = 8
border_size = 2
border_color = "#1e1e2e"
background_color = "#262633"
text_color = "#cdd6f4"

[animation]
# Animation settings
animation_duration = 200
easing = "ease-out"

[volume]
# Volume indicator
show_volume = true
show_mute = true
icon = "audio-volume-high"
show_percent = true
max_value = 100

[brightness]
# Brightness indicator
show_brightness = true
icon = "display-brightness"
show_percent = true
max_value = 100
EOF

    log_success "SwayOSD configured"
}

# Configure Mako (notifications)
configure_mako() {
    log_info "Configuring Mako notifications..."

    mkdir -p ~/.config/mako

    cat > ~/.config/mako/config << 'EOF'
# Mako notification daemon configuration

[global]
max_history=10
default_timeout=5000
background_color=#1e1e2e
text_color=#cdd6f4
width=400
height=60
margin=10
border_size=2
border_color=#313244
radius=8
padding=10
icon_location=left
font=JetBrains Mono Nerd Font 12
anchor=top-right
gravity=top-right

[critical]
background_color=#f38ba8
border_color=#f38ba8
priority=critical
EOF

    log_success "Mako configured"
}

# Configure UWSM (Wayland session manager)
configure_uwsm() {
    log_info "Configuring UWSM..."

    mkdir -p ~/.config/uwsm

    cat > ~/.config/uwsm/default << 'EOF'
# UWSM default session configuration

# Session management
session_type=hyprland
session_command=hyprland

# Terminal settings
terminal=kitty
terminal_editor=nvim

# Browser settings
browser=firefox
browser_private=firefox --private-window

# Launcher
launcher=walker

# Workaround settings
workarounds=
    * allow_wayland_screenshots
    * enable_fractional_scaling

# Environment variables
env=WAYLAND_DISPLAY,wayland-1
env=XDG_RUNTIME_DIR,/run/user/$(id -u)
env=GDK_SCALE,2
env=GDK_BACKEND,wayland
env=SDL_VIDEODRIVER,wayland
env=QT_QPA_PLATFORM,wayland
env=CLUTTER_BACKEND,wayland
env=TOOLKIT_SCALE factor,2
env=QT_WAYLAND_FORCE_DPI,192

# Application settings
app=firefox
    class=^Firefox$
    app_id=firefox

app=code
    class=^Code$
    app_id=code

app=neovim
    class=^kitty$
    title=^nvim$
    app_id=kitty

app=kitty
    class=^kitty$
    app_id=kitty

app=nautilus
    class=^Nautilus$
    app_id=nautilus
EOF

    log_success "UWSM configured"
}

# Configure Dunst (notification daemon)
configure_dunst() {
    log_info "Configuring Dunst notifications..."

    mkdir -p ~/.config/dunst

    cat > ~/.config/dunst/dunstrc << 'EOF'
# Dunst notification daemon configuration

[global]
    monitor = 0
    follow = mouse
    geometry = "300x50-10+10"
    indicate_hidden = yes
    shrink = yes
    transparency = 0
    notification_height = 0
    separator_height = 2
    text_format = yes
    markup = yes
    icon_position = left
    max_icon_size = 48
    icon_path = /usr/share/icons/gnome:/usr/share/icons/hicolor
    font = JetBrains Mono Nerd Font 12
    line_height = 4
    format = "<b>%s</b>\n%b"
    alignment = left
    vertical_alignment = center
    show_age_threshold = 60
    word_wrap = yes
    ellipsize = middle
    ignore_newline = no
    queue_overflow = 10
    enable_dbus = yes
    DBus_Properties = yes
    mouse_left_click = close_current
    mouse_middle_click = do_action, close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    timeout = 5
    urgency = low

[urgency_normal]
    background = "#262633"
    foreground = "#cdd6f4"
    timeout = 8
    urgency = normal

[urgency_critical]
    background = "#f38ba8"
    foreground = "#1e1e2e"
    timeout = 0
    urgency = critical
EOF

    log_success "Dunst configured"
}

# Configure Alacritty (terminal)
configure_alacritty() {
    log_info "Configuring Alacritty..."

    mkdir -p ~/.config/alacritty

    cat > ~/.config/alacritty/alacritty.toml << 'EOF'
# Alacritty configuration

[window]
opacity = 0.9
padding = { x = 10, y = 10 }
dynamic_padding = false
decorations = "full"
blur = true

[window.dimensions]
columns = 80
lines = 24

[window.position]
x = 0
y = 0

[window.class]
instance = "Alacritty"
general = "Alacritty"

[window.gtk_theme_variant]
variant = "dark"

[scrolling]
history = 10000
multiplier = 3

[font]
size = 13

[font.normal]
family = "JetBrains Mono Nerd Font"
style = "Regular"

[font.bold]
family = "JetBrains Mono Nerd Font"
style = "Bold"

[font.italic]
family = "JetBrains Mono Nerd Font"
style = "Italic"

[font.bold_italic]
family = "JetBrains Mono Nerd Font"
style = "Bold Italic"

[colors]
draw_bold_text_with_light_colors = true

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.cursor]
text = "#1e1e2e"
cursor = "#f38ba8"

[colors.vi_mode_cursor]
text = "#1e1e2e"
cursor = "#89b4fa"

[colors.search]
matches = { foreground = "#1e1e2e", background = "#a6e3a1" }
focused_match = { foreground = "#1e1e2e", background = "#a6e3a1" }

[colors.hints]
start = { foreground = "#1e1e2e", background = "#f9e2af" }
end = { foreground = "#1e1e2e", background = "#f9e2af" }

[colors.selection]
text = "#1e1e2e"
background = "#89b4fa"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#cba6f7"
cyan = "#94e2d5"
white = "#b4befe"

[colors.bright]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#cba6f7"
cyan = "#94e2d5"
white = "#b4befe"

[colors.dim]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#cba6f7"
cyan = "#94e2d5"
white = "#b4befe"
EOF

    log_success "Alacritty configured"
}

# Configure Kitty (terminal)
configure_kitty() {
    log_info "Configuring Kitty..."

    mkdir -p ~/.config/kitty

    cat > ~/.config/kitty/kitty.conf << 'EOF'
# Kitty configuration

# Window settings
window_margin_width 10
window_padding_width 10
border_radius 8
window_gap_multiplier 1.0

# Font
font_family JetBrains Mono Nerd Font
font_size 13.0
bold_italic_font_family JetBrains Mono Nerd Font

# Colors - Dracula theme
foreground #cdd6f4
background #1e1e2e
cursor #f38ba8
selection_background #89b4fa
selection_foreground #1e1e2e
url_color #f9e2af

# Normal colors
color0 #45475a
color1 #f38ba8
color2 #a6e3a1
color3 #f9e2af
color4 #89b4fa
color5 #cba6f7
color6 #94e2d5
color7 #b4befe

# Bright colors
color8 #45475a
color9 #f38ba8
color10 #a6e3a1
color11 #f9e2af
color12 #89b4fa
color13 #cba6f7
color14 #94e2d5
color15 #b4befe

# Tab bar
tab_bar_style slider
tab_title_format "{index}: {title}"
active_tab_foreground #1e1e2e
active_tab_background #89b4fa
inactive_tab_foreground #cdd6f4
inactive_tab_background #262633

# Scrolling
scrollback_lines 10000

# Mouse
hide_mouse_cursor when_typing yes
EOF

    log_success "Kitty configured"
}

# Configure Ghostty (terminal)
configure_ghostty() {
    log_info "Configuring Ghostty..."

    mkdir -p ~/.config/ghostty

    cat > ~/.config/ghostty/config << 'EOF'
# Ghostty configuration

# Font
font-family: JetBrains Mono Nerd Font
font-size: 13

# Colors - Dracula theme
foreground: #cdd6f4
background: #1e1e2e
cursor: #f38ba8
selection-background: #89b4fa
selection-foreground: #1e1e2e

# Window
window-padding-x: 10
window-padding-y: 10
window-rounding: 8

# Scrollback
scrollback-lines: 10000

# Mouse
mouse-hide-while-typing: yes
EOF

    log_success "Ghostty configured"
}

# Configure starship prompt
configure_starship() {
    log_info "Configuring Starship prompt..."

    mkdir -p ~/.config/starship

    cat > ~/.config/starship/starship.toml << 'EOF'
# Starship prompt configuration

format = """
$directory\
$git_branch\
$git_state\
$git_metrics\
$git_status\
$python\
$nodejs\
$ruby\
$golang\
$rust\
$docker_context\
$package\
$cmd_duration\
$line_break\
$jobs\
$time\
$battery\
$status\
$shell\
$character"""

right_format = """
$git_branch\
$git_status\
$package\
$docker_context\
$nodejs\
$golang\
$ruby\
$python"""

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true
style = "bold #89b4fa"
format = '[$path]($style) [$read_only]($read_only_style)'

[git_branch]
style = "bold #f38ba8"
format = '[$symbol$branch]($style) '

[git_status]
style = "bold #f38ba8"
format = '[$all_status$ahead_behind]($style) '

[nodejs]
style = "bold #a6e3a1"
format = '[$symbol$version]($style) '

[ruby]
style = "bold #f38ba8"
format = '[$symbol$version]($style) '

[python]
style = "bold #a6e3a1"
format = '[$symbol$version]($style) '

[golang]
style = "bold #a6e3a1"
format = '[$symbol$version]($style) '

[rust]
style = "bold #f38ba8"
format = '[$symbol$version]($style) '

[docker_context]
style = "bold #89b4fa"
format = '[$symbol$context]($style) '

[package]
style = "bold #f9e2af"
format = '[$symbol$version]($style) '

[battery]
full_symbol = "🔋"
charging_symbol = "⚡️"
discharging_symbol = "💀"

[cmd_duration]
min_time = 500
format = "took [$duration]"

[jobs]
symbol = "✦"
style = "bold #89b4fa"

[time]
format = '[$time]($style) '
style = "bold #b4befe"

[shell]
zsh = "󰆪"
bash = "󰈸"
fish = "󰈺"
powershell = "󰐽"
icon = "(shell) "
EOF

    log_success "Starship prompt configured"
}

# Configure zoxide (better cd)
configure_zoxide() {
    log_info "Configuring Zoxide..."

    # Add to shell config
    if [ -f ~/.bashrc ]; then
        if ! grep -q "zoxide init" ~/.bashrc; then
            echo 'eval "$(zoxide init bash)"' >> ~/.bashrc
        fi
    fi

    if [ -f ~/.zshrc ]; then
        if ! grep -q "zoxide init" ~/.zshrc; then
            echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
        fi
    fi

    log_success "Zoxide configured"
}

# Configure mcfly (better history)
configure_mcfly() {
    log_info "Configuring McFly..."

    # Add to shell config
    if [ -f ~/.bashrc ]; then
        if ! grep -q "mcfly init" ~/.bashrc; then
            echo 'eval "$(mcfly init bash)"' >> ~/.bashrc
        fi
    fi

    if [ -f ~/.zshrc ]; then
        if ! grep -q "mcfly init" ~/.zshrc; then
            echo 'eval "$(mcfly init zsh)"' >> ~/.zshrc
        fi
    fi

    log_success "McFly configured"
}

# Configure xbindkeys
configure_xbindkeys() {
    log_info "Configuring XBindKeys..."

    mkdir -p ~/.config

    cat > ~/.config/xbindkeys.scm << 'EOF'
; XBindKeys configuration

; Volume controls
(start
 (media-audio-lower)
 "pulsemixer --volume -5")

(start
 (media-audio-raise)
 "pulsemixer --volume +5")

(start
 (media-audio-mute)
 "pulsemixer --toggle-mute")

; Brightness controls
(start
 (monitor-brightness-up)
 "brightnessctl set +10%")

(start
 (monitor-brightness-down)
 "brightnessctl set 10%-")

; Screenshot
(start
 (print)
 "grim - | wl-copy")

(start
 (shift print)
 "grim -g \"$(slurp)\" - | wl-copy")
EOF

    log_success "XBindKeys configured"
}

# Configure Firefox
configure_firefox() {
    log_info "Configuring Firefox..."

    mkdir -p ~/.mozilla/firefox/default-release

    cat > ~/.mozilla/firefox/default-release/prefs.js << 'EOF'
// Firefox user preferences (Hyprland optimized)

// Wayland settings
user_pref("widget.wayland-drm-backend", true);
user_pref("widget.disable-user-input-in-offscreen-tabs", false);

// Privacy settings
user_pref("privacy.globalconfig.private_browsing_mode", true);
user_pref("browser.startup.homepage", "https://start.duckduckgo.com");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.pinned", "https://start.duckduckgo.com");

// Disable telemetry
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);

// Enable dark theme
user_pref("browser.theme.dark-theme", true);
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Enable hardware acceleration
user_pref("gfx.webrender.all", true);
user_pref("media.hardware-video-decoding.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// Disable updates (optional)
user_pref("app.update.auto", false);
EOF

    log_success "Firefox configured"
}

# Configure Chrome/Chromium
configure_chrome() {
    log_info "Configuring Chrome/Chromium..."

    local chrome_dirs=(
        "$HOME/.config/google-chrome"
        "$HOME/.config/chromium"
    )

    for dir in "${chrome_dirs[@]}"; do
        if [ -d "$dir" ]; then
            mkdir -p "$dir/Policies/Manual"
            cat > "$dir/Policies/Manual/wayland_policy.json" << 'EOF'
{
  "AutoSelectCertificateForUrls": [],
  "BrowserLoginPromptEnabled": true,
  "ClearBrowsingDataOnExit": [],
  "Disable3DAPIs": false,
  "DisableConnectivityCheck": true,
  "DisableDictionariesDownload": false,
  "DisableExtensions": false,
  "DisableFeatures": [],
  "DisableFontRendering": false,
  "DisableGaiaServices": false,
  "DisablePlatformVerification": false,
  "DisableSandbox": false,
  "DisableSync": true,
  "Enable3DAPIs": true,
  "EnableDisplayCompositor": true,
  "EnableGaiaSync": false,
  "EnableHybridEncryption": true,
  "EnableWaylandServer": true,
  "FileURLPrefix": "",
  "FontRenderHinting": 3,
  "FontScrollableX": false,
  "FontScrollableY": false,
  "HideWebStoreIcon": true,
  "IncognitoEnabled": true,
  "PasswordManagerEnabled": true,
  "ProfileAvatarURL": "",
  "ProfileName": "",
  "PromptForDownloadLocation": true,
  "SavePasswordBulkEntry": true,
  "ScreenCaptureUseMediaFoundation": false,
  "ScriptingAllowDocumentWrite": true,
  "ScriptingAllowInteraction": true,
  "SecurityDomainIsolationEnabled": true,
  "SitePerProcess": true,
  "SMBVolumeMountOptions": "",
  "SyncEverything": false,
  "SystemDevtoolsLocation": "",
  "SystemLogEnabled": false,
  "UploadFileUsingJavaScript": true,
  "VRModeEnabled": false,
  "WebRtcAllowPrivateIpAddresses": true,
  "WebRtcEnableUdpUnderNAT": true,
  "WebRtcMstcpEnabled": true,
  "WebRtcUdpPortRange": "10000-15000"
}
EOF
        fi
    done

    log_success "Chrome/Chromium configured"
}

# Configure Vim/Neovim
configure_vim() {
    log_info "Configuring Vim/Neovim..."

    mkdir -p ~/.config/nvim
    mkdir -p ~/.vim

    # Basic .vimrc for Vim
    cat > ~/.vimrc << 'EOF'
" Basic settings
set number
set relativenumber
set cursorline
set showcmd
set showmode
set laststatus=2
set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set softtabstop=4
set hidden
set title
set mouse=a
set termguicolors
set guifont=JetBrains\ Mono\ Nerd\ Font:h13

" Color scheme
set background=dark
colorscheme default

" Search settings
set incsearch
set hlsearch
set ignorecase
set smartcase

" Backup settings
set nobackup
set nowritebackup
set undofile
set undodir=~/.vim/undofile

" Line wrapping
set wrap
set linebreak
set textwidth=0
set softlinebreak=1

" File settings
set binary
set bomb
set fileformats=unix,dos,mac
set fileencoding=utf-8

" Autocommands
autocmd bufwritepost .vimrc source $MYVIMRC
autocmd bufwritepost .config/nvim/init.vim source $MYVIMRC
EOF

    # Basic init.vim for Neovim
    cat > ~/.config/nvim/init.vim << 'EOF'
" Neovim basic configuration

" Basic settings
set number
set relativenumber
set cursorline
set showcmd
set showmode
set laststatus=2
set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set softtabstop=4
set hidden
set title
set mouse=a
set termguicolors

" Color scheme
set background=dark
colorscheme default

" Search settings
set incsearch
set hlsearch
set ignorecase
set smartcase

" Backup settings
set nobackup
set nowritebackup
set undofile
set undodir=~/.local/share/nvim/undofile

" Line wrapping
set wrap
set linebreak
set textwidth=0
set softlinebreak=1

" Autocommands
augroup MyAutoCmd
    autocmd!
    autocmd BufWritePost ~/.config/nvim/init.vim source $MYVIMRC
augroup END

" Key mappings
nnoremap <C-s> :w<CR>
vnoremap <C-c> "+y
nnoremap <C-v> "+p
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa<CR>
nnoremap <leader>n :NERDTreeToggle<CR>

" Plugins (optional - requires plugin manager)
" call plug#begin('~/.local/share/nvim/plugged')
" call plug#end()
EOF

    log_success "Vim/Neovim configured"
}

# Configure shell environment
configure_shell() {
    log_info "Configuring shell environment..."

    # Create .profile with common settings
    cat >> ~/.profile << 'EOF'

# Shell configuration additions
# Hyprland Wayland settings
if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    export MOZ_ENABLE_WAYLAND=1
    export SDL_VIDEODRIVER=wayland
    export QT_QPA_PLATFORM=wayland
    export CLUTTER_BACKEND=wayland
    export GDK_BACKEND=wayland
    export EGL_PLATFORM=wayland
    export _JAVA_AWT_WM_NONREPARENTING=1
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=Hyprland
fi

# Add local bin to PATH
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Add Go bin to PATH if installed
if [ -d "$HOME/go/bin" ]; then
    export PATH="$HOME/go/bin:$PATH"
fi

# Enable colored output for ls
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -A'
alias l='ls -CF'

# Enable colored grep output
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# History settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups
shopt -s histappend

# Update window title
export PROMPT_COMMAND='printf "\033]0;%s@%s:%s\007" "${USER}" "${HOSTNAME%%.*}" "${PWD##*/}"'

# Less colors
export LESS="-R"

# Editor settings
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less

# GPG settings
export GPG_TTY=$(tty)

# Starship prompt
if [ -f "$(command -v starship)" ]; then
    eval "$(starship init bash)"
fi

# Zoxide
if [ -f "$(command -v zoxide)" ]; then
    eval "$(zoxide init bash)"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Node env
export NODE_ENV=development
EOF

    # Add to bashrc if not already present
    if [ -f ~/.bashrc ]; then
        if ! grep -q "Shell configuration additions" ~/.bashrc; then
            cat >> ~/.bashrc << 'EOF'

# Hyprland/UbuntuOmarchy additions (skip if already added)
if [ -f ~/.profile ]; then
    source ~/.profile
fi
EOF
        fi
    fi

    # Configure bash completion
    cat >> ~/.bash_completion << 'EOF'
# Hyprland completions
if command -v hyprctl &> /dev/null; then
    complete -C hyprctl hyprctl
fi

# Walker completions
if command -v walker &> /dev/null; then
    complete -C walker walker
fi
EOF

    log_success "Shell environment configured"
}

# Configure git
configure_git() {
    log_info "Configuring Git..."

    # Check if git is already configured
    if ! git config --global user.name &>/dev/null; then
        read -p "Enter your name for Git commits: " git_name
        git config --global user.name "$git_name"
    fi

    if ! git config --global user.email &>/dev/null; then
        read -p "Enter your email for Git commits: " git_email
        git config --global user.email "$git_email"
    fi

    # Common git settings
    git config --global core.editor "nvim"
    git config --global core.pager "less"
    git config --global core.autocrlf input
    git config --global core.filemode true
    git config --global core.precomposeunicode true
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global push.default simple
    git config --global credential.helper store
    git config --global color.ui auto
    git config --global color.branch auto
    git config --global color.diff auto
    git config --global color.status auto
    git config --global core.pager "less -RX"
    git config --global log.date iso8601

    # Aliases
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.hist "log --oneline --graph --all"
    git config --global alias.last "log -1 HEAD"
    git config --global alias.unstage "reset HEAD --"
    git config --global alias.ignore "echo"  # Placeholder

    # GitHub CLI settings (if installed)
    if command -v gh &>/dev/null; then
        gh auth status 2>/dev/null || true
    fi

    log_success "Git configured"
}

# Configure Docker
configure_docker() {
    log_info "Configuring Docker..."

    # Create Docker config directory
    mkdir -p ~/.config/docker

    # Docker config
    cat > ~/.config/docker/config.json << 'EOF'
{
    "default-runtime": "runc",
    "runtimes": {
        "runc": {
            "path": "runc"
        }
    },
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "hosts": [
        "unix:///var/run/docker.sock"
    ]
}
EOF

    # Add user to docker group if not already
    if ! groups $USER | grep -q docker; then
        sudo usermod -aG docker $USER
        log_info "Added user to docker group. Please logout and login for changes to take effect."
    fi

    # Docker Compose config
    mkdir -p ~/.config/docker-compose
    cat > ~/.config/docker-compose/config.yml << 'EOF'
version: '3.8'

services:
  # Example service - customize as needed
  example:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
EOF

    log_success "Docker configured"
}

# Configure SSH
configure_ssh() {
    log_info "Configuring SSH..."

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh

    cat > ~/.ssh/config << 'EOF'
# SSH Configuration

Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ForwardAgent yes
    ForwardX11 yes
    ForwardX11Trusted yes
    Compression yes
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentityAgent ~/Library/Keychain/ssh-socket 2>/dev/null || echo ~/.ssh/ssh-agent.sock

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

# GitLab
Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519

# Bitbucket
Host bitbucket.org
    HostName bitbucket.org
    User git
    IdentityFile ~/.ssh/id_ed25519

# Custom servers
Host server
    HostName your-server-ip
    User your-username
    Port 22
    IdentityFile ~/.ssh/id_ed25519

# Jump hosts
Host jump
    HostName jump-server-ip
    User jump-user
    IdentityFile ~/.ssh/id_ed25519

Host behind-jump
    HostName internal-server-ip
    User internal-user
    ProxyJump jump
    IdentityFile ~/.ssh/id_ed25519
EOF

    chmod 600 ~/.ssh/config

    # Generate SSH key if none exists
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        log_info "Generating SSH key..."
        ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f ~/.ssh/id_ed25519 -N ""
        log_success "SSH key generated. Add this to your GitHub/GitLab:"
        cat ~/.ssh/id_ed25519.pub
    fi

    log_success "SSH configured"
}

# Configure tmux
configure_tmux() {
    log_info "Configuring Tmux..."

    mkdir -p ~/.config/tmux

    cat > ~/.config/tmux/tmux.conf << 'EOF'
# Tmux configuration

# Basic settings
set -g prefix C-a
bind C-a send-prefix

# Window management
set -g renumber-windows on
set -g mouse on
set -g status-keys vi

# Colors - Dracula theme
set -g status-style bg="#1e1e2e",fg="#cdd6f4"
set -g window-style bg="#262633",fg="#b4befe"
set -g window-status-current-style bg="#89b4fa",fg="#1e1e2e",bold
set -g pane-border-style fg="#313244"
set -g pane-active-border-style fg="#89b4fa"

# Status bar
set -g status-justify centre
set -g status-interval 5
set -g status-left-length 20
set -g status-right-length 50
set -g status-left "#[fg=#f38ba8]#S #[fg=#b4befe]%H:%M"
set -g status-right "#[fg=#a6e3a1]#(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 'AC')% #[fg=#89b4fa]%d %b"

# Pane management
bind h resize-pane -L 5
bind j resize-pane -D 5
bind k resize-pane -U 5
bind l resize-pane -R 5

# Window navigation
bind-key -r C-h select-window -t :-
bind-key -r C-l select-window -t :+

# Copy mode
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection
bind-key -T copy-mode-vi Escape send-keys -X cancel

# Quick commands
bind C-c new-window -c "#{pane_current_path}"
bind C-v split-window -c "#{pane_current_path}"
bind C-x kill-pane

# Save/restore sessions
bind C-s run-shell "tmux ls > /tmp/tmux-saved"
bind C-r run-shell "tmux attach -t $(head -1 /tmp/tmux-saved | cut -d: -f1 | tr -d ' ')"
EOF

    log_success "Tmux configured"
}

# Install Hyprland user scripts
install_hyprland_scripts() {
    log_info "Installing Hyprland helper scripts..."

    # Create scripts directory
    mkdir -p ~/.local/bin

    # Hyprland window close all
    cat > ~/.local/bin/hyprland-window-close-all << 'EOF'
#!/bin/bash
# Close all windows on current workspace

hyprctl dispatch closeactive all
EOF
    chmod +x ~/.local/bin/hyprland-window-close-all

    # Hyprland workspace toggle gaps
    cat > ~/.local/bin/hyprland-workspace-toggle-gaps << 'EOF'
#!/bin/bash
# Toggle gaps on current workspace

current_ws=$(hyprctl active workspace -j | jq -r '.id')
current_gaps=$(hyprctl getoption gapsIn -j | jq -r '.int')

if [ "$current_gaps" -eq 0 ]; then
    hyprctl keyword gapsIn 5
    hyprctl keyword gapsOut 10
    hyprctl keyword windowGapRemoveEdge 1
else
    hyprctl keyword gapsIn 0
    hyprctl keyword gapsOut 0
    hyprctl keyword windowGapRemoveEdge 0
fi
EOF
    chmod +x ~/.local/bin/hyprland-workspace-toggle-gaps

    # Screenshot script
    cat > ~/.local/bin/omarchy-cmd-screenshot << 'EOF'
#!/bin/bash
# Screenshot tool for Hyprland

smart=${1:-}
clipboard=${2:-}

screenshot_dir="$HOME/Pictures/Screenshots"
mkdir -p "$screenshot_dir"

timestamp=$(date +%Y%m%d_%H%M%S)
filename="$screenshot_dir/screenshot_${timestamp}.png"

if [ "$smart" = "smart" ]; then
    # Usegrim and slurp for region selection
    selected=$(slurp 2>/dev/null)
    if [ -n "$selected" ]; then
        grim -g "$selected" "$filename"
        if [ "$clipboard" = "clipboard" ]; then
            wl-copy < "$filename"
        fi
        notify-send "Screenshot saved" "$filename"
    fi
else
    # Full screen
    grim "$filename"
    if [ "$clipboard" = "clipboard" ]; then
        wl-copy < "$filename"
    fi
    notify-send "Screenshot saved" "$filename"
fi
EOF
    chmod +x ~/.local/bin/omarchy-cmd-screenshot

    # Screenrecord script
    cat > ~/.local/bin/omarchy-cmd-screenrecord << 'EOF'
#!/bin/bash
# Screen recording tool

recording_pid=$(pgrep -f "obs --startrecording" || true)
 stop_recording=false

for arg in "$@"; do
    if [ "$arg" = "--stop-recording" ]; then
        stop_recording=true
        break
    fi
done

if [ "$stop_recording" = true ]; then
    if [ -n "$recording_pid" ]; then
        kill "$recording_pid"
        notify-send "Screen recording stopped"
    else
        notify-send "No recording in progress"
    fi
    exit 0
fi

# Start recording
recording_dir="$HOME/Videos/Recordings"
mkdir -p "$recording_dir"
timestamp=$(date +%Y%m%d_%H%M%S)
output="$recording_dir/recording_${timestamp}.mkv"

# Record with ffmpeg
ffmpeg -f wayland -i screenshot -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$output" &
recording_pid=$!

notify-send "Screen recording started" "Saving to $output"

# Wait for recording to complete (or be killed)
wait "$recording_pid"
EOF
    chmod +x ~/.local/bin/omarchy-cmd-screenrecord

    # Share script
    cat > ~/.local/bin/omarchy-cmd-share << 'EOF'
#!/bin/bash
# File/folder sharing script

mode=${1:-clipboard}

case "$mode" in
    clipboard)
        # Share clipboard content
        wl-paste | wl-copy
        notify-send "Clipboard shared"
        ;;
    file)
        # Select and share file
        file=$(walker -p "Select file to share...")
        if [ -n "$file" ] && [ -f "$file" ]; then
            wl-copy < "$file"
            notify-send "File copied to clipboard" "$file"
        fi
        ;;
    folder)
        # Select and share folder
        folder=$(walker -p "Select folder to share...")
        if [ -n "$folder" ] && [ -d "$folder" ]; then
            # List files in folder
            tree "$folder" | wl-copy
            notify-send "Folder contents copied" "$folder"
        fi
        ;;
    *)
        echo "Usage: $0 [clipboard|file|folder]"
        ;;
esac
EOF
    chmod +x ~/.local/bin/omarchy-cmd-share

    # Terminal cwd helper
    cat > ~/.local/bin/omarchy-cmd-terminal-cwd << 'EOF'
#!/bin/bash
# Get current terminal working directory

if [ -n "$TMUX" ]; then
    # Inside tmux
    cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || echo "$PWD")
else
    cwd="$PWD"
fi

echo "$cwd"
EOF
    chmod +x ~/.local/bin/omarchy-cmd-terminal-cwd

    log_success "Hyprland scripts installed"
}

# Install terminal themes
install_terminal_themes() {
    log_info "Installing terminal themes..."

    # Install Nord theme for terminal
    git clone --depth 1 https://github.com/arcticicestudio/nord-iterm2.git /tmp/nord-theme 2>/dev/null || true
    if [ -d /tmp/nord-theme ]; then
        cp -r /tmp/nord-theme/src/terminal ~/.config/nord-theme 2>/dev/null || true
        rm -rf /tmp/nord-theme
    fi

    # Dracula theme
    git clone --depth 1 https://github.com/dracula/kitty.git /tmp/dracula-kitty 2>/dev/null || true
    if [ -d /tmp/dracula-kitty ]; then
        cat /tmp/dracula-kitty/config >> ~/.config/kitty/kitty.conf 2>/dev/null || true
        rm -rf /tmp/dracula-kitty
    fi

    log_success "Terminal themes installed"
}

# Set up theme manager
setup_theme_manager() {
    log_info "Setting up theme manager..."

    # Create theme installation script
    cat > ~/.local/bin/omarchy-theme-install << 'EOF'
#!/bin/bash
# Theme installation manager

echo "Available themes:"
echo "  1. Nord"
echo "  2. Dracula"
echo "  3. Gruvbox"
echo "  4. OneDark"
echo "  5. Catppuccin"
echo "  6. Ayu"
echo ""

read -p "Select theme number: " choice

case "$choice" in
    1)
        # Install Nord
        sudo apt install -y papirus-icon-theme
        gsettings set org.gnome.desktop.interface theme "Nord"
        gsettings set org.gnome.desktop.interface icon-theme "Nord"
        gsettings set org.gnome.desktop.interface cursor-theme "Nord"
        ;;
    2)
        # Install Dracula
        gsettings set org.gnome.desktop.interface theme "Dracula"
        gsettings set org.gnome.desktop.interface icon-theme "Dracula"
        ;;
    3)
        # Install Gruvbox
        gsettings set org.gnome.desktop.interface theme "gruvbox-dark"
        ;;
    4)
        # Install OneDark
        gsettings set org.gnome.desktop.interface theme "OneDark"
        ;;
    5)
        # Install Catppuccin
        gsettings set org.gnome.desktop.interface theme "Catppuccin-Mocha"
        ;;
    6)
        # Install Ayu
        gsettings set org.gnome.desktop.interface theme "ayu-dark"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo "Theme applied successfully!"
EOF
    chmod +x ~/.local/bin/omarchy-theme-install

    log_success "Theme manager set up"
}

# Install font manager
setup_font_manager() {
    log_info "Setting up font manager..."

    cat > ~/.local/bin/omarchy-font-set << 'EOF'
#!/bin/bash
# Font manager

if [ "$1" = "list" ]; then
    fc-list | cut -d: -f1 | sort -u
elif [ -n "$1" ]; then
    font="$1"
    gsettings set org.gnome.desktop.interface font-name "$font"
    gsettings set org.gnome.desktop.interface monospace-font-name "${font} 10"
    echo "Font set to: $font"
else
    echo "Usage: $0 [list|<font-name>]"
fi
EOF
    chmod +x ~/.local/bin/omarchy-font-set

    log_success "Font manager set up"
}

# Install terminal launcher
setup_terminal_launcher() {
    log_info "Setting up terminal launcher..."

    cat > ~/.local/bin/omarchy-launch-editor << 'EOF'
#!/bin/bash
# Launch editor (vim/nvim)

if command -v nvim &>/dev/null; then
    uwsm-app -- nvim "$@"
elif command -v vim &>/dev/null; then
    uwsm-app -- vim "$@"
else
    uwsm-app -- editor "$@"
fi
EOF
    chmod +x ~/.local/bin/omarchy-launch-editor

    cat > ~/.local/bin/omarchy-launch-tui << 'EOF'
#!/bin/bash
# Launch TUI application

app="$1"
shift

case "$app" in
    lazygit)
        uwsm-app -- lazygit "$@"
        ;;
    btop)
        uwsm-app -- btop "$@"
        ;;
    htop)
        uwsm-app -- htop "$@"
        ;;
    *)
        echo "Unknown TUI: $app"
        exit 1
        ;;
esac
EOF
    chmod +x ~/.local/bin/omarchy-launch-tui

    log_success "Terminal launcher set up"
}

# Configure network manager
configure_networkmanager() {
    log_info "Configuring NetworkManager..."

    # Enable nm-applet for system tray
    sudo apt install -y nm-tray network-manager-gnome 2>/dev/null || true

    log_success "NetworkManager configured"
}

# Install additional tools
install_additional_tools() {
    log_info "Installing additional tools..."

    # Install lazydocker
    if ! command -v lazydocker &> /dev/null; then
        curl -sL https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_linux_amd64.tar.gz | tar xz -C /tmp
        sudo mv /tmp/lazydocker /usr/local/bin/
    fi

    # Install lazyvim
    if ! command -v nvim &> /dev/null; then
        sudo apt install -y neovim
    fi

    # Install fzf
    if ! command -v fzf &> /dev/null; then
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --all
    fi

    # Install ripgrep
    if ! command -v rg &> /dev/null; then
        sudo apt install -y ripgrep
    fi

    log_success "Additional tools installed"
}

# Apply desktop settings
apply_desktop_settings() {
    log_info "Applying desktop settings..."

    # Apply common settings
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
    gsettings set org.gnome.desktop.interface icon-theme "Adwaita"
    gsettings set org.gnome.desktop.interface cursor-theme "Adwaita"
    gsettings set org.gnome.desktop.interface font-name "Sans 11"
    gsettings set org.gnome.desktop.interface monospace-font-name "Monospace 10"
    gsettings set org.gnome.desktop.interface document-font-name "Sans 11"
    gsettings set org.gnome.desktop.interface titlebar-font-name "Sans Bold 11"

    # Accessibility
    gsettings set org.gnome.desktop.interface enable-animations true
    gsettings set org.gnome.desktop.interface toolkit-accessibility false

    # Workspace settings
    gsettings set org.gnome.mutter dynamic-workspaces true
    gsettings set org.gnome.mutter center-new-windows true

    # Touchpad settings
    gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true

    # Power settings
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 300

    # Privacy settings
    gsettings set org.gnome.desktop.privacy recent-files-max-age 30
    gsettings set org.gnome.desktop.privacy recent-files-max-age 30

    log_success "Desktop settings applied"
}

# Configure login manager
configure_login_manager() {
    log_info "Configuring login manager..."

    # Configure SDDM (if installed)
    if [ -f /etc/sddm.conf ]; then
        cat >> /etc/sddm.conf << 'EOF'
[Theme]
# Theme configuration
CursorTheme=Adwaita
Current=breeze
EOF
    fi

    log_success "Login manager configured"
}

# Final setup
final_setup() {
    log_info "Running final setup..."

    # Create desktop entry for Hyprland
    if [ ! -f /usr/share/xsessions/Hyprland.desktop ]; then
        cat > /tmp/Hyprland.desktop << 'EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
TryExec=Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
EOF
        sudo mv /tmp/Hyprland.desktop /usr/share/xsessions/Hyprland.desktop
    fi

    # Create Wayland session entry
    if [ ! -f /usr/share/wayland-sessions/Hyprland.desktop ]; then
        cat > /tmp/Hyprland-wayland.desktop << 'EOF'
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
TryExec=Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
EOF
        sudo mv /tmp/Hyprland-wayland.desktop /usr/share/wayland-sessions/Hyprland.desktop
    fi

    # Create desktop entry for launcher
    if [ ! -f ~/.local/share/applications/omarchy-menu.desktop ]; then
        cat > ~/.local/share/applications/omarchy-menu.desktop << 'EOF'
[Desktop Entry]
Name=Omarchy Menu
Comment=Application launcher menu
Exec=walker -p "Launch..."
Icon=system-run
Type=Application
Categories=System;Utility;
Terminal=false
EOF
    fi

    # Create desktop entry for terminal
    if [ ! -f ~/.local/share/applications/org.omarchy.terminal.desktop ]; then
        cat > ~/.local/share/applications/org.omarchy.terminal.desktop << 'EOF'
[Desktop Entry]
Name=Terminal
Comment=Terminal emulator
Exec=kitty
Icon=utilities-terminal
Type=Application
Categories=System;TerminalEmulator;
Terminal=false
StartupNotify=true
EOF
    fi

    # Refresh application cache
    update-desktop-database ~/.local/share/applications 2>/dev/null || true

    log_success "Final setup completed"
}

# Display summary
display_summary() {
    log_info "=== Installation Summary ==="
    echo ""
    echo "System packages installed:"
    echo "  - Hyprland and related packages"
    echo "  - Waybar, Walker, UWSM"
    echo "  - Terminal emulators (Alacritty, Kitty, Ghostty)"
    echo "  - Firefox and Chrome/Chromium configured"
    echo "  - Neovim with configuration"
    echo "  - Git, Docker, SSH configured"
    echo ""
    echo "Configuration files created:"
    echo "  - ~/.config/hypr/hyprland.conf"
    echo "  - ~/.config/waybar/config.jsonc"
    echo "  - ~/.config/walker/config.toml"
    echo "  - ~/.config/swayosd/config.toml"
    echo "  - ~/.config/mako/config"
    echo "  - ~/.config/uwsm/default"
    echo "  - ~/.config/dunst/dunstrc"
    echo "  - ~/.config/alacritty/alacritty.toml"
    echo "  - ~/.config/kitty/kitty.conf"
    echo "  - ~/.config/starship/starship.toml"
    echo "  - ~/.config/nvim/init.vim"
    echo "  - ~/.bashrc and ~/.profile updated"
    echo ""
    echo "Helper scripts installed:"
    echo "  - ~/.local/bin/omarchy-cmd-screenshot"
    echo "  - ~/.local/bin/omarchy-cmd-screenrecord"
    echo "  - ~/.local/bin/omarchy-cmd-share"
    echo "  - ~/.local/bin/omarchy-cmd-terminal-cwd"
    echo "  - ~/.local/bin/omarchy-launch-editor"
    echo "  - ~/.local/bin/omarchy-launch-tui"
    echo ""
    echo "To start Hyprland:"
    echo "  1. Log out of your session"
    echo "  2. Select 'Hyprland' from the session menu"
    echo "  3. Log in"
    echo ""
    echo "To launch the menu, press SUPER (Win key) + S"
    echo "To lock the screen, press SUPER + L"
    echo ""
    log_success "Setup complete! Please reboot or logout to apply changes."
}

# Main installation function
main() {
    echo -e "${CYAN}"
    echo "  ▄████████    ▄████████  ▄█  ████████ "
    echo "  ███    ███   ███    ███ ███  ███   ███"
    echo "  ███    ███   ███    ███ ███▌ ███   ███"
    echo "  ███    ███   ███    ███ ███▌ ███   ███"
    echo "  ███    ███ ▀███████████ ███  ███   ███"
    echo "  ███    ███   ███    ███ ███  ███   ███"
    echo "  ███    ███   ███    ███ ███  ███   ███"
    echo "  ████████▀    ███    █▀  ▀█   ████████ "
    echo -e "${NC}"
    echo "Omarchy-style Hyprland Setup for Ubuntu 24.04"
    echo ""

    # Check for root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root!"
        exit 1
    fi

    # Check for sudo access
    if ! sudo -n true 2>/dev/null; then
        log_warning "Sudo access is required for package installation"
        read -p "Please ensure you have sudo access. Continue? (y/N) " -n 1 -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi

    # Run installation steps
    check_system
    enable_repositories
    install_base_packages
    install_additional_packages
    install_hyprland

    # Create directories and configure
    create_directories
    configure_hyprland
    configure_waybar
    configure_walker
    configure_swayosd
    configure_mako
    configure_uwsm
    configure_dunst
    configure_alacritty
    configure_kitty
    configure_ghostty
    configure_starship
    configure_zoxide
    configure_mcfly
    configure_xbindkeys
    configure_firefox
    configure_chrome
    configure_vim
    configure_shell
    configure_git
    configure_docker
    configure_ssh
    configure_tmux

    # Install scripts
    install_hyprland_scripts
    install_terminal_themes
    setup_theme_manager
    setup_font_manager
    setup_terminal_launcher

    # Additional tools
    install_additional_tools

    # Final setup
    apply_desktop_settings
    configure_login_manager
    final_setup

    # Display summary
    display_summary
}

# Run main function
main "$@"
