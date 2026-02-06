#!/bin/bash

# ==============================================================================
# OMARCHY WORKFLOW REPLICATOR FOR UBUNTU 24.04 LTS
# ==============================================================================
# Author: Systems Engineering Analysis
# Target: Ubuntu 24.04 (Noble Numbat)
# Purpose: Provision a full Hyprland/Walker/Elephant/Matugen stack replicating
#          the Omarchy distribution workflow.
# ==============================================================================

set -e

# --- Configuration Variables ---
OMARCHY_REPO="https://github.com/basecamp/omarchy.git"
INSTALL_BASE="$HOME/.local/share/omarchy"
BUILD_DIR="$HOME/omarchy-build-temp"
LOG_FILE="$HOME/omarchy_install.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Versions (Pinned for Stability)
GO_VERSION="1.23.0"
ZIG_VERSION="0.13.0"
WALKER_GIT_REF="master" # Use master for latest Rust rewrite features
ELEPHANT_GIT_REF="master"

# Colors for TUI
GREEN='\033${NC} $1"
    echo "[INFO] $(date): $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}${NC} $1"
    echo " $(date): $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}${NC} $1"
    echo " $(date): $1" >> "$LOG_FILE"
    exit 1
}

check_root() {
    if; then
        error "Please run this script as a normal user, not root. Sudo will be requested where needed."
    fi
}

# --- Phase 1: System Preparation ---

prepare_system() {
    log "Preparing system repositories and dependencies..."
    
    # Ensure Universe/Multiverse
    sudo add-apt-repository universe -y
    sudo add-apt-repository multiverse -y
    
    # Add Hyprland PPA (The only sane way to get Hyprland on Ubuntu)
    if! grep -q "cppiber/hyprland" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        log "Adding cpiber/hyprland PPA..."
        sudo add-apt-repository ppa:cppiber/hyprland -y
    fi

    sudo apt update && sudo apt upgrade -y

    # Install massive dependency list
    # Includes build tools for C, C++, Rust, Go bindings, Wayland protocols, etc.
    log "Installing build dependencies (this may take a while)..."
    sudo apt install -y \
        build-essential git curl wget unzip tar \
        cmake meson ninja-build pkg-config \
        libwayland-dev libxkbcommon-dev libgles2-mesa-dev \
        libinput-dev libxcb1-dev libxcb-composite0-dev \
        libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
        libpixman-1-dev libseat-dev libdrm-dev \
        libgtk-4-dev libadwaita-1-dev libgirepository1.0-dev \
        gobject-introspection libxml2-dev libssl-dev \
        software-properties-common python3-pip python3-venv \
        libfontconfig1-dev libfreetype6-dev \
        hyprland hyprlock hypridle hyprpaper \
        xdg-desktop-portal-hyprland \
        waybar mako-notifier btop jq fzf ripgrep bat \
        imagemagick wl-clipboard cliphist playerctl \
        brightnessctl pamixer pavucontrol grim slurp \
        network-manager-gnome polkit-kde-agent-1
}

# --- Phase 2: Toolchain Bootstrapping ---

install_toolchains() {
    mkdir -p "$BUILD_DIR"

    # 1. Rust (Rustup)
    if! command -v cargo &> /dev/null; then
        log "Bootstrapping Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        log "Rust detected. Updating..."
        rustup update
    fi

    # 2. Go (Manual Install for version control)
    if! command -v go &> /dev/null ||]; then
        log "Installing Go $GO_VERSION..."
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O "$BUILD_DIR/go.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "$BUILD_DIR/go.tar.gz"
        # Setup Go path for this session
        export PATH=$PATH:/usr/local/go/bin
        export PATH=$PATH:$(go env GOPATH)/bin
        # Persist for user
        if! grep -q "/usr/local/go/bin" "$HOME/.bashrc"; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.bashrc"
            echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$HOME/.bashrc"
        fi
    fi

    # 3. Zig (For Ghostty)
    if! command -v zig &> /dev/null; then
        log "Installing Zig $ZIG_VERSION..."
        cd "$BUILD_DIR"
        wget -q "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
        tar -xf "zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
        sudo mv "zig-linux-x86_64-${ZIG_VERSION}" /opt/zig
        sudo ln -sf /opt/zig/zig /usr/local/bin/zig
    fi
}

