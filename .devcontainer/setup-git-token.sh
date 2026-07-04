#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# Stockage chiffré des tokens Git (pass + GPG), protection AU CHOIX PAR HÔTE.
#
#   setup-git-token                         → init du store + aide
#   setup-git-token <host> [mode]           → configure un hôte
#
#   mode :
#     none         (défaut)  clé locale SANS passphrase — comportement actuel,
#                            unattended. Entrée : git/<host>
#     passphrase             clé locale AVEC passphrase (une par hôte) —
#                            déchiffrement demande la passphrase (mise en
#                            cache par gpg-agent). Entrée : git/<host>/token
#     card:<KEYID>           clé dont la partie PRIVÉE est sur la YubiKey via
#                            le gpg-agent de l'HÔTE (socket forwardé, cf.
#                            GUIDE). Touch à chaque déchiffrement. La clé
#                            privée ne touche jamais le conteneur.
#                            Entrée : git/<host>/token
#
# Trousseau GPG dédié ~/.gnupg-pass (isolé du ~/.gnupg par défaut, qui peut
# contenir des clés v5 illisibles par le GnuPG de bookworm).
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

PASS_HOME="${HOME}/.gnupg-pass"
export PASSWORD_STORE_GPG_OPTS="--homedir ${PASS_HOME}"
mkdir -p -m 700 "$PASS_HOME"
# Autorise la saisie de passphrase sans pinentry graphique (mode loopback)
grep -qs allow-loopback-pinentry "$PASS_HOME/gpg-agent.conf" 2>/dev/null \
    || echo "allow-loopback-pinentry" >> "$PASS_HOME/gpg-agent.conf"

HOST="${1:-}"
MODE="${2:-none}"

_keyid_for_uid() {  # $1 = uid exact → keyid (vide si absent)
    gpg --homedir "$PASS_HOME" --list-keys --with-colons "=$1" 2>/dev/null \
        | awk -F: '/^pub/{print $5; exit}'
}

_nopass_keyid() {   # clé locale sans passphrase (créée si absente)
    local uid="claude-devcontainer pass (no-pass) <node@devcontainer>" kid
    kid="$(_keyid_for_uid "$uid")"
    if [ -z "$kid" ]; then
        gpg --homedir "$PASS_HOME" --batch --pinentry-mode loopback --passphrase '' \
            --quick-generate-key "$uid" default default never >/dev/null 2>&1
        kid="$(_keyid_for_uid "$uid")"
    fi
    printf '%s' "$kid"
}

# Store de base initialisé sur la clé sans passphrase (rétrocompat mode none)
if [ ! -f "${HOME}/.password-store/.gpg-id" ]; then
    echo "→ Initialisation du store pass (clé locale sans passphrase)…"
    pass init "$(_nopass_keyid)" >/dev/null
fi
# Helper git générique (un seul pour tous les hôtes)
git config --global credential.helper "/usr/local/bin/git-credential-pass"

if [ -z "$HOST" ]; then
    cat <<EOF
Store pass prêt. Configure un hôte :

  setup-git-token <host> none          # sans passphrase (défaut, comme avant)
  setup-git-token <host> passphrase    # clé locale avec passphrase
  setup-git-token <host> card:<KEYID>  # YubiKey via gpg-agent de l'hôte

Exemples :
  setup-git-token github.com
  setup-git-token gitlab-df.imt-atlantique.fr passphrase
  setup-git-token gitlab.com card:0xABCDEF01

Puis enregistre le token (1re ligne = token, ligne 'login: user' optionnelle) :
  mode none        →  pass insert -m git/<host>
  passphrase/card  →  pass insert -m git/<host>/token
EOF
    exit 0
fi

case "$MODE" in
  none)
    echo "✔ $HOST : mode none (clé locale sans passphrase)."
    echo "  → pass insert -m git/$HOST"
    ;;

  passphrase)
    uid="claude-devcontainer pass ($HOST) <node@devcontainer>"
    kid="$(_keyid_for_uid "$uid")"
    if [ -z "$kid" ]; then
        echo "→ Génère une clé pour $HOST — choisis sa passphrase :"
        gpg --homedir "$PASS_HOME" --pinentry-mode loopback \
            --quick-generate-key "$uid" default default never
        kid="$(_keyid_for_uid "$uid")"
    fi
    pass init -p "git/$HOST" "$kid" >/dev/null
    echo "✔ $HOST : mode passphrase (clé $kid)."
    echo "  → pass insert -m git/$HOST/token"
    ;;

  card:*)
    kid="${MODE#card:}"
    if ! gpg --homedir "$PASS_HOME" --list-keys "$kid" >/dev/null 2>&1; then
        cat <<EOF
⚠️ Clé publique $kid absente du trousseau $PASS_HOME.
   La partie PRIVÉE reste sur ta YubiKey (via le gpg-agent de l'hôte), mais
   pass a besoin de la clé PUBLIQUE pour chiffrer. Importe-la d'abord :

     gpg --homedir $PASS_HOME --recv-keys $kid        # depuis un keyserver
   ou  gpg --homedir $PASS_HOME --import cle-pub.asc  # depuis un fichier

   Et vérifie que le socket gpg-agent de l'hôte est forwardé (cf. GUIDE).
EOF
        exit 1
    fi
    pass init -p "git/$HOST" "$kid" >/dev/null
    echo "✔ $HOST : mode card/YubiKey (clé $kid, déchiffrement via agent hôte)."
    echo "  → pass insert -m git/$HOST/token"
    ;;

  *)
    echo "Mode inconnu : $MODE   (none | passphrase | card:<KEYID>)" >&2
    exit 1
    ;;
esac
