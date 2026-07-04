# ──────────────────────────────────────────────────────────────────────────
# DURCISSEMENT — neutralisation des ponts VSCode vers l'hôte.
# Installé dans /etc/security-harden.sh (root, dans l'image) et sourcé
# depuis /etc/bash.bashrc : hors du volume home, donc non modifiable par
# node et mis à jour à chaque rebuild.
# ──────────────────────────────────────────────────────────────────────────

# Socket IPC VSCode -> peut EXÉCUTER DES COMMANDES sur l'hôte Windows
unset VSCODE_IPC_HOOK_CLI

# IPC de l'extension Git VSCode -> accès aux credentials Git de l'hôte
unset VSCODE_GIT_IPC_HANDLE \
      GIT_ASKPASS \
      VSCODE_GIT_ASKPASS_MAIN \
      VSCODE_GIT_ASKPASS_NODE \
      VSCODE_GIT_ASKPASS_EXTRA_ARGS

# IPC Remote Containers -> pont d'exécution de commandes hôte
unset REMOTE_CONTAINERS_IPC \
      REMOTE_CONTAINERS_SOCKETS \
      REMOTE_CONTAINERS_DISPLAY_SOCK

# Forwarding GUI Wayland/X11 (risque faible mais inutile)
unset WAYLAND_DISPLAY DISPLAY

# Helper navigateur -> actions sur l'hôte via --openExternal
export BROWSER=

# Agents SSH/GPG -> vidés pour empêcher le fallback vers les sockets par défaut
export SSH_AUTH_SOCK=
export GPG_AGENT_INFO=

# Bascule pratique du pare-feu (mode recherche/install vs verrouillé)
alias net-open='sudo /usr/local/bin/init-firewall.sh open'
alias net-strict='sudo /usr/local/bin/init-firewall.sh strict'

# pass utilise un trousseau GPG dédié (~/.gnupg-pass), isolé du ~/.gnupg
# par défaut qui peut contenir des clés v5 illisibles par le GnuPG bookworm.
export PASSWORD_STORE_GPG_OPTS="--homedir ${HOME}/.gnupg-pass"

# ── CLI d'API Git : token injecté depuis pass À L'APPEL (jamais en clair) ──
# Le token = 1re ligne de l'entrée pass. Deux conventions essayées :
# git/<host> (mode none) ou git/<host>/token (passphrase/yubikey).
# gh : GitHub (hôte unique). glab : GitLab, hôte déduit du remote courant
# (sinon gitlab.com), avec le token pass correspondant.
_git_remote_host() {
    git remote get-url "${1:-origin}" 2>/dev/null \
        | sed -E -e 's#^[a-z]+://##' -e 's#^[^@]*@##' -e 's#[:/].*$##'
}
_pass_git_token() {   # $1 = host → 1re ligne (token) de la 1re entrée trouvée
    local host="$1" e store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
    # Ne matche qu'un FICHIER .gpg (pas un dossier). git/<host>/token prioritaire.
    for e in "git/$host/token" "git/$host"; do
        if [ -f "$store/$e.gpg" ]; then
            pass show "$e" 2>/dev/null | head -n1
            return 0
        fi
    done
    return 1
}
gh() {
    GH_TOKEN="$(_pass_git_token github.com)" command gh "$@"
}
glab() {
    local host="${GITLAB_HOST:-$(_git_remote_host)}"
    case "$host" in *.*) ;; *) host="gitlab.com" ;; esac
    GITLAB_HOST="$host" \
    GITLAB_TOKEN="$(_pass_git_token "$host")" \
    command glab "$@"
}
