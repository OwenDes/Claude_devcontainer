#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# git credential helper adossé à pass (token chiffré au repos).
# git l'appelle avec l'opération en $1 (get/store/erase) ; on ne gère que
# 'get'. L'hôte demandé est lu sur stdin, mappé vers l'entrée pass
# "git/<host>". Convention de l'entrée : 1re ligne = token ; ligne
# optionnelle "login: <user>" = nom d'utilisateur (défaut : oauth2).
#
# Ainsi le token n'est JAMAIS en clair dans ~/.bashrc, l'env ou l'image :
# il est déchiffré (GPG) uniquement au moment d'une opération git.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

[ "${1:-}" = "get" ] || exit 0

host=""
while IFS='=' read -r key value; do
    [ -z "$key" ] && break
    [ "$key" = "host" ] && host="$value"
done

[ -n "$host" ] || exit 0
entry="git/$host"

pass show "$entry" >/dev/null 2>&1 || exit 0
secret="$(pass show "$entry" 2>/dev/null)"
token="$(printf '%s\n' "$secret" | head -n1)"
login="$(printf '%s\n' "$secret" | sed -n 's/^login: *//p' | head -n1)"
[ -n "$login" ] || login="oauth2"

printf 'username=%s\n' "$login"
printf 'password=%s\n' "$token"