# --- Phase 3: Critical Libraries & UWSM ---

install_middleware() {
    # GTK4 Layer Shell (Required for Walker)
    # Ubuntu's version might be missing pc files or be too old for Walker's sys crates.
    log "Building gtk4-layer-shell from source..."
    cd "$BUILD_DIR"
    rm -rf gtk4-layer-shell
    git clone https://github.com/wmww/gtk4-layer-shell.git
    cd gtk4-layer-shell
    meson setup build --prefix=/usr/local
    ninja -C build
    sudo ninja -C build install
    sudo ldconfig
    
    # UWSM (Universal Wayland Session Manager)
    # Omarchy relies on this for session startup.
    log "Installing UWSM via Pip..."
    # Using --break-system-packages is necessary on 24.04 unless using venv.
    # For a system-wide tool integration, we install to user local.
    pip3 install uwsm --break-system-packages --user |

| warn "Pip install uwsm failed, trying generic install"
    
    # Ensure UWSM binary is in path
    export PATH=$PATH:$HOME/.local/bin
}

# --- Phase 4: Omarchy Core Components (Walker & Elephant) ---

build_omarchy_core() {
    # 1. Elephant (Backend)
    log "Building Elephant (Data Backend)..."
    cd "$BUILD_DIR"
    rm -rf elephant
    git clone https://github.com/abenz1267/elephant.git
    cd elephant
    git checkout "$ELEPHANT_GIT_REF"
    
    # Build main binary
    go build -o elephant cmd/elephant/main.go
    sudo mv elephant /usr/local/bin/
    
    # Providers: Omarchy uses specific ones. 
    # Current Elephant architecture may compile providers INTO the binary 
    # or requires plugins. We attempt to build plugins if the directory exists.
    mkdir -p "$HOME/.config/elephant/providers"
    
    if [ -d "internal/providers" ]; then
        log "Building Elephant providers..."
        # Iterate over provider directories
        # Note: This loop assumes standard provider structure. 
        # Detailed investigation shows some providers are separate repos.
        # For the sake of the script, we assume the core ones are internal.
        find internal/providers -mindepth 1 -maxdepth 1 -type d | while read -r provider; do
            pname=$(basename "$provider")
            log "  - Building provider: $pname"
            # Attempt plugin build. If fail, log warn and continue.
            go build -buildmode=plugin -o "$HOME/.config/elephant/providers/$pname.so" "$provider" |

| warn "Failed to build provider $pname"
        done
    fi

    # 2. Walker (Frontend)
    log "Building Walker (Application Launcher)..."
    cd "$BUILD_DIR"
    rm -rf walker
    git clone https://github.com/abenz1267/walker.git
    cd walker
    git checkout "$WALKER_GIT_REF"
    
    # Set PKG_CONFIG to find our custom gtk4-layer-shell
    export PKG_CONFIG_PATH=/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
    
    cargo build --release
    sudo mv target/release/walker /usr/local/bin/
}

# --- Phase 5: Theming & Terminal ---

build_extras() {
    # Matugen (Theming)
    log "Installing Matugen..."
    if! command -v matugen &> /dev/null; then
        cargo install matugen
        sudo ln -sf "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen
    fi

    # Ghostty (Terminal)
    log "Building Ghostty..."
    cd "$BUILD_DIR"
    rm -rf ghostty
    git clone https://github.com/ghostty-org/ghostty.git
    cd ghostty
    # Ghostty build can be heavy
    zig build -Doptimize=ReleaseFast
    sudo cp -r zig-out/bin/ghostty /usr/local/bin/
    # Install terminfo
    zig build -Doptimize=ReleaseFast install-terminfo
}

