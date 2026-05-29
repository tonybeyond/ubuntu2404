#!/usr/bin/env bash
# =============================================================================
# bash-setup.sh — Bash shell enhancement
# ble.sh · Starship · fzf · eza · Hack Nerd Font
# =============================================================================
# À lancer en tant qu'utilisateur normal (pas root) :
#   bash /opt/ubuntu2404/scripts/bash-setup.sh
# =============================================================================

set -euo pipefail

log_info()  { echo "[$(date +'%H:%M:%S')] ·     $*"; }
log_ok()    { echo "[$(date +'%H:%M:%S')] ✓     $*"; }
log_error() { echo "[$(date +'%H:%M:%S')] ✗     $*" >&2; }

[[ $EUID -ne 0 ]] || { echo "Lancer sans sudo (en tant qu'utilisateur normal)."; exit 1; }

# ── 1. Dépendances apt ────────────────────────────────────────────────────────
log_info "Dépendances apt..."
sudo apt install -y git curl fzf bash-completion gawk eza unzip \
  && log_ok "Dépendances OK" || log_error "Certains paquets ont échoué, on continue"

# ── 2. ble.sh ─────────────────────────────────────────────────────────────────
log_info "ble.sh (autosuggestions + syntax highlighting bash)..."
if [[ ! -d "${HOME}/ble.sh" ]]; then
  git clone --recursive --depth 1 --shallow-submodules \
    https://github.com/akinomyoga/ble.sh.git "${HOME}/ble.sh"
fi
make -C "${HOME}/ble.sh" install PREFIX=~/.local \
  && log_ok "ble.sh installé" || log_error "ble.sh build failed"

# ── 3. Starship prompt ────────────────────────────────────────────────────────
log_info "Starship prompt..."
if ! command -v starship &>/dev/null; then
  curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    && log_ok "Starship installé" || log_error "Starship install failed"
else
  log_ok "Starship déjà présent"
fi

# Config Starship (prompt deux lignes, style minimaliste)
mkdir -p "${HOME}/.config"
if [[ ! -f "${HOME}/.config/starship.toml" ]]; then
  cat > "${HOME}/.config/starship.toml" << 'TOML'
# Starship — deux lignes, info contextuelle
format = """
$os$username$hostname$directory$git_branch$git_status$python$nodejs$rust$golang$docker_context
$character"""

[os]
disabled = false
[os.symbols]
Ubuntu = " "

[username]
style_user  = "bold green"
style_root  = "bold red"
show_always = true
format      = "[$user]($style)@"

[hostname]
ssh_only = false
format   = "[$hostname](bold blue) "

[directory]
truncation_length = 3
style             = "bold cyan"

[git_branch]
format = "[$symbol$branch]($style) "
style  = "bold yellow"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
TOML
  log_ok "Config Starship créée"
fi

# ── 4. Hack Nerd Font ─────────────────────────────────────────────────────────
log_info "Hack Nerd Font..."
FONT_DIR="${HOME}/.local/share/fonts/HackNerdFont"
if [[ ! -d "${FONT_DIR}" ]]; then
  mkdir -p "${FONT_DIR}"
  curl -fLo /tmp/Hack.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip \
    && unzip -o /tmp/Hack.zip -d "${FONT_DIR}" \
    && rm /tmp/Hack.zip \
    && fc-cache -fv >/dev/null \
    && log_ok "Hack Nerd Font installé" || log_error "Hack Nerd Font failed"
else
  log_ok "Hack Nerd Font déjà présent"
fi

# ── 5. Patch ~/.bashrc ────────────────────────────────────────────────────────
log_info "Patch ~/.bashrc..."
BASHRC="${HOME}/.bashrc"
MARKER="# ── ubuntu2404 bash tweaks"

if grep -q "${MARKER}" "${BASHRC}" 2>/dev/null; then
  log_ok "~/.bashrc déjà patché"
else
  cp "${BASHRC}" "${BASHRC}.bak-$(date +%Y%m%d-%H%M%S)"

  cat >> "${BASHRC}" << 'BASHRC_BLOCK'

# ── ubuntu2404 bash tweaks ────────────────────────────────────────────────────

# ble.sh — autosuggestions + syntax highlighting (→ ou End pour accepter)
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --noattach

# Starship prompt
eval "$(starship init bash)"

# fzf — Ctrl+R historique, Ctrl+T fichiers, Alt+C dossiers
eval "$(fzf --bash)"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

# Historique étendu
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# bash-completion
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
  source /usr/share/bash-completion/bash_completion
fi

# ls → eza (icônes + couleurs + tri dossiers)
alias ls='eza -al --color=always --group-directories-first --icons'
alias la='eza -a  --color=always --group-directories-first --icons'
alias ll='eza -l  --color=always --group-directories-first --icons'
alias lt='eza -aT --color=always --group-directories-first --icons'
alias l.='eza -a | grep -E "^\."'

# apt
alias upall='sudo apt upgrade -y'
alias upcheck='sudo apt update'
alias cleanup='sudo apt autoremove --purge'

# Colorisation
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias ip='ip --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Ops sécurisées
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# Attacher ble.sh en fin de .bashrc
[[ ${BLE_VERSION-} ]] && ble-attach

# ── fin ubuntu2404 bash tweaks ────────────────────────────────────────────────
BASHRC_BLOCK

  log_ok "~/.bashrc patché"
fi

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  bash-setup terminé ✓                        ║"
echo "╠═══════════════════════════════════════════════╣"
echo "║  • source ~/.bashrc  (ou ouvrir un terminal) ║"
echo "║  • Police terminal → Hack Nerd Font Mono     ║"
echo "║  • → ou End : accepter la suggestion ble.sh  ║"
echo "║  • Ctrl+R : historique fuzzy (fzf)           ║"
echo "╚═══════════════════════════════════════════════╝"
