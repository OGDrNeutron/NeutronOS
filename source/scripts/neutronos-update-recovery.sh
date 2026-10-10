#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ${EUID} -eq 0 ]]; then
    # Root actions are pinned to the authoritative live tree; never accept a
    # caller-controlled root path at this trust boundary.
    ROOT="/opt/neutronos"
else
    ROOT="${NEUTRONOS_ROOT:-/opt/neutronos}"
fi
ROOT="$(readlink -f "$ROOT")"
STATE="$ROOT/state/update-recovery"
RECOVERY="$ROOT/backups/recovery"
LOG="$STATE/helper.log"
LOCK="/var/lock/neutronos-update-recovery.lock"
ACTION="${1:-}"
shift || true
SERVICE_STOPPED=0
TMP_DIRS=()

mkdir -p "$STATE" "$RECOVERY" "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || { echo "Another update or recovery operation is active." >&2; exit 73; }
exec >>"$LOG" 2>&1
printf '\n[%s] action=%s root=%s\n' "$(date --iso-8601=seconds)" "$ACTION" "$ROOT"

cleanup() {
    local path
    if [[ "$SERVICE_STOPPED" == "1" ]]; then
        systemctl start neutronos.service >/dev/null 2>&1 || true
    fi
    for path in "${TMP_DIRS[@]:-}"; do
        [[ -n "$path" ]] && rm -rf -- "$path"
    done
}
trap cleanup EXIT

safe_label() {
    printf '%s' "${1:-manual}" | tr -cs 'A-Za-z0-9._-' '_' | cut -c1-48
}

copy_release_source() {
    local destination="$1"
    mkdir -p "$destination"
    local items=(CMakeLists.txt src qml config systemd scripts themes)
    [[ -d "$ROOT/services" ]] && items+=(services)
    tar -C "$ROOT" -cf - \
        --exclude='qml/apps/games/roms' \
        --exclude='qml/apps/games/cards' \
        --exclude='scripts/__pycache__' \
        "${items[@]}" | tar -C "$destination" -xf -
}

archive_current() {
    local label stamp archive stage
    label="$(safe_label "${1:-recovery}")"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    stage="$(mktemp -d /tmp/neutronos-recovery-source-XXXXXX)"
    TMP_DIRS+=("$stage")
    copy_release_source "$stage/source"
    if command -v zstd >/dev/null 2>&1; then
        archive="$RECOVERY/${stamp}-${label}.tar.zst"
        tar --zstd -cf "$archive" -C "$stage/source" .
    else
        archive="$RECOVERY/${stamp}-${label}.tar.gz"
        tar -zcf "$archive" -C "$stage/source" .
    fi
    sha256sum "$archive" > "$archive.sha256"
    printf '%s\n' "$archive"
}

clean_build() {
    local source="$1" build="$2"
    rm -rf "$build"
    cmake -S "$source" -B "$build" \
        -DNEUTRONOS_RUNTIME_ROOT="$ROOT" \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build" -j2
    [[ -x "$build/NeutronShell" ]]
    chmod +x "$build/NeutronShell"
}


