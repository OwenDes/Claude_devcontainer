#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# Configuration UNIQUE du stockage chiffré des tokens Git (pass + GPG).
# À lancer une fois, en tant que node :  setup-git-token
#
# Choix "cached / unattended" : clé GPG SANS passphrase -> git peut pousser
# sans intervention. La protection couvre le repos (chiffré) et l'exposition
# accidentelle (plus de token en clair dans l'env/.bashrc/logs), PAS un agent
# malveillant qui pourrait le déchiffrer à l'usage. Pour ce dernier cas :
# YubiKey touch (passage) ou broker côté hôte.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

GILAB_HOST="gitlab-df.imt-atlantique.fr"

# 1. Clé GPG sans passphrase (déchiffrement unattended)
if ! gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec'; then
    echo "→ Génération d'une clé GPG dédiée (sans passphrase)…"
    gpg --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "claude-devcontainer (git token store) <node@devcontainer>" \
        default default never
fi
KEYID="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec/{print $5; exit}')"
echo "→ Clé GPG : $KEYID"

# 2. Store pass
if [ ! -d "$HOME/.password-store" ]; then
    echo "→ Initialisation de pass…"
    pass init "$KEYID"
fi

# 3. Helper git par hôte (survit au scrub du helper VSCode)
git config --global "credential.https://github.com.helper" "/usr/local/bin/git-credential-pass"
git config --global "credential.https://${GILAB_HOST}.helper" "/usr/local/bin/git-credential-pass"
echo "→ Helper pass configuré pour github.com et ${GILAB_HOST}"

cat <<EOF

✅ Prêt. Enregistre tes tokens (1re ligne = le token) :

    pass insert -m git/github.com
    pass insert -m git/${GILAB_HOST}

  (option : ajouter une ligne  login: <ton-user>  ; défaut = oauth2)

Ensuite :
  • retire la ligne  export GITLAB_TOKEN=...  de ~/.bashrc
  • RÉVOQUE l'ancien token (il a fuité en clair dans des logs)
  • teste :  git ls-remote https://${GILAB_HOST}/<projet>.git
EOF
