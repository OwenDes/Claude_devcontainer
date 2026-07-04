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
