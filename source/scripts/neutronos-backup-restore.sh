#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${NEUTRONOS_ROOT:-$HOME/NeutronOS}"
[[ -d "$ROOT" ]] || ROOT="/opt/neutronos"
STATE="$ROOT/state/backup-restore"
DEFAULT_DEST="$ROOT/backups/system"
LOG="$STATE/helper.log"
STATUS_FILE="$STATE/last-system-operation.json"
LOCK="/var/lock/neutronos-backup-restore.lock"
[[ -w "$(dirname "$LOCK")" ]] || LOCK="$STATE/backup-restore.lock"
ACTION="${1:-}"
shift || true

mkdir -p "$STATE" "$DEFAULT_DEST" "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || { echo "Another backup, restore, wipe, or reinstall operation is active." >&2; exit 73; }
exec >> >(tee -a "$LOG") 2>&1
printf '\n[%s] action=%s\n' "$(date --iso-8601=seconds)" "$ACTION"

TRACK_STATUS=1
[[ "$ACTION" == "create-backup" || "$ACTION" == "verify-backup" ]] && TRACK_STATUS=0
STATUS_FINALIZED=0
TEMP_STAGE=""

write_status() {
    [[ "$TRACK_STATUS" == "1" ]] || return 0
    local state="$1" message="$2"
    python3 - "$STATUS_FILE" "$ACTION" "$state" "$message" "$LOG" <<'PY2'
import json, os, sys
from datetime import datetime, timezone
path, action, state, message, log_path = sys.argv[1:]
payload = {
    "action": action,
    "state": state,
    "message": message,
    "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
    "log": log_path,
}
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
os.replace(tmp, path)
PY2
}

on_exit() {
    local code=$?
    [[ -z "$TEMP_STAGE" || ! -d "$TEMP_STAGE" ]] || rm -rf "$TEMP_STAGE"
    if [[ "$TRACK_STATUS" == "1" && "$STATUS_FINALIZED" == "0" ]]; then
        write_status "failed" "${ACTION:-Backup/restore operation} failed with exit code $code. Open Logs for details."
    fi
    exit "$code"
}
trap on_exit EXIT

safe_label() {
    printf '%s' "${1:-manual}" | tr -cs 'A-Za-z0-9._-' '_' | cut -c1-40
}

validate_archive_paths() {
    local archive="$1" bad
    bad="$(tar -tf "$archive" | awk 'BEGIN{bad=0} /^\//{print;bad=1} /(^|\/)\.\.($|\/)/{print;bad=1} END{exit bad}')" || {
        echo "Unsafe path in backup/package: $bad" >&2
        exit 65
    }
}

verify_archive() {
    local archive="$1"
    [[ -f "$archive" ]] || { echo "Backup archive was not found." >&2; exit 66; }
    [[ -f "$archive.sha256" ]] || { echo "Backup checksum sidecar is missing." >&2; exit 65; }
    (cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive.sha256")")
    validate_archive_paths "$archive"
    local listing
    listing="$(tar -tf "$archive")"
    grep -qx 'manifest.json' <<<"$listing" || { echo "Backup manifest is missing." >&2; exit 65; }
    grep -qx 'payload.sha256' <<<"$listing" || { echo "Backup payload integrity manifest is missing." >&2; exit 65; }
    grep -q '^payload/' <<<"$listing" || { echo "Backup payload is missing." >&2; exit 65; }
    local verify_stage
    verify_stage="$(mktemp -d /tmp/neutronos-backup-verify-XXXXXX)"
    tar -xf "$archive" -C "$verify_stage" manifest.json payload.sha256 payload
    python3 - "$verify_stage/manifest.json" <<'PY2'
import json, sys
manifest=json.load(open(sys.argv[1], encoding="utf-8"))
if manifest.get("product") != "NeutronOS" or manifest.get("codename") != "Gemini":
    raise SystemExit("Backup product/codename compatibility check failed.")
if manifest.get("format") != "NeutronOS Backup v2":
    raise SystemExit("Unsupported backup format.")
PY2
    (cd "$verify_stage" && sha256sum -c payload.sha256)
    rm -rf "$verify_stage"
}

copy_if_exists() {
    local source="$1" target="$2"
    [[ -e "$source" ]] || return 0
    if [[ -d "$source" ]]; then
        mkdir -p "$target"
        rsync -a "$source/" "$target/"
    else
        mkdir -p "$(dirname "$target")"
        cp -a "$source" "$target"
    fi
}

