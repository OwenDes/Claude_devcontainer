#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# INIT DU HOME — remplit le volume /home/node depuis /opt/home-skel au
# premier démarrage (volume neuf = pas de .bashrc), puis ne touche plus
# à rien. Lancé en root via le sudoers restreint (postCreateCommand).
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [ ! -f /home/node/.bashrc ]; then
    echo "Volume home neuf -> initialisation depuis /opt/home-skel"
    cp -a /opt/home-skel/. /home/node/
    chown -R node:node /home/node
fi

# Migration : volume créé avec une ancienne image (claude installé via
# npm -g, absent du home) -> on récupère l'install native depuis le skel.
if [ ! -x /home/node/.local/bin/claude ] && [ -x /opt/home-skel/.local/bin/claude ]; then
    echo "Claude Code absent du volume home -> copie depuis le skel"
    cp -a /opt/home-skel/.local /home/node/
    chown -R node:node /home/node/.local
fi
