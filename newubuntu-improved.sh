#!/usr/bin/env bash

#------------------------------------------------------------------------------
# newubuntu.sh - Secure & Reliable Ubuntu 24.04 Tweak Script (IMPROVED)
#------------------------------------------------------------------------------
# Usage: bash ./newubuntu.sh
# Description: Automates removal of unwanted GNOME apps, installs useful tooling,
# fetches fonts and shells, sets up locales, installs browsers, terminals, and
# configures advanced dev environment with comprehensive error handling.
#------------------------------------------------------------------------------

set -euo pipefail

# --- Variables ---
downloads_path="${HOME}/Downloads"
log_file="${downloads_path}/install.log"
error_count=0
mkdir -p "${downloads_path}" && touch "${log_file}"
chmod 600 "${log_file}"

# --- Functions ---
log_info() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - INFO: $*" | tee -a "${log_file}"
}

log_error() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "${log_file}" >&2
  ((error_count++))
}

log_success() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - SUCCESS: $*" | tee -a "${log_file}"
}

is_package_installed() {
  dpkg -s "$1" &>/dev/null
}

check_sudo_or_exit() {
  if [[ "$EUID" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_info "This script requires sudo/root privileges."
    sudo -v || { log_error "Failed to obtain sudo privileges"; exit 1; }
  fi
}

remove_unwanted_packages() {
  log_info "Removing unwanted GNOME packages..."
  local packages=(
    gnome-games evolution cheese gnome-maps gnome-music gnome-sound-recorder
    rhythmbox gnome-weather gnome-clocks gnome-contacts gnome-characters
  )
  
  # Get installed Thunderbird and LibreOffice packages dynamically
  local thunderbird_packages=($(apt list --installed 2>/dev/null | grep -i thunderbird | awk -F/ '{print $1}' || true))
  local libreoffice_packages=($(apt list --installed 2>/dev/null | grep -i libreoffice | awk -F/ '{print $1}' || true))
  
  for package in "${packages[@]}"; do
    if is_package_installed "$package"; then
      sudo apt remove -y "$package" || log_error "Failed to remove $package"
    fi
  done
  
  if [[ ${#thunderbird_packages[@]} -gt 0 ]]; then
    sudo apt remove -y "${thunderbird_packages[@]}" || log_error "Failed to remove Thunderbird packages"
  fi
  
  if [[ ${#libreoffice_packages[@]} -gt 0 ]]; then
    sudo apt remove -y "${libreoffice_packages[@]}" || log_error "Failed to remove LibreOffice packages"
  fi
  
  sudo apt autoremove --purge -y || log_error "Failed to autoremove packages"
  sudo apt autoclean || log_error "Failed to autoclean"
  log_success "Unwanted packages removed"
}

install_packages() {
  local failed_pkgs=()
  for pkg in "$@"; do
    if ! sudo apt install -y "$pkg" 2>>"${log_file}"; then
      failed_pkgs+=("$pkg")
      log_error "Failed to install: $pkg"
    fi
  done
  
  if [[ ${#failed_pkgs[@]} -gt 0 ]]; then
    log_error "Package installation failures: ${failed_pkgs[*]}"
    return 1
  fi
  return 0
}

install_git() {
  log_info "Checking git installation..."
  if ! is_package_installed git; then
    sudo apt update || { log_error "apt update failed"; return 1; }
    install_packages git || { log_error "git installation failed"; return 1; }
  fi
  log_success "git is installed"
}

install_other_packages() {
  log_info "Installing system packages..."
  sudo apt update || { log_error "apt update failed"; return 1; }
  
  local packages=(
    curl zsh gnome-tweaks btop hyfetch flameshot xclip gimagereader tesseract-ocr
    tesseract-ocr-fra tesseract-ocr-eng gnome-shell-extension-appindicator
    gnome-shell-extension-manager wget build-essential node-typescript bat nala
    vlc eza fzf
  )
  
  local failed_packages=()
  for package in "${packages[@]}"; do
    if ! is_package_installed "$package"; then
      if ! sudo apt install -y "$package" 2>>"${log_file}"; then
        failed_packages+=("$package")
        log_error "Failed to install: $package"
      fi
    fi
  done
  
  if [[ ${#failed_packages[@]} -gt 0 ]]; then
    log_error "Some packages failed to install: ${failed_packages[*]}"
    return 1
  fi
  
  log_success "System packages installed"
  return 0
}

install_virtualization() {
  log_info "Installing virtualization stack (QEMU/KVM)..."
  
  if ! install_packages qemu-kvm libvirt-clients libvirt-daemon-system bridge-utils virtinst libvirt-daemon virt-manager; then
    log_error "Virtualization package installation failed"
    return 1
  fi
  
  # Start default network
  if ! sudo virsh net-list --all | grep -q default; then
    log_error "Default libvirt network not found"
  else
    sudo virsh net-start default 2>/dev/null || log_info "Default network already started"
    sudo virsh net-autostart default || log_error "Failed to autostart default network"
  fi
  
  # Enable and start libvirtd
  sudo systemctl enable libvirtd || log_error "Failed to enable libvirtd"
  sudo systemctl start libvirtd || log_error "Failed to start libvirtd"
  
  # Add user to libvirt groups
  sudo adduser "$USER" libvirt || log_info "User already in libvirt group"
  sudo adduser "$USER" libvirt-qemu || log_info "User already in libvirt-qemu group"
  
  log_success "Virtualization stack installed"
}

install_nerd_fonts() {
  log_info "Installing Nerd Fonts..."
  cd "${downloads_path}" || { log_error "cd ${downloads_path} failed"; return 1; }
  
  if [[ -d nerd-fonts ]]; then
    log_info "Nerd Fonts directory exists, pulling updates..."
    cd nerd-fonts || { log_error "cd nerd-fonts failed"; return 1; }
    git pull || log_error "git pull failed"
  else
    log_info "Cloning Nerd Fonts repository..."
    if ! git clone https://github.com/ryanoasis/nerd-fonts.git --depth=1; then
      log_error "Failed to clone Nerd Fonts repository"
      return 1
    fi
    cd nerd-fonts || { log_error "cd nerd-fonts failed"; return 1; }
  fi
  
  # Make install script executable and run it
  if [[ -f install.sh ]]; then
    chmod +x install.sh || { log_error "Failed to make install.sh executable"; return 1; }
    if ./install.sh; then
      log_success "Nerd Fonts installed successfully"
    else
      log_error "Nerd Fonts install.sh failed"
      return 1
    fi
  else
    log_error "install.sh not found in nerd-fonts directory"
    return 1
  fi
  
  cd "${downloads_path}" || log_error "Failed to return to downloads directory"
}

install_vivaldi_browser() {
  log_info "Installing Vivaldi browser..."
  
  # Install dependencies
  if ! is_package_installed curl || ! is_package_installed gnupg; then
    sudo apt update || log_error "apt update failed"
    install_packages curl gnupg || { log_error "Failed to install dependencies"; return 1; }
  fi
  
  # Download and import GPG key
  if ! curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/vivaldi.gpg; then
    log_error "Failed to import Vivaldi GPG key"
    return 1
  fi
  
  # Verify GPG key was imported
  if [[ ! -f /usr/share/keyrings/vivaldi.gpg ]]; then
    log_error "Vivaldi GPG key file not found after import"
    return 1
  fi
  log_info "Vivaldi GPG key imported successfully"
  
  # Add repository using modern .sources format
  cat <<EOF | sudo tee /etc/apt/sources.list.d/vivaldi.sources >/dev/null
Types: deb
URIs: https://repo.vivaldi.com/archive/deb/
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/vivaldi.gpg
EOF
  
  if [[ ! -f /etc/apt/sources.list.d/vivaldi.sources ]]; then
    log_error "Failed to create Vivaldi repository file"
    return 1
  fi
  
  # Update and install
  sudo apt update || { log_error "apt update after adding Vivaldi repo failed"; return 1; }
  
  if install_packages vivaldi-stable; then
    # Remove legacy .list file if exists
    [[ -f /etc/apt/sources.list.d/vivaldi.list ]] && sudo rm -f /etc/apt/sources.list.d/vivaldi.list
    log_success "Vivaldi browser installed"
    
    # Verify installation
    if command -v vivaldi &>/dev/null; then
      vivaldi --version | tee -a "${log_file}"
    fi
  else
    log_error "Vivaldi installation failed"
    return 1
  fi
}

install_ghostty() {
  log_info "Installing Ghostty terminal emulator..."
  cd "${downloads_path}" || { log_error "cd ${downloads_path} failed"; return 1; }
  
  # Detect Ubuntu version
  local ubuntu_version
  ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "24.04")
  log_info "Detected Ubuntu version: ${ubuntu_version}"
  
  # Download appropriate .deb package for Ubuntu 24.04
  local ghostty_deb="ghostty_1.2.3-0.ppa1_amd64_24.04.deb"
  local ghostty_url="https://github.com/mkasberg/ghostty-ubuntu/releases/download/v1.2.3/${ghostty_deb}"
  
  log_info "Downloading Ghostty .deb package..."
  if ! wget -O "${ghostty_deb}" "${ghostty_url}"; then
    log_error "Failed to download Ghostty .deb package"
    return 1
  fi
  
  # Verify file was downloaded
  if [[ ! -f "${ghostty_deb}" ]]; then
    log_error "Ghostty .deb file not found after download"
    return 1
  fi
  
  log_info "Installing Ghostty package..."
  if sudo dpkg -i "${ghostty_deb}"; then
    log_success "Ghostty installed successfully"
    
    # Install any missing dependencies
    sudo apt-get install -f -y || log_error "Failed to fix Ghostty dependencies"
    
    # Verify installation
    if command -v ghostty &>/dev/null; then
      ghostty --version 2>&1 | tee -a "${log_file}" || log_info "Ghostty version check not supported"
    fi
    
    # Clean up downloaded file
    rm -f "${ghostty_deb}"
  else
    log_error "Ghostty dpkg installation failed"
    # Try to fix dependencies
    sudo apt-get install -f -y || log_error "Failed to fix dependencies"
    return 1
  fi
  
  cd "${downloads_path}" || log_error "Failed to return to downloads directory"
}

install_snaps() {
  log_info "Installing snap packages..."
  
  # Check if snapd is installed
  if ! command -v snap &>/dev/null; then
    log_error "snapd is not installed, cannot install snap packages"
    return 1
  fi
  
  # Install notion-snap-reborn
  if sudo snap install notion-snap-reborn 2>>"${log_file}"; then
    log_success "notion-snap-reborn installed"
  else
    log_error "Failed to install notion-snap-reborn"
  fi
  
  # Install vscode
  if sudo snap install vscode --classic 2>>"${log_file}"; then
    log_success "vscode installed"
  else
    log_error "Failed to install vscode"
  fi
}

modify_locales() {
  log_info "Modifying locales..."
  
  # Check if locale exists in locale.gen
  if ! grep -q "fr_CH.UTF" /etc/locale.gen; then
    log_error "fr_CH.UTF locale not found in /etc/locale.gen"
    return 1
  fi
  
  sudo sed -i 's/# fr_CH.UTF/fr_CH.UTF/' /etc/locale.gen || { log_error "Failed to modify locale.gen"; return 1; }
  sudo locale-gen || { log_error "locale-gen failed"; return 1; }
  
  log_success "Locales modified"
}

install_pop_shell() {
  log_info "Installing Pop Shell..."
  cd "${downloads_path}" || { log_error "cd ${downloads_path} failed"; return 1; }
  
  if [[ -d shell ]]; then
    log_info "Pop Shell directory exists, pulling updates..."
    cd shell || { log_error "cd shell failed"; return 1; }
    git pull || log_error "git pull failed"
  else
    log_info "Cloning Pop Shell repository..."
    if ! git clone https://github.com/pop-os/shell.git --depth=1; then
      log_error "Failed to clone Pop Shell repository"
      return 1
    fi
    cd shell || { log_error "cd shell failed"; return 1; }
  fi
  
  # Install dependencies first
  log_info "Installing Pop Shell dependencies..."
  install_packages node-typescript || log_error "Failed to install Pop Shell dependencies"
  
  if make local-install 2>>"${log_file}"; then
    log_success "Pop Shell installed"
  else
    log_error "Pop Shell installation failed"
    return 1
  fi
  
  cd "${downloads_path}" || log_error "Failed to return to downloads directory"
}

install_neovim() {
  log_info "Installing Neovim from source..."
  cd "${downloads_path}" || { log_error "cd ${downloads_path} failed"; return 1; }
  
  # Install build dependencies
  log_info "Installing Neovim build dependencies..."
  if ! install_packages ninja-build gettext cmake unzip curl build-essential; then
    log_error "Failed to install Neovim dependencies"
    return 1
  fi
  
  if [[ -d neovim ]]; then
    log_info "Neovim directory exists, pulling updates..."
    cd neovim || { log_error "cd neovim failed"; return 1; }
    git pull || log_error "git pull failed"
  else
    log_info "Cloning Neovim repository..."
    if ! git clone https://github.com/neovim/neovim --branch=stable --depth=1; then
      log_error "Failed to clone Neovim repository"
      return 1
    fi
    cd neovim || { log_error "cd neovim failed"; return 1; }
  fi
  
  # Build Neovim
  log_info "Building Neovim (this may take a while)..."
  if ! make CMAKE_BUILD_TYPE=RelWithDebInfo 2>>"${log_file}"; then
    log_error "Neovim build failed"
    return 1
  fi
  
  # Create and install DEB package
  cd build || { log_error "cd build failed"; return 1; }
  if cpack -G DEB 2>>"${log_file}"; then
    local deb_file=$(find . -name "nvim-linux64.deb" | head -n1)
    if [[ -z "$deb_file" ]]; then
      log_error "Neovim .deb package not found"
      return 1
    fi
    
    if sudo dpkg -i "$deb_file"; then
      log_success "Neovim installed"
      
      # Verify installation
      if command -v nvim &>/dev/null; then
        nvim --version | head -n1 | tee -a "${log_file}"
      fi
    else
      log_error "Neovim dpkg installation failed"
      return 1
    fi
  else
    log_error "Neovim package creation failed"
    return 1
  fi
  
  # Install kickstart.nvim configuration
  local kickstart_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
  if [[ ! -d "$kickstart_config_dir" ]]; then
    log_info "Installing kickstart.nvim configuration..."
    if git clone https://github.com/nvim-lua/kickstart.nvim.git "$kickstart_config_dir"; then
      log_success "kickstart.nvim configuration installed"
    else
      log_error "Failed to clone kickstart.nvim"
    fi
  else
    log_info "Neovim config directory already exists, skipping kickstart.nvim"
  fi
  
  cd "${downloads_path}" || log_error "Failed to return to downloads directory"
}

install_debs() {
  log_info "Installing additional .deb packages..."
  cd "${downloads_path}" || { log_error "cd ${downloads_path} failed"; return 1; }
  
  # Microsoft Edge
  local edge_url="https://packages.microsoft.com/repos/edge/pool/main/m/microsoft-edge-stable/microsoft-edge-stable_136.0.3240.76-1_amd64.deb"
  local edge_deb="edge.deb"
  
  log_info "Downloading Microsoft Edge..."
  if wget -O "${edge_deb}" "${edge_url}"; then
    if sudo dpkg -i "${edge_deb}"; then
      log_success "Microsoft Edge installed"
      # Fix dependencies if needed
      sudo apt-get install -f -y || log_error "Failed to fix Edge dependencies"
    else
      log_error "Microsoft Edge installation failed"
      sudo apt-get install -f -y || log_error "Failed to fix dependencies"
    fi
    rm -f "${edge_deb}"
  else
    log_error "Failed to download Microsoft Edge"
  fi
  
  cd "${downloads_path}" || log_error "Failed to return to downloads directory"
}

install_oh_my_zsh() {
  log_info "Installing Oh My Zsh..."
  
  # Check if zsh is installed
  if ! command -v zsh &>/dev/null; then
    log_error "zsh is not installed, cannot install Oh My Zsh"
    return 1
  fi
  
  # Check if Oh My Zsh is already installed
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log_info "Oh My Zsh already installed, skipping..."
    return 0
  fi
  
  # Install Oh My Zsh
  if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
    log_success "Oh My Zsh installed"
  else
    log_error "Oh My Zsh installation failed"
    return 1
  fi
  
  # Install plugins
  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  
  # zsh-syntax-highlighting
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    log_info "Installing zsh-syntax-highlighting..."
    if git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"; then
      log_success "zsh-syntax-highlighting installed"
    else
      log_error "Failed to install zsh-syntax-highlighting"
    fi
  fi
  
  # zsh-autosuggestions
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    log_info "Installing zsh-autosuggestions..."
    if git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"; then
      log_success "zsh-autosuggestions installed"
    else
      log_error "Failed to install zsh-autosuggestions"
    fi
  fi
  
  # zsh-autocomplete
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autocomplete" ]]; then
    log_info "Installing zsh-autocomplete..."
    if git clone https://github.com/marlonrichert/zsh-autocomplete.git "$ZSH_CUSTOM/plugins/zsh-autocomplete"; then
      log_success "zsh-autocomplete installed"
    else
      log_error "Failed to install zsh-autocomplete"
    fi
  fi
  
  # Configure plugins in .zshrc
  if [[ -f "$HOME/.zshrc" ]]; then
    # Backup existing .zshrc
    cp "$HOME/.zshrc" "$HOME/.zshrc.bak-$(date +%Y%m%d-%H%M%S)" || log_error "Failed to backup .zshrc"
    
    # Update plugins line if it exists
    if grep -q "^plugins=(" "$HOME/.zshrc"; then
      sed -i 's/^plugins=(.*)$/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-autocomplete)/' "$HOME/.zshrc" || log_error "Failed to update plugins in .zshrc"
      log_success "Updated .zshrc with Oh My Zsh plugins"
    fi
  fi
}

print_summary() {
  echo ""
  echo "============================================================================="
  echo "                    Installation Summary"
  echo "============================================================================="
  echo "Log file location: ${log_file}"
  echo "Total errors encountered: ${error_count}"
  echo ""
  
  if [[ ${error_count} -eq 0 ]]; then
    echo "✓ All installations completed successfully!"
  else
    echo "⚠ Some installations encountered errors. Check the log file for details."
  fi
  
  echo ""
  echo "Installed components:"
  echo "  - System packages (curl, zsh, btop, fzf, etc.)"
  echo "  - Nerd Fonts (from official repository)"
  echo "  - Vivaldi browser"
  echo "  - Ghostty terminal emulator (.deb package)"
  echo "  - QEMU/KVM virtualization"
  echo "  - Neovim with kickstart.nvim"
  echo "  - Pop Shell"
  echo "  - Oh My Zsh with plugins"
  echo ""
  echo "Next steps:"
  echo "  1. Review log file: less ${log_file}"
  echo "  2. Change default shell: chsh -s \$(which zsh)"
  echo "  3. Re-login for libvirt group membership to take effect"
  echo "  4. Reboot for all changes to take effect"
  echo "============================================================================="
}

# --- Script Entry Point ---
log_info "Starting Ubuntu 24.04 setup script"
log_info "Script started by user: ${USER}"
log_info "Date: $(date)"

check_sudo_or_exit

echo "------------------------- Running Ubuntu setup tool -------------------------"

# Execute installation functions with error handling
remove_unwanted_packages || log_error "Unwanted packages removal had issues"
install_git || log_error "Git installation had issues"
install_other_packages || log_error "System packages installation had issues"
install_nerd_fonts || log_error "Nerd Fonts installation had issues"
install_vivaldi_browser || log_error "Vivaldi browser installation had issues"
install_virtualization || log_error "Virtualization installation had issues"
install_ghostty || log_error "Ghostty installation had issues"
install_neovim || log_error "Neovim installation had issues"
install_oh_my_zsh || log_error "Oh My Zsh installation had issues"
install_pop_shell || log_error "Pop Shell installation had issues"

# Optional installations (commented out by default)
# install_snaps || log_error "Snap packages installation had issues"
# modify_locales || log_error "Locale modification had issues"
# install_debs || log_error "Additional .deb packages installation had issues"

print_summary

log_info "Setup script completed with ${error_count} errors"

# Ask user if they want to reboot
echo ""
read -p "Installation completed. Do you want to reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  log_info "Rebooting system..."
  sudo reboot
else
  log_info "Reboot skipped. Please reboot manually when ready."
fi
