#!/usr/bin/env bash
# READ-ONLY preflight. No credentials or private key contents.
set -u
sudo -v || exit 1
echo '=== System and mounts ==='
date
uname -a
tailscale ip -4
findmnt -M /NeutronMedia
df -h /NeutronMedia /NeutronOS
echo '=== Service state only ==='
for s in neutronllm-http neutronllm-ingress torrentlab2 torrentlab-private-dns docker jellyfin qbittorrent qbittorrent-nox neutronstream neutronstream-live; do
  echo SERVICE:$s
  systemctl show "$s" -p LoadState -p ActiveState -p SubState -p FragmentPath -p User -p WorkingDirectory --no-page 2>/dev/null
done
echo '=== Relevant installed unit names ==='
systemctl list-unit-files --no-legend 2>/dev/null | grep -Ei 'neutron|torrent|jellyfin|qbit|dnsmasq|nginx' | head -80
echo '=== Container names and ports, not environment ==='
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo '=== Listening ports ==='
sudo ss -lntp
echo '=== Nginx files and harmless directives only ==='
for dir in /etc/neutronai /etc/nginx; do
  if sudo test -d "$dir"; then
    sudo grep -RnIE --include='*.conf' '^[[:space:]]*(listen|server_name|ssl_verify_client|ssl_client_certificate|ssl_certificate|include|proxy_pass|allow|deny)[[:space:]]' "$dir" 2>/dev/null | grep -v 'ssl_certificate_key' | head -120
  fi
done
echo '=== Private CA filenames only (no key contents) ==='
for dir in /root/neutronos-private-ca /etc/torrentlab2; do
  if sudo test -d "$dir"; then
    echo DIRECTORY:$dir
    sudo find "$dir" -maxdepth 2 -type f \( -name '*.crt' -o -name '*.pem' -o -name '*.p12' \) -printf '%P\n' 2>/dev/null | head -35
  fi
done
echo '=== Private DNS file paths ==='
for path in /etc/dnsmasq-torrentlab.conf /etc/dnsmasq.conf /etc/dnsmasq.d; do
  if sudo test -e "$path"; then sudo stat -c '%F %n' "$path"; fi
done
echo '=== Private DNS routing entries only ==='
for file in /etc/dnsmasq-torrentlab.conf /etc/dnsmasq.conf; do
  if sudo test -f "$file"; then
    sudo grep -E '^(address=|host-record=|local=|listen-address=|interface=)' "$file" | head -40 || true
  fi
done
echo '=== Tailscale DNS resolver ==='
resolvectl status tailscale0 2>/dev/null | grep -E 'DNS Servers:|DNS Domain:|Current DNS Server:' || true
echo '=== Local backend responses, codes only ==='
for port in 8792 8793 8765; do
  echo -n "$port: "
  curl -sS --connect-timeout 2 --max-time 3 -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$port/" 2>&1 || true
done
echo '=== Complete. Read-only ==='