verify_signed_update() {
    local package="$1" envelope="$2" expected_version="$3"
    [[ -f "$package" ]] || { echo "Update package not found." >&2; return 66; }
    [[ -f "$envelope" ]] || { echo "Signed update manifest not found." >&2; return 66; }
    [[ -f /etc/neutronos/keys/neutronos-release.gpg ]] || {
        echo "Trusted update key /etc/neutronos/keys/neutronos-release.gpg is not installed." >&2
        return 77
    }
    /usr/bin/python3 - "$package" "$envelope" "$expected_version" /etc/neutronos/keys/neutronos-release.gpg <<'PYVERIFY'
import base64, binascii, ctypes, ctypes.util, hashlib, hmac, json, os, platform, re, sys
package_path, envelope_path, expected_version, key_path = sys.argv[1:]

def fail(message, code=65):
    print(message, file=sys.stderr)
    raise SystemExit(code)

try:
    raw_envelope = open(envelope_path, 'rb').read(1024 * 1024 + 1)
except OSError as exc:
    fail(f"Could not read signed update manifest: {exc}", 66)
if len(raw_envelope) > 1024 * 1024:
    fail("Signed update manifest exceeded the 1 MiB safety limit.")
try:
    envelope = json.loads(raw_envelope)
except Exception as exc:
    fail(f"Signed update manifest is invalid JSON: {exc}")
if not isinstance(envelope, dict) or envelope.get('format') != 'neutronos.update-manifest.v2':
    fail('Unsupported or unsigned update manifest format.')
try:
    signed_payload = base64.b64decode(str(envelope.get('signedPayload', '')), validate=True)
    signature = base64.b64decode(str(envelope.get('signature', '')), validate=True)
except (ValueError, binascii.Error):
    fail('Signed update manifest contains invalid base64.')
if not signature or len(signature) > 16384 or not signed_payload:
    fail('Signed update manifest signature is malformed.')
import subprocess,tempfile
with tempfile.TemporaryDirectory(prefix='neutronos-release-boundary-') as folder:
    meta=os.path.join(folder,'manifest');sig=os.path.join(folder,'signature')
    open(meta,'wb').write(signed_payload);open(sig,'wb').write(signature)
    result=subprocess.run(['/usr/local/libexec/neutronos-release-verify','verify',meta,sig],capture_output=True,text=True,timeout=35)
if result.returncode:
    fail(result.stderr.strip()[:600] or 'The release signature is not trusted.',77)
try:
    manifest = json.loads(signed_payload)
except Exception as exc:
    fail(f"The signed release payload is invalid: {exc}")
if not isinstance(manifest, dict):
    fail('The signed release payload is not an object.')
if manifest.get('product') != 'NeutronOS' or manifest.get('codename', 'Gemini') != 'Gemini':
    fail('The signed release does not target NeutronOS Gemini.')
version = str(manifest.get('version') or '').strip()
if not version or not hmac.compare_digest(version, expected_version):
    fail('The signed release version does not match the requested deployment.')
if int(manifest.get('updateFormatVersion') or 0) != 2:
    fail('Unsupported signed update format version.')
arch = str(manifest.get('architecture') or '').strip().lower()
current = platform.machine().lower()
if current in ('x86_64', 'amd64'):
    current = 'amd64'
if arch != current:
    fail(f'The signed release architecture {arch!r} does not match {current!r}.')
artifact = manifest.get('artifact')
if not isinstance(artifact, dict):
    fail('The signed release artifact metadata is missing.')
expected_sha = str(artifact.get('sha256') or '').strip().lower()
if not re.fullmatch(r'[0-9a-f]{64}', expected_sha):
    fail('The signed release SHA-256 is malformed.')
size = artifact.get('size')
try:
    if size not in (None, '') and int(size) > 0 and os.path.getsize(package_path) != int(size):
        fail('The update package size does not match signed metadata.')
except (OSError, ValueError, TypeError):
    fail('The signed update size metadata is invalid.')
h = hashlib.sha256()
try:
    with open(package_path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
except OSError as exc:
    fail(f'Could not hash update package: {exc}', 66)
if not hmac.compare_digest(h.hexdigest(), expected_sha):
    fail('Update checksum verification failed against the signed release manifest.', 77)
print(expected_sha)
PYVERIFY
}

validate_archive_paths() {
    local package="$1"
    local entry
    while IFS= read -r entry; do
        [[ "$entry" != /* ]] || { echo "Unsafe absolute archive path: $entry" >&2; exit 65; }
        [[ "$entry" != ".." && "$entry" != ../* && "$entry" != */../* && "$entry" != */.. ]] || {
            echo "Unsafe traversal archive path: $entry" >&2
            exit 65
        }
    done < <(tar -tf "$package")
}

install_source_and_build() {
    local source="$1" build="$2"
    systemctl stop neutronos.service
    SERVICE_STOPPED=1
    rsync -a --delete \
        --exclude='state/' \
        --exclude='backups/' \
        --exclude='build/' \
        --exclude='qml/apps/games/roms/' \
        --exclude='qml/apps/games/cards/' \
        "$source/" "$ROOT/"
    rm -rf "$ROOT/build"
    cp -a "$build" "$ROOT/build"
    chmod +x "$ROOT/build/NeutronShell"
    systemctl start neutronos.service
    SERVICE_STOPPED=0
}

case "$ACTION" in
    stage-update)
        PACKAGE="${1:?Update package is required}"
        MANIFEST="${2:?Signed release manifest is required}"
        RAW_VERSION="${3:?Version is required}"
        VERSION="$(safe_label "$RAW_VERSION")"
        [[ "$VERSION" == "$RAW_VERSION" ]] || { echo "Unsafe update version label." >&2; exit 65; }
        verify_signed_update "$PACKAGE" "$MANIFEST" "$RAW_VERSION" >/dev/null
        validate_archive_paths "$PACKAGE"
        DEPLOYMENTS="$STATE/deployments"
        mkdir -p "$DEPLOYMENTS"
        CANDIDATE="$DEPLOYMENTS/$VERSION"
        [[ ! -e "$CANDIDATE" ]] || { echo "Candidate deployment already exists: $VERSION" >&2; exit 73; }
        STAGE="$(mktemp -d "$DEPLOYMENTS/.candidate-$VERSION-XXXXXX")"
        TMP_DIRS+=("$STAGE")
        mkdir -p "$STAGE/package" "$STAGE/source"
        tar -xf "$PACKAGE" -C "$STAGE/package"
        [[ -f "$STAGE/package/manifest.json" && -d "$STAGE/package/payload" ]] || {
            echo "Invalid .nosupdate package: manifest.json and payload/ are required." >&2
            exit 65
        }
        copy_release_source "$STAGE/source"
        rsync -a "$STAGE/package/payload/" "$STAGE/source/"
        clean_build "$STAGE/source" "$STAGE/build"
        mv "$STAGE" "$CANDIDATE"
        TMP_DIRS=()
        /usr/bin/python3 - "$STATE/deployment-state.json" "$VERSION" "$CANDIDATE" <<'PY'
