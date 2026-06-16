#!/usr/bin/env bash
#
# install.sh — installe mon environnement perso dans N'IMPORTE QUEL dev container.
# Lancé automatiquement par VS Code via le réglage "dotfiles.installCommand".
#
# Important : tout s'installe dans le HOME / le système du container, jamais dans
# le workspace du projet. Le repo client reste donc 100% vierge.

set -euo pipefail
echo "==> Bootstrap de l'environnement perso…"

# 0) Prérequis (curl, git) — sudo est dispo dans la plupart des dev containers.
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends curl git ca-certificates
fi

# 1) Node.js (requis par Claude Code) — installé seulement s'il manque dans l'image.
if ! command -v npm >/dev/null 2>&1; then
  echo "==> Node absent → installation (LTS)…"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

# 2) Claude Code (paquet npm officiel).
npm install -g @anthropic-ai/claude-code

# 3) Tes autres outils (glab, etc.).
#    >>> COLLE ICI les commandes que tu as DÉJÀ dans le Dockerfile de ton repo de dev.
#        Elles fonctionnent déjà, autant les réutiliser telles quelles. Par exemple :
#    sudo apt-get install -y <paquet>
#    # ... ou un téléchargement de binaire, etc.

# 4) Le repo dont tu as besoin, cloné dans le HOME (hors du workspace client).
#    >>> Adapte l'URL et le nom du dossier.
if [ ! -d "$HOME/ai-skills" ]; then
  git clone https://gitlab.com/swosh/ai-skills.git "$HOME/ai-skills"
fi

# 5) Filet de sécurité : gitignore global.
#    Même si un outil crée .claude/, .env, etc. dans un repo, ça ne sera JAMAIS commité.
#    (Suppose dotfiles.targetPath = "~/dotfiles" — voir réglages VS Code.)
git config --global core.excludesfile "$HOME/dotfiles/.gitignore_global"

# 6) (Optionnel) tes fichiers de config perso, en symlink depuis le repo dotfiles.
# ln -sf "$HOME/dotfiles/.gitconfig" "$HOME/.gitconfig"
# ln -sf "$HOME/dotfiles/.bashrc"    "$HOME/.bashrc"

echo "==> OK : Claude Code, tes outils et ai-skills sont prêts."
