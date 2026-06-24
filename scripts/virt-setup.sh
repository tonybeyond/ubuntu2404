#!/usr/bin/env bash
# =============================================================================
# virt-setup.sh — Stack QEMU/KVM + virt-manager
# =============================================================================
# Installe et configure la virtualisation KVM complète.
# L'utilisateur courant peut gérer les VMs SANS sudo grâce à :
#   • Groupes libvirt + kvm
#   • Règle polkit (auth transparente dans virt-manager)
#   • LIBVIRT_DEFAULT_URI=qemu:///system dans .bashrc / .zshrc
#
# Usage (en tant qu'utilisateur normal) :
#   sudo bash /opt/ubuntu2404/scripts/virt-setup.sh
#   sudo bash /opt/debiantrixie/scripts/virt-setup.sh
# =============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
[[ -n "${TARGET_USER}" && "${TARGET_USER}" != "root" ]] \
  || { echo "Lancer avec sudo depuis un compte utilisateur (ex: sudo bash $0)"; exit 1; }
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)

LOG="/var/log/virt-setup.log"
ERROR_COUNT=0

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { printf "${BLUE}  ·${NC}  %s\n" "$*" | tee -a "${LOG}"; }
log_ok()      { printf "${GREEN}  ✓${NC}  %s\n" "$*" | tee -a "${LOG}"; }
log_warn()    { printf "${YELLOW}  ⚠${NC}  %s\n" "$*" | tee -a "${LOG}"; }
log_error()   { printf "${RED}  ✗${NC}  %s\n" "$*" | tee -a "${LOG}" >&2; ((ERROR_COUNT++)) || true; }
log_section() { printf "\n${BOLD}── %s ──${NC}\n" "$*" | tee -a "${LOG}"; }

[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
mkdir -p "$(dirname "${LOG}")"
log_info "=== virt-setup — $(date) ==="
log_info "Utilisateur : ${TARGET_USER}"

# ── 1. Vérifier le support matériel KVM ───────────────────────────────────────
log_section "Support matériel KVM"
CPU_FLAGS=$(grep -oE '(vmx|svm)' /proc/cpuinfo | head -1 || true)
if [[ "${CPU_FLAGS}" == "vmx" ]]; then
  log_ok "Intel VT-x détecté"
elif [[ "${CPU_FLAGS}" == "svm" ]]; then
  log_ok "AMD-V détecté"
else
  log_warn "Virtualisation matérielle non détectée dans /proc/cpuinfo"
  log_warn "Vérifier que VT-x/AMD-V est activé dans le BIOS/UEFI"
  log_warn "KVM sera en mode émulation (lent) si le CPU ne supporte pas"
fi

if [[ -e /dev/kvm ]]; then
  log_ok "/dev/kvm disponible — KVM opérationnel"
else
  log_warn "/dev/kvm absent — modules KVM non chargés"
  modprobe kvm 2>/dev/null && modprobe kvm_intel 2>/dev/null \
    || modprobe kvm_amd 2>/dev/null || true
  [[ -e /dev/kvm ]] && log_ok "Module KVM chargé" \
    || log_warn "KVM non disponible — les VMs tourneront en émulation pure"
fi

# ── 2. Installation des paquets ────────────────────────────────────────────────
log_section "Installation (QEMU + KVM + libvirt + virt-manager)"
apt-get update -q

# Paquets principaux
PKGS=(
  qemu-kvm qemu-utils qemu-system-x86
  libvirt-daemon-system libvirt-daemon-config-network libvirt-clients
  virt-manager virtinst virt-viewer
  bridge-utils dnsmasq iptables
  ovmf                # Firmware UEFI pour VMs
  libguestfs-tools    # Accès filesystem des VMs
)

for pkg in "${PKGS[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    log_ok "déjà présent : $pkg"
  elif apt-get install -y "$pkg" &>/dev/null; then
    log_ok "installé : $pkg"
  else
    log_warn "indisponible : $pkg (paquet optionnel)"
  fi
done

# cpu-checker (disponible sur Ubuntu, absent sur certains Debian)
apt-get install -y cpu-checker &>/dev/null && log_ok "cpu-checker (kvm-ok)" || true

log_ok "Paquets QEMU/KVM installés"

# ── 3. Activer et démarrer libvirtd ───────────────────────────────────────────
log_section "Service libvirtd"
systemctl enable --now libvirtd 2>/dev/null \
  && log_ok "libvirtd actif et activé au démarrage" \
  || log_error "libvirtd : échec"

systemctl enable --now virtlogd 2>/dev/null || true

# ── 4. Groupes utilisateur (libvirt + kvm) ────────────────────────────────────
log_section "Groupes ${TARGET_USER}"
for grp in libvirt libvirt-qemu kvm; do
  if getent group "${grp}" &>/dev/null; then
    if id -nG "${TARGET_USER}" | grep -qw "${grp}"; then
      log_ok "déjà membre du groupe : ${grp}"
    else
      usermod -aG "${grp}" "${TARGET_USER}" \
        && log_ok "ajouté au groupe : ${grp}" \
        || log_error "impossible d'ajouter au groupe : ${grp}"
    fi
  fi
done

# ── 5. Règle polkit — gestion VMs sans sudo ────────────────────────────────────
log_section "polkit (gestion VMs sans authentification)"
POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
mkdir -p "${POLKIT_RULES_DIR}"

cat > "${POLKIT_RULES_DIR}/50-libvirt.rules" << 'POLKIT'
// Membres du groupe libvirt peuvent gérer les VMs sans saisir de mot de passe
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("libvirt")) {
        return polkit.Result.YES;
    }
});
POLKIT
log_ok "Règle polkit : org.libvirt.unix.manage → YES pour groupe libvirt"

