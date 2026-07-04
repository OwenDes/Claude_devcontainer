# ──────────────────────────────────────────────────────────────────────────
# Claude Code Sandbox — VERSION DURCIE (Podman) + HOME PERSISTANT
# Base Node.js 22 sur Debian Bookworm (Node 20 = fin de vie avril 2026)
#
# ⚠️ Contexte de build = le dossier .devcontainer/ (à cause des COPY) :
#    podman build -t IMAGE .devcontainer
# ──────────────────────────────────────────────────────────────────────────
FROM node:22-bookworm

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
    iptables \
    ipset \
    dnsutils \
    iproute2 \
    pass \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/fr_FR.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr LC_ALL=fr_FR.UTF-8

# ──────────────────────────────────────────────────────────────────────────
# CLI d'API Git (issues, tickets, MR/PR) : gh (GitHub) + glab (GitLab).
# Binaires statiques depuis les releases officielles (amd64). Non fatal si un
# téléchargement échoue -> l'image se construit quand même (bump des versions
# ci-dessous si besoin). Le token vient de pass via des wrappers shell
# (voir security-harden.sh), donc aucun secret ici.
# ──────────────────────────────────────────────────────────────────────────
ARG GH_VERSION=2.63.2
ARG GLAB_VERSION=1.48.0
RUN { curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" -o /tmp/gh.tgz \
        && tar xzf /tmp/gh.tgz -C /tmp \
        && install "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
        && gh --version; } || echo "⚠️ gh non installé (ajuste GH_VERSION)"; \
    { curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" -o /tmp/glab.tgz \
        && tar xzf /tmp/glab.tgz -C /tmp \
        && install "$(find /tmp -type f -name glab | head -1)" /usr/local/bin/glab \
        && glab --version; } || echo "⚠️ glab non installé (ajuste GLAB_VERSION)"; \
    rm -rf /tmp/gh* /tmp/glab*

# ──────────────────────────────────────────────────────────────────────────
# DURCISSEMENT — script de neutralisation des ponts VSCode.
# Placé dans /etc (root, dans l'image) et PAS dans le home : il n'est pas
# masqué par le volume persistant, il reçoit les mises à jour à chaque
# rebuild, et l'utilisateur node ne peut pas le modifier.
# Sourcé depuis /etc/bash.bashrc (tous les bash interactifs) ; l'historique
# persistant est configuré au même endroit.
# ──────────────────────────────────────────────────────────────────────────
COPY security-harden.sh /etc/security-harden.sh
RUN chmod 644 /etc/security-harden.sh \
    && { echo 'source /etc/security-harden.sh'; \
         echo 'export PROMPT_COMMAND="history -a"'; \
         echo 'export HISTSIZE=10000'; \
         echo 'export HISTFILESIZE=20000'; } >> /etc/bash.bashrc

# ──────────────────────────────────────────────────────────────────────────
# SCRIPTS D'INIT (root, non modifiables par node)
#  - init-home.sh     : remplit le volume home depuis le skel (1er démarrage)
#  - init-firewall.sh : pare-feu sortant allowlist (à chaque démarrage)
# ──────────────────────────────────────────────────────────────────────────
COPY init-home.sh init-firewall.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/init-home.sh /usr/local/bin/init-firewall.sh

# ──────────────────────────────────────────────────────────────────────────
# TOKENS GIT CHIFFRÉS (pass) — helper de credential + setup unique.
# git-credential-pass : déchiffre le token à la volée (jamais en clair).
# setup-git-token.sh  : à lancer une fois par node pour créer clé+store.
# (.sh retiré à la copie pour un appel propre : git-credential-pass)
# ──────────────────────────────────────────────────────────────────────────
COPY git-credential-pass.sh /usr/local/bin/git-credential-pass
COPY setup-git-token.sh /usr/local/bin/setup-git-token
RUN chmod 755 /usr/local/bin/git-credential-pass /usr/local/bin/setup-git-token

# ──────────────────────────────────────────────────────────────────────────
# SUDO RESTREINT — node ne peut lancer QUE les deux scripts d'init.
# Pas de NOPASSWD:ALL : un process compromis dans le conteneur ne peut
# pas devenir root.
# ──────────────────────────────────────────────────────────────────────────
RUN echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-home.sh, /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# ──────────────────────────────────────────────────────────────────────────
# CLAUDE CODE — installeur natif dans ~/.local : embarqué dans le skel,
# donc persistant dans le volume home, et capable de se mettre à jour
# tout seul (aucun sudo nécessaire, contrairement à npm -g).
# ──────────────────────────────────────────────────────────────────────────
USER node
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root
ENV PATH="/home/node/.local/bin:${PATH}"

# ──────────────────────────────────────────────────────────────────────────
# HOME PERSISTANT — copie "modèle" du home hors du point de montage.
# Un volume VIDE monté sur /home/node masquerait le contenu créé au build ;
# init-home.sh (postCreateCommand) le remplit depuis /opt/home-skel au
# premier démarrage, puis ne touche plus à rien.
# ──────────────────────────────────────────────────────────────────────────
RUN mkdir -p /opt/home-skel \
    && cp -a /home/node/. /opt/home-skel/ \
    && chown -R node:node /opt/home-skel

RUN chown -R node:node /home/node

USER node
WORKDIR /workspaces
CMD ["bash"]