stage_profile() {
    local profile="$1" include_roms="$2" stage="$3"
    mkdir -p "$stage/payload/root" "$stage/payload/external"
    case "$profile" in
        full)
            for item in CMakeLists.txt src qml config scripts systemd themes services; do
                [[ -e "$ROOT/$item" ]] && rsync -a "$ROOT/$item" "$stage/payload/root/"
            done
            local state_source="$ROOT/state"
            if [[ -L "$ROOT/state" ]]; then
                state_source="${NEUTRONOS_BACKUP_STATE_ROOT:-/var/lib/neutronos}"
                [[ "$(readlink -f -- "$ROOT/state")" == "$(readlink -f -- "$state_source")" ]] || {
                    echo "NeutronOS state link does not match the trusted state location." >&2
                    exit 65
                }
            fi
            [[ -d "$state_source" ]] && rsync -a \
                --exclude='update-recovery/downloads/' \
                --exclude='backup-restore/' \
                --exclude='apps/mediaoptimizer/cache/' \
                --exclude='security/' \
                --exclude='terminal/' \
                --exclude='remote/' \
                "$state_source/" "$stage/payload/root/state/"
            ;;
        settings)
            copy_if_exists "$ROOT/config" "$stage/payload/root/config"
            copy_if_exists "$ROOT/themes/Default/users" "$stage/payload/root/themes/Default/users"
            copy_if_exists "$ROOT/state/settings" "$stage/payload/root/state/settings"
            copy_if_exists "$ROOT/state/screensaver" "$stage/payload/root/state/screensaver"
            ;;
        apps)
            copy_if_exists "$ROOT/config/apps" "$stage/payload/root/config/apps"
            copy_if_exists "$ROOT/state/apps" "$stage/payload/root/state/apps"
            copy_if_exists "$ROOT/services" "$stage/payload/root/services"
            ;;
        personal)
            copy_if_exists "$ROOT/themes/Default/users" "$stage/payload/root/themes/Default/users"
            copy_if_exists "$ROOT/state/user" "$stage/payload/root/state/user"
            copy_if_exists "$ROOT/qml/apps/games/cards" "$stage/payload/root/qml/apps/games/cards"
            ;;
        *) echo "Unsupported backup profile: $profile" >&2; exit 64 ;;
    esac
    if [[ "$include_roms" == "1" && -d "$ROOT/qml/apps/games/roms" ]]; then
        copy_if_exists "$ROOT/qml/apps/games/roms" "$stage/payload/root/qml/apps/games/roms"
    fi
    # Restore payloads are data-only. Trusted NeutronOS links, including the
    # state link, are recreated or verified by Recovery rather than archives.
    find "$stage/payload" -type l -delete
    # Unified Security Core credentials, recovery material, vault data, and
    # runtime secrets are never placed in an unencrypted backup. The safe,
    # declarative security defaults under config/ remain exportable.
}

clean_build() {
    local source="$1" build="$2"
    rm -rf "$build"
    cmake -S "$source" -B "$build" -DNEUTRONOS_RUNTIME_ROOT="$ROOT" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$build" -j1
    [[ -x "$build/NeutronShell" ]] || { echo "Clean build did not produce NeutronShell." >&2; exit 70; }
    chmod +x "$build/NeutronShell"
}

best_effort_secure_remove() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    if command -v shred >/dev/null 2>&1; then
        find "$path" -xdev -type f -size -64M -print0 2>/dev/null | xargs -0 -r shred -u -n 1 -z -- 2>/dev/null || true
    fi
    rm -rf -- "$path"
}

write_status "running" "${ACTION:-Backup/restore operation} started."
RESULT_MESSAGE="Operation completed."

