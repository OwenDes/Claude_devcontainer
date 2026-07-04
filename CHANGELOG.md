# Changelog

## 2026-07-04 (suite) — Correctifs après le premier démarrage réel

Vérifications faites dans le conteneur reconstruit : pare-feu actif
(`example.com` bloqué, `api.anthropic.com` accessible), sudo restreint OK,
Node 22 OK. Deux trous découverts dans les logs de démarrage :

- **`dev.containers.gitCredentialHelperConfigLocation: "none"`** ajouté dans
  `.vscode/settings.json` : même avec `copyGitConfig:false`, VSCode
  injectait son credential helper Git (pont vers les credentials de l'hôte)
  dans `/etc/gitconfig` ET `~/.gitconfig` du conteneur. L'entrée déjà écrite
  dans le `~/.gitconfig` persistant a été retirée.
- **`postStartCommand`** : ajout de `vscode-ipc-*.sock` et
  `vscode-git-*.sock` aux motifs de nettoyage (sockets de session
  précédente non couverts). Limite connue : pendant une session active,
  ces sockets sont recréés — le nettoyage ne vaut qu'au démarrage.
- ⚠️ Hors dépôt : un `GITLAB_TOKEN` en clair traînait dans le `~/.bashrc`
  du volume home (et donc dans l'env de tous les process du conteneur).
  À révoquer côté GitLab et à sortir de l'environnement.

## 2026-07-04 — Durcissement du devcontainer (revue de sécurité)

Revue complète de `.devcontainer/` : correction d'une config morte, suppression
du sudo illimité, ajout d'un pare-feu sortant, et durcissement rendu
inviolable depuis le conteneur.

### Corrigé

- **`.devcontainer/settings.json` supprimé (config morte)** : VSCode ne lit
  jamais un fichier à cet emplacement — les réglages qu'il contenait ne
  s'appliquaient donc à rien. `dev.containers.dockerCredentialHelper: false`
  et `dev.containers.copyGitConfig: false` sont déplacés dans
  `.vscode/settings.json` (le seul emplacement projet que VSCode lit).
  Les doublons dans `customizations.vscode.settings` du `devcontainer.json`
  sont retirés : appliqués DANS le conteneur après sa création, ils
  arrivaient trop tard pour agir.
- **`node:20-bookworm` → `node:22-bookworm`** : Node 20 est en fin de vie
  depuis avril 2026 (plus de correctifs de sécurité).

### Sécurité

- **Sudo restreint** (`Dockerfile`) : remplacement de
  `node ALL=(ALL) NOPASSWD:ALL` par une autorisation limitée à exactement
  deux scripts root non modifiables (`init-home.sh`, `init-firewall.sh`).
  Avant, n'importe quel process du conteneur (y compris Claude en session
  autonome) pouvait devenir root et défaire tout le durcissement.
- **Pare-feu sortant** (`init-firewall.sh`, nouveau) : bloque tout le trafic
  sortant sauf une allowlist — Anthropic/Claude (API + login OAuth), plages
  IP GitHub, npm, marketplace VSCode. Lancé à chaque démarrage via
  `postStartCommand` ; nécessite `--cap-add=NET_ADMIN,NET_RAW` (ajoutés dans
  `runArgs`). Fail-soft : sans les capacités, le conteneur démarre avec un
  ⚠️ explicite. Inspiré du devcontainer de référence Anthropic.
- **Durcissement sorti du volume home** : `security-harden.sh` est désormais
  installé en `/etc/security-harden.sh` (root, dans l'image) et sourcé depuis
  `/etc/bash.bashrc`, au lieu de vivre dans `~/.config` + `~/.bashrc`.
  Corrige deux failles du montage home persistant : (1) une version mise à
  jour du script au rebuild n'atteignait jamais les volumes existants ;
  (2) un `~/.bashrc` trafiqué par une session compromise survivait à tous
  les rebuilds. La config d'historique bash migre aussi vers
  `/etc/bash.bashrc`.
- **`DISPLAY` (X11) neutralisé** : ajouté au `remoteEnv` et au script de
  durcissement — seul `WAYLAND_DISPLAY` était coupé jusqu'ici.

### Modifié

- **Claude Code : `npm install -g` → installeur natif dans `~/.local/bin`** :
  la version n'est plus figée au build de l'image ; le binaire vit dans le
  volume home persistant et se met à jour tout seul, sans sudo.
  `ENV PATH` étendu en conséquence.
- **Scripts extraits en vrais fichiers** (`security-harden.sh`,
  `init-home.sh`, `init-firewall.sh` dans `.devcontainer/`) et intégrés par
  `COPY`, au lieu de heredocs dans le `Dockerfile`. Plus lisible, lintable,
  et plus de dépendance aux heredocs BuildKit.
  ⚠️ **Le contexte de build change** : `podman build -t IMAGE .devcontainer`
  (et non plus `-f .devcontainer/Dockerfile .`).
- **`init-home.sh`** reprend la logique d'init du volume home depuis
  `/opt/home-skel` (ex-`postCreateCommand` inline), avec en plus une
  migration : si un volume existant (ancienne image npm) n'a pas
  `~/.local/bin/claude`, le binaire est copié depuis le skel.
- **`GUIDE-COMPLET.md`** mis à jour partout : commandes de build (nouveau
  contexte), snippet devcontainer « école » (runArgs, DISPLAY, nouveaux
  postCreate/postStart), méthode terminal pur, sections sécurité (pare-feu,
  sudo restreint) et commandes de vérification (`sudo -l`, tests curl du
  pare-feu, `$DISPLAY`).

### Inchangé (choix assumés)

- Volume home `claude-code-home` partagé entre projets sur une même machine
  (login Claude conservé) — contamination croisée possible entre projets,
  suffixer le nom du volume si besoin d'isolation.
- Nettoyage best-effort des sockets VSCode en `postStartCommand` — la vraie
  défense reste les réglages hôte documentés dans le guide.
