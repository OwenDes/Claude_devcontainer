#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# Configuration UNIQUE du stockage chiffré des tokens Git (pass + GPG).
# À lancer une fois, en tant que node :  setup-git-token
#
# Trousseau GPG DÉDIÉ (~/.gnupg-pass), isolé du ~/.gnupg par défaut : ce
# dernier peut contenir des clés v5 illisibles par le GnuPG de bookworm
# (erreur "unknown version 5"), qui feraient échouer pass init.
#
# Choix "cached / unattended" : clé GPG SANS passphrase -> git peut pousser
# sans intervention. Protège le token au repos et contre l'exposition
# accidentelle (plus de token en clair dans l'env/.bashrc/logs), PAS un
# agent malveillant qui le déchiffrerait à l'usage. Pour ce dernier cas :
# YubiKey touch (passage) ou broker côté hôte.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

GITLAB_HOST="gitlab-df.imt-atlantique.fr"
PASS_HOME="${HOME}/.gnupg-pass"
export PASSWORD_STORE_GPG_OPTS="--homedir ${PASS_HOME}"

# 1. Clé GPG sans passphrase dans le trousseau dédié
mkdir -p -m 700 "$PASS_HOME"
if ! gpg --homedir "$PASS_HOME" --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec'; then
    echo "→ Génération d'une clé GPG dédiée (sans passphrase)…"
    gpg --homedir "$PASS_HOME" --batch --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "claude-devcontainer (git token store) <node@devcontainer>" \
        default default never
fi
KEYID="$(gpg --homedir "$PASS_HOME" --list-secret-keys --with-colons | awk -F: '/^sec/{print $5; exit}')"
echo "→ Clé GPG dédiée : $KEYID"

# 2. Store pass (adossé au trousseau dédié via PASSWORD_STORE_GPG_OPTS)
if [ ! -f "${HOME}/.password-store/.gpg-id" ]; then
    echo "→ Initialisation de pass…"
    pass init "$KEYID"
fi

# 3. Helper git par hôte (survit au scrub ciblé du helper VSCode)
git config --global "credential.https://github.com.helper" "/usr/local/bin/git-credential-pass"
git config --global "credential.https://${GITLAB_HOST}.helper" "/usr/local/bin/git-credential-pass"
echo "→ Helper pass configuré pour github.com et ${GITLAB_HOST}"

cat <<EOF

✅ Prêt. Enregistre tes tokens (1re ligne = le token) :

    pass insert -m git/github.com
    pass insert -m git/${GITLAB_HOST}

  (option : ajouter une ligne  login: <ton-user>  ; défaut = oauth2)

Ensuite :
  • retire la ligne  export GITLAB_TOKEN=...  de ~/.bashrc
  • RÉVOQUE l'ancien token (il a fuité en clair dans des logs)
  • teste :  git ls-remote https://${GITLAB_HOST}/<projet>.git
EOF