case "$ACTION" in
    create-backup)
        PROFILE="${1:-full}"
        INCLUDE_ROMS="${2:-0}"
        LABEL="$(safe_label "${3:-manual}")"
        DEST="${4:-$DEFAULT_DEST}"
        [[ "$DEST" == /* && "$DEST" != "/" ]] || { echo "Unsafe backup destination." >&2; exit 64; }
        mkdir -p "$DEST"
        STAGE="$(mktemp -d /tmp/neutronos-backup-XXXXXX)"
        TEMP_STAGE="$STAGE"
        echo "PROGRESS:5:Preparing $PROFILE backup"
        stage_profile "$PROFILE" "$INCLUDE_ROMS" "$STAGE"
        (cd "$STAGE" && find payload -type f -print0 | sort -z | xargs -0 -r sha256sum > payload.sha256)
        python3 - "$STAGE/manifest.json" "$PROFILE" "$INCLUDE_ROMS" "$ROOT/config/version.json" <<'PY2'
import json, os, socket, sys
from datetime import datetime, timezone
path, profile, include_roms, version_path = sys.argv[1:]
try:
    release = json.load(open(version_path, encoding="utf-8"))
except Exception:
    release = {}
payload = {
    "format": "NeutronOS Backup v2",
    "product": "NeutronOS",
    "codename": "Gemini",
    "neutronOSVersion": release.get("version", "Unknown"),
    "releaseId": release.get("releaseId", "Unknown"),
    "profile": profile,
    "includeRoms": include_roms == "1",
    "includedComponents": ["settings", "profiles", "dashboard-layouts", "app-configuration"] if profile == "full" else [profile],
    "integrityManifest": "payload.sha256",
    "secretsPolicy": "privileged-runtime-secrets-excluded",
    "created": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    "hostname": socket.gethostname(),
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY2
        echo "PROGRESS:55:Compressing backup"
        STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
        if command -v zstd >/dev/null 2>&1; then
            ARCHIVE="$DEST/${STAMP}-${PROFILE}-backup.tar.zst"
            tar --zstd -cf "$ARCHIVE" -C "$STAGE" manifest.json payload.sha256 payload
        else
            ARCHIVE="$DEST/${STAMP}-${PROFILE}-backup.tar.gz"
            tar -zcf "$ARCHIVE" -C "$STAGE" manifest.json payload.sha256 payload
        fi
        echo "PROGRESS:90:Writing checksum"
        (cd "$DEST" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
        echo "PROGRESS:100:$(basename "$ARCHIVE")"
        echo "Backup created: $ARCHIVE"
        rm -rf "$STAGE"; TEMP_STAGE=""
        ;;

    verify-backup)
        ARCHIVE="${1:?Backup archive is required}"
        echo "PROGRESS:10:Checking archive and checksum"
        verify_archive "$ARCHIVE"
        echo "PROGRESS:100:$(basename "$ARCHIVE") verified"
        echo "Backup verified: $ARCHIVE"
        ;;

    restore-backup)
        [[ "${NEUTRONOS_ALLOW_LIVE_RESTORE:-0}" == 1 ]] || { echo "Live restore denied during development; validation/inspection only." >&2; exit 77; }
        ARCHIVE="${1:?Backup archive is required}"
        verify_archive "$ARCHIVE"
        STAGE="$(mktemp -d /tmp/neutronos-restore-XXXXXX)"
        TEMP_STAGE="$STAGE"
        tar -xf "$ARCHIVE" -C "$STAGE"
        PROFILE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["profile"])' "$STAGE/manifest.json")"
        systemctl stop neutronos.service
        if [[ -d "$STAGE/payload/root" ]]; then
            rsync -a "$STAGE/payload/root/" "$ROOT/"
        fi
        if [[ "$PROFILE" == "full" ]]; then
            clean_build "$ROOT" "$STAGE/build"
            rm -rf "$ROOT/build"
            cp -a "$STAGE/build" "$ROOT/build"
        fi
        sync
        systemctl start neutronos.service
        RESULT_MESSAGE="Backup $(basename "$ARCHIVE") restored successfully."
        rm -rf "$STAGE"; TEMP_STAGE=""
        ;;

    wipe-user-data)
        [[ "${NEUTRONOS_ALLOW_LIVE_RESTORE:-0}" == 1 ]] || { echo "Live reset denied during development." >&2; exit 77; }
        CONFIRM="${1:-}"
        INCLUDE_ROMS="${2:-0}"
        [[ "$CONFIRM" == "WIPE MY NEUTRONOS DATA" ]] || { echo "Confirmation phrase mismatch." >&2; exit 64; }
        KEEP="$(mktemp -d /tmp/neutronos-wipe-keep-XXXXXX)"
        TEMP_STAGE="$KEEP"
        for file in version.json release-manifest.sha256 update-public-key; do
            [[ -f "$ROOT/config/$file" ]] && cp -a "$ROOT/config/$file" "$KEEP/$file"
        done
        if [[ "$INCLUDE_ROMS" != "1" && -d "$ROOT/qml/apps/games/roms" ]]; then
            mkdir -p "$KEEP/roms"
            rsync -a "$ROOT/qml/apps/games/roms/" "$KEEP/roms/"
        fi
        systemctl stop neutronos.service
        best_effort_secure_remove "$ROOT/state"
        best_effort_secure_remove "$ROOT/config"
        best_effort_secure_remove "$ROOT/backups"
        best_effort_secure_remove "$ROOT/themes/Default/users"
        best_effort_secure_remove /var/lib/neutronos/security
        mkdir -p "$ROOT/state" "$ROOT/config" "$ROOT/backups" "$ROOT/themes/Default/users" /var/lib/neutronos/security
        for file in version.json release-manifest.sha256 update-public-key; do
            [[ -f "$KEEP/$file" ]] && cp -a "$KEEP/$file" "$ROOT/config/$file"
        done
        if [[ "$INCLUDE_ROMS" != "1" && -d "$KEEP/roms" ]]; then
            mkdir -p "$ROOT/qml/apps/games/roms"
            rsync -a "$KEEP/roms/" "$ROOT/qml/apps/games/roms/"
        fi
        sync
        systemctl start neutronos.service
        RESULT_MESSAGE="NeutronOS user data was reset. Flash storage wear-leveling means forensic erasure cannot be guaranteed without an offline full-device reimage."
        rm -rf "$KEEP"; TEMP_STAGE=""
        ;;

    clean-reinstall)
        [[ "${NEUTRONOS_ALLOW_LIVE_RESTORE:-0}" == 1 ]] || { echo "Live reinstall denied during development." >&2; exit 77; }
        PACKAGE="${1:?Verified full-install package is required}"
        EXPECTED="${2:?Expected package SHA-256 is required}"
        PRESERVE="${3:-1}"
        CONFIRM="${4:-}"
        [[ "$CONFIRM" == "REINSTALL NEUTRONOS GEMINI" ]] || { echo "Confirmation phrase mismatch." >&2; exit 64; }
        [[ -f "$PACKAGE" ]] || { echo "Reinstall package not found." >&2; exit 66; }
        printf '%s  %s\n' "$EXPECTED" "$PACKAGE" | sha256sum -c -
        validate_archive_paths "$PACKAGE"
        STAGE="$(mktemp -d /tmp/neutronos-clean-reinstall-XXXXXX)"
        TEMP_STAGE="$STAGE"
        mkdir -p "$STAGE/package" "$STAGE/source" "$STAGE/preserve"
        tar -xf "$PACKAGE" -C "$STAGE/package"
        [[ -f "$STAGE/package/manifest.json" && -d "$STAGE/package/payload" ]] || { echo "Invalid NeutronOS update package." >&2; exit 65; }
        python3 - "$STAGE/package/manifest.json" <<'PY2'
import json, sys
obj=json.load(open(sys.argv[1], encoding='utf-8'))
if obj.get('product') != 'NeutronOS' or obj.get('edition') != 'Gemini' or obj.get('fullInstall') is not True or str(obj.get('architecture', '')).lower() not in ('amd64', 'x86_64'):
    raise SystemExit('Clean reinstall requires an Gemini package with fullInstall=true.')
PY2
        rsync -a "$STAGE/package/payload/" "$STAGE/source/"
        [[ -f "$STAGE/source/CMakeLists.txt" && -f "$STAGE/source/src/main.cpp" && -f "$STAGE/source/qml/Main.qml" ]] || {
            echo "Full-install package does not contain a complete NeutronOS source tree." >&2; exit 65;
        }
        if [[ "$PRESERVE" == "1" ]]; then
            for item in state backups qml/apps/games/roms qml/apps/games/cards themes/Default/users; do
                [[ -e "$ROOT/$item" ]] || continue
                mkdir -p "$STAGE/preserve/$(dirname "$item")"
                rsync -a "$ROOT/$item" "$STAGE/preserve/$item"
            done
            [[ -d /var/lib/neutronos/security ]] && rsync -a /var/lib/neutronos/security "$STAGE/preserve/var-lib-neutronos-security"
        fi
        clean_build "$STAGE/source" "$STAGE/build"
        systemctl stop neutronos.service
        for item in src qml scripts systemd themes services config CMakeLists.txt; do
            rm -rf "$ROOT/$item"
        done
        rsync -a "$STAGE/source/" "$ROOT/"
        rm -rf "$ROOT/build"
        cp -a "$STAGE/build" "$ROOT/build"
        if [[ "$PRESERVE" == "1" ]]; then
            rsync -a "$STAGE/preserve/" "$ROOT/"
            if [[ -d "$ROOT/var-lib-neutronos-security" ]]; then
                rm -rf /var/lib/neutronos/security
                mkdir -p /var/lib/neutronos
                mv "$ROOT/var-lib-neutronos-security" /var/lib/neutronos/security
            fi
        else
            best_effort_secure_remove /var/lib/neutronos/security
            mkdir -p /var/lib/neutronos/security
        fi
        sync
        systemctl start neutronos.service
        RESULT_MESSAGE="NeutronOS Gemini was cleanly reinstalled from the verified full-install package."
        rm -rf "$STAGE"; TEMP_STAGE=""
        ;;

    *)
        echo "Usage: $0 {create-backup|verify-backup|restore-backup|wipe-user-data|clean-reinstall}" >&2
        exit 64
        ;;
esac

if [[ "$TRACK_STATUS" == "1" ]]; then
    write_status "success" "$RESULT_MESSAGE"
    STATUS_FINALIZED=1
fi