import json, os, sys, tempfile
path, version, candidate = sys.argv[1:]
try:
    state = json.load(open(path))
except Exception:
    state = {"schemaVersion": 1, "CURRENT": "workspace", "PREVIOUS_KNOWN_GOOD": ""}
state.update({"CANDIDATE": candidate, "candidateVersion": version,
              "status": "STAGED", "validation": "PENDING"})
os.makedirs(os.path.dirname(path), exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".deployment-state.")
with os.fdopen(fd, "w") as handle:
    json.dump(state, handle, indent=2, sort_keys=True); handle.write("\n")
os.replace(tmp, path)
PY
        echo "Candidate staged at $CANDIDATE"
        ;;

    prepare-rollback)
        ARCHIVE="${1:?Recovery archive is required}"
        [[ -f "$ARCHIVE" ]] || { echo "Recovery archive not found." >&2; exit 66; }
        [[ ! -f "$ARCHIVE.sha256" ]] || (cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE.sha256")")
        validate_archive_paths "$ARCHIVE"
        printf '{"schemaVersion":1,"status":"ROLLBACK_REQUESTED","archive":"%s"}\n' "$ARCHIVE" > "$STATE/rollback-request.json"
        echo "Rollback request prepared; no live files were replaced."
        ;;

    create-recovery)
        archive_current "${1:-manual}"
        ;;

    repair)
        archive_current "pre-repair"
        STAGE="$(mktemp -d /tmp/neutronos-repair-XXXXXX)"
        TMP_DIRS+=("$STAGE")
        copy_release_source "$STAGE/source"
        clean_build "$STAGE/source" "$STAGE/build"
        install_source_and_build "$STAGE/source" "$STAGE/build"
        ;;

    rollback)
        ARCHIVE="${1:?Recovery archive is required}"
        [[ -f "$ARCHIVE" ]] || { echo "Recovery archive not found." >&2; exit 66; }
        if [[ -f "$ARCHIVE.sha256" ]]; then
            (cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE.sha256")")
        fi
        validate_archive_paths "$ARCHIVE"
        STAGE="$(mktemp -d /tmp/neutronos-rollback-XXXXXX)"
        TMP_DIRS+=("$STAGE")
        mkdir -p "$STAGE/source"
        tar -xf "$ARCHIVE" -C "$STAGE/source"
        clean_build "$STAGE/source" "$STAGE/build"
        install_source_and_build "$STAGE/source" "$STAGE/build"
        ;;

    install-update)
        [[ "${NEUTRONOS_ALLOW_LIVE_UPDATE:-0}" == 1 ]] || {
            echo "Live in-place update denied: atomic deployment backend is unavailable." >&2
            exit 77
        }
        PACKAGE="${1:?Update package is required}"
        MANIFEST="${2:?Signed release manifest is required}"
        VERSION="${3:-unknown}"
        verify_signed_update "$PACKAGE" "$MANIFEST" "$VERSION" >/dev/null
        validate_archive_paths "$PACKAGE"
        RECOVERY_POINT="$(archive_current "pre-update-$VERSION")"
        echo "Recovery point: $RECOVERY_POINT"
        STAGE="$(mktemp -d /tmp/neutronos-update-XXXXXX)"
        TMP_DIRS+=("$STAGE")
        mkdir -p "$STAGE/package"
        tar -xf "$PACKAGE" -C "$STAGE/package"
        [[ -f "$STAGE/package/manifest.json" && -d "$STAGE/package/payload" ]] || {
            echo "Invalid .nosupdate package: manifest.json and payload/ are required." >&2
            exit 65
        }
        copy_release_source "$STAGE/source"
        rsync -a "$STAGE/package/payload/" "$STAGE/source/"
        if [[ -f "$STAGE/package/remove.list" ]]; then
            while IFS= read -r relative; do
                [[ -z "$relative" || "$relative" == \#* ]] && continue
                [[ "$relative" != /* && "$relative" != ".." && "$relative" != ../* && "$relative" != */../* && "$relative" != */.. ]] || {
                    echo "Unsafe remove path: $relative" >&2
                    exit 65
                }
                rm -rf -- "$STAGE/source/$relative"
            done < "$STAGE/package/remove.list"
        fi
        clean_build "$STAGE/source" "$STAGE/build"
        install_source_and_build "$STAGE/source" "$STAGE/build"
        ;;

    debian-upgrade)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get -y upgrade
        ;;

    *)
        echo "Usage: $0 {stage-update|prepare-rollback|create-recovery|repair|rollback|install-update|debian-upgrade}" >&2
        exit 64
        ;;
esac
