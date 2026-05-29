# ubuntu2404

Configuration Ubuntu 24.04 LTS — installation entièrement automatisée.  
Interface : **en_US** · Formats : **fr_CH** (date/monnaie/mesures) · Clavier : **ch/fr**  
Stack : Brave · Ghostty · Neovim · Zsh · Starship · Hack Nerd Font · Citrix Workspace

---

## Structure

```
ubuntu2404/
├── autoinstall/
│   ├── user-data          # Config Ubuntu Autoinstall (cloud-init/subiquity)
│   └── meta-data          # Métadonnées cloud-init (obligatoire)
├── configs/
│   ├── ghostty/config     # Ghostty : thème Ayu Mirage, splits, Hack Nerd Font
│   └── zshrc              # Zsh : Oh My Zsh + plugins + aliases eza/git
├── scripts/
│   ├── create-iso.sh      # Crée l'ISO autoinstall (macOS + Linux)
│   ├── post-install.sh    # Setup automatique (root, pendant autoinstall)
│   ├── bash-setup.sh      # ble.sh — à lancer manuellement post-reboot
│   ├── citrix-setup.sh    # Citrix Workspace App 2601 — à lancer manuellement
│   ├── niri-setup.sh      # Niri WM (build Rust ~20 min) — à lancer manuellement
│   ├── edge.sh            # MS Edge — portail Office 365 (mode app)
│   ├── outlook.sh         # Outlook web (Edge)
│   ├── perplexity.sh      # Perplexity web app (Brave)
│   ├── teams.sh           # Teams web app
│   ├── textrecon.sh       # OCR via gimagereader
│   └── youtube.sh         # YouTube web app
└── README.md
```

---

## Démarrage rapide

### 1. Préparer le mot de passe

```bash
echo "tonmotdepasse" | openssl passwd -6 -stdin
# → Coller le résultat dans autoinstall/user-data (ligne password:)
```

### 2. Créer la clé USB bootable

```bash
git clone https://github.com/tonybeyond/ubuntu2404.git
cd ubuntu2404
bash scripts/create-iso.sh --usb
```

Le script détecte macOS ou Linux, télécharge Ubuntu 24.04.4, vérifie le SHA-256 officiel, intègre l'autoinstall et guide l'écriture USB.

### 3. Démarrer et installer

Insérer la clé → démarrer depuis la clé (F12/F2/DEL) → l'installation démarre automatiquement (~15 min) → reboot.

---

## Ce que l'autoinstall installe automatiquement

`post-install.sh` s'exécute en root pendant l'installation. Un seul script, pas de sudo imbriqué.

| Composant | Détail |
|-----------|--------|
| **Locale** | `en_US.UTF-8` interface · `fr_CH.UTF-8` formats (date, monnaie, mesures) |
| **Clavier** | `ch/fr` (Suisse romande) |
| **Brave Browser** | Via repo Brave officiel |
| **Ghostty** | Terminal, thème Ayu Mirage, Hack Nerd Font Mono |
| **Neovim** | Build depuis source (stable) + kickstart.nvim |
| **Oh My Zsh** | Thème bira + plugins autosuggestions/syntax/autocomplete |
| **Starship** | Prompt contextuel installé system-wide |
| **Hack Nerd Font** | Police terminal avec icônes |
| **~/.bashrc** | Aliases eza, git, apt · fzf · Starship · ble.sh optionnel |
| **Citrix** | Si le `.deb` est présent dans `~/Downloads` — sinon skipped |
| **Paquets apt** | eza, fzf, bat, btop, hyfetch, nala, vlc, flameshot, tesseract (fr/en)… |

---

## Scripts à lancer après le premier reboot

Se connecter en tant que `tony`, ouvrir un terminal, puis :

```bash
# 1. Niri WM (compositeur Wayland) — build Rust depuis source (~20 min)
bash /opt/ubuntu2404/scripts/niri-setup.sh

# 2. ble.sh (autosuggestions + syntax highlighting bash)
bash /opt/ubuntu2404/scripts/bash-setup.sh

# 3. Citrix Workspace App (après téléchargement du .deb)
#    → https://www.citrix.com/downloads/workspace-app/linux/
#    → Placer le .deb dans ~/Downloads/ puis :
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh
```

---

## Locale : en_US + fr_CH

Configuration dans `/etc/default/locale` après installation :

```
LANG=en_US.UTF-8            # Interface, messages système
LC_TIME=fr_CH.UTF-8         # Format des dates  (29.05.2026)
LC_NUMERIC=fr_CH.UTF-8      # Séparateur décimal (1'234.56)
LC_MONETARY=fr_CH.UTF-8     # Monnaie (CHF 12.50)
LC_PAPER=fr_CH.UTF-8        # Format papier (A4)
LC_MEASUREMENT=fr_CH.UTF-8  # Unités métriques
LC_ADDRESS=fr_CH.UTF-8
LC_TELEPHONE=fr_CH.UTF-8
```

Vérifier après installation : `locale`

---

## Niri WM

`niri-setup.sh` compile Niri depuis les sources et génère les configs.

| Raccourci | Action |
|-----------|--------|
| `Super+Enter` | Terminal (Ghostty) |
| `Super+Space` | Launcher (Fuzzel) |
| `Super+W` | Navigateur (Brave) |
| `Super+HJKL` | Navigation Vim-style |
| `Super+Shift+HJKL` | Déplacer fenêtre |
| `Super+Q` | Fermer fenêtre |
| `Super+Shift+E` | Quitter Niri |
| `Print` | Screenshot |

Style Catppuccin Mocha · Waybar flottante · Clavier ch/fr

---

## Citrix Workspace App

Version : **2601** (5 mars 2026)  
SHA-256 : `7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a`

Téléchargement manuel requis (EULA Citrix) :
→ https://www.citrix.com/downloads/workspace-app/linux/

`citrix-setup.sh` vérifie le checksum, installe les dépendances et fixe les certificats SSL.

---

## Bash shell

`bash-setup.sh` compile et installe ble.sh pour améliorer bash sans changer de shell.

| Touche | Fonction |
|--------|----------|
| `→` ou `End` | Accepter suggestion ble.sh |
| `Ctrl+R` | Historique fuzzy (fzf) |
| `Ctrl+T` | Insérer fichier (fzf) |
| `Alt+C` | Naviguer dossiers (fzf) |

> Police du terminal : **Hack Nerd Font Mono** (installée automatiquement).

---

## Usage standalone

Sur une install Ubuntu existante :

```bash
git clone https://github.com/tonybeyond/ubuntu2404.git /opt/ubuntu2404
sudo bash /opt/ubuntu2404/scripts/post-install.sh
bash /opt/ubuntu2404/scripts/niri-setup.sh
bash /opt/ubuntu2404/scripts/bash-setup.sh
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh
```
