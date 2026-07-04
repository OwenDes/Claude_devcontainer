# Changelog

## 2026-07-04 (CLI API) — glab + gh avec token pass injecté

Le token pass sert à l'**API** (issues, tickets, MR/PR), pas au `git push`
(qui reste en SSH via les clés). Ajout des outils correspondants :

- **`gh` et `glab` installés** dans l'image (binaires des releases
  officielles, versions figées par `GH_VERSION`/`GLAB_VERSION` ; install non
  fatale au build).
- **Wrappers shell** (`security-harden.sh`) : `gh`/`glab` récupèrent le token
  depuis `pass` **à l'appel** (jamais en clair). `glab` déduit l'hôte du
  remote git courant (SSH ou HTTPS), sinon `gitlab.com` ; surcharge via
  `GITLAB_HOST`. Logique de détection d'hôte + récupération token vérifiée.
- Non testés ici (nécessitent rebuild + réseau) : le build de l'image et les
  binaires `gh`/`glab` eux-mêmes.

## 2026-07-04 (mise en service pass) — Trousseau isolé, token retiré, notes

Mise en service réelle du stockage pass et finition sécurité.

- **Trousseau GPG dédié `~/.gnupg-pass`** (commit `2823a28`) : le `~/.gnupg`
  persistant contient des clés au format v5 que le GnuPG 2.2 de bookworm ne
  sait pas lire (« unknown version 5 »), ce qui faisait échouer `pass init`.
  `pass` utilise donc un trousseau isolé via `PASSWORD_STORE_GPG_OPTS`
  (`setup-git-token`, `git-credential-pass`, `security-harden.sh`) ; le
  `~/.gnupg` de l'utilisateur n'est pas touché. Round-trip token vérifié
  (`git credential fill` → username/password déchiffrés).
- **`GITLAB_TOKEN` retiré de `~/.bashrc`** (fait) et backup temporaire
  détruit au `shred` (il contenait le token). ⚠️ Les shells déjà ouverts
  gardent la variable jusqu'à fermeture. **Révocation du token côté GitLab =
  action utilisateur, toujours requise** (fuité en clair dans des logs).
- **Helper git générique** : un seul `credential.helper` pour tous les hôtes
  (au lieu d'un par hôte). Ajouter un serveur = `pass insert git/<host>`,
  aucune reconfig git — le helper décline proprement si l'hôte n'a pas
  d'entrée. Nommage : l'entrée doit être `git/<host>` exact.
  ⚠️ Concerne les remotes HTTPS. Pour l'usage API (issues, tickets via
  glab/gh/curl), le token pass se passe à l'appel — voir le guide.
- **Note SSH** : ce repo a un remote SSH (`git@github.com`) et une clé
  `~/.ssh/id_ed25519` **sans passphrase** dans le volume → push unattended
  sans agent. Le helper pass ne concerne que les remotes `https://…`.
  Choix laissé ouvert : rester en SSH, ou passer en HTTPS+pass (token
  chiffré au repos, plus cohérent avec le reste du durcissement).

## 2026-07-04 (accès) — Bascule réseau + tokens Git chiffrés

Répond à deux besoins : ouvrir/fermer l'accès réseau à la demande, et
sortir le token Git du clair (il fuitait dans `~/.bashrc` et les logs).

### Bascule réseau (mode recherche vs verrouillé)

- `init-firewall.sh` accepte maintenant un mode : `strict` (défaut,
  allowlist) ou `open` (egress complet pour recherche web / apt / pip / npm).
- Alias pratiques (dans `security-harden.sh`) : `net-open` / `net-strict`.
- `gitlab.com` et `gitlab-df.imt-atlantique.fr` ajoutés à l'allowlist stricte
  (accès Git constant sans ouvrir tout le réseau).
- ⚠️ Rappel : `node` a CAP_NET_ADMIN → contrôle d'intention pour agent de
  confiance, pas une barrière contre un agent malveillant.

### Tokens Git chiffrés (pass, cached/unattended)

- `pass` installé ; helper `git-credential-pass` (déchiffre le token à la
  volée, jamais en clair dans l'env/.bashrc/l'image) ; `setup-git-token`
  (config unique : clé GPG sans passphrase + store + helper par hôte).
- Scrub du helper VSCode rendu ciblé (match `vscode-remote-containers`) pour
  ne pas supprimer le helper `pass` légitime.
- Choix assumé « cached/unattended » : protège le token AU REPOS et contre la
  fuite accidentelle, PAS contre un agent malveillant qui le déchiffrerait à
  l'usage (pour ça : YubiKey touch / broker hôte — non retenus ici).
- **À faire par l'utilisateur** après rebuild : lancer `setup-git-token`,
  `pass insert -m git/<host>`, retirer `GITLAB_TOKEN` de `~/.bashrc`, et
  **révoquer** l'ancien token (fuité en clair).

## 2026-07-04 (audit) — Audit en conteneur & correctifs

Audit complet depuis l'intérieur du conteneur reconstruit. **Réussis** :
identité non privilégiée (uid=1000), neutralisation shell (IPC/ASKPASS/
DISPLAY/WAYLAND/SSH/GPG/BROWSER vides), scripts root non modifiables par
node, sudo confiné (hors allowlist refusé), pare-feu IPv4 (example.com
bloqué / anthropic OK), montages propres (pas de docker.sock ni .ssh/.gnupg,
workspace limité au projet). **Trous corrigés** :

- **IPv6 non filtré** (`init-firewall.sh`) : l'allowlist était purement
  IPv4, tout l'IPv6 contournait le pare-feu. Ajout de règles `ip6tables`
  qui DROP tout l'IPv6 (loopback + connexions établies exceptés). Pas de
  route IPv6 active actuellement, mais faille latente sinon.
- **Pont credential Git réinjecté** : VSCode réécrit son helper dans
  `/etc/gitconfig` (root) ET `~/.gitconfig` à chaque reconnexion. Scrub
  ajouté à chaque démarrage : `/etc/gitconfig` via `init-firewall.sh`
  (root), `~/.gitconfig` via `postStartCommand` (node). Vérifié : node ne
  peut PAS écrire `/etc/gitconfig` lui-même (d'où le scrub root).

### Limite connue (non corrigée — décision requise)

- **node possède CAP_NET_ADMIN + CAP_NET_RAW dans son set effectif** : sous
  Podman rootless, les `--cap-add` du conteneur sont hérités par
  l'utilisateur. Conséquence prouvée : `iptables -F OUTPUT` réussit sans
  sudo → un process compromis peut désactiver le pare-feu. Le pare-feu
  protège donc contre une fuite *accidentelle*, mais n'est pas une barrière
  contre un process *malveillant* dans le conteneur. Fermeture propre =
  refonte (init réseau privilégié séparé + drop des caps pour node).

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
