#!/usr/bin/env bash

#------------------------------------------------------------------------------
# newubuntu.sh - Secure & Reliable Ubuntu Tweak Script
#------------------------------------------------------------------------------
# Usage: bash ./newubuntu.sh
# Description: Automates removal of unwanted GNOME apps, installs useful tooling,
# fetches fonts and shells, sets up locales, installs browsers, terminals, and
# configures advanced dev environment.
#------------------------------------------------------------------------------

set -euo pipefail

# --- Variables ---
downloads_path="${HOME}/Downloads"
log_file="${downloads_path}/install.log"
mkdir -p "${downloads_path}" && touch "${log_file}"
chmod 600 "${log_file}"

# --- Functions ---
log_error() { echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $*" >> "${log_file}"; }

is_package_installed() { dpkg -s "$1" &>/dev/null; }

check_sudo_or_exit() {
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo/root privileges." >&2
    sudo -v
  fi
}

remove_unwanted_packages() {
  echo "Removing unwanted GNOME packages..."
  local packages=(
    gnome-games evolution cheese gnome-maps gnome-music gnome-sound-recorder
    rhythmbox gnome-weather gnome-clocks gnome-contacts gnome-characters
  )
  local thunderbird_packages=($(apt list --installed 2>/dev/null | grep thunderbird | awk -F/ '{print $1}'))
  local libreoffice_packages=($(apt list --installed 2>/dev/null | grep libreoffice | awk -F/ '{print $1}'))
  for package in "${packages[@]}"; do
    if is_package_installed "$package"; then
      sudo apt remove -y "$package" || log_error "Failed to remove $package"
    fi
  done
  [[ ${#thunderbird_packages[@]} -gt 0 ]] && sudo apt remove -y "${thunderbird_packages[@]}" || log_error "Failed to remove Thunderbird"
  [[ ${#libreoffice_packages[@]} -gt 0 ]] && sudo apt remove -y "${libreoffice_packages[@]}" || log_error "Failed to remove LibreOffice"
  sudo apt autoremove --purge -y
  sudo apt autoclean
}

install_packages() {
  sudo apt update
  sudo apt install -y "$@" || log_error "Failed to install: $*"
}

install_git() { is_package_installed git || install_packages git; }

install_other_packages() {
  local packages=(
    curl zsh gnome-tweaks btop hyfetch flameshot xclip gimagereader tesseract-ocr
    tesseract-ocr-fra tesseract-ocr-eng gnome-shell-extension-appindicator
    gnome-shell-extension-manager wget build-essential node-typescript bat nala
    vlc eza fzf
  )
  local failed_packages=()
  for package in "${packages[@]}"; do
    is_package_installed "$package" || install_packages "$package" || failed_packages+=("$package")
  done
  [[ ${#failed_packages[@]} -gt 0 ]] && log_error "Failed to install: ${failed_packages[*]}"
}

install_virtualization() {
  echo "Installing virtualization stack (QEMU/KVM)..."
  install_packages qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virtinst libvirt-daemon virt-manager
  sudo virsh net-start default
  sudo virsh net-autostart default
  sudo systemctl enable libvirtd
  sudo systemctl start libvirtd
  sudo adduser "$USER" libvirt
  sudo adduser "$USER" libvirt-qemu
}

install_nerd_fonts() {
  cd "${downloads_path}" || log_error "cd ${downloads_path} failed"
  [[ -d nerd-fonts ]] || git clone https://github.com/ryanoasis/nerd-fonts.git --depth=1
  cd nerd-fonts || log_error "cd nerd-fonts failed"
  ./install.sh || log_error "Nerd Fonts install failed"
}

install_brave_browser() {
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
  install_packages brave-browser
}

install_ghostty() {
  cd "${downloads_path}" || log_error "cd ${downloads_path} failed"
  [[ -d ghostty ]] || git clone https://github.com/mitchellh/ghostty.git --depth=1
  cd ghostty || log_error "cd ghostty failed"
  install_packages libgtk-4-dev libpango1.0-dev libglib2.0-dev libfontconfig-dev libgtkmm-4.0-dev zig
  zig build -Doptimize=ReleaseSafe || log_error "Ghostty build failed"
  mkdir -p "$HOME/.local/bin"
  cp zig-out/bin/ghostty "$HOME/.local/bin/" || log_error "Ghostty binary copy failed"
  [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
  mkdir -p "$HOME/.local/share/applications"
  cat > "$HOME/.local/share/applications/ghostty.desktop" << EOF
[Desktop Entry]
Name=Ghostty
Comment=A fast, feature-rich terminal emulator
Exec=$HOME/.local/bin/ghostty
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;TerminalEmulator;
StartupNotify=true
EOF
}

install_snaps() {
  sudo snap install notion-snap-reborn || log_error "Failed notion-snap-reborn"
  sudo snap install vscode --classic || log_error "Failed vscode"
}

modify_locales() {
  sudo sed -i 's/# fr_CH.UTF/fr_CH.UTF/' /etc/locale.gen
  sudo locale-gen
}

install_pop_shell() {
  cd "${downloads_path}" || log_error "cd ${downloads_path} failed"
  [[ -d shell ]] || git clone https://github.com/pop-os/shell.git --depth=1
  cd shell || log_error "cd shell failed"
  make local-install || log_error "Pop Shell install failed"
}

install_neovim() {
  cd "${downloads_path}" || log_error "cd ${downloads_path} failed"
  [[ -d neovim ]] || git clone https://github.com/neovim/neovim --branch=stable --depth=1
  cd neovim || log_error "cd neovim failed"
  make CMAKE_BUILD_TYPE=RelWithDebInfo || log_error "Neovim build failed"
  cd build && cpack -G DEB && sudo dpkg -i nvim-linux64.deb || log_error "Install Neovim failed"
  local kickstart_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  [[ -d "$kickstart_config_dir" ]] || git clone https://github.com/nvim-lua/kickstart.nvim.git "$kickstart_config_dir"
}

install_debs() {
  local deb_urls=("https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_136.0.3240.76-1_amd64.deb?brand=M102")
  local deb_names=("edge.deb")
  for i in "${!deb_urls[@]}"; do
    wget "${deb_urls[$i]}" -O "${deb_names[$i]}" || log_error "Download ${deb_names[$i]} failed"
    sudo dpkg -i "${deb_names[$i]}" || log_error "Install ${deb_names[$i]} failed"
  done
}

install_oh_my_zsh() {
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || log_error "Oh My Zsh install failed"
  ZSH_CUSTOM=${ZSH_CUSTOM:-"$HOME/.oh-my-zsh/custom"}
  [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] || git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [[ -d "$ZSH_CUSTOM/plugins/zsh-autocomplete" ]] || git clone https://github.com/marlonrichert/zsh-autocomplete.git "$ZSH_CUSTOM/plugins/zsh-autocomplete"
  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak-$(date +%Y%m%d-%H%M%S)"
  sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-autocomplete)/g' "$HOME/.zshrc"
}

# --- Script Entry Point ---
check_sudo_or_exit

echo "------------------------- Running Ubuntu setup tool -------------------------"
remove_unwanted_packages
install_git
install_other_packages
install_nerd_fonts
#install_brave_browser
install_virtualization
#install_snaps
#modify_locales
#install_debs
install_neovim
install_ghostty
install_oh_my_zsh
install_pop_shell
echo "Installation completed. Rebooting..."
sudo reboot
