#!/bin/bash
set -e

# ==============================================================================
# Niri Installer for Ubuntu 24.04
# Builds Niri from source and configures a beautiful "Catppuccin" environment.
# ==============================================================================

# Colors for outputni
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}>> [1/7] Updating System & Installing Build Dependencies...${NC}"
sudo apt update && sudo apt upgrade -y

# Dependencies for building Niri + Runtime tools
# (Waybar, Fuzzel, Swaybg, Swaync, Kitty, Git, Rust deps)
sudo apt install -y \
    build-essential git curl wget \
    pkg-config libwayland-dev libxkbcommon-dev libgbm-dev \
    libinput-dev libudev-dev libseat-dev libdisplay-info-dev \
    libpango1.0-dev libglib2.0-dev libxml2-dev \
    kitty waybar fuzzel swaybg sway-notification-center \
    xdg-desktop-portal-gnome policykit-1-gnome \
    fonts-noto-color-emoji fonts-font-awesome

# ==============================================================================
# 2. Install Rust (Required to build Niri)
# ==============================================================================
echo -e "${BLUE}>> [2/7] Checking Rust Toolchain...${NC}"
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust via Rustup (standard method)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust is already installed."
fi

# ==============================================================================
# 3. Build & Install Niri
# ==============================================================================
echo -e "${BLUE}>> [3/7] Building Niri (This will take 10-20 mins)...${NC}"
if [ ! -d "$HOME/niri-src" ]; then
    git clone https://github.com/YaLTeR/niri.git "$HOME/niri-src"
fi

cd "$HOME/niri-src"
git pull
cargo build --release

# Install binary to /usr/local/bin
echo "Installing Niri binary..."
sudo cp target/release/niri /usr/local/bin/

# Install Session Files (so it appears in Login Manager)
echo "Installing Desktop Session..."
sudo cp resources/niri.desktop /usr/share/wayland-sessions/
sudo cp resources/niri-session /usr/local/bin/
sudo cp resources/niri.service /usr/lib/systemd/user/
sudo cp resources/niri-shutdown.target /usr/lib/systemd/user/

# Enable systemd user units
systemctl --user daemon-reload

# ==============================================================================
# 4. Setup Directories 
# ==============================================================================
echo -e "${BLUE}>> [4/7] Setting up Directory Structure...${NC}"
CONFIG_DIR="$HOME/.config"
NIRI_CONFIG="$CONFIG_DIR/niri"
WAYBAR_CONFIG="$CONFIG_DIR/waybar"
FUZZEL_CONFIG="$CONFIG_DIR/fuzzel"
SWAYNC_CONFIG="$CONFIG_DIR/swaync"

mkdir -p "$NIRI_CONFIG" "$WAYBAR_CONFIG" "$FUZZEL_CONFIG" "$SWAYNC_CONFIG"

# ==============================================================================
# 5. Generate "Beautiful" Configurations (Catppuccin Mocha Style)
# ==============================================================================
echo -e "${BLUE}>> [5/7] Generating Configs...${NC}"

# --- NIRI CONFIG (config.kdl) ---
cat <<EOF > "$NIRI_CONFIG/config.kdl"
// Niri Configuration - Omarchy Style
// Keybinds: Super+HJKL, Super+Return (Term), Super+Space (Launcher)

input {
    keyboard {
        xkb {
            layout "us"
        }
    }
    touchpad {
        tap
        natural-scroll
    }
}

output "eDP-1" {
    scale 1.0
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
        on
        width 2
        // Beautiful Gradient (Blue to Purple)
        active-gradient from="#89b4fa" to="#cba6f7" angle=45
        inactive-color "#585b70"
    }
}

// Startup Applications
spawn-at-startup "waybar"
spawn-at-startup "swaync"
spawn-at-startup "swaybg" "-c" "#1e1e2e" // Dark background

binds {
    // Keys
    Mod+Shift+Slash { show-hotkey-overlay; }

    // Apps
    Mod+Return { spawn "kitty"; }
    Mod+Space { spawn "fuzzel"; }
    Mod+W { spawn "firefox"; }

    // Session
    Mod+Q { close-window; }
    Mod+Shift+E { quit; }

    // Navigation (Vim Style)
    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    // Moving Windows
    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }
    
    // Scrolling (Infinite Strip)
    Mod+WheelScrollDown { focus-column-right; }
    Mod+WheelScrollUp   { focus-column-left; }

    // Screenshot
    Print { screenshot; }
}
EOF

# --- WAYBAR CONFIG ---
cat <<EOF > "$WAYBAR_CONFIG/config"
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
        "format-icons": {
            "default": "",
            "active": ""
        }
    },
    "clock": {
        "format": "{:%H:%M  %a %d}"
    },
    "cpu": { "format": " {usage}%" },
    "memory": { "format": " {}%" },
    "pulseaudio": { "format": " {volume}%" },
    "battery": { "format": " {capacity}%" },
    "custom/notification": {
        "tooltip": false,
        "format": "",
        "on-click": "swaync-client -t -sw"
    }
}
EOF

# --- WAYBAR STYLE (CSS) ---
cat <<EOF > "$WAYBAR_CONFIG/style.css"
* {
    border: none;
    font-family: "JetBrainsMono Nerd Font", "Font Awesome 6 Free", sans-serif;
    font-size: 14px;
    font-weight: bold;
}

window#waybar {
    background: transparent;
}

.modules-left, .modules-center, .modules-right {
    background: #1e1e2e; /* Mocha Base */
    border-radius: 12px;
    padding: 0 10px;
    border: 1px solid #45475a;
}

#clock { color: #cba6f7; padding: 0 10px; }
#cpu { color: #89b4fa; padding: 0 10px; }
#memory { color: #a6e3a1; padding: 0 10px; }
#pulseaudio { color: #f9e2af; padding: 0 10px; }
#battery { color: #fab387; padding: 0 10px; }

#workspaces button {
    color: #585b70;
    padding: 0 5px;
}
#workspaces button.active {
    color: #cba6f7;
}
EOF

# --- FUZZEL CONFIG (Launcher) ---
cat <<EOF > "$FUZZEL_CONFIG/fuzzel.ini"
[main]
font=JetBrainsMono Nerd Font:size=14
prompt="❯ "
terminal=kitty
width=40
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
EOF

# ==============================================================================
# 6. Final Steps
# ==============================================================================
echo -e "${BLUE}>> [6/7] Finalizing...${NC}"

# Ensure permissions
sudo chmod +x /usr/local/bin/niri*

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN} Niri Installation Complete! ${NC}"
echo "--------------------------------------------------------"
echo "1. Reboot your system: 'sudo reboot'"
echo "2. At the login screen, click the gear icon and select 'Niri'."
echo "--------------------------------------------------------"
echo "Keybinds:"
echo " - Terminal: Super+Enter"
echo " - Launcher: Super+Space"
echo " - Close:    Super+Q"
echo " - Move:     Super+H/L (Left/Right)"
echo "========================================================"
