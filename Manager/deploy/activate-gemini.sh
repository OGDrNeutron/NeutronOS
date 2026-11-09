#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
SRC=${1:?Pass the Manager source directory}
[[ -f "$SRC/server/app.py" && -f "$SRC/web/index.html" ]] || { echo 'Manager source is missing' >&2; exit 1; }
DOMAIN=neutronos.neutronprojects.com
CA=/root/neutronos-private-ca
ISSUED=$CA/issued
CONFIG=/etc/neutronai/nginx.conf
DNS=/etc/dnsmasq-torrentlab.conf
BASE=/opt/neutronos-manager
ETC=/etc/neutronos-manager
TAIL=$(tailscale ip -4 | head -1)
[[ $TAIL == 100.* ]] || { echo 'Tailscale is not connected'; exit 1; }
mountpoint -q /NeutronMedia || { echo 'NeutronMedia is not mounted'; exit 1; }
for f in "$CA/ca.crt" "$CA/ca.key.pem" "$CONFIG" "$DNS"; do [[ -f "$f" ]] || { echo "STOP: missing $f"; exit 1; }; done
systemctl is-active --quiet neutronllm-http.service || { echo 'NeutronAI Nginx is not running'; exit 1; }
systemctl is-active --quiet torrentlab-private-dns.service || { echo 'TorrentLab private DNS is not running'; exit 1; }
/usr/sbin/nginx -t -c "$CONFIG" || exit 1
mkdir -p "$ISSUED" "$ETC" "$BASE"
chmod 700 "$ETC"
CERT=$ISSUED/neutronos-server.crt.pem
KEY=$ISSUED/neutronos-server.key.pem
if [[ ! -s $CERT || ! -s $KEY ]] || ! openssl x509 -in "$CERT" -noout -checkhost "$DOMAIN" >/dev/null 2>&1; then
 echo 'Creating server certificate signed by your EXISTING TorrentLab private CA.'
 echo 'Enter the private CA signing-key passphrase if OpenSSL requests it.'
 openssl req -new -newkey rsa:3072 -nodes -subj "/O=Neutron Projects/CN=$DOMAIN" -keyout "$KEY" -out "$ISSUED/neutronos-server.csr.pem"
 cat > "$ISSUED/neutronos-server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMAIN
EOF
 openssl x509 -req -in "$ISSUED/neutronos-server.csr.pem" -CA "$CA/ca.crt" -CAkey "$CA/ca.key.pem" -CAcreateserial -out "$CERT" -days 365 -sha256 -extfile "$ISSUED/neutronos-server.ext"
