#!/usr/bin/env bash
# NeutronOS Gemini private manager installer, prepared for the Nov 8 2026 inventory.
# Creates a new SNI site; DOES NOT replace TorrentLab, NeutronAI, or NeutronStream.
set -Eeuo pipefail
umask 077
[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root with sudo" >&2; exit 1; }
[[ "$#" -eq 1 ]] || { echo "Usage: sudo bash deploy-gemini-reviewed.sh /path/to/Manager" >&2; exit 1; }
SOURCE="$1"
[[ -s "$SOURCE/server/app.py" && -s "$SOURCE/web/index.html" ]] || { echo "ERROR: Manager source is missing" >&2; exit 1; }

HOST="neutronos.neutronprojects.com"
IP="100.69.100.100"
CA="/root/neutronos-private-ca"
CA_CERT="$CA/ca.crt"
CA_KEY="$CA/ca.key.pem"
DNS="/etc/dnsmasq-torrentlab.conf"
ROOT="/opt/neutronos-manager"
CONF="/etc/neutronos-manager"
HTTP_SERVER_UNIT="neutronllm-http.service"
HTTPS_SERVER_UNIT="torrentlab2-https.service"
DNS_UNIT="torrentlab-private-dns.service"
CERT="$CONF/server.crt"
KEY="$CONF/server.key"
CLIENT_CA="$CONF/trusted-clients.crt"
SITE="$CONF/neutronos-private-vhost.conf"

say(){ printf '\n[NeutronOS Manager] %s\n' "$*"; }
stop(){ printf '\n[STOP] %s\n' "$*" >&2; exit 1; }
# Reuse the binary already serving HTTPS, including custom Nginx builds.
NGINX_BIN="$(command -v nginx 2>/dev/null || true)"
if [[ -z "$NGINX_BIN" || ! -x "$NGINX_BIN" ]]; then
  for proc in /proc/[0-9]*/comm; do
    [[ "$(cat "$proc" 2>/dev/null)" == nginx ]] || continue
    exe="${proc%/comm}/exe"
    [[ -x "$exe" ]] || continue
    NGINX_BIN="$exe"
    break
  done
fi
[[ -n "$NGINX_BIN" && -x "$NGINX_BIN" ]] || stop "Cannot locate the running Nginx executable"
say "Nginx executable: $NGINX_BIN"
command -v openssl >/dev/null || stop "OpenSSL is missing"
command -v python3 >/dev/null || stop "Python3 is missing"
command -v git >/dev/null || stop "git is missing"
[[ "$(tailscale ip -4 | head -1)" == "$IP" ]] || stop "Unexpected Tailscale IP, refusing to alter the old HTTPS site"
mountpoint -q /NeutronMedia || stop "NeutronMedia is not mounted"
[[ -r "$CA_CERT" && -r "$CA_KEY" && -r "$DNS" ]] || stop "Existing TorrentLab CA or DNS files not found"
systemctl is-active --quiet "$HTTPS_SERVER_UNIT" || stop "The existing TorrentLab HTTPS service is not active"
systemctl is-active --quiet "$HTTP_SERVER_UNIT" || stop "Existing NeutronAI is not active"
systemctl is-active --quiet "$DNS_UNIT" || stop "Private DNS service is not active"
[[ ! -e "$SITE" ]] || stop "NeutronOS vhost already exists; manual update review required"

# Locate the nginx master process managed by the EXISTING HTTPS systemd unit.
# HTTPS may be launched by a forking/oneshot unit without a tracked MainPID.
MASTER_PID="$(systemctl show "$HTTPS_SERVER_UNIT" -p MainPID --value 2>/dev/null || true)"
NGINX_CMD=""
if [[ "$MASTER_PID" =~ ^[1-9][0-9]*$ ]]; then
  NGINX_CMD="$(ps -p "$MASTER_PID" -o args= || true)"
fi
HTTPS_CONF="$(printf "%s" "$NGINX_CMD" | sed -nE 's/.*[[:space:]]-c[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)"
if [[ -z "$HTTPS_CONF" ]]; then
  HTTPS_CMD="$(systemctl show "$HTTPS_SERVER_UNIT" -p ExecStart --value)"
  HTTPS_CONF="$(printf "%s" "$HTTPS_CMD" | sed -nE 's/.*[[:space:]]-c[[:space:]]+([^[:space:];}]+).*/\1/p' | head -1)"
fi
if [[ -z "$HTTPS_CONF" ]]; then
  HTTPS_CONF="$(ps -eo args= | grep -E 'nginx: master process .* -c /' | sed -nE 's/.*[[:space:]]-c[[:space:]]+([^[:space:]]+).*/\1/p' | grep -v '^/etc/neutronai/nginx.conf$' | head -1 || true)"
fi
 [[ "$HTTPS_CONF" == /* && -r "$HTTPS_CONF" ]] || stop "Unable to discover the existing HTTPS Nginx config. Do not guess; share systemctl cat torrentlab2-https.service."
[[ "$HTTPS_CONF" != "/etc/neutronai/nginx.conf" ]] || stop "HTTPS and HTTP unexpectedly share a configuration; review before proceeding"
grep -Eq '^[[:space:]]*http[[:space:]]*\{' "$HTTPS_CONF" || stop "HTTPS config lacks an editable http block"
if grep -Eq '^[[:space:]]*server_name[[:space:]]+neutronos\.neutronprojects\.com([[:space:];]|$)' "$HTTPS_CONF"; then
 stop "The manager hostname already appears in the existing HTTPS config; review before proceeding"
fi
"$NGINX_BIN" -t -c "$HTTPS_CONF" || stop "Existing HTTPS config fails nginx -t BEFORE changes"
say "Validated existing HTTPS config: $HTTPS_CONF"

# This is not meant to turn on any high-risk permissions.
[[ ! -e "/etc/systemd/system/neutronos-manager.service" ]] || stop "Manager service already installed; review rather than overwrite"
[[ ! -e "$ROOT" ]] || stop "Manager install directory already exists; review rather than overwrite"
[[ ! -e "$CONF" ]] || stop "Manager configuration directory already exists; review rather than overwrite"
[[ ! -e "/etc/sudoers.d/neutron-manager" ]] || stop "Existing manager sudo permissions found; review before proceeding"
command -v visudo >/dev/null || stop "visudo is required for the restricted Docker-status permissions"
[[ -x /usr/bin/docker ]] || stop "Docker binary not at /usr/bin/docker"
[[ -x /usr/bin/sudo ]] || stop "sudo binary not at /usr/bin/sudo"
[[ -x /usr/sbin/dnsmasq ]] || stop "dnsmasq binary not at /usr/sbin/dnsmasq"

# Validate certificate and toolchain ahead of touching existing HTTPS or DNS.
openssl x509 -in "$CA_CERT" -noout -checkend 86400 >/dev/null || stop "TorrentLab CA certificate expired or nearly expired"
openssl pkey -in "$CA_KEY" -noout >/dev/null || stop "Existing CA signing key cannot be read (possibly passphrase-protected)"
command -v pip3 >/dev/null || say "Using venv-provided pip"
mkdir -p "$CONF"
chmod 700 "$CONF"
openssl req -new -newkey rsa:3072 -nodes -subj "/O=Neutron Projects/CN=$HOST" \
 -keyout "$KEY" -out "$CONF/server.csr"
cat > "$CONF/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$HOST
EOF
openssl x509 -req -in "$CONF/server.csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
 -out "$CERT" -days 365 -sha256 -extfile "$CONF/server.ext"
openssl verify -CAfile "$CA_CERT" "$CERT" || stop "New certificate cannot be verified against TorrentLab CA"
openssl x509 -in "$CERT" -noout -checkhost "$HOST" || stop "Certificate hostname mismatch"
cp "$CA_CERT" "$CLIENT_CA"
chmod 600 "$KEY"
chmod 644 "$CERT" "$CLIENT_CA"
PROXY_SECRET="$(openssl rand -hex 32)"
cat > "$CONF/environment" <<EOF
MANAGER_HOSTNAME=$HOST
MANAGER_PROXY_SECRET=$PROXY_SECRET
MANAGER_OS_VERSION=NeutronOS Gemini
MANAGER_USER_DATA_PATH=/NeutronOS/drneutron
MANAGER_FILES_HOME=/var/lib/neutron-manager
MANAGER_ENABLE_POWER=0
MANAGER_READ_ONLY=1
MANAGER_CONTAINER_JELLYFIN=jellyfin
MANAGER_CONTAINER_QBITTORRENT=qbittorrent
MANAGER_TOOL_TORRENTLAB=https://torrentlab.neutronprojects.com/torrentlab/
MANAGER_TOOL_NEUTRONAI=https://neutronai.neutronprojects.com/
EOF
chmod 600 "$CONF/environment"

if ! id neutron-manager >/dev/null 2>&1; then
 useradd --system --user-group --home-dir /var/lib/neutron-manager --create-home \
  --shell /usr/sbin/nologin neutron-manager
fi
install -d -m 0700 -o neutron-manager -g neutron-manager /var/lib/neutron-manager
install -d -m 0755 -o root -g root "$ROOT"
cp -a "$SOURCE/web" "$SOURCE/server" "$ROOT/"
chown -R root:root "$ROOT/web" "$ROOT/server"
python3 -m venv "$ROOT/.venv" || stop "Python venv failed; install python3-venv"
"$ROOT/.venv/bin/pip" -q install --disable-pip-version-check -r "$ROOT/server/requirements.txt"

cat > "/etc/systemd/system/neutronos-manager.service" <<EOF
[Unit]
Description=NeutronOS Manager (private mTLS/Tailscale)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=neutron-manager
Group=neutron-manager
WorkingDirectory=$ROOT
EnvironmentFile=$CONF/environment
ExecStart=$ROOT/.venv/bin/uvicorn server.app:app --host 127.0.0.1 --port 8877 --no-proxy-headers
Restart=on-failure
RestartSec=4
UMask=0077
NoNewPrivileges=false
PrivateTmp=true
PrivateDevices=true
ProtectHome=read-only
ProtectSystem=strict
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
ReadWritePaths=/var/lib/neutron-manager

[Install]
WantedBy=multi-user.target
EOF
# Only exact read-only docker inspect operations are authorized. No start/stop/restart
# or blanket Docker group access. Change this only after live security validation.
cat > /etc/sudoers.d/neutron-manager.docker-status <<'EOF'
Cmnd_Alias NEUTRON_DOCKER_STATUS = /usr/bin/docker inspect --format {{.State.Status}} jellyfin, /usr/bin/docker inspect --format {{.State.Status}} qbittorrent
neutron-manager ALL=(root) NOPASSWD: NEUTRON_DOCKER_STATUS
EOF
chmod 0440 /etc/sudoers.d/neutron-manager.docker-status
visudo -cf /etc/sudoers.d/neutron-manager.docker-status || stop "Restricted docker status sudoers validation failed"
systemctl daemon-reload
systemctl enable --now neutronos-manager.service
systemctl is-active --quiet neutronos-manager.service || stop "Manager backend did not start: journalctl -u neutronos-manager -n 40"

# New virtual host is inserted into the correct running HTTPS nginx instance,
# not into NeutronAI's port-80 nginx. Client certificate and secret required.
cat > "$SITE" <<EOF
server {
 listen $IP:443 ssl;
 server_name $HOST;
 ssl_certificate $CERT;
 ssl_certificate_key $KEY;
 ssl_client_certificate $CLIENT_CA;
 ssl_verify_client on;
 ssl_verify_depth 2;
 ssl_protocols TLSv1.2 TLSv1.3;
 allow 100.64.0.0/10;
 deny all;
 client_max_body_size 128m;
 server_tokens off;

 location / {
  proxy_pass http://127.0.0.1:8877;
  proxy_http_version 1.1;
  proxy_set_header Host $HOST;
  proxy_set_header X-Neutron-Client-Verified \$ssl_client_verify;
  proxy_set_header X-Neutron-Proxy-Secret $PROXY_SECRET;
  proxy_set_header X-Forwarded-Proto https;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_read_timeout 3600s;
  proxy_buffering off;
 }
}
EOF
BACKUP="$CONF/original-https-nginx.conf"
cp -a "$HTTPS_CONF" "$BACKUP"
python3 - "$HTTPS_CONF" "$SITE" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]);inc='include '+sys.argv[2]+';';s=p.read_text()
if inc in s: raise SystemExit('vhost already included')
m=re.search(r'(?m)^[ \t]*http[ \t]*\{',s)
if not m: raise SystemExit('no http block')
p.write_text(s[:m.end()]+'\n  '+inc+'\n'+s[m.end():])
PY
if ! "$NGINX_BIN" -t -c "$HTTPS_CONF"; then
 cp -a "$BACKUP" "$HTTPS_CONF"
 stop "New Nginx vhost rejected, ORIGINAL HTTPS CONFIG RESTORED"
fi
if ! "$NGINX_BIN" -s reload -c "$HTTPS_CONF"; then
 cp -a "$BACKUP" "$HTTPS_CONF"
 "$NGINX_BIN" -s reload -c "$HTTPS_CONF" || true
 stop "HTTPS Nginx reload failed, original config restored"
fi

# mTLS must DENY an unauthenticated request before we modify DNS.
sleep 1
NO_CERT_STATUS="$(curl -skS --noproxy '*' --resolve "$HOST:443:$IP" --connect-timeout 3 --max-time 8 \
 -o /dev/null -w '%{http_code}' "https://$HOST/" || true)"
if [[ "$NO_CERT_STATUS" != 400 && "$NO_CERT_STATUS" != 403 && "$NO_CERT_STATUS" != 495 && "$NO_CERT_STATUS" != 496 ]]; then
 cp -a "$BACKUP" "$HTTPS_CONF"
 "$NGINX_BIN" -s reload -c "$HTTPS_CONF" || true
 stop "mTLS rejection test failed (status $NO_CERT_STATUS); existing HTTPS config restored"
fi

# Test the new route with the original iPhone client certificate held on Gemini.
IPHONE_CRT="$CA/issued/iphone15-client.crt.pem"
IPHONE_KEY="$CA/issued/iphone15-client.key.pem"
if [[ -r "$IPHONE_CRT" && -r "$IPHONE_KEY" ]]; then
 # Check the ACTUAL Manager API, not merely an unrelated 200 OK page
 # from an existing default virtual host. Do not print the session CSRF response.
 API_RESPONSE="$(curl -fsS --noproxy '*' --cacert "$CA_CERT" --cert "$IPHONE_CRT" --key "$IPHONE_KEY" \
  --resolve "$HOST:443:$IP" --connect-timeout 3 --max-time 9 \
  "https://$HOST/api/session" || true)"
 if ! printf '%s' "$API_RESPONSE" | python3 -c 'import json,sys; data=json.load(sys.stdin); assert isinstance(data.get("csrf"),str) and len(data["csrf"])>20 and data.get("idle_timeout_seconds")==1800' 2>/dev/null; then
   cp -a "$BACKUP" "$HTTPS_CONF"
   "$NGINX_BIN" -s reload -c "$HTTPS_CONF" || true
   stop "Valid certificate did not reach the Manager API; existing HTTPS config restored"
 fi
 unset API_RESPONSE
else
 say "No local iPhone test key present; server-side mTLS rejection was verified"
fi

# Add a record to the EXISTING TorrentLab private DNS, preserving all prior names.
DNS_BACKUP="$CONF/original-private-dns.conf"
cp -a "$DNS" "$DNS_BACKUP"
if ! grep -Fq "host-record=$HOST," "$DNS"; then
 printf '\n# NeutronOS Manager (Tailscale only)\nhost-record=%s,%s\nlocal=/%s/\n' \
  "$HOST" "$IP" "$HOST" >> "$DNS"
fi
if ! /usr/sbin/dnsmasq --test --conf-file="$DNS" >/dev/null 2>&1; then
 cp -a "$DNS_BACKUP" "$DNS"
 stop "DNS syntax check failed, original DNS restored"
fi
if ! systemctl restart "$DNS_UNIT"; then
 cp -a "$DNS_BACKUP" "$DNS"
 systemctl restart "$DNS_UNIT" || true
 stop "Private DNS failed, original DNS restored"
fi

say "Installed: HTTPS $HOST, mTLS signed by existing TorrentLab CA, backend at loopback:8877"
say "Existing TorrentLab and NeutronAI HTTP configurations were left intact."
say "REMOTE POWER, SERVICE MODIFICATIONS, FILE UPLOADS AND TERMINAL REMAIN LOCKED."
say "If iPhone doesn't resolve domain, add restricted Tailscale DNS nameserver $IP for $HOST at https://login.tailscale.com/admin/dns"
say "On iPhone: connect Tailscale, open https://$HOST in Safari with installed client identity."
