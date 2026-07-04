#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
# PARE-FEU SORTANT — bloque tout le trafic sortant sauf une allowlist
# (Anthropic, GitHub, npm, marketplace VSCode). Inspiré du devcontainer
# de référence Anthropic. Nécessite --cap-add=NET_ADMIN,NET_RAW.
# Relancé à chaque démarrage via postStartCommand (les règles iptables
# ne persistent pas d'un démarrage à l'autre).
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Repartir de zéro (politiques ACCEPT le temps de résoudre les domaines)
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F
iptables -X
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
ipset destroy allowed-domains 2>/dev/null || true

# Localhost + DNS (nécessaires pour résoudre l'allowlist)
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

ipset create allowed-domains hash:net

# Plages IP GitHub officielles (git clone/push, releases)
gh_meta=$(curl -fsS --max-time 10 https://api.github.com/meta || true)
if [ -n "$gh_meta" ]; then
    echo "$gh_meta" | jq -r '(.web + .api + .git + .packages)[]' 2>/dev/null \
        | while read -r cidr; do
            ipset add allowed-domains "$cidr" 2>/dev/null || true
        done
fi

# Domaines indispensables : Claude Code + login OAuth, npm, VSCode
for domain in \
    api.anthropic.com \
    claude.ai \
    console.anthropic.com \
    statsig.anthropic.com \
    statsig.com \
    sentry.io \
    registry.npmjs.org \
    update.code.visualstudio.com \
    marketplace.visualstudio.com \
    anthropic.gallerycdn.vsassets.io \
    objects.githubusercontent.com; do
    for ip in $(dig +short A "$domain" 2>/dev/null); do
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done
done

# Réseau de l'hôte (passerelle, résolveur, IPC devcontainer)
host_ip=$(ip route | awk '/default/ {print $3; exit}')
if [ -n "$host_ip" ]; then
    host_net="${host_ip%.*}.0/24"
    iptables -A INPUT -s "$host_net" -j ACCEPT
    iptables -A OUTPUT -d "$host_net" -j ACCEPT
fi

# Connexions déjà établies
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Sortie autorisée uniquement vers l'allowlist
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Tout le reste : refusé par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# ── IPv6 ── L'allowlist ci-dessus est purement IPv4 : sans ces règles,
# tout le trafic IPv6 contournerait le pare-feu. On bloque tout l'IPv6
# (le loopback reste ouvert), sauf si ip6tables est indisponible.
if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -F 2>/dev/null || true
    ip6tables -X 2>/dev/null || true
    ip6tables -A INPUT  -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -P INPUT DROP 2>/dev/null || true
    ip6tables -P FORWARD DROP 2>/dev/null || true
    ip6tables -P OUTPUT DROP 2>/dev/null || true
fi

echo "Pare-feu sortant actif : $(ipset list allowed-domains | grep -cE '^[0-9]') entrées autorisées (IPv6 bloqué)"

# ── Pont credential Git ── VSCode réinjecte son credential helper (pont vers
# les credentials Git de l'hôte) dans /etc/gitconfig à chaque reconnexion,
# malgré gitCredentialHelperConfigLocation. On l'enlève ici (script root) ;
# le ~/.gitconfig (node) est nettoyé côté postStartCommand.
git config --system --unset-all credential.helper 2>/dev/null || true
