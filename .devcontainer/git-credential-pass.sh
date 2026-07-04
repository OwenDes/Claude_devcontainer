#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# git credential helper adossé à pass (token chiffré au repos).
# git l'appelle avec l'opération en $1 (get/store/erase) ; on ne gère que
# 'get'. L'hôte demandé est lu sur stdin.
#
# Deux conventions d'entrée, essayées dans l'ordre :
#   git/<host>          → mode "none" (entrée à plat, clé par défaut du store)
#   git/<host>/token    → mode "passphrase"/"yubikey" (sous-dossier avec sa
#                         propre clé GPG, cf. setup-git-token)
# 1re ligne = token ; ligne "login: <user>" optionnelle (défaut : oauth2).
#
# Trousseau GPG dédié (~/.gnupg-pass), isolé du ~/.gnupg par défaut.
# Auto-suffisant (fixe l'option ici) pour marcher même appelé par le git
# de VSCode, dont l'environnement ne source pas forcément le shell.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

export PASSWORD_STORE_GPG_OPTS="--homedir ${HOME}/.gnupg-pass"

[ "${1:-}" = "get" ] || exit 0

host=""
while IFS='=' read -r key value; do
    [ -z "$key" ] && break
    [ "$key" = "host" ] && host="$value"
done
[ -n "$host" ] || exit 0

# On ne matche qu'un FICHIER pass réel (.gpg), pas un dossier (dont
# "pass show" renverrait l'arborescence). git/<host>/token (protégé) est
# prioritaire sur git/<host> (mode none à plat).
store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
secret=""
for entry in "git/$host/token" "git/$host"; do
    if [ -f "$store/$entry.gpg" ]; then
        secret="$(pass show "$entry" 2>/dev/null)" || secret=""
        [ -n "$secret" ] && break
    fi
done
[ -n "$secret" ] || exit 0

token="$(printf '%s\n' "$secret" | head -n1)"
login="$(printf '%s\n' "$secret" | sed -n 's/^login: *//p' | head -n1)"
[ -n "$login" ] || login="oauth2"

printf 'username=%s\n' "$login"
printf 'password=%s\n' "$token"
