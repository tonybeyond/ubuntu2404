# ubuntu2404

Configuration Ubuntu 24.04 LTS — setup automatisé pour desktop personnel.

## Structure

```
ubuntu2404/
├── autoinstall/
│   ├── user-data          # Config Ubuntu Autoinstall (cloud-init)
│   └── meta-data          # Métadonnées cloud-init (requis)
├── scripts/
│   ├── post-install.sh    # Setup système (root) — appelé par autoinstall
│   ├── bash-setup.sh      # Bash tweaks (user) — ble.sh · Starship · fzf · eza
│   ├── citrix-setup.sh    # Citrix Workspace App 2601 (nécessite .deb manuel)
│   ├── niri2.sh           # Niri WM depuis source + configs Catppuccin
│   ├── edge.sh            # MS Edge en mode app
│   ├── outlook.sh         # Outlook web app (Edge)
│   ├── perplexity.sh      # Perplexity web app
│   ├── teams.sh           # Teams web app
│   ├── textrecon.sh       # OCR via gimagereader
│   └── youtube.sh         # YouTube web app
├── configs/
│   └── ghostty/config     # Config Ghostty (thème Ayu Mirage, splits)
├── zsh/
│   ├── new_zshrc          # .zshrc Oh My Zsh (référence)
│   └── .zshrc             # .zshrc variante
├── ghostty/
│   └── .config/ghostty/config  # Config Ghostty (legacy path)
├── install.sh             # Script post-install manuel (version originale)
└── newubuntu-improved.sh  # Script post-install amélioré (version standalone)
```

## Déploiement automatisé (Ubuntu Autoinstall)

### Méthode clé USB CIDATA (recommandée pour un seul poste)

**Matériel requis :** une clé USB bootable (ISO Ubuntu 24.04) + une deuxième partition CIDATA.

```bash
# Créer la partition CIDATA sur une 2e clé USB (ou 2e partition)
mkfs.fat -F32 -n CIDATA /dev/sdX

# Monter et copier les fichiers
mount /dev/sdX /mnt/cidata
cp autoinstall/user-data /mnt/cidata/user-data
cp autoinstall/meta-data /mnt/cidata/meta-data
umount /mnt/cidata
```

> Ubuntu détecte automatiquement le volume `CIDATA` au démarrage.  
> L'installation se déroule sans interaction, puis redémarre.

### Avant de déployer — adapter `autoinstall/user-data`

```bash
# 1. Générer un hash de mot de passe
echo "tonmotdepasse" | openssl passwd -6 -stdin

# 2. Remplacer dans user-data
#    password: '$6$CHANGEME$PLEASE_REPLACE...'
#    → coller le hash généré
```

Vérifier aussi : `hostname`, `username`, `keyboard.layout/variant`.

## Post-installation

### Ce que fait `autoinstall` automatiquement

| Étape | Script | Ce qui est installé |
|-------|--------|---------------------|
| late-commands | `post-install.sh` | APT, Ghostty, Vivaldi, Neovim, Oh My Zsh + plugins, zshrc, Citrix* |
| late-commands | `bash-setup.sh` | ble.sh, Starship, Hack Nerd Font, ~/.bashrc tweaks |

*Citrix nécessite le .deb pré-téléchargé (voir ci-dessous).

### Étapes manuelles après reboot

```bash
# 1. Citrix Workspace App
#    → Télécharger le .deb sur https://www.citrix.com/downloads/workspace-app/linux/
#    → Placer dans ~/Downloads/
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh

# 2. Niri (compositeur Wayland) — ~20 min, build depuis source
bash /opt/ubuntu2404/scripts/niri2.sh

# 3. Bash tweaks (si non fait en autoinstall)
bash /opt/ubuntu2404/scripts/bash-setup.sh
```

## Utilisation standalone (sans autoinstall)

Sur une install Ubuntu existante :

```bash
git clone https://github.com/tonybeyond/ubuntu2404.git /opt/ubuntu2404
sudo bash /opt/ubuntu2404/scripts/post-install.sh
bash /opt/ubuntu2404/scripts/bash-setup.sh        # en tant qu'utilisateur
sudo bash /opt/ubuntu2404/scripts/citrix-setup.sh # après téléchargement du .deb
```

## Bash shell (ble.sh + Starship + fzf + eza)

`bash-setup.sh` configure un bash moderne sans changer de shell :

| Outil | Rôle |
|-------|------|
| **ble.sh** | Autosuggestions grisées (→ accepter) + syntax highlighting |
| **Starship** | Prompt contextuel (git, python, docker…) |
| **fzf** | Ctrl+R historique · Ctrl+T fichiers · Alt+C dossiers |
| **eza** | `ls` amélioré avec icônes et couleurs |
| **Hack Nerd Font** | Police terminal requise pour les icônes |

> Configurer la police du terminal sur **Hack Nerd Font Mono**.

## Citrix Workspace App

Version : **2601** (5 mars 2026)  
SHA-256 : `7ce8c3a32e1e9d698e7bca349ad582136040774a49e35f47e529430918f8b94a`

Le téléchargement nécessite l'acceptation de l'EULA Citrix — pas de lien direct possible.  
`citrix-setup.sh` vérifie le checksum, installe les dépendances, et fixe les certificats SSL.

## Niri (Wayland compositor)

`niri2.sh` installe Niri depuis les sources avec :
- Waybar flottante (style Catppuccin Mocha)
- Fuzzel comme launcher
- Config clavier `ch/fr`
- Keybinds Vim-style (`Super+HJKL`)
- Terminal : Ghostty (`Super+Return`)
- Browser : Vivaldi (`Super+W`)

## Composants installés

- **Shell** : Zsh + Oh My Zsh (thème bira) + plugins autosuggestions/syntax/autocomplete
- **Terminal** : Ghostty (thème Ayu Mirage, ProFont IIx Nerd Font)
- **Éditeur** : Neovim (stable, depuis source) + kickstart.nvim
- **Browser** : Vivaldi (+ Edge, Outlook, Teams, Perplexity en mode app)
- **WM** : Niri (Wayland, scrolling columns)
- **Outils** : btop, bat, eza, fzf, flameshot, hyfetch, nala, vlc, tesseract-ocr (fr/en)
- **VPN/Bureau distant** : Citrix Workspace App 2601