# ── 6. Réseau default (NAT virbr0) ────────────────────────────────────────────
log_section "Réseau virtuel default (NAT)"
if virsh --connect qemu:///system net-list --all 2>/dev/null | grep -q "default"; then
  if virsh --connect qemu:///system net-list 2>/dev/null | grep -q "default.*active"; then
    log_ok "Réseau 'default' déjà actif (virbr0)"
  else
    virsh --connect qemu:///system net-start default 2>/dev/null \
      && log_ok "Réseau 'default' démarré" || log_warn "net-start default échoué"
  fi
  virsh --connect qemu:///system net-autostart default 2>/dev/null \
    && log_ok "Réseau 'default' : autostart activé" || true
else
  log_warn "Réseau 'default' non trouvé — libvirtd peut avoir besoin d'un redémarrage"
fi

# ── 7. Storage pool default ───────────────────────────────────────────────────
log_section "Storage pool (images VMs)"
POOL_PATH="/var/lib/libvirt/images"
mkdir -p "${POOL_PATH}"

if virsh --connect qemu:///system pool-list --all 2>/dev/null | grep -q "default"; then
  log_ok "Storage pool 'default' déjà configuré (${POOL_PATH})"
else
  virsh --connect qemu:///system pool-define-as default dir --target "${POOL_PATH}" 2>/dev/null \
    && virsh --connect qemu:///system pool-start default 2>/dev/null \
    && virsh --connect qemu:///system pool-autostart default 2>/dev/null \
    && log_ok "Storage pool 'default' créé → ${POOL_PATH}" \
    || log_warn "Création du storage pool échouée"
fi

# ── 8. Virtualisation imbriquée (nested KVM) ──────────────────────────────────
log_section "Virtualisation imbriquée (nested KVM)"
NESTED=false
if [[ -f /sys/module/kvm_intel/parameters/nested ]]; then
  if [[ "$(cat /sys/module/kvm_intel/parameters/nested)" == "Y" ]] || \
     [[ "$(cat /sys/module/kvm_intel/parameters/nested)" == "1" ]]; then
    log_ok "Nested KVM Intel déjà activé"
    NESTED=true
  else
    echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-nested.conf
    log_ok "Nested KVM Intel activé → /etc/modprobe.d/kvm-nested.conf (effectif au reboot)"
    NESTED=true
  fi
elif [[ -f /sys/module/kvm_amd/parameters/nested ]]; then
  if [[ "$(cat /sys/module/kvm_amd/parameters/nested)" == "Y" ]] || \
     [[ "$(cat /sys/module/kvm_amd/parameters/nested)" == "1" ]]; then
    log_ok "Nested KVM AMD déjà activé"
    NESTED=true
  else
    echo "options kvm_amd nested=1" > /etc/modprobe.d/kvm-nested.conf
    log_ok "Nested KVM AMD activé → /etc/modprobe.d/kvm-nested.conf (effectif au reboot)"
    NESTED=true
  fi
else
  log_warn "Module KVM non chargé — nested KVM non configuré"
fi

# ── 9. Env utilisateur (.bashrc + .zshrc) ────────────────────────────────────
log_section "Variables d'environnement (connexion URI libvirt)"
LIBVIRT_ENV='export LIBVIRT_DEFAULT_URI=qemu:///system'

for rc in "${TARGET_HOME}/.bashrc" "${TARGET_HOME}/.zshrc"; do
  [[ -f "${rc}" ]] || continue
  if grep -q "LIBVIRT_DEFAULT_URI" "${rc}"; then
    log_ok "LIBVIRT_DEFAULT_URI déjà dans $(basename ${rc})"
  else
    echo "" >> "${rc}"
    echo "# KVM / libvirt" >> "${rc}"
    echo "${LIBVIRT_ENV}" >> "${rc}"
    chown "${TARGET_USER}:${TARGET_USER}" "${rc}"
    log_ok "LIBVIRT_DEFAULT_URI ajouté dans $(basename ${rc})"
  fi
done

# ── 10. Résumé ────────────────────────────────────────────────────────────────
echo ""
printf "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗\n"
printf "║  Stack QEMU/KVM installé ✓                                   ║\n"
printf "╠══════════════════════════════════════════════════════════════╣\n"
printf "║  ⚠  DÉCONNEXION/RECONNEXION REQUISE                          ║\n"
printf "║     pour activer les groupes libvirt + kvm                   ║\n"
printf "╠══════════════════════════════════════════════════════════════╣\n"
printf "║  Après reconnexion :                                         ║\n"
printf "║  • virt-manager                 → interface graphique VMs    ║\n"
printf "║  • virsh list --all             → lister les VMs             ║\n"
printf "║  • virsh net-list               → réseaux virtuels           ║\n"
printf "╠══════════════════════════════════════════════════════════════╣\n"
printf "║  Réseau : virbr0 (NAT 192.168.122.0/24)                      ║\n"
printf "║  Images : /var/lib/libvirt/images/                           ║\n"
if [[ "${NESTED}" == true ]]; then
printf "║  Nested KVM : activé (VMs dans VMs possible)                 ║\n"
fi
printf "╠══════════════════════════════════════════════════════════════╣\n"
printf "║  Erreurs : %-3d — Log : /var/log/virt-setup.log              ║\n" "${ERROR_COUNT}"
printf "╚══════════════════════════════════════════════════════════════╝${NC}\n"

exit 0
