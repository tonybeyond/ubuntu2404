#!/bin/bash
set -euo pipefail

# ==============================================================================
# Niri + Tony's Ubuntu Defaults Installer
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[OK] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Check for sudo
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_info "Sudo privileges required."
    sudo -v || exit 1
fi

# 1. System Prep & Dependencies
log_info "Updating system and installing base dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential git curl wget pkg-config unzip \
    libwayland-dev libxkbcommon-dev libgbm-dev libinput-dev libudev-dev \
    libseat-dev libdisplay-info-dev libpango1.0-dev libglib2.0-dev libxml2-dev \
    libpipewire-0.3-dev libspa-0.2-dev libdbus-1-dev libsystemd-dev clang \
    libegl1-mesa-dev xdg-desktop-portal-gnome policykit-1-gnome \
    waybar fuzzel swaybg sway-notification-center fonts-noto-color-emoji

# 2. Install Rust (for Niri)
if ! command -v cargo &> /dev/null; then
    log_info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    log_info "Rust already installed."
fi

# 3. Build & Install Niri
log_info "Building Niri (this may take time)..."
if [ ! -d "$HOME/niri-src" ]; then
    git clone https://github.com/YaLTeR/niri.git "$HOME/niri-src"
fi
cd "$HOME/niri-src"
git pull
cargo build --release
sudo cp target/release/niri /usr/local/bin/
sudo cp resources/niri.desktop /usr/share/wayland-sessions/
sudo cp resources/niri-session /usr/local/bin/

# 4. Install Ghostty (Terminal)
log_info "Installing Ghostty..."
if ! command -v ghostty &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
else
    log_info "Ghostty already installed."
fi

# Download custom Ghostty config
mkdir -p "$HOME/.config/ghostty"
log_info "Fetching Ghostty config..."
curl -fsSL https://raw.githubusercontent.com/tonybeyond/ubuntu2404/refs/heads/main/ghostty/.config/ghostty/config -o "$HOME/.config/ghostty/config"

# 5. Install Vivaldi (Browser)
log_info "Installing Vivaldi..."
if ! command -v vivaldi &>/dev/null; then
    wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/vivaldi-browser.gpg
    echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=$(dpkg --print-architecture)] https://repo.vivaldi.com/archive/deb/ stable main" | sudo tee /etc/apt/sources.list.d/vivaldi.list
    sudo apt update && sudo apt install -y vivaldi-stable
else
    log_info "Vivaldi already installed."
fi

# 6. Install Neovim (Stable Source) + Kickstart
log_info "Installing Neovim from source..."
sudo apt install -y ninja-build gettext cmake unzip curl
if [ ! -d "$HOME/neovim-build" ]; then
    git clone https://github.com/neovim/neovim.git "$HOME/neovim-build" --branch stable --depth 1
else
    cd "$HOME/neovim-build" && git pull
fi
cd "$HOME/neovim-build"
make CMAKE_BUILD_TYPE=RelWithDebInfo
cd build && cpack -G DEB
sudo dpkg -i $HOME/neovim-build/build/nvim-linux-arm64.deb

# Install Kickstart config
if [ ! -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" ]; then
    log_info "Cloning Kickstart.nvim..."
    git clone https://github.com/nvim-lua/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
fi

# 7. Install Zsh + Oh My Zsh + Plugins
log_info "Setting up Zsh..."
sudo apt install -y zsh fzf eza bat
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autocomplete" ] && git clone https://github.com/marlonrichert/zsh-autocomplete.git "$ZSH_CUSTOM/plugins/zsh-autocomplete"

# Download custom .zshrc
log_info "Fetching custom .zshrc..."
curl -fsSL https://raw.githubusercontent.com/tonybeyond/ubuntu2404/refs/heads/main/zsh/new_zshrc -o "$HOME/.zshrc"

# Set Zsh as default
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s "$(which zsh)" "$USER"
fi

# 8. Install Nerd Fonts (Symbols Only for speed, or your pref)
log_info "Installing Nerd Fonts (Symbols Only)..."
mkdir -p "$HOME/.local/share/fonts"
cd "$HOME/Downloads"
wget -N https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip -o NerdFontsSymbolsOnly.zip -d "$HOME/.local/share/fonts/NerdFonts"
fc-cache -f

# 9. Configure Niri (Beautiful + Custom Apps)
log_info "Generating Niri Config..."
mkdir -p "$HOME/.config/niri"
cat <<EOF > "$HOME/.config/niri/config.kdl"
// Niri Configuration - Tony Custom
// Keybinds: Super+HJKL, Super+Return (Ghostty), Super+W (Vivaldi)

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

// Startup
spawn-at-startup "waybar"
spawn-at-startup "swaync"
spawn-at-startup "swaybg" "-c" "#1e1e2e"

binds {
    Mod+Shift+Slash { show-hotkey-overlay; }

    // Applications
    Mod+Return { spawn "ghostty"; }
    Mod+Space { spawn "fuzzel"; }
    Mod+W { spawn "vivaldi"; }

    // Session
    Mod+Q { close-window; }
    Mod+Shift+E { quit; }

    // Vim Navigation
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }
    
    // Scrolling
    Mod+WheelScrollDown { focus-column-right; }
    Mod+WheelScrollUp   { focus-column-left; }
    
    Print { screenshot; }
}
EOF

# 10. Generate Waybar Config (Floating / Catppuccin)
mkdir -p "$HOME/.config/waybar"
cat <<EOF > "$HOME/.config/waybar/config"
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
        "format-icons": { "default": "", "active": "" }
    },
    "clock": { "format": "{:%H:%M  %a %d}" },
    "cpu": { "format": " {usage}%" },
    "memory": { "format": " {}%" },
    "custom/notification": {
        "tooltip": false,
        "format": "",
        "on-click": "swaync-client -t -sw"
    }
}
EOF

cat <<EOF > "$HOME/.config/waybar/style.css"
* { border: none; font-family: "Symbols Nerd Font", sans-serif; font-size: 14px; font-weight: bold; }
window#waybar { background: transparent; }
.modules-left, .modules-center, .modules-right {
    background: #1e1e2e;
    border-radius: 12px;
    padding: 0 10px;
    border: 1px solid #45475a;
    color: #cdd6f4;
}
#workspaces button.active { color: #cba6f7; }
EOF

log_success "Installation Complete! Please reboot to enter your new setup."