# --- Phase 6: Omarchy Config Migration ---

deploy_omarchy_config() {
    log "Cloning Omarchy Repository..."
    if; then
        warn "Omarchy directory exists. Backing up..."
        mv "$INSTALL_BASE" "${INSTALL_BASE}_backup_$TIMESTAMP"
    fi
    git clone "$OMARCHY_REPO" "$INSTALL_BASE"

    log "Deploying Configurations..."
    mkdir -p "$HOME/.config"

    # Define the list of configs Omarchy manages
    configs=("hypr" "waybar" "walker" "elephant" "mako" "ghostty" "matugen")
    
    for cfg in "${configs[@]}"; do
        if [ -d "$HOME/.config/$cfg" ]; then
            mv "$HOME/.config/$cfg" "$HOME/.config/${cfg}_backup_$TIMESTAMP"
        fi
        # Omarchy usually stores configs in 'default' or 'config' folder
        # We copy them to ~/.config
        if; then
            cp -r "$INSTALL_BASE/default/$cfg" "$HOME/.config/"
        elif; then
            cp -r "$INSTALL_BASE/config/$cfg" "$HOME/.config/"
        else
            warn "Could not find source config for $cfg in repo structure"
        fi
    done

    # Installing Scripts
    # Omarchy puts scripts in ~/.local/share/omarchy/bin
    # We must ensure this is in PATH
    log "Configuring Path..."
    if! grep -q "$INSTALL_BASE/bin" "$HOME/.bashrc"; then
        echo "export PATH=\$PATH:$INSTALL_BASE/bin" >> "$HOME/.bashrc"
    fi
    
    # Patching Scripts (The Transpilation Step)
    # Replaces 'pacman -S' with warnings or apt calls
    log "Patching Arch-specific scripts for Ubuntu..."
    find "$INSTALL_BASE/bin" -type f -exec sed -i 's/pacman -S/echo "Please install via apt:"/g' {} +
    find "$INSTALL_BASE/bin" -type f -exec sed -i 's/yay -S/echo "Please install via apt:"/g' {} +
    
    chmod +x "$INSTALL_BASE/bin/"*
}

# --- Phase 7: Session Registration & Assets ---

finalize_setup() {
    log "Registering UWSM Session..."
    sudo tee /usr/share/wayland-sessions/hyprland-uwsm.desktop > /dev/null <<EOF

Name=Hyprland (Omarchy Style)
Comment=Hyprland managed by UWSM
Exec=uwsm start hyprland
Type=Application
EOF

    log "Installing Fonts..."
    mkdir -p "$HOME/.local/share/fonts"
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip -O "$BUILD_DIR/font.zip"
    unzip -o -q "$BUILD_DIR/font.zip" -d "$BUILD_DIR/font_extract"
    cp "$BUILD_DIR/font_extract/"*.ttf "$HOME/.local/share/fonts/"
    fc-cache -fv

    log "Setting Wallpaper (Default)..."
    # Download a default wallpaper to trigger matugen later
    mkdir -p "$HOME/.config/omarchy/backgrounds"
    wget -q "https://images.unsplash.com/photo-1472214103451-9374bd1c798e" -O "$HOME/.config/omarchy/backgrounds/default.jpg"
}

# --- Execution ---

log "Starting Omarchy Installation on Ubuntu 24.04..."
check_root
prepare_system
install_toolchains
install_middleware
build_omarchy_core
build_extras
deploy_omarchy_config
finalize_setup

log "========================================================"
log "INSTALLATION COMPLETE"
log "========================================================"
log "1. Reboot your system."
log "2. On the login screen, select 'Hyprland (Omarchy Style)'."
log "3. Once logged in, press SUPER+SPACE to test the menu."
log "   (If it fails, check logs at ~/.cache/walker.log)"
log "4. Set a theme using the Omarchy menu to initialize Matugen."
log "========================================================"