fi
openssl verify -CAfile "$CA/ca.crt" "$CERT" || exit 1
openssl x509 -in "$CERT" -noout -checkhost "$DOMAIN" || exit 1
openssl x509 -in "$CERT" -noout -checkend 86400 >/dev/null || { echo 'Server certificate expired'; exit 1; }
cp "$KEY" "$ETC/server.key"
cat "$CERT" "$CA/ca.crt" > "$ETC/server-chain.crt"
cp "$CA/ca.crt" "$ETC/client-ca.crt"
chmod 600 "$ETC/server.key"
chmod 644 "$ETC/server-chain.crt" "$ETC/client-ca.crt"
if ! id neutron-manager >/dev/null 2>&1; then useradd --system --user-group --home-dir /var/lib/neutron-manager --create-home --shell /usr/sbin/nologin neutron-manager; fi
install -d -o neutron-manager -g neutron-manager -m 0700 /var/lib/neutron-manager
cp -a "$SRC/web" "$SRC/server" "$BASE/"
chown -R root:root "$BASE/web" "$BASE/server"
python3 -m venv "$BASE/.venv" || { echo 'python3-venv is required'; exit 1; }
"$BASE/.venv/bin/pip" -q install --disable-pip-version-check -r "$BASE/server/requirements.txt"
cat > "$ETC/environment" <<EOF
MANAGER_HOSTNAME=$DOMAIN
MANAGER_OS_VERSION=NeutronOS Gemini
MANAGER_USER_DATA_PATH=/NeutronOS/drneutron
MANAGER_FILES_HOME=/var/lib/neutron-manager
MANAGER_ENABLE_POWER=0
MANAGER_READ_ONLY=1
MANAGER_TOOL_TORRENTLAB=https://torrentlab.neutronprojects.com/torrentlab/
MANAGER_TOOL_NEUTRONAI=https://neutronai.neutronprojects.com/
MANAGER_CONTAINER_JELLYFIN=jellyfin
MANAGER_CONTAINER_QBITTORRENT=qbittorrent
EOF
chmod 600 "$ETC/environment"
cat > /etc/systemd/system/neutronos-manager.service <<EOF
[Unit]
Description=Private NeutronOS Manager
After=network-online.target
Wants=network-online.target
[Service]
User=neutron-manager
Group=neutron-manager
WorkingDirectory=$BASE
EnvironmentFile=$ETC/environment
ExecStart=$BASE/.venv/bin/uvicorn server.app:app --host 127.0.0.1 --port 8877 --no-proxy-headers
Restart=on-failure
RestartSec=3
UMask=0077
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/var/lib/neutron-manager /NeutronMedia
[Install]
WantedBy=multi-user.target
EOF
# Initial deployment is read-only. Do not grant service, Docker or shutdown privileges.
systemctl daemon-reload
systemctl enable --now neutronos-manager.service
systemctl is-active --quiet neutronos-manager.service || { echo 'Manager backend could not start'; exit 1; }
cat > "$ETC/nginx-vhost.conf" <<EOF
server {
 listen $TAIL:443 ssl;
 server_name $DOMAIN;
 ssl_certificate $ETC/server-chain.crt;
 ssl_certificate_key $ETC/server.key;
 ssl_client_certificate $ETC/client-ca.crt;
 ssl_verify_client on;
 ssl_verify_depth 2;
 allow 100.64.0.0/10;
 deny all;
 client_max_body_size 128m;
 server_tokens off;
 location / {
  proxy_pass http://127.0.0.1:8877;
  proxy_http_version 1.1;
  proxy_set_header Host $DOMAIN;
  proxy_set_header X-Neutron-Client-Verified \$ssl_client_verify;
  proxy_set_header X-Forwarded-Proto https;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_read_timeout 3600s;
  proxy_buffering off;
 }
}
EOF
BACKUP_NGINX=$ETC/neutronai-nginx.backup.$(date +%Y%m%d-%H%M%S)
cp -a "$CONFIG" "$BACKUP_NGINX"
python3 - "$CONFIG" "$ETC/nginx-vhost.conf" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]);t=p.read_text();inc='include '+sys.argv[2]+';'
if inc not in t:
    m=re.search(r'(?m)^\s*http\s*\{',t)
    if not m: raise SystemExit('No http block in current NeutronAI Nginx config')
    p.write_text(t[:m.end()]+'\n  '+inc+'\n'+t[m.end():])
PY
if ! /usr/sbin/nginx -t -c "$CONFIG"; then cp -a "$BACKUP_NGINX" "$CONFIG"; echo 'Nginx config invalid; restored existing config'; exit 1; fi
if ! /usr/sbin/nginx -s reload -c "$CONFIG"; then cp -a "$BACKUP_NGINX" "$CONFIG"; /usr/sbin/nginx -s reload -c "$CONFIG" || :; echo 'Nginx reload failed; restored config'; exit 1; fi
BACKUP_DNS=$ETC/torrentlab-dns.backup.$(date +%Y%m%d-%H%M%S)
cp -a "$DNS" "$BACKUP_DNS"
if ! grep -Fq "host-record=$DOMAIN," "$DNS"; then
 printf '\n# NeutronOS private manager\nhost-record=%s,%s\nlocal=/%s/\n' "$DOMAIN" "$TAIL" "$DOMAIN" >> "$DNS"
fi
if ! /usr/sbin/dnsmasq --test --conf-file="$DNS" >/dev/null 2>&1 || ! systemctl restart torrentlab-private-dns.service; then
 cp -a "$BACKUP_DNS" "$DNS"; systemctl restart torrentlab-private-dns.service || :
 echo 'Private DNS configuration failed; restored old record'; exit 1
fi
HTTP=$(curl -sk --resolve "$DOMAIN:443:$TAIL" --connect-timeout 3 --max-time 6 -o /dev/null -w '%{http_code}' "https://$DOMAIN/" || :)
if [[ $HTTP != 400 && $HTTP != 403 && $HTTP != 495 && $HTTP != 496 ]]; then echo "WARNING: unexpected unauthenticated HTTP $HTTP: investigate mTLS before using"; exit 1; fi
printf '\n[OK] Manager is on Gemini, Tailscale HTTPS and mTLS protected.\n'
printf 'NOW add Tailscale Admin DNS restricted resolver: domain %s -> nameserver %s\n' "$DOMAIN" "$TAIL"
printf 'Admin page: https://login.tailscale.com/admin/dns\n'
printf 'Then open https://%s on the iPhone while connected to Tailscale with existing client cert.\n' "$DOMAIN"
