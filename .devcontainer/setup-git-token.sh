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

# 2b. Adosse le store à git. Deux bénéfices :
#     - historique auditable des rotations (blobs chiffrés, jamais en clair) ;
#     - l'extension officielle `pass update` (mode --provide) s'appuie sur
#       git_add_file ; sans dépôt git celui-ci renvoie 1 et update affiche une
#       fausse erreur "encryption aborted" alors que l'entrée EST mise à jour.
#     (Utilise l'identité git globale ; réutilisable sur un store existant.)
if [ ! -d "${HOME}/.password-store/.git" ]; then
    echo "→ Adossement du store à git…"
    pass git init
fi

# 3. Helper git GÉNÉRIQUE : un seul pour TOUS les hôtes. git-credential-pass
#    décline proprement (exit 0, rien) si l'hôte n'a pas d'entrée pass. Donc
#    ajouter un nouvel hôte = juste "pass insert git/<host>", AUCUNE reconfig
#    git. (Survit au scrub, qui ne retire que la valeur "vscode-remote-…".)
git config --global credential.helper "/usr/local/bin/git-credential-pass"
# Nettoie d'anciennes entrées par hôte devenues inutiles
for h in github.com gitlab.com "${GITLAB_HOST}"; do
    git config --global --unset-all "credential.https://${h}.helper" 2>/dev/null || true
done
echo "→ Helper pass GÉNÉRIQUE configuré (tous les hôtes via git/<host>)"

cat <<EOF

✅ Prêt. Pour CHAQUE hôte que tu utilises, enregistre son token
   (1re ligne = le token) — le nom doit être exactement l'hôte :

    pass insert -m git/github.com
    pass insert -m git/gitlab.com
    pass insert -m git/${GITLAB_HOST}

  (option : ajouter une ligne  login: <ton-user>  ; défaut = oauth2)
  Nouveau serveur plus tard ? juste  pass insert -m git/<host>  → ça marche.

Ensuite :
  • retire la ligne  export GITLAB_TOKEN=...  de ~/.bashrc
  • RÉVOQUE l'ancien token (il a fuité en clair dans des logs)
  • teste :  git ls-remote https://${GITLAB_HOST}/<projet>.git
EOF
