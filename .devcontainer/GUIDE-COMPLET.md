# Guide complet — Claude Code Sandbox (Podman / Docker + Docker Hub)

Guide de référence pour ton environnement Claude Code durci, avec **home persistant** (login + conversations gardés entre les redémarrages). Mis à jour après le passage à Podman, le durcissement, et la correction du `.claude.json`.

> Remplace **partout** `TONUSER` par ton vrai username Docker Hub.

---

## Sommaire

- [Rappel de ton setup](#rappel-de-ton-setup)
- [Notions de base Podman / Docker](#notions-de-base-podman--docker)
- [Comment marche la persistance (home + skel)](#comment-marche-la-persistance-home--skel)
- [Partie 1 — Build & push depuis chez toi (Podman)](#partie-1--build--push-depuis-chez-toi-podman)
- [Partie 2 — Usage à l'école (Docker)](#partie-2--usage-à-lécole-docker)
- [Partie 3 — Mettre à jour l'image](#partie-3--mettre-à-jour-limage)
- [Partie 4 — Pièges rencontrés & solutions](#partie-4--pièges-rencontrés--solutions)
- [Partie 5 — Conseils & sécurité](#partie-5--conseils--sécurité)
- [Aide-mémoire des commandes](#aide-mémoire-des-commandes)

---

## Rappel de ton setup

```
ton-projet/
├── .devcontainer/
│   ├── Dockerfile           # image durcie + skel pour le home persistant
│   ├── devcontainer.json    # volume home + remoteEnv + capacités pare-feu
│   ├── security-harden.sh   # neutralisation des ponts VSCode (-> /etc)
│   ├── init-home.sh         # init du volume home depuis le skel (root)
│   └── init-firewall.sh     # pare-feu sortant allowlist (root)
└── .vscode/
    └── settings.json        # réglages de durcissement portables
```

Ce qui **voyage** avec ton projet : le dossier `.devcontainer/` et le `.vscode/settings.json`.
Ce qui **voyage** avec l'image Docker Hub : l'OS, les outils, Claude Code, le script de durcissement, le modèle de home (`/opt/home-skel`).
Ce qui **NE voyage PAS** : les réglages User de VSCode liés à la machine (`dockerPath`, cases Wayland/WSL) ; et les volumes (donc le login Claude est à refaire une fois par machine).

---

## Notions de base Podman / Docker

- **Image** : modèle figé (OS + outils + ton appli). Format **OCI standard** -> marche sous Podman ET Docker.
- **Conteneur** : instance qui tourne, créée depuis une image. Jetable.
- **Volume nommé** : stockage persistant géré par le moteur, qui survit aux redémarrages/suppressions de conteneurs. Ici : `claude-code-home` (tout le home de `node`).
- **Bind mount** : un dossier de ton PC monté dans le conteneur (ton workspace projet, monté automatiquement par VSCode).
- **Registry** : dépôt d'images en ligne (Docker Hub).
- **Tag** : étiquette de version (`:latest`, `:v1.0`).
- **Rootless** (Podman) : conteneurs sous ton utilisateur, pas root système -> plus sûr.
- **Daemon** : service en arrière-plan. Docker en a un (`dockerd`) qui peut planter ; Podman n'en a pas.

Mêmes commandes des deux côtés : tout `docker xxx` devient `podman xxx`.

---

## Comment marche la persistance (home + skel)

C'est la nouveauté qui règle le souci du `.claude.json` introuvable.

**Le problème** : Claude Code stocke ses données à deux endroits — le dossier `/home/node/.claude/` (token, historique) ET le fichier `/home/node/.claude.json` (config principale). Si on ne persiste que le dossier, le fichier `.claude.json` est perdu à chaque recréation du conteneur.

**La solution** : on persiste **tout le home** `/home/node` dans un seul volume nommé `claude-code-home`. Du coup `.claude.json`, `.claude/`, `.bash_history`, `.config/` survivent ensemble.

**Le piège géré** : un volume vide monté sur le home masquerait le contenu créé au build (le `.bashrc` avec le durcissement, le `security-harden.sh`). Pour l'éviter :

1. Le Dockerfile garde une copie "modèle" du home hors du point de montage, dans `/opt/home-skel`.
2. Au **premier démarrage**, le `postCreateCommand` lance `sudo /usr/local/bin/init-home.sh`, qui détecte que le volume est neuf (pas de `.bashrc`) et le remplit depuis le modèle. C'est (avec `init-firewall.sh`) le **seul** usage de sudo autorisé : le sudoers est restreint à ces deux scripts root, plus de `NOPASSWD:ALL`.
3. Aux **démarrages suivants**, le `.bashrc` est présent -> on ne touche à rien, tes données (login, conversations) sont préservées.

> Le durcissement lui-même (`security-harden.sh`) ne vit **plus dans le home** mais dans `/etc/security-harden.sh`, sourcé via `/etc/bash.bashrc`. Avantages : pas masqué par le volume, mis à jour à chaque rebuild d'image, et non modifiable par `node` (ni par un process compromis dans le conteneur).

> ⚠️ Comme la structure de volume a changé (un seul `claude-code-home` au lieu des anciens `claude-code-config` + `claude-code-bashhistory`), il faut repartir d'un volume neuf et refaire le login `claude` une dernière fois.

---

## Partie 1 — Build & push depuis chez toi (Podman)

### Prérequis

- Podman Desktop installé, machine Podman "Running"
- Le dossier projet avec `.devcontainer/` dedans
- Connexion internet correcte (~1-2 Go à uploader)
- Compte Docker Hub : <https://hub.docker.com/signup> (note ton **username**)

### Étape 1 — Build

```powershell
cd C:\Users\desch\Desktop\ai\claude-code_podman

podman build -t docker.io/TONUSER/claude-code-sandbox:latest .devcontainer
```

> ⚠️ Le contexte de build est maintenant `.devcontainer` (et plus `.`) : le Dockerfile fait des `COPY` des scripts qui vivent dans ce dossier.

### Étape 2 — Login

```powershell
podman login docker.io
```

### Étape 3 — Push

```powershell
podman push docker.io/TONUSER/claude-code-sandbox:latest
```

> ⚠️ Avant de push : aucun secret/token en dur dans le Dockerfile. Image publique = lisible par tous.

Vérifie sur `https://hub.docker.com/r/TONUSER/claude-code-sandbox`.

---

## Partie 2 — Usage à l'école (Docker)

Une image buildée par Podman tourne sans souci sous Docker (format OCI commun).

### Réglages VSCode à mettre à l'école

| Réglage | Valeur |
|---|---|
| `dev.containers.dockerPath` | `docker` (ou vide) |
| `dev.containers.dockerComposePath` | vide |
| Mount Wayland Socket | décoché (cohérence durcissement) |
| Forward WSL Services | décoché |

`dockerCredentialHelper:false`, `copyGitConfig:false` et `gitCredentialHelperConfigLocation:"none"` viennent déjà du `.vscode/settings.json` du projet. Le troisième est indispensable : sans lui, VSCode injecte son credential helper Git (pont vers les credentials de l'hôte) dans `/etc/gitconfig` et `~/.gitconfig` du conteneur, même avec `copyGitConfig:false`.

### Méthode A — Avec VSCode (recommandé)

Crée un dossier projet à l'école, avec un `.devcontainer/devcontainer.json` qui **pull** l'image (pas de Dockerfile nécessaire — le skel est déjà dans l'image) :

```json
{
    "name": "Claude Code Sandbox (école)",
    "image": "docker.io/TONUSER/claude-code-sandbox:latest",
    "remoteUser": "node",
    "containerUser": "node",
    "updateRemoteUserUID": true,
    "runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"],
    "remoteEnv": {
        "SSH_AUTH_SOCK": "",
        "GPG_AGENT_INFO": "",
        "BROWSER": "",
        "VSCODE_IPC_HOOK_CLI": null,
        "VSCODE_GIT_IPC_HANDLE": null,
        "GIT_ASKPASS": null,
        "VSCODE_GIT_ASKPASS_MAIN": null,
        "VSCODE_GIT_ASKPASS_NODE": null,
        "VSCODE_GIT_ASKPASS_EXTRA_ARGS": null,
        "REMOTE_CONTAINERS_IPC": null,
        "REMOTE_CONTAINERS_SOCKETS": null,
        "REMOTE_CONTAINERS_DISPLAY_SOCK": null,
        "WAYLAND_DISPLAY": null,
        "DISPLAY": null
    },
    "mounts": [
        "source=claude-code-home,target=/home/node,type=volume"
    ],
    "customizations": {
        "vscode": {
            "settings": {
                "terminal.integrated.defaultProfile.linux": "bash"
            },
            "extensions": ["anthropic.claude-code"]
        }
    },
    "postCreateCommand": "sudo /usr/local/bin/init-home.sh && claude --version",
    "postStartCommand": "sudo /usr/local/bin/init-firewall.sh || echo '⚠️ Pare-feu NON initialisé : sortie réseau non filtrée'; find /tmp -maxdepth 2 \\( -name 'vscode-ssh-auth-*.sock' -o -name 'vscode-remote-containers-ipc-*.sock' -o -name 'vscode-remote-containers-*.js' \\) -delete 2>/dev/null || true"
}
```

> Le `postCreateCommand` avec l'init du skel est **indispensable** ici aussi : l'image pull contient `/opt/home-skel`, et c'est lui qui réinitialise le volume home neuf au premier démarrage.

Puis : `Ctrl+Shift+P` → **Dev Containers: Reopen in Container** → `claude` + login OAuth (1 fois sur ce PC).

### Méthode B — Sans VSCode (terminal)

```powershell
cd Bureau\mon-projet-ecole

docker pull docker.io/TONUSER/claude-code-sandbox:latest

docker run -it --rm `
  --cap-add=NET_ADMIN --cap-add=NET_RAW `
  -v claude-code-home:/home/node `
  -v "${PWD}:/workspaces/projet" `
  -w /workspaces/projet `
  docker.io/TONUSER/claude-code-sandbox:latest `
  bash -c "sudo /usr/local/bin/init-home.sh; sudo /usr/local/bin/init-firewall.sh || echo 'pare-feu NON actif'; exec bash"
```

Sur Linux/macOS : `${PWD}` -> `$(pwd)`, les `` ` `` -> `\`.

Tu arrives dans le bash du conteneur, tape `claude`.

> En terminal pur, on lance les mêmes scripts d'init que le devcontainer : `init-home.sh` (volume home neuf) et `init-firewall.sh` (pare-feu sortant). Le durcissement `/etc/security-harden.sh` s'applique automatiquement via `/etc/bash.bashrc` au démarrage du bash.

---

## Partie 3 — Mettre à jour l'image

### Chez toi (rebuild + push)

```powershell
cd C:\Users\desch\Desktop\ai\claude-code_podman

podman build -t docker.io/TONUSER/claude-code-sandbox:latest .devcontainer
podman push docker.io/TONUSER/claude-code-sandbox:latest
```

> 💡 Claude Code est installé dans `~/.local/bin` (donc dans le volume home) : il se met à jour **tout seul**, sans rebuild. Le rebuild d'image sert pour l'OS, les outils et les scripts de durcissement.

### À l'école (récupérer la nouvelle version)

```powershell
docker pull docker.io/TONUSER/claude-code-sandbox:latest
```

Puis VSCode : `Ctrl+Shift+P` → **Dev Containers: Rebuild Container**.

> 💡 Rebuild de l'image ≠ effacement du volume. Tes données dans `claude-code-home` restent intactes lors d'un simple rebuild d'image. Le skel ne réécrase QUE si le volume est vide.

### Versionner (recommandé)

```powershell
podman build -t docker.io/TONUSER/claude-code-sandbox:latest -t docker.io/TONUSER/claude-code-sandbox:v1.0 .devcontainer
podman push docker.io/TONUSER/claude-code-sandbox:latest
podman push docker.io/TONUSER/claude-code-sandbox:v1.0
```

---

## Partie 4 — Pièges rencontrés & solutions

### "Docker daemon not running" / Docker Desktop plante
Raison du passage à Podman (pas de daemon -> plus ce problème).

### Popup "Add Dev Container Configuration Files" qui revient
- Mauvais dossier ouvert (ouvre celui qui CONTIENT `.devcontainer/`).
- Dossier mal nommé : exactement `.devcontainer` (pas `.devcontaineur`).

### "Command not found: 'podman-compose'" / "no Dockerfile specified"
Compose mal supporté sous Windows avec Podman. Solution : pas de compose, version simple (Dockerfile + devcontainer.json).

### "unsupported UNC path ... wayland-0"
Podman ne sait pas monter le socket Wayland WSL. Solution : décocher **Mount Wayland Socket** + **Forward WSL Services** dans les settings VSCode.

### "Claude configuration file not found at /home/node/.claude.json"
Le `.claude.json` n'était pas persisté. Solution : volume sur tout le home (`claude-code-home`) + mécanisme skel. C'est ce que fait ce pack.

### Permissions sur le workspace (Podman rootless)
`updateRemoteUserUID:true` + `containerUser:node` dans le devcontainer.json évitent le souci. Si ça persiste : `:Z` sur le mount ou `userns`.

---

## Partie 5 — Conseils & sécurité

### Login Claude
- Volumes locaux à chaque machine -> première fois sur un PC = `claude` + OAuth.
- Ensuite persistant sur ce PC (volume `claude-code-home`).

### Image publique vs privée
- Docker Hub gratuit = image publique par défaut (OK, rien de sensible).
- Privée : Docker Hub → repo → Settings → "Make Private" (1 max en gratuit).

### Jamais de secret dans l'image
❌ `ENV ANTHROPIC_API_KEY=...` dans le Dockerfile.
✅ Login OAuth interactif, token dans le volume local, jamais dans l'image.

### Git depuis le conteneur (durcissement actif)
Partage auto des credentials coupé. `git commit` marche, `git push` non.
- Le plus sûr : push depuis l'hôte (hors conteneur).
- Sinon : PAT à permissions limitées + expiration courte, ou deploy key dédiée par repo.
- Clé SSH montée : lecture seule, avec passphrase, jamais dans l'image.

### Pare-feu sortant (egress)
Le conteneur démarre avec `--cap-add=NET_ADMIN/NET_RAW` et `init-firewall.sh` bloque **toute** sortie réseau sauf l'allowlist (Anthropic, GitHub, npm, marketplace VSCode). Claude ne peut donc pas exfiltrer des données ni télécharger n'importe quoi.
- Domaine légitime bloqué (ex : `pip install`) ? Ajoute-le dans `init-firewall.sh` et rebuild.
- Moteur qui refuse les capacités ? Le conteneur démarre quand même, avec un ⚠️ au postStart : sortie **non filtrée**, à toi de voir si c'est acceptable.

### Sudo restreint
`node` ne peut lancer via sudo QUE `init-home.sh` et `init-firewall.sh` (scripts root, non modifiables). Plus de `NOPASSWD:ALL` : un process compromis dans le conteneur ne peut plus devenir root ni saboter le durcissement.

### Vérifier que le durcissement est actif
```bash
echo "IPC:$VSCODE_IPC_HOOK_CLI ASKPASS:$GIT_ASKPASS BROWSER:$BROWSER SSH:$SSH_AUTH_SOCK WAYLAND:$WAYLAND_DISPLAY X11:$DISPLAY"
# Tout doit être vide après les deux-points.

sudo -l          # doit lister UNIQUEMENT les deux scripts d'init
curl -m 5 https://example.com   # doit ÉCHOUER (pare-feu actif)
curl -m 5 https://api.anthropic.com   # doit répondre (403/404 = OK, ça passe)
```

---

## Aide-mémoire des commandes

Remplace `podman` par `docker` à l'école.

```powershell
# Images / conteneurs / volumes
podman images
podman ps -a
podman volume ls

# Build / login / push / pull (contexte = .devcontainer, à cause des COPY)
podman build -t docker.io/TONUSER/claude-code-sandbox:latest .devcontainer
podman login docker.io
podman push docker.io/TONUSER/claude-code-sandbox:latest
podman pull docker.io/TONUSER/claude-code-sandbox:latest

# Supprimer une image locale
podman rmi docker.io/TONUSER/claude-code-sandbox:latest

# Reset complet (efface login + conversations + tout le home persistant)
podman volume rm claude-code-home

# Sauvegarder le home persistant (login + conversations) vers un .tar.gz
podman run --rm -v claude-code-home:/data -v ${PWD}:/backup alpine tar czf /backup/claude-home-backup.tar.gz -C /data .

# Restaurer le home depuis une sauvegarde
podman volume create claude-code-home
podman run --rm -v claude-code-home:/data -v ${PWD}:/backup alpine tar xzf /backup/claude-home-backup.tar.gz -C /data

# Machine Podman (recréer une VM propre si souci)
podman machine stop && podman machine rm && podman machine init && podman machine start

# Re-login Docker Hub
podman logout docker.io && podman login docker.io
```

---

## En résumé

```text
CHEZ TOI (Podman)                    À L'ÉCOLE (Docker)
─────────────────                    ──────────────────
1. podman build                      1. Crée un dossier de projet
2. podman login docker.io            2. .devcontainer/ avec "image" (+ postCreate skel)
3. podman push                       3. dockerPath=docker, cases décochées
                                     4. Pull + Reopen in Container
                                     5. claude + login OAuth (1 fois)
                                     6. Code 🚀
```

Image portable (Podman chez toi, Docker à l'école), durcissement embarqué, et **home persistant** : login + conversations gardés entre tous les redémarrages sur une même machine. Bon dev ! 🐳
