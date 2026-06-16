# ──────────────────────────────────────────────────────────────────────────
# Claude Code Sandbox — VERSION DURCIE (Podman) + HOME PERSISTANT
# Base Node.js 20 sur Debian Bookworm
# ──────────────────────────────────────────────────────────────────────────
FROM node:20-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    unzip \
    zip \
    less \
    nano \
    vim \
    jq \
    ripgrep \
    fd-find \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    openssh-client \
    bash-completion \
    locales \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/fr_FR.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr LC_ALL=fr_FR.UTF-8

RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

RUN npm install -g @anthropic-ai/claude-code

# ──────────────────────────────────────────────────────────────────────────
# DURCISSEMENT — script de neutralisation des ponts VSCode
# (sourcé en ligne 1 de .bashrc, voir plus bas)
# ──────────────────────────────────────────────────────────────────────────
RUN mkdir -p /home/node/.config && cat << 'HARDEN' > /home/node/.config/security-harden.sh
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

# Forwarding GUI (risque faible mais inutile)
unset WAYLAND_DISPLAY

# Helper navigateur -> actions sur l'hôte via --openExternal
export BROWSER=

# Agents SSH/GPG -> vidés pour empêcher le fallback vers les sockets par défaut
export SSH_AUTH_SOCK=
export GPG_AGENT_INFO=
HARDEN

# Source le script en TOUTE PREMIÈRE ligne de .bashrc
RUN sed -i '1i source ~/.config/security-harden.sh 2>/dev/null || true' /home/node/.bashrc

# Bash history persistant
RUN echo 'export HISTFILE=/home/node/.bash_history' >> /home/node/.bashrc \
    && echo 'export PROMPT_COMMAND="history -a"' >> /home/node/.bashrc \
    && echo 'export HISTSIZE=10000' >> /home/node/.bashrc \
    && echo 'export HISTFILESIZE=20000' >> /home/node/.bashrc

# ──────────────────────────────────────────────────────────────────────────
# HOME PERSISTANT — mécanisme d'initialisation du volume
#
# Le devcontainer.json monte un volume nommé sur /home/node. Un volume VIDE
# masquerait tout le contenu créé ci-dessus (.bashrc, .config, etc.).
# Solution : on garde une COPIE "modèle" du home hors du point de montage
# (/opt/home-skel). Au premier démarrage, le postCreateCommand copie ce
# modèle dans le volume s'il est vide. Aux démarrages suivants, le volume
# contient déjà les données -> on ne touche à rien.
# ──────────────────────────────────────────────────────────────────────────
RUN mkdir -p /opt/home-skel \
    && cp -a /home/node/. /opt/home-skel/ \
    && chown -R node:node /opt/home-skel

RUN chown -R node:node /home/node

USER node
WORKDIR /workspaces
CMD ["bash"]
