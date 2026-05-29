# ubuntu2404

Configuration Ubuntu 24.04 LTS — installation entièrement automatisée.  
Inclut : Brave · Ghostty · Niri WM · Neovim · Zsh · Citrix Workspace · Bash tweaks.

## Structure du repo

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
│   ├── post-install.sh    # Setup système (root) — orchestrateur principal
│   ├── bash-setup.sh      # Bash : ble.sh · Starship · fzf · eza · Hack Nerd Font
│   ├── citrix-setup.sh    # Citrix Workspace App 2601 (nécessite .deb manuel)
│   ├── niri-setup.sh      # Niri WM : build source + Waybar + Fuzzel (Catppuccin)
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

### Étape 1 — Préparer le mot de passe

```bash
# Générer un hash SHA-512 pour autoinstall/user-data
echo "tonmotdepasse" | openssl passwd -6 -stdin
```

Éditer `autoinstall/user-data` → remplacer la ligne `password:` avec le hash généré.  
Adapter aussi `hostname` et `username` si nécessaire.

### Étape 2 — Créer la clé USB bootable

```bash
# macOS ou Linux — crée l'ISO + propose l'écriture USB
bash scripts/create-iso.sh --usb

# Crée l'ISO seulement (écriture manuelle ensuite)
bash scripts/create-iso.sh
```

Ce script :
- Détecte macOS ou Linux, installe les dépendances si nécessaire (Homebrew/apt)
- Télécharge Ubuntu 24.04.2 Desktop (~5.7 Go) avec vérification SHA-256 officielle
- Intègre `autoinstall/user-data` + `meta-data` dans l'ISO
- Patche GRUB pour démarrer directement en autoinstall (timeout 3s)
- (Optionnel) Écrit l'ISO sur la clé USB via `dd`

### Étape 3 — Démarrer et installer

1. Insérer la clé USB dans la machine cible
2. Démarrer depuis la clé (F12 / F2 / DEL selon BIOS)
3. L'installation démarre automatiquement (~10-20 min)
4. La machine redémarre et est prête

---

## Ce que l'autoinstall installe automatiquement

### Via `post-install.sh` (root, pendant autoinstall)

| Composant | Détail |
|-----------|--------|
| **Brave Browser** | Via repo Brave officiel |
| **Ghostty** | Terminal, thème Ayu Mirage, splits clavier |
| **Neovim** | Build depuis source (stable) + kickstart.nvim |
| **Oh My Zsh** | Thème bira + plugins autosuggestions/syntax/autocomplete |
| **Niri WM** | Compositeur Wayland, build depuis source (~15-20 min) |
| **Citrix Workspace** | Si le `.deb` est disponible — sinon skipped |
| **Paquets apt** | eza, fzf, bat, btop, hyfetch, nala, vlc, flameshot, tesseract… |
| **Locale** | fr_CH.UTF-8 activée |

### Via `bash-setup.sh` (utilisateur tony, pendant autoinstall)

| Composant | Détail |
|-----------|--------|
| **ble.sh** | Autosuggestions bash + syntax highlighting |
| **Starship** | Prompt contextuel (git, python, docker…) |
| **Hack Nerd Font** | Police terminal avec icônes |
| **~/.bashrc** | Aliases eza, git, apt + config fzf/historique |

---

## Citrix Workspace App

Version actuelle : **2601** (5 mars 2026)  
SHA-256 : `7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a`

⚠️ Le téléchargement requiert l'acceptation de la licence Citrix (pas de lien direct).

```bash
# 1. Télécharger le .deb sur :
#    https://www.citrix.com/downloads/workspace-app/linux/
# 2. Placer dans ~/Downloads/
# 3. Installer :
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh
```

Le script vérifie le checksum, installe les dépendances et fixe les certificats SSL.

---

## Niri — Compositeur Wayland

`niri-setup.sh` est appelé automatiquement lors du post-install et peut aussi être relancé manuellement.

**Keybinds :**

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

Style : Catppuccin Mocha — Waybar flottante, bordures dégradé bleu→violet.  
Clavier : `ch/fr` configuré dans Niri.

---

## Bash shell (ble.sh + Starship + fzf)

`bash-setup.sh` améliore bash sans changer de shell :

| Touche | Fonction |
|--------|----------|
| `→` ou `End` | Accepter suggestion ble.sh |
| `Ctrl+R` | Historique fuzzy (fzf) |
| `Ctrl+T` | Insérer fichier via fzf |
| `Alt+C` | Naviguer dans les dossiers via fzf |

> Configurer la police du terminal sur **Hack Nerd Font Mono** pour les icônes.

---

## Usage standalone (install existante)

```bash
git clone https://github.com/tonybeyond/ubuntu2404.git /opt/ubuntu2404

# Setup système (root)
sudo bash /opt/ubuntu2404/scripts/post-install.sh

# Bash tweaks (utilisateur)
bash /opt/ubuntu2404/scripts/bash-setup.sh

# Citrix (après téléchargement du .deb)
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh
```

---

## Notes

- `post-install.sh` patche automatiquement `exa → eza` dans le `.zshrc` au déploiement
- La config Ghostty utilise Hack Nerd Font Mono (installé par `bash-setup.sh`)
- `niri-setup.sh` génère automatiquement les configs Niri, Waybar, Fuzzel avec le thème Catppuccin
- Les web apps (Edge, Outlook, Teams, YouTube, Perplexity) sont dans `scripts/` — lancer manuellement selon besoin
