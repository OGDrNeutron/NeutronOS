#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Host-side privileged builder. It never operates on the live NeutronOS root.
PROJECT="$(readlink -f "$(dirname -- "${BASH_SOURCE[0]}")/..")"
RELEASE_WORK_ROOT="${NEUTRONOS_RELEASE_WORK_ROOT:-/home/echo/neutronos-release-work}"
RELEASE_OUTPUT_ROOT="${NEUTRONOS_RELEASE_OUTPUT_ROOT:-/home/echo/neutronos-release-output}"
VERSION="1.0.0-alpha.1"
IMAGE="${NEUTRONOS_RELEASE_IMAGE:-$RELEASE_OUTPUT_ROOT/NeutronOS-Apollo-$VERSION-arm64.img}"
BASE_IMAGE_XZ="${NEUTRONOS_BASE_IMAGE_XZ:-$RELEASE_WORK_ROOT/base/2026-06-18-raspios-trixie-arm64-lite.img.xz}"
BASE_IMAGE_SHA256="${NEUTRONOS_BASE_IMAGE_SHA256:-acff736ca7945e3b305f07cda4abdb870910e12634991da69783611756e381b3}"
MIN_IMAGE_SIZE_BYTES=7499999744
TARGET_IMAGE_SIZE_BYTES="${NEUTRONOS_IMAGE_SIZE_BYTES:-$MIN_IMAGE_SIZE_BYTES}"
BUILD_DIR="${NEUTRONOS_BUILD_DIR:-$RELEASE_WORK_ROOT/build}"
WORK="${NEUTRONOS_IMAGE_WORK:-$RELEASE_WORK_ROOT/image-work}"
OUT="${NEUTRONOS_RELEASE_OUTPUT:-$RELEASE_OUTPUT_ROOT}"
ROOT="$WORK/mnt/root"
BOOT="$WORK/mnt/boot"
LOOP=""
MOUNTS=()
CLEANUP_DONE=0
LOG="${NEUTRONOS_BUILD_LOG:-$RELEASE_WORK_ROOT/logs/alpha1-image-build.log}"
KEY="${NEUTRONOS_SIGNING_KEY:-/var/lib/neutronos-release-signing/release-ed25519.key}"
GENERATE_SIGNED_UPDATE="${NEUTRONOS_GENERATE_SIGNED_UPDATE:-0}"
LEGACY_PROJECT_KEY="$PROJECT/sign key.txt"
LOCK_FILE="$WORK/.builder.lock"
LOCK_FD=9

log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
die(){ log "ERROR: $*"; exit 1; }
path_within(){
    local child parent
    child="$(readlink -m -- "$1")"
    parent="$(readlink -m -- "$2")"
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

known_pseudo_mount(){
    local target="$1" source="$2" fstype="$3"
    case "$target:$fstype:$source" in
        "$ROOT/dev/pts:devpts:"*|"$ROOT/dev:devtmpfs:"*|"$ROOT/proc:proc:"*|"$ROOT/sys:sysfs:"*|"$ROOT/run:tmpfs:"*) return 0 ;;
    esac
    return 1
}

builder_mount_classifier_self_test(){
    local root="$WORK/mnt/root" tuple
    local -a accepted=(
        "$root/dev/pts|devpts|devpts"
        "$root/dev|udev|devtmpfs"
        "$root/proc|proc|proc"
        "$root/sys|sysfs|sysfs"
        "$root/run|tmpfs|tmpfs"
        "$root/boot/firmware|/dev/loop99p1|vfat"
        "$root|/dev/loop99p2|ext4"
    )
    for tuple in "${accepted[@]}"; do
        IFS='|' read -r target source fstype <<< "$tuple"
        case "$target:$fstype:$source" in
            "$root/dev/pts:devpts:"*|"$root/dev:devtmpfs:"*|"$root/proc:proc:"*|"$root/sys:sysfs:"*|"$root/run:tmpfs:"*|"$root/boot/firmware:vfat:/dev/loop"*p1|"$root:ext2:/dev/loop"*p2|"$root:ext3:/dev/loop"*p2|"$root:ext4:/dev/loop"*p2) ;;
            *) printf 'mount classifier self-test failed: %s\n' "$tuple" >&2; return 1 ;;
        esac
        if [[ "$target" == "$root/dev/pts" || "$target" == "$root/dev" || "$target" == "$root/proc" || "$target" == "$root/sys" || "$target" == "$root/run" ]]; then
            known_pseudo_mount "$target" "$source" "$fstype" || {
                printf 'pseudo-mount self-test failed: %s\n' "$tuple" >&2
                return 1
            }
        fi
    done
    tuple="$root/unexpected|overlay|overlay"
    IFS='|' read -r target source fstype <<< "$tuple"
    case "$target:$fstype:$source" in
        "$root/dev/pts:devpts:"*|"$root/dev:devtmpfs:"*|"$root/proc:proc:"*|"$root/sys:sysfs:"*|"$root/run:tmpfs:"*|"$root/boot/firmware:vfat:/dev/loop"*p1|"$root:ext2:/dev/loop"*|"$root:ext3:/dev/loop"*|"$root:ext4:/dev/loop"*)
            printf 'mount classifier self-test failed: unknown tuple accepted\n' >&2; return 1 ;;
    esac
    tuple="$root/dev/pts|devpts|ext4"
    IFS='|' read -r target source fstype <<< "$tuple"
    case "$target:$fstype:$source" in
        "$root/dev/pts:devpts:"*)
            printf 'mount classifier self-test failed: unexpected filesystem accepted\n' >&2; return 1 ;;
    esac
    printf 'mount classifier self-test: PASS\n'
}

if [[ "${NEUTRONOS_BUILDER_SELF_TEST:-0}" == 1 ]]; then
    builder_mount_classifier_self_test
    exit 0
fi

[[ "$(id -u)" == 0 ]] || die "run this builder with sudo"
path_within "$PROJECT" "$RELEASE_WORK_ROOT" || die "project is outside the authorized release-work root"
path_within "$WORK" "$RELEASE_WORK_ROOT" || die "image work is outside the authorized release-work root"
path_within "$BUILD_DIR" "$RELEASE_WORK_ROOT" || die "build directory is outside the authorized release-work root"
path_within "$LOG" "$RELEASE_WORK_ROOT" || die "build log is outside the authorized release-work root"
path_within "$BASE_IMAGE_XZ" "$RELEASE_WORK_ROOT/base" || die "base image is outside the authorized base directory"
path_within "$OUT" "$RELEASE_OUTPUT_ROOT" || die "release output is outside the authorized output root"
path_within "$IMAGE" "$RELEASE_OUTPUT_ROOT" || die "release image is outside the authorized output root"
[[ "$IMAGE" != "$RELEASE_OUTPUT_ROOT" ]] || die "release image path must name a file beneath the output root"
[[ "$WORK" != "$RELEASE_WORK_ROOT" && "$BUILD_DIR" != "$RELEASE_WORK_ROOT" ]] \
    || die "work/build paths must be dedicated subdirectories"
[[ "$TARGET_IMAGE_SIZE_BYTES" =~ ^[0-9]+$ ]] \
    || die "NEUTRONOS_IMAGE_SIZE_BYTES must be a whole number of bytes"
(( TARGET_IMAGE_SIZE_BYTES >= MIN_IMAGE_SIZE_BYTES )) \
    || die "release image capacity must be at least $MIN_IMAGE_SIZE_BYTES bytes"
(( TARGET_IMAGE_SIZE_BYTES % 512 == 0 )) \
    || die "release image capacity must be aligned to a 512-byte sector"
mkdir -p "$WORK" "$OUT" "$(dirname -- "$LOG")" "$(dirname -- "$IMAGE")"
exec > >(tee -a "$LOG") 2>&1

[[ -f "$BUILD_DIR/NeutronShell" ]] || die "validated NeutronShell is missing"
[[ -x "$BUILD_DIR/NeutronBootRenderer" ]] || die "validated NeutronBootRenderer is missing"
[[ -f "$PROJECT/design-reference/Boot.zip" ]] || die "approved Boot.zip is missing"
[[ "$(sha256sum "$PROJECT/design-reference/Boot.zip" | awk '{print $1}')" == \
   53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f ]] \
    || die "approved Boot.zip hash mismatch"
PROJECT_REAL="$(readlink -f "$PROJECT")"
if [[ "$GENERATE_SIGNED_UPDATE" == 1 ]]; then
    [[ -f "$KEY" ]] || die "root-owned host signing key is missing: $KEY"
    [[ "$(stat -c '%a' "$KEY")" == 600 ]] || die "signing key permissions must be 0600"
    [[ "$(stat -c '%u' "$KEY")" == 0 ]] || die "signing key must be owned by root"
    KEY_REAL="$(readlink -f "$KEY")"
    [[ "$KEY_REAL" != "$PROJECT_REAL" && "$KEY_REAL" != "$PROJECT_REAL/"* ]] \
        || die "private signing key must not live inside the NeutronOS project tree"
elif [[ "$GENERATE_SIGNED_UPDATE" != 0 ]]; then
    die "NEUTRONOS_GENERATE_SIGNED_UPDATE must be 0 or 1"
fi
[[ ! -e "$LEGACY_PROJECT_KEY" ]] \
    || die "legacy project signing key still exists; run the Security HIGH remediation migration"
[[ "$PROJECT_REAL" != / ]] || die "unsafe project path"

if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" || -n "${SSH_TTY:-}" ]]; then
    log "Remote session detected: live network/service mutation prohibited"
fi

if [[ "${NEUTRONOS_BUILDER_MOUNT_NS:-0}" != 1 ]]; then
    exec {LOCK_FD}>"$LOCK_FILE"
    flock -n "$LOCK_FD" || die "another Alpha 1 image builder is already running"
fi
[[ ! -L "$IMAGE" ]] || die "release image must not be a symbolic link: $IMAGE"
if [[ ! -e "$IMAGE" ]]; then
    [[ -f "$BASE_IMAGE_XZ" && ! -L "$BASE_IMAGE_XZ" ]] || die "verified compressed base is missing"
    [[ "$(sha256sum "$BASE_IMAGE_XZ" | awk '{print $1}')" == "$BASE_IMAGE_SHA256" ]] \
        || die "compressed base image SHA-256 mismatch"
    log "Expanding verified clean base into sparse release image"
    xz -dc -- "$BASE_IMAGE_XZ" | dd of="$IMAGE" bs=4M conv=sparse status=progress
    sync "$IMAGE"
fi
[[ -f "$IMAGE" && ! -L "$IMAGE" ]] || die "release image is missing or unsafe: $IMAGE"
CURRENT_IMAGE_SIZE_BYTES="$(stat -c '%s' "$IMAGE")"
(( CURRENT_IMAGE_SIZE_BYTES <= TARGET_IMAGE_SIZE_BYTES )) \
    || die "release image exceeds configured capacity; refusing to shrink it"
if (( CURRENT_IMAGE_SIZE_BYTES < TARGET_IMAGE_SIZE_BYTES )); then
    log "Enlarging raw image from $CURRENT_IMAGE_SIZE_BYTES to $TARGET_IMAGE_SIZE_BYTES bytes"
    truncate -s "$TARGET_IMAGE_SIZE_BYTES" -- "$IMAGE"
    sync "$IMAGE"
fi
[[ "$(stat -c '%s' "$IMAGE")" == "$TARGET_IMAGE_SIZE_BYTES" ]] \
    || die "release image did not reach the required logical capacity"

safe_release_root(){
    local p="$1" r
    r="$(readlink -f "$p")"
    [[ "$r" != / && "$r" != "$PROJECT" && "$r" != "$PROJECT/" ]] || die "refusing live-root target: $r"
    [[ "$r" == "$ROOT" || "$r" == "$ROOT/" || "$r" == "$ROOT/"* ]] || die "target is outside release mount: $r"
    mountpoint -q "$ROOT" || die "release root is not mounted"
    local src
    src="$(findmnt -n -o SOURCE --target "$ROOT" || true)"
    [[ "$src" == /dev/loop* ]] || die "release root is not backed by this image loop device"
}
release_rm(){ local p="$ROOT/$1"; safe_release_root "$ROOT"; rm -rf -- "$p"; }
release_mkdir(){ local p="$ROOT/$1"; safe_release_root "$ROOT"; install -d "$p"; }
factory_profile_entries(){
    local root="$1" directory legacy_state
    legacy_state="$root/home/echo/NeutronOS/state"
    for directory in "$root/var/lib/neutronos/security/users"; do
        [[ -d "$directory" ]] || continue
        find "$directory" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
    done
    # Development/source trees may still have a real legacy state directory.
    # Never traverse the release image's absolute /var/lib compatibility link
    # from the host-side builder.
    if [[ ! -L "$legacy_state" && -d "$legacy_state/users" ]]; then
        find "$legacy_state/users" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
    fi
}
assert_factory_sterile(){
    local root="$1" label="$2" account_output profile_output
    if ! account_output=$("$PROJECT/scripts/neutronos-human-accounts" \
            --root "$root" --assert-none 2>&1); then
        die "$label contains human login accounts: $account_output"
    fi
    profile_output="$(factory_profile_entries "$root" | sort -u)"
    [[ -z "$profile_output" ]] \
        || die "$label contains NeutronOS owner/profile state: $profile_output"
    [[ ! -e "$root/var/lib/neutronos/setup/setup.json" ]] \
        || die "$label contains a Setup Wizard completion marker"
}
assert_distribution_branding(){
    local root="$1" contract
    local -a expected_os_release=(
        'PRETTY_NAME="NeutronOS Apollo 1.0.0-alpha.1"'
        'NAME="NeutronOS"'
        'VERSION_ID="1.0.0-alpha.1"'
        'VERSION="1.0.0-alpha.1 (Apollo)"'
        'VERSION_CODENAME=apollo'
        'ID=neutronos'
        'ID_LIKE=debian'
        'VARIANT="Apollo"'
        'VARIANT_ID=apollo'
    )
    [[ -f "$root/usr/lib/os-release" && ! -L "$root/usr/lib/os-release" ]] \
        || die "canonical NeutronOS os-release is missing"
    [[ -L "$root/etc/os-release" && "$(readlink "$root/etc/os-release")" == ../usr/lib/os-release ]] \
        || die "etc/os-release does not resolve to the canonical NeutronOS identity"
    cmp -s "$PROJECT/config/distribution/os-release" "$root/usr/lib/os-release" \
        || die "canonical NeutronOS os-release differs from the release contract"
    cmp -s "$root/etc/os-release" "$root/usr/lib/os-release" \
        || die "etc/os-release does not resolve to the NeutronOS identity"
    for contract in "${expected_os_release[@]}"; do
        grep -Fxq -- "$contract" "$root/usr/lib/os-release" \
            || die "NeutronOS os-release contract missing: $contract"
    done
    cmp -s "$PROJECT/config/distribution/issue" "$root/etc/issue" \
        || die "NeutronOS local console branding is invalid"
    cmp -s "$PROJECT/config/distribution/issue.net" "$root/etc/issue.net" \
        || die "NeutronOS remote console branding is invalid"
    cmp -s "$PROJECT/config/distribution/dpkg-origin-neutronos" "$root/etc/dpkg/origins/neutronos" \
        || die "NeutronOS dpkg origin is invalid"
    [[ -L "$root/etc/dpkg/origins/default" && "$(readlink "$root/etc/dpkg/origins/default")" == neutronos ]] \
        || die "default dpkg origin does not point to NeutronOS"
    [[ -f "$root/etc/dpkg/origins/debian" ]] \
        || die "Debian upstream dpkg origin was not preserved"
    [[ "$(chroot "$root" dpkg-vendor --query Vendor)" == NeutronOS ]] \
        || die "dpkg-vendor does not report NeutronOS"
    [[ "$(chroot "$root" dpkg-vendor --query Parent)" == Debian ]] \
        || die "dpkg-vendor does not report Debian as the parent"
    chroot "$root" dpkg-vendor --derives-from Debian \
        || die "dpkg-vendor does not retain Debian lineage"
    grep -RhsEq '(deb\.debian\.org/debian|archive\.raspberrypi\.com/debian)' \
        "$root/etc/apt/sources.list" "$root/etc/apt/sources.list.d" \
        || die "Debian/Raspberry Pi upstream package repositories were not preserved"
}
validate_mountpoint(){
    local p="$1" rp
    rp="$(readlink -f "$p")"
    [[ "$rp" != / && "$rp" != "$PROJECT" && "$rp" == "$WORK/"* ]] || die "unsafe mount point: $p"
    [[ -d "$p" && ! -L "$p" ]] || die "mount point is not a real directory: $p"
    ! mountpoint -q "$p" || die "mount point is already mounted: $p"
}

loop_devices_for_image(){
    # losetup may annotate a detached/stale association with "(lost)".
    # Match the device prefix independently of that annotation.
    losetup -j "$IMAGE" 2>/dev/null | sed -n 's#^\(/dev/loop[0-9][0-9]*\).*#\1#p'
}

path_is_under(){
    local child parent
    child="$(readlink -f "$1")"
    parent="$(readlink -f "$2")"
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

mount_tuple_is_known(){
    local target="$1" source="$2" fstype="$3"
    case "$target:$fstype:$source" in
        "$ROOT/dev/pts:devpts:"*) return 0 ;;
        "$ROOT/dev:devtmpfs:"*) return 0 ;;
        "$ROOT/proc:proc:"*) return 0 ;;
        "$ROOT/sys:sysfs:"*) return 0 ;;
        "$ROOT/run:tmpfs:"*) return 0 ;;
        "$ROOT/boot/firmware:vfat:/dev/loop"*p1|"$ROOT/boot/firmware:fat:/dev/loop"*p1) return 0 ;;
        "$ROOT:ext2:/dev/loop"*p2|"$ROOT:ext3:/dev/loop"*p2|"$ROOT:ext4:/dev/loop"*p2) return 0 ;;
    esac
    return 1
}

release_mount_source_owned(){
    local target="$1" source fstype opts loop
    # A target can appear more than once across mount namespaces.  Recovery
    # only needs the first record in this namespace; pseudo-filesystem sources
    # such as "devpts" are valid and are not block-device paths.
    source="$(findmnt -n -o SOURCE --target "$target" 2>/dev/null | head -1 || true)"
    fstype="$(findmnt -n -o FSTYPE --target "$target" 2>/dev/null | head -1 || true)"
    opts="$(findmnt -n -o OPTIONS --target "$target" 2>/dev/null | head -1 || true)"
    [[ -n "$fstype" ]] || die "cannot determine filesystem type for stale mount: $target"
    if [[ "$target" == "$ROOT" || "$target" == "$BOOT" ]]; then
        while read -r loop; do
            [[ -n "$loop" && "$source" == "$loop"p[12] ]] && return 0
        done < <(loop_devices_for_image)
        die "stale image mount is not backed by this release image: $target ($source)"
    fi
    path_is_under "$target" "$ROOT" || die "stale mount is outside release root: $target"
    mount_tuple_is_known "$target" "$source" "$fstype" && return 0
    die "cannot prove builder ownership of stale mount: $target ($source,$fstype,$opts)"
}

unmount_staging_target(){
    local target="$1" source fstype
    source="$(findmnt -n -o SOURCE --target "$target" 2>/dev/null | head -1 || true)"
    fstype="$(findmnt -n -o FSTYPE --target "$target" 2>/dev/null | head -1 || true)"
    if umount "$target" 2>/dev/null; then
        return 0
    fi
    if known_pseudo_mount "$target" "$source" "$fstype"; then
        # A stale bind of host /run can legitimately show host processes.
        # Do not inspect or terminate them; detach only this exact staging mount.
        log "Normal unmount busy for known pseudo/bind mount; lazy-detaching: $target"
        umount -l "$target" 2>/dev/null && return 0
        die "could not detach known stale pseudo/bind mount: $target"
    fi
    die "could not unmount release resource safely: $target"
}

recover_stale_release_resources(){
    local target loop mounts=()
    for target in "$ROOT" "$BOOT"; do
        if mountpoint -q "$target"; then
            mounts+=("$target")
        fi
    done
    if mountpoint -q "$ROOT"; then
        # Query TARGET as its own raw field.  IFS intentionally excludes
        # spaces globally, so parsing TARGET,SOURCE,FSTYPE on one line would
        # incorrectly place the whole line in $target (notably for devpts).
        while IFS= read -r target; do
            [[ -n "$target" ]] || continue
            mounts+=("$target")
        done < <(findmnt -R -rn -o TARGET "$ROOT" 2>/dev/null || true)
    fi
    mapfile -t mounts < <(printf '%s\n' "${mounts[@]}" | awk 'NF' | sort -u | awk '{print length($0) "\t" $0}' | sort -rn | cut -f2-)
    for target in "${mounts[@]}"; do
        [[ -n "$target" ]] || continue
        path_is_under "$target" "$WORK" || die "stale mount is outside builder work tree: $target"
        release_mount_source_owned "$target"
        log "Unmounting stale release mount: $target"
        unmount_staging_target "$target"
    done
    while read -r loop; do
        [[ -n "$loop" ]] || continue
        for part in "$loop"p1 "$loop"p2; do
            while read -r target; do
                [[ -z "$target" ]] && continue
                path_is_under "$target" "$WORK" || die "release loop has unrelated mount: $part -> $target"
            done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null || true)
        done
        log "Detaching stale release loop: $loop"
        losetup -d "$loop" || die "could not detach stale release loop: $loop"
    done < <(loop_devices_for_image)
}

enter_private_mount_namespace(){
    [[ "${NEUTRONOS_BUILDER_MOUNT_NS:-0}" == 1 ]] && return 0
    command -v unshare >/dev/null 2>&1 || die "unshare is required for isolated image construction"
    log "Entering private mount namespace for image/chroot phase"
    export NEUTRONOS_BUILDER_MOUNT_NS=1
    exec unshare --mount --propagation private -- "$BASH" "$0" "$@"
}

cleanup(){
    (( CLEANUP_DONE == 0 )) || return 0
    CLEANUP_DONE=1
    set +e
    sync
    for ((i=${#MOUNTS[@]}-1;i>=0;i--)); do
        unmount_staging_target "${MOUNTS[$i]}" 2>/dev/null || true
    done
    [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
}
on_error(){
    local status=$?
    cleanup
    exit "$status"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP
trap on_error ERR

mkdir -p "$WORK/mnt/root/boot/firmware" "$WORK/mnt/root/dev/pts" "$WORK/mnt/root/proc" "$WORK/mnt/root/sys" "$WORK/mnt/root/run" "$WORK/mnt/boot" "$OUT"
if [[ "${NEUTRONOS_BUILDER_MOUNT_NS:-0}" != 1 ]]; then
    recover_stale_release_resources
    enter_private_mount_namespace "$@"
fi
recover_stale_release_resources
validate_mountpoint "$ROOT"
validate_mountpoint "$BOOT"
LOOP="$(losetup --find --show --partscan "$IMAGE")" || die "cannot attach release image loop device"
[[ "$LOOP" == /dev/loop* ]] || die "unexpected loop device"
ROOT_PART="${LOOP}p2"; BOOT_PART="${LOOP}p1"
[[ -b "$ROOT_PART" && -b "$BOOT_PART" ]] || die "partition scan did not expose boot/root partitions"

LOOP_SIZE_BYTES="$(blockdev --getsize64 "$LOOP")"
[[ "$LOOP_SIZE_BYTES" == "$TARGET_IMAGE_SIZE_BYTES" ]] \
    || die "loop device does not expose the required image capacity"
LOGICAL_SECTOR_BYTES="$(blockdev --getss "$LOOP")"
[[ "$LOGICAL_SECTOR_BYTES" == 512 ]] \
    || die "release image loop device must use 512-byte logical sectors"
SECTORS="$(blockdev --getsz "$LOOP")"
PARTITION_LINE="$(sfdisk -d "$IMAGE" | awk '/img2|p2/ {print; exit}')"
ROOT_START="$(sed -nE 's/.*start=[[:space:]]*([0-9]+).*/\1/p' <<< "$PARTITION_LINE")"
ROOT_SECTORS="$(sed -nE 's/.*size=[[:space:]]*([0-9]+).*/\1/p' <<< "$PARTITION_LINE")"
[[ "$ROOT_START" =~ ^[0-9]+$ && "$ROOT_SECTORS" =~ ^[0-9]+$ ]] \
    || die "cannot inspect release root partition geometry"
EXPECTED_ROOT_SECTORS=$((SECTORS - ROOT_START))
(( EXPECTED_ROOT_SECTORS > 0 )) || die "release root partition start is outside the image"
if (( ROOT_SECTORS != EXPECTED_ROOT_SECTORS )); then
    log "Root partition is not yet expanded — growing it to image capacity"
    printf ',+\n' | sfdisk --no-reread -N 2 "$IMAGE"
    partprobe "$LOOP" || die "could not reload expanded release partition table"
    udevadm settle
else
    log "Root partition already expanded — skipping partition resize"
fi
PART_BYTES="$(blockdev --getsize64 "$ROOT_PART")"
EXPECTED_ROOT_BYTES=$((EXPECTED_ROOT_SECTORS * LOGICAL_SECTOR_BYTES))
[[ "$PART_BYTES" == "$EXPECTED_ROOT_BYTES" ]] \
    || die "release root partition does not fill the enlarged image"
FS_BLOCKS="$(dumpe2fs -h "$ROOT_PART" 2>/dev/null | awk -F: '/Block count/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
FS_SIZE="$(dumpe2fs -h "$ROOT_PART" 2>/dev/null | awk -F: '/Block size/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
[[ "$FS_BLOCKS" =~ ^[0-9]+$ && "$FS_SIZE" =~ ^[0-9]+$ ]] || die "cannot inspect root filesystem size"
FS_BYTES=$((FS_BLOCKS * FS_SIZE))
if (( FS_BYTES < PART_BYTES - 1048576 )); then
    log "Root filesystem is smaller than its partition — checking and resizing"
    e2fsck -fy "$ROOT_PART"
    resize2fs "$ROOT_PART"
else
    log "Root filesystem already expanded — skipping filesystem resize"
fi
FS_BLOCKS="$(dumpe2fs -h "$ROOT_PART" 2>/dev/null | awk -F: '/Block count/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
FS_SIZE="$(dumpe2fs -h "$ROOT_PART" 2>/dev/null | awk -F: '/Block size/ {gsub(/[[:space:]]/,"",$2); print $2; exit}')"
[[ "$FS_BLOCKS" =~ ^[0-9]+$ && "$FS_SIZE" =~ ^[0-9]+$ ]] \
    || die "cannot verify resized root filesystem size"
FS_BYTES=$((FS_BLOCKS * FS_SIZE))
FS_SLACK_BYTES=$((PART_BYTES - FS_BYTES))
(( FS_SLACK_BYTES >= 0 && FS_SLACK_BYTES < FS_SIZE )) \
    || die "release root filesystem does not fill its enlarged partition"
validate_mountpoint "$ROOT"
mount "$ROOT_PART" "$ROOT"; MOUNTS+=("$ROOT")
[[ "$(readlink -f "$(findmnt -n -o SOURCE --target "$ROOT")")" == "$(readlink -f "$ROOT_PART")" ]] || die "root mount source mismatch"
install -d "$ROOT/boot/firmware" "$ROOT/dev/pts" "$ROOT/proc" "$ROOT/sys" "$ROOT/run"
validate_mountpoint "$BOOT"
mount "$BOOT_PART" "$BOOT"; MOUNTS+=("$BOOT")
mount --bind "$BOOT" "$ROOT/boot/firmware"; MOUNTS+=("$ROOT/boot/firmware")
safe_release_root "$ROOT"

log "Installing runtime dependencies inside the sterile image"
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf.release-builder"
mount --bind /dev "$ROOT/dev"; MOUNTS+=("$ROOT/dev")
mount --bind /dev/pts "$ROOT/dev/pts"; MOUNTS+=("$ROOT/dev/pts")
mount -t proc proc "$ROOT/proc"; MOUNTS+=("$ROOT/proc")
mount -t sysfs sysfs "$ROOT/sys"; MOUNTS+=("$ROOT/sys")
mount -t tmpfs -o mode=755 tmpfs "$ROOT/run"; MOUNTS+=("$ROOT/run")
install -d -m 0755 "$ROOT/run/lock" "$ROOT/run/systemd"
chroot "$ROOT" mv -f /etc/resolv.conf.release-builder /etc/resolv.conf
cat > "$ROOT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 0755 "$ROOT/usr/sbin/policy-rc.d"
chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get update
chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl dbus-user-session e2fsprogs ffmpeg iproute2 iw \
    libegl1 libpam0g libsodium23 network-manager nftables openssh-client \
    initramfs-tools unzip plymouth plymouth-label plymouth-themes libplymouth5 \
    python3 python3.13 libpython3.13-stdlib rsync sudo passwd libpam-modules locales systemd udev util-linux bluez pipewire \
    wireplumber alsa-utils qml6-module-qtquick qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtqml-workerscript \
    libqt6quick6 libqt6qml6 libqt6gui6 libqt6network6 libqt6dbus6 qt6-svg-plugins
# A prior Alpha builder's over-broad secret-name cleanup could remove token.py
# and tokenize.py while leaving dpkg's package state as installed.  Reinstall
# the owning runtime package so rerunning this builder repairs that image via
# Debian packaging rather than copying individual standard-library files.
chroot "$ROOT" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --reinstall \
    python3.13-minimal libpython3.13-minimal libpython3.13-stdlib
rm -f "$ROOT/usr/sbin/policy-rc.d"

log "Applying NeutronOS distribution identity"
install -d -m 0755 "$ROOT/usr/lib" "$ROOT/etc/dpkg/origins"
install -m 0644 "$PROJECT/config/distribution/os-release" "$ROOT/usr/lib/os-release"
release_rm etc/os-release
ln -s ../usr/lib/os-release "$ROOT/etc/os-release"
install -m 0644 "$PROJECT/config/distribution/issue" "$ROOT/etc/issue"
install -m 0644 "$PROJECT/config/distribution/issue.net" "$ROOT/etc/issue.net"
install -m 0644 "$PROJECT/config/distribution/dpkg-origin-neutronos" \
    "$ROOT/etc/dpkg/origins/neutronos"
release_rm etc/dpkg/origins/default
ln -s neutronos "$ROOT/etc/dpkg/origins/default"
assert_distribution_branding "$ROOT"

log "Installing validated NeutronOS payload"
safe_release_root "$ROOT"
install -d "$ROOT/home/echo/NeutronOS"
tar -C "$PROJECT" -cf - \
    --exclude='./state' --exclude='./backups' --exclude='./build' \
    --exclude='./dist' --exclude='./design-reference' --exclude='./.git' \
    --exclude='./.codex' --exclude='./qml/apps/codex' --exclude='./scripts/apps/codex' \
    --exclude='./config/apps/codex-bridge.schema.json' \
    --exclude='./themes/Default/apps/icons/codex*' --exclude='./themes/Default/apps/posters/codex*' \
    qml themes config scripts services CMakeLists.txt | tar -C "$ROOT/home/echo/NeutronOS" -xf -
# The release payload is immutable, root-owned application data. Normalize
# source-worktree ownership/modes instead of preserving the development host's
# numeric echo:nogroup identity in the image.
chown -hR root:root "$ROOT/home/echo/NeutronOS"
find "$ROOT/home/echo/NeutronOS" -xdev -type d -exec chmod 0755 {} +
find "$ROOT/home/echo/NeutronOS" -xdev -type f -perm /0111 -exec chmod 0755 {} +
find "$ROOT/home/echo/NeutronOS" -xdev -type f ! -perm /0111 -exec chmod 0644 {} +
install -d -o root -g root -m 0755 \
    "$ROOT/home/echo/NeutronOS/config/app-store/repository" \
    "$ROOT/home/echo/NeutronOS/themes/Default/apps/icons" \
    "$ROOT/home/echo/NeutronOS/themes/Default/apps/posters" \
    "$ROOT/home/echo/NeutronOS/themes/Default/users"
install -m 0755 "$BUILD_DIR/NeutronShell" "$ROOT/home/echo/NeutronOS/build-NeutronShell"
install -m 0755 "$BUILD_DIR/NeutronBootRenderer" "$ROOT/home/echo/NeutronOS/build-NeutronBootRenderer"
install -m 0755 "$BUILD_DIR/NeutronBrowser" "$ROOT/home/echo/NeutronOS/build-NeutronBrowser" 2>/dev/null || true
mkdir -p "$ROOT/home/echo/NeutronOS/build"
mv "$ROOT/home/echo/NeutronOS/build-NeutronShell" "$ROOT/home/echo/NeutronOS/build/NeutronShell"
mv "$ROOT/home/echo/NeutronOS/build-NeutronBootRenderer" "$ROOT/home/echo/NeutronOS/build/NeutronBootRenderer"
[[ ! -e "$ROOT/home/echo/NeutronOS/build/NeutronBrowser" ]] || mv "$ROOT/home/echo/NeutronOS/build-NeutronBrowser" "$ROOT/home/echo/NeutronOS/build/NeutronBrowser"

install -d "$ROOT/etc/neutronos" "$ROOT/usr/local/sbin" "$ROOT/usr/local/lib/neutronos" "$ROOT/usr/local/libexec"
install -m 0644 "$PROJECT/config/update-public-key" "$ROOT/etc/neutronos/update-public-key"
install -m 0644 "$PROJECT/config/security-authorization.json" "$ROOT/etc/neutronos/security-authorization.json"
install -m 0755 "$PROJECT/scripts/neutronos-state-setup" "$ROOT/usr/local/sbin/neutronos-state-setup"
install -m 0755 "$PROJECT/scripts/neutronos-human-accounts" "$ROOT/usr/local/sbin/neutronos-human-accounts"
# Keep the version-specific privileged helper untouched behind a stable Security guard.
install -m 0755 "$PROJECT/release/neutronos-privileged-helper" "$ROOT/usr/local/libexec/neutronos-privileged-helper.real"
install -m 0755 "$PROJECT/scripts/neutronos-privileged-helper-guard.py" "$ROOT/usr/local/sbin/neutronos-privileged-helper"
install -d -m 0755 "$ROOT/etc/sudoers.d"
install -m 0440 "$PROJECT/release/neutronos-privileged-helper.sudoers" \
    "$ROOT/etc/sudoers.d/neutronos-privileged-helper"
install -m 0755 \
    "$PROJECT/scripts/neutronos-recovery-control" \
    "$PROJECT/scripts/neutronos-recovery-banner" \
    "$PROJECT/scripts/neutronos-shell-failure" \
    "$PROJECT/scripts/neutronos-shell-mark-stable" \
    "$ROOT/usr/local/sbin/"
install -m 0755 "$PROJECT/scripts/neutron-securityd.py" "$ROOT/usr/local/lib/neutronos/neutron-securityd.py"
install -m 0755 "$PROJECT/scripts/neutron-security-watchdog.py" "$ROOT/usr/local/lib/neutronos/neutron-security-watchdog.py"
install -m 0644 "$PROJECT/scripts/neutronos_app_security.py" "$PROJECT/scripts/neutronos_remote_security.py" "$ROOT/usr/local/lib/neutronos/"
install -m 0755 "$PROJECT/scripts/neutronos-offline-networkd.py" "$ROOT/usr/local/libexec/neutronos-offline-networkd.py"
install -m 0755 "$PROJECT/scripts/neutronos-offline-network-control" "$ROOT/usr/local/sbin/neutronos-offline-network-control"
install -m 0755 "$PROJECT/scripts/neutronos-firewall-generate" "$ROOT/usr/local/sbin/neutronos-firewall-generate"
install -m 0644 "$PROJECT/scripts/neutronos_firewall.py" "$ROOT/usr/local/lib/neutronos/neutronos_firewall.py"
install -m 0755 "$PROJECT/scripts/neutronos-firewall-guard.py" "$ROOT/usr/local/lib/neutronos/neutronos-firewall-guard.py"
install -m 0755 "$PROJECT/services/remote/neutronos_remote_controller.py" "$ROOT/usr/local/lib/neutronos/neutronos-remote-controller.py" 2>/dev/null || true
install -d "$ROOT/usr/local/lib/neutronos/neutronos_ipc"
install -m 0644 "$PROJECT/scripts/neutronos_ipc"/*.py "$ROOT/usr/local/lib/neutronos/neutronos_ipc/"
install -m 0644 "$PROJECT/systemd"/*.service "$PROJECT/systemd"/*.target "$ROOT/etc/systemd/system/"
install -d "$ROOT/etc/systemd/system/nftables.service.d"
install -m 0644 "$PROJECT/systemd/nftables.service.d/10-neutronos-life-support.conf" \
    "$ROOT/etc/systemd/system/nftables.service.d/10-neutronos-life-support.conf"
install -d "$ROOT/etc/systemd/system/neutron-remote-service.service.d"
install -m 0644 "$PROJECT/systemd/neutron-remote-service.service.d/20-neutronos-security-isolation.conf" \
    "$ROOT/etc/systemd/system/neutron-remote-service.service.d/20-neutronos-security-isolation.conf"
install -m 0644 "$PROJECT/config/nftables-life-support.conf" "$ROOT/etc/nftables.conf"
install -m 0644 "$PROJECT/config/firewall-normal.nft" "$ROOT/etc/neutronos/firewall-normal.nft"
install -m 0644 "$PROJECT/config/version.json" "$ROOT/etc/neutronos/version.json"
install -m 0600 "$PROJECT/config/offline-network.json" "$ROOT/etc/neutronos/offline-network.json"
install -m 0640 "$PROJECT/config/offline-network-authorization.json" "$ROOT/etc/neutronos/offline-network-authorization.json"
# Canonical boot installation is shared with the development system. This also
# reserves tty1 for explicit recovery and masks Raspberry Pi's userconf wizard.
"$PROJECT/scripts/neutronos-configure-boot-root" \
    "$ROOT" "$BOOT" "$PROJECT" "$WORK" "$BUILD_DIR"
cat > "$ROOT/etc/neutronos/neutronos.conf" <<EOF
NEUTRONOS_ROOT=/home/echo/NeutronOS
NEUTRONOS_STATE_DIR=/var/lib/neutronos
NEUTRONOS_SECURITY_STATE_DIR=/var/lib/neutronos/security
EOF
ln -sfn ../neutronos.target "$ROOT/etc/systemd/system/multi-user.target.wants/neutronos.target"
install -d "$ROOT/etc/systemd/system/sysinit.target.wants"
ln -sfn ../neutronos-firewall-guard.service \
    "$ROOT/etc/systemd/system/sysinit.target.wants/neutronos-firewall-guard.service"

log "Configuring factory state"
safe_release_root "$ROOT"
release_rm var/lib/neutronos
release_mkdir var/lib/neutronos/security
release_mkdir var/lib/neutronos/security-core
release_mkdir var/lib/neutronos/security-core/firewall
install -m 0600 "$PROJECT/config/firewall-normal.nft" "$ROOT/var/lib/neutronos/security-core/firewall/known-good.nft"
release_mkdir var/lib/neutronos/network
release_mkdir var/lib/neutronos/network/firewall
install -m 0600 "$PROJECT/config/firewall-normal.nft" "$ROOT/var/lib/neutronos/network/firewall/known-good.nft"
release_mkdir var/lib/neutronos/recovery
release_mkdir var/log/neutronos
# In-place rebuilds can retain the destination's old mutable state directory:
# excluding ./state from the source tar does not remove an existing directory.
# Remove only that release-image copy before creating the compatibility alias.
release_rm home/echo/NeutronOS/state
release_rm var/lib/neutronos/setup
release_rm home/echo/.codex
release_rm home/echo/.ssh
release_rm home/echo/.bash_history
release_rm root/.bash_history
release_rm etc/NetworkManager/system-connections
release_mkdir etc/NetworkManager/system-connections
release_rm var/lib/bluetooth
release_rm var/lib/tailscale
release_rm home/echo/Downloads
release_rm home/echo/.config
release_rm home/echo/.cache
safe_release_root "$ROOT"
# Secret-name sanitization is limited to mutable NeutronOS and account state.
# Never apply filename heuristics to package-managed runtime trees: doing so
# previously deleted Python's package-owned token.py and tokenize.py.
RELEASE_SECRET_SEARCH_ROOTS=(
    "$ROOT/root"
    "$ROOT/etc/neutronos"
    "$ROOT/var/lib/neutronos"
    "$ROOT/var/lib/NetworkManager"
)
find "${RELEASE_SECRET_SEARCH_ROOTS[@]}" -xdev -type f \
    \( -name '*.key' -o -name '*.pem' -o -name '*token*' -o -name '*credential*' \) -delete
printf '' > "$ROOT/etc/machine-id"
rm -f "$ROOT/var/lib/dbus/machine-id" "$ROOT/etc/ssh/ssh_host_"* 2>/dev/null || true
rm -f "$ROOT/etc/neutronos/sign key.txt" "$ROOT/home/echo/NeutronOS/sign key.txt"
chmod 700 "$ROOT/var/lib/neutronos" "$ROOT/var/lib/neutronos/security"
chmod 0750 "$ROOT/var/lib/neutronos/security-core" "$ROOT/var/lib/neutronos/security-core/firewall"
chmod 0700 "$ROOT/var/lib/neutronos/network" "$ROOT/var/lib/neutronos/recovery"
sha256sum "$ROOT/usr/local/lib/neutronos/neutron-securityd.py" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/securityd.sha256"
sha256sum "$ROOT/usr/local/lib/neutronos/neutron-security-watchdog.py" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/watchdog.sha256"
sha256sum "$ROOT/usr/local/lib/neutronos/neutronos-firewall-guard.py" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/firewall-guard.sha256"
sha256sum "$ROOT/usr/local/lib/neutronos/neutronos_firewall.py" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/firewall-module.sha256"
sha256sum "$ROOT/usr/local/sbin/neutronos-privileged-helper" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/privileged-helper.sha256"
sha256sum "$ROOT/usr/local/libexec/neutronos-privileged-helper.real" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/privileged-helper-real.sha256"
sha256sum "$ROOT/etc/systemd/system/neutron-securityd.service" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/securityd-unit.sha256"
sha256sum "$ROOT/etc/systemd/system/neutron-security-watchdog.service" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/watchdog-unit.sha256"
sha256sum "$ROOT/etc/systemd/system/neutronos-firewall-guard.service" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/firewall-guard-unit.sha256"
sha256sum "$ROOT/etc/nftables.conf" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/nftables-conf.sha256"
sha256sum "$ROOT/etc/neutronos/firewall-normal.nft" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/firewall-normal-policy.sha256"
sha256sum "$ROOT/etc/systemd/system/neutron-remote-service.service.d/20-neutronos-security-isolation.conf" | awk '{print $1}' > "$ROOT/var/lib/neutronos/security-core/remote-security-isolation.sha256"
chmod 0640 "$ROOT/var/lib/neutronos/security-core/"*.sha256
chroot "$ROOT" useradd --system --create-home --home-dir /home/echo --shell /usr/sbin/nologin echo 2>/dev/null || true
chroot "$ROOT" passwd -l echo 2>/dev/null || true
chroot "$ROOT" usermod --shell /usr/sbin/nologin echo
chroot "$ROOT" getent group neutronos-shell >/dev/null \
    || chroot "$ROOT" groupadd --system neutronos-shell
DISPLAY_GROUPS=(neutronos-shell)
for group in audio video input render bluetooth; do
    chroot "$ROOT" getent group "$group" >/dev/null \
        || chroot "$ROOT" groupadd --system "$group"
    DISPLAY_GROUPS+=("$group")
done
DISPLAY_GROUP_LIST="$(IFS=,; printf '%s' "${DISPLAY_GROUPS[*]}")"
chroot "$ROOT" usermod -a -G "$DISPLAY_GROUP_LIST" echo
for account in pi debian; do
    chroot "$ROOT" userdel -r "$account" 2>/dev/null || true
done
chroot "$ROOT" chown echo:echo /home/echo
chmod 0755 "$ROOT/home/echo"
chown root:root "$ROOT/home/echo/NeutronOS"
chmod 0755 "$ROOT/home/echo/NeutronOS"
# Apply the same ownership contract used at boot. Factory mode deliberately
# skips creation of the per-install remote-controller credential.
chroot "$ROOT" /usr/bin/env NEUTRONOS_FACTORY_BUILD=1 \
    NEUTRONOS_OWNER=echo NEUTRONOS_GROUP=echo \
    /usr/local/sbin/neutronos-state-setup
# Legacy managers still spell mutable paths as $NEUTRONOS_ROOT/state. Create
# the staging-safe compatibility alias only after every host-side legacy
# cleanup operation; later mutations use $ROOT/var/lib directly.
bash "$PROJECT/scripts/neutronos-prepare-state-alias" "$ROOT"

# Initramfs is generated after factory sanitization and after the NeutronOS
# Plymouth theme, hook, and label plugin have been installed.
chroot "$ROOT" plymouth-set-default-theme neutronos
if compgen -G "$ROOT/boot/initrd.img-*" >/dev/null; then
    chroot "$ROOT" update-initramfs -u -k all
else
    chroot "$ROOT" update-initramfs -c -k all
fi

log "Verifying release boot and factory contracts before unmount"
assert_distribution_branding "$ROOT"
[[ -f "$BOOT/config.txt" ]] || die "release firmware config missing"
[[ "$(awk -F= '/^[[:space:]]*disable_splash[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); value=$2} END{print value}' "$BOOT/config.txt")" == 1 ]] || die "firmware rainbow splash is not disabled"
[[ -x "$ROOT/home/echo/NeutronOS/build/NeutronBootRenderer" ]] || die "boot renderer missing"
[[ -f "$ROOT/home/echo/NeutronOS/design-reference/Boot.zip" ]] || die "approved Boot.zip missing"
[[ "$(sha256sum "$ROOT/home/echo/NeutronOS/design-reference/Boot.zip" | awk '{print $1}')" == \
   53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f ]] \
    || die "approved Boot.zip hash mismatch"
chroot "$ROOT" /home/echo/NeutronOS/build/NeutronBootRenderer --validate \
    || die "boot renderer rejected approved Boot.zip"
for package in plymouth plymouth-label plymouth-themes libplymouth5; do
    [[ "$(chroot "$ROOT" dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" == \
       "install ok installed" ]] || die "required Plymouth package missing: $package"
done
[[ -f "$ROOT/usr/share/plymouth/themes/neutronos/neutronos.plymouth" ]] \
    || die "NeutronOS Plymouth theme missing"
[[ -f "$ROOT/usr/share/plymouth/themes/neutronos/neutronos.script" ]] \
    || die "NeutronOS Plymouth script missing"
[[ "$(grep -E '^Theme=' "$ROOT/etc/plymouth/plymouthd.conf" | tail -1)" == Theme=neutronos ]] \
    || die "NeutronOS Plymouth theme is not configured"
mapfile -t RELEASE_PLYMOUTH_ASSETS < <(find \
    "$ROOT/usr/share/plymouth/themes/neutronos/assets" -maxdepth 1 \
    -type f -name '*.png' -print | sort)
[[ ${#RELEASE_PLYMOUTH_ASSETS[@]} -eq 25 ]] \
    || die "NeutronOS Plymouth theme must contain exactly 25 artwork frames"
for asset in neutronos_progress_000.png neutronos_progress_100.png \
             neutronos_reboot.png neutronos_shutdown.png neutronos_recovery.png \
             neutronos_error.png; do
    [[ -s "$ROOT/usr/share/plymouth/themes/neutronos/assets/$asset" ]] \
        || die "NeutronOS Plymouth artwork missing: $asset"
done
for helper in neutronos-boot-progress neutronos-boot-failure \
              neutronos-plymouth-adopt neutronos-plymouth-finalize \
              neutronos-plymouth-release neutronos-shell-start-prep; do
    [[ -x "$ROOT/usr/local/sbin/$helper" ]] \
        || die "required Plymouth lifecycle helper missing: $helper"
done
[[ -x "$ROOT/usr/lib/systemd/system-generators/neutronos-boot-generator" ]] \
    || die "NeutronOS Plymouth milestone generator missing"
[[ -x "$ROOT/etc/initramfs-tools/scripts/init-premount/neutronos-plymouth" ]] \
    || die "NeutronOS Plymouth initramfs hook missing"
[[ -x "$ROOT/etc/initramfs-tools/hooks/zz-neutronos-plymouth-label" ]] \
    || die "NeutronOS Plymouth label hook missing"
LABEL_PLUGIN_REL="$(chroot "$ROOT" dpkg-query -L plymouth-label 2>/dev/null \
    | awk '/\/label-pango\.so$/ {print; exit}')"
[[ -n "$LABEL_PLUGIN_REL" && -f "$ROOT$LABEL_PLUGIN_REL" ]] \
    || die "Plymouth label-pango plugin missing"
file "$ROOT$LABEL_PLUGIN_REL" | grep -Eq 'ARM aarch64|ARM64' \
    || die "Plymouth label-pango plugin is not ARM64"
readelf -d "$ROOT$LABEL_PLUGIN_REL" >/dev/null 2>&1 \
    || die "Plymouth label-pango plugin is not a valid ELF shared object"
for unit in neutronos.service neutronos.target neutronos-boot-failure.service; do
    [[ -f "$ROOT/etc/systemd/system/$unit" ]] || die "required systemd unit missing: $unit"
done
# Every service reached by neutronos.target, the boot progress chain, or
# the shell stability hook must be complete on a sterile image.
declare -A RELEASE_SERVICE_EXECUTABLES=(
    [neutronos-boot-failure.service]="/usr/local/sbin/neutronos-boot-failure"
    [neutronos-state-setup.service]="/usr/local/sbin/neutronos-state-setup"
    [neutron-securityd.service]="/usr/local/lib/neutronos/neutron-securityd.py"
    [neutron-security-watchdog.service]="/usr/local/lib/neutronos/neutron-security-watchdog.py"
    [neutronos-firewall-guard.service]="/usr/local/lib/neutronos/neutronos-firewall-guard.py"
    [neutronos-offline-network.service]="/usr/local/libexec/neutronos-offline-networkd.py"
    [neutronos-remote-controller.service]="/usr/local/lib/neutronos/neutronos-remote-controller.py"
    [neutronos-shell-stability.service]="/usr/local/sbin/neutronos-shell-mark-stable"
    [neutronos-shell-failure.service]="/usr/local/sbin/neutronos-shell-failure"
)
for unit in "${!RELEASE_SERVICE_EXECUTABLES[@]}"; do
    [[ -f "$ROOT/etc/systemd/system/$unit" ]] || die "release service unit missing: $unit"
    executable="${RELEASE_SERVICE_EXECUTABLES[$unit]}"
    [[ -x "$ROOT$executable" ]] || die "release service executable missing: $unit -> $executable"
done
for helper in useradd usermod userdel chpasswd hostnamectl; do
    chroot "$ROOT" /bin/sh -c "command -v '$helper' >/dev/null" || die "account runtime missing: $helper"
done
chroot "$ROOT" getent passwd echo >/dev/null || die "NeutronShell runtime account missing"
chroot "$ROOT" getent group neutronos-shell >/dev/null || die "NeutronShell IPC group missing"
[[ -x "$ROOT/usr/local/sbin/neutronos-privileged-helper" ]] || die "Setup Wizard account helper missing"
chroot "$ROOT" visudo -cf /etc/sudoers.d/neutronos-privileged-helper \
    || die "Setup Wizard privilege boundary is invalid"
grep -q '^User=echo$' "$ROOT/etc/systemd/system/neutronos.service" \
    || die "NeutronShell production service is not unprivileged"
grep -q '^Group=echo$' "$ROOT/etc/systemd/system/neutronos.service" \
    || die "NeutronShell production service group is invalid"
! grep -q '^ExecStart=+' "$ROOT/etc/systemd/system/neutronos.service" \
    || die "NeutronShell production executable has a privileged systemd prefix"
[[ -x "$ROOT/usr/bin/python3" ]] || die "release Python executable missing"
PYTHON_RELEASE_VERSION="$(chroot "$ROOT" /usr/bin/python3 -c \
    'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" \
    || die "release Python version check failed"
[[ "$PYTHON_RELEASE_VERSION" == "3.13" ]] || die "release Python must be Debian 13 Python 3.13 family"
for package in python3 python3.13 python3.13-minimal libpython3.13-minimal libpython3.13-stdlib; do
    [[ "$(chroot "$ROOT" dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" == "install ok installed" ]] \
        || die "release Python runtime package missing: $package"
done
[[ -f "$ROOT/usr/lib/python3.13/token.py" ]] || die "release Python token.py missing"
[[ -f "$ROOT/usr/lib/python3.13/tokenize.py" ]] || die "release Python tokenize.py missing"
TOKENIZE_PROVIDER="$(chroot "$ROOT" dpkg-query -S /usr/lib/python3.13/tokenize.py 2>/dev/null | cut -d: -f1 || true)"
[[ "$TOKENIZE_PROVIDER" == "libpython3.13-minimal" ]] \
    || die "release Python tokenize.py package ownership is invalid"
PYTHON_PACKAGE_VERIFY="$(chroot "$ROOT" dpkg --verify \
    python3 python3.13 python3.13-minimal libpython3.13-minimal libpython3.13-stdlib 2>&1)" \
    || die "release Python package integrity query failed"
[[ -z "$PYTHON_PACKAGE_VERIFY" ]] \
    || die "release Python package integrity check failed: $PYTHON_PACKAGE_VERIFY"
[[ "$(chroot "$ROOT" dpkg-query -W -f='${Status}' qt6-svg-plugins 2>/dev/null || true)" == "install ok installed" ]] \
    || die "Qt SVG image-format package missing"
# Debian's qt6-svg-plugins must own the actual libqsvg.so decoder used by
# QQuickImage/QImageReader; checking libQt6Svg alone is insufficient.
SVG_PLUGIN_REL="$(chroot "$ROOT" dpkg-query -L qt6-svg-plugins 2>/dev/null \
    | awk '/\/qt6\/plugins\/imageformats\/libqsvg\.so$/ {print; exit}')"
[[ -n "$SVG_PLUGIN_REL" && -f "$ROOT$SVG_PLUGIN_REL" ]] \
    || die "Qt SVG image-format plugin missing"
[[ "$(chroot "$ROOT" dpkg-query -S "$SVG_PLUGIN_REL" 2>/dev/null | cut -d: -f1 || true)" == qt6-svg-plugins ]] \
    || die "Qt SVG plugin package ownership is invalid"
readelf -d "$ROOT$SVG_PLUGIN_REL" >/dev/null 2>&1 \
    || die "Qt SVG plugin is not a valid shared object"
chroot "$ROOT" /usr/bin/python3 -c \
    'import os, sys, json, socket, struct, pathlib, dataclasses, inspect, tokenize, threading, subprocess, selectors, logging, hashlib, hmac, secrets, time, datetime, typing, enum, re, collections, contextlib, signal' \
    || die "release Python standard-library smoke test failed"
chroot "$ROOT" /usr/bin/python3 -c 'import dataclasses, inspect, tokenize' \
    || die "release Python inspect/tokenize dependency chain failed"
chroot "$ROOT" /usr/bin/python3 -m py_compile \
    /usr/local/sbin/neutronos-privileged-helper \
    /usr/local/libexec/neutronos-privileged-helper.real \
    /usr/local/lib/neutronos/neutron-securityd.py \
    /usr/local/lib/neutronos/neutron-security-watchdog.py \
    /usr/local/lib/neutronos/neutronos-firewall-guard.py \
    /usr/local/libexec/neutronos-offline-networkd.py \
    /usr/local/lib/neutronos/neutronos-remote-controller.py || die "release Python service validation failed"
chroot "$ROOT" /usr/bin/python3 /usr/local/sbin/neutronos-privileged-helper --self-test \
    || die "release privileged-helper Security guard self-test failed"
chroot "$ROOT" /usr/bin/env PYTHONPATH=/usr/local/lib/neutronos /usr/bin/python3 -c \
    'import neutronos_ipc, neutronos_ipc.authorization, neutronos_ipc.sessions, neutronos_firewall' \
    || die "release Security/Offline Network Python dependencies are incomplete"
chroot "$ROOT" /usr/bin/env PYTHONPATH=/usr/local/lib/neutronos /usr/bin/python3 -c \
    'import runpy; [runpy.run_path(path) for path in ("/usr/local/lib/neutronos/neutron-securityd.py", "/usr/local/lib/neutronos/neutron-security-watchdog.py", "/usr/local/lib/neutronos/neutronos-firewall-guard.py", "/usr/local/libexec/neutronos-offline-networkd.py")]' \
    || die "release Security/Offline Network Python entrypoint imports failed"
chroot "$ROOT" /usr/bin/env \
    NEUTRONOS_ROOT=/home/echo/NeutronOS NEUTRONOS_OWNER=echo \
    NEUTRONOS_GROUP=echo PYTHONPATH=/usr/local/lib/neutronos \
    /usr/bin/python3 /usr/local/lib/neutronos/neutron-securityd.py \
    --state-dir /run/neutronos/securityd-smoke/state \
    --project-root /home/echo/NeutronOS --owner echo --group echo \
    --socket /run/neutronos/securityd-smoke/control.sock \
    --socket-group neutronos-shell \
    --authorization-policy /etc/neutronos/security-authorization.json \
    --smoke-test || die "release neutron-securityd real ExecStart smoke test failed"
release_rm run/neutronos/securityd-smoke
chroot "$ROOT" /usr/bin/env PYTHONPATH=/usr/local/lib/neutronos \
    /usr/bin/python3 /usr/local/lib/neutronos/neutron-security-watchdog.py \
    --self-test || die "release security watchdog payload/integrity smoke test failed"
chroot "$ROOT" /usr/bin/env PYTHONPATH=/usr/local/lib/neutronos \
    /usr/bin/python3 /usr/local/lib/neutronos/neutronos-firewall-guard.py \
    --self-test || die "release firewall life-support self-test failed"
chroot "$ROOT" /usr/bin/env PYTHONPATH=/usr/local/lib/neutronos \
    /usr/bin/python3 /usr/local/libexec/neutronos-offline-networkd.py \
    --self-test || die "release offline-network daemon self-test failed"
! grep -Eq '^[[:space:]]*flush[[:space:]]+ruleset' "$ROOT/etc/nftables.conf" \
    || die "release nftables compatibility file must never flush the global ruleset"
! grep -Eq '^[[:space:]]*flush[[:space:]]+ruleset' "$ROOT/etc/neutronos/firewall-normal.nft" \
    || die "release normal firewall policy must never flush the global ruleset"
grep -q 'policy drop' "$ROOT/etc/neutronos/firewall-normal.nft" \
    || die "release normal firewall policy is not fail-closed"
[[ -f "$ROOT/etc/systemd/system/nftables.service.d/10-neutronos-life-support.conf" ]] \
    || die "release nftables life-support compatibility drop-in missing"
[[ -L "$ROOT/etc/systemd/system/sysinit.target.wants/neutronos-firewall-guard.service" ]] \
    || die "release firewall life-support guard is not enabled at sysinit"
systemd-analyze --root="$ROOT" verify \
    neutronos.service neutronos-boot-failure.service neutronos-state-setup.service neutronos-firewall-guard.service \
    neutron-securityd.service neutron-security-watchdog.service neutronos-offline-network.service \
    plymouth-start.service plymouth-reboot.service plymouth-poweroff.service plymouth-halt.service \
    neutronos-remote-controller.service neutronos-shell-stability.service \
    neutronos-shell-stability.path neutronos.target \
    neutronos-shell-failure.service || die "release systemd service verification failed"
mapfile -t RELEASE_INITRDS < <(compgen -G "$ROOT/boot/initrd.img-*" | sort)
(( ${#RELEASE_INITRDS[@]} > 0 )) || die "release initramfs missing"
[[ -f "$BOOT/initramfs8" ]] || die "Raspberry Pi firmware initramfs8 missing"
if printf '%s\n' "${RELEASE_INITRDS[@]}" | grep -q 'rpi-2712'; then
    [[ -f "$BOOT/initramfs_2712" ]] || die "Raspberry Pi 2712 firmware initramfs missing"
fi
PLYMOUTH_INITRAMFS_PATTERNS=(
    '(^|/)usr/sbin/plymouthd$'
    '(^|/)scripts/init-premount/neutronos-plymouth$'
    '(^|/)usr/share/plymouth/themes/neutronos/neutronos\.plymouth$'
    '(^|/)usr/share/plymouth/themes/neutronos/neutronos\.script$'
    '(^|/)usr/share/plymouth/themes/neutronos/assets/neutronos_progress_000\.png$'
    '(^|/)usr/share/plymouth/themes/neutronos/assets/neutronos_progress_100\.png$'
    '(^|/)usr/share/plymouth/themes/neutronos/assets/neutronos_reboot\.png$'
    '(^|/)usr/share/plymouth/themes/neutronos/assets/neutronos_shutdown\.png$'
    '(^|/)label-pango\.so$'
)
assert_plymouth_initramfs()
{
    local initrd=$1 contents=$2 pattern
    for pattern in "${PLYMOUTH_INITRAMFS_PATTERNS[@]}"; do
        grep -Eq "$pattern" <<< "$contents" \
            || die "required Plymouth payload missing from initramfs $initrd: $pattern"
    done
}
for INITRD_PATH in "${RELEASE_INITRDS[@]}"; do
    INITRD_CONTENTS="$(lsinitramfs "$INITRD_PATH" 2>/dev/null)" \
        || die "cannot inspect release initramfs: $INITRD_PATH"
    assert_plymouth_initramfs "$INITRD_PATH" "$INITRD_CONTENTS"
done
for FIRMWARE_INITRD in "$BOOT/initramfs8" "$BOOT/initramfs_2712"; do
    if [[ -f "$FIRMWARE_INITRD" ]]; then
        FIRMWARE_INITRD_CONTENTS="$(lsinitramfs "$FIRMWARE_INITRD" 2>/dev/null)" \
            || die "cannot inspect firmware initramfs: $FIRMWARE_INITRD"
        assert_plymouth_initramfs "$FIRMWARE_INITRD" "$FIRMWARE_INITRD_CONTENTS"
    fi
done
[[ -f "$BOOT/cmdline.txt" ]] || die "release cmdline missing"
grep -qE '(^| )quiet( |$)' "$BOOT/cmdline.txt" || die "quiet missing from release cmdline"
grep -qE '(^| )splash( |$)' "$BOOT/cmdline.txt" || die "Plymouth splash missing from release cmdline"
grep -qE '(^| )plymouth\.ignore-serial-consoles( |$)' "$BOOT/cmdline.txt" \
    || die "Plymouth serial-console guard missing from release cmdline"
! grep -qE '(^| )resize( |$)' "$BOOT/cmdline.txt" \
    || die "first-boot root resize token remains"
for forbidden in console=tty1 systemd.show_status=1 ignore_loglevel; do
    ! grep -qE "(^| )${forbidden//./\\.}( |$)" "$BOOT/cmdline.txt" \
        || die "diagnostic boot token leaked into release cmdline: $forbidden"
done
grep -qE '(^| )systemd\.show_status=false( |$)' "$BOOT/cmdline.txt" || die "systemd status suppression missing"
grep -qE '(^| )loglevel=3( |$)' "$BOOT/cmdline.txt" || die "kernel log suppression missing"
grep -qE '(^| )vt\.global_cursor_default=0( |$)' "$BOOT/cmdline.txt" || die "VT cursor suppression missing"
for masked in getty@tty1.service plymouth-quit.service \
              plymouth-quit-wait.service userconfig.service; do
    [[ -L "$ROOT/etc/systemd/system/$masked" && "$(readlink "$ROOT/etc/systemd/system/$masked")" == /dev/null ]] \
        || die "healthy-boot VT/onboarding unit is not masked: $masked"
done
assert_factory_sterile "$ROOT" "staged factory image"
[[ ! -e "$ROOT/var/lib/neutronos/recovery/crash-state.json" ]] || die "factory shell crash counter leaked into image"
[[ ! -e "$ROOT/var/lib/neutronos/recovery/safe-mode-next-boot.json" ]] || die "factory safe-mode flag leaked into image"
[[ ! -e "$ROOT/var/lib/neutronos/recovery/next-boot.json" ]] || die "factory recovery flag leaked into image"
[[ "$(systemctl --root="$ROOT" is-enabled userconfig.service 2>/dev/null || true)" == masked ]] \
    || die "stock 'Which user would you like to rename:' onboarding is enabled"
LEGACY_STATE_ALIAS="$ROOT/home/echo/NeutronOS/state"
LEGACY_STATE_RESOLVED="$(realpath -e -- "$LEGACY_STATE_ALIAS" 2>/dev/null || true)"
CANONICAL_STATE_RESOLVED="$(realpath -e -- "$ROOT/var/lib/neutronos" 2>/dev/null || true)"
LEGACY_STATE_INTERNAL="$(chroot "$ROOT" /usr/bin/realpath -e \
    /home/echo/NeutronOS/state 2>/dev/null || true)"
[[ -L "$LEGACY_STATE_ALIAS" && \
   "$LEGACY_STATE_RESOLVED" == "$CANONICAL_STATE_RESOLVED" && \
   "$LEGACY_STATE_INTERNAL" == /var/lib/neutronos && \
   "$LEGACY_STATE_RESOLVED" != "$ROOT/home/echo/NeutronOS" && \
   "$LEGACY_STATE_RESOLVED" != "$ROOT/home/echo/NeutronOS/"* ]] \
    || die "legacy NeutronOS state alias does not resolve outside immutable payload"
for packaged_dir in \
    /home/echo/NeutronOS/qml \
    /home/echo/NeutronOS/themes \
    /home/echo/NeutronOS/themes/Default \
    /home/echo/NeutronOS/themes/Default/apps/icons \
    /home/echo/NeutronOS/themes/Default/apps/posters \
    /home/echo/NeutronOS/themes/Default/users \
    /home/echo/NeutronOS/config \
    /home/echo/NeutronOS/config/app-store/repository; do
    chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/test -r "$packaged_dir" \
        || die "display account cannot read packaged directory: $packaged_dir"
    chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/test -x "$packaged_dir" \
        || die "display account cannot traverse packaged directory: $packaged_dir"
done
for immutable_dir in \
    /home/echo/NeutronOS/qml \
    /home/echo/NeutronOS/themes \
    /home/echo/NeutronOS/config; do
    ! chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/test -w "$immutable_dir" \
        || die "display account can write immutable payload directory: $immutable_dir"
done
chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/test -w /var/lib/neutronos/app-store \
    || die "display account cannot write App Store runtime state"
! find "$ROOT/home/echo/NeutronOS" -xdev \( -type d -o -type f \) -perm /0002 -print -quit | grep -q . \
    || die "immutable NeutronOS payload contains world-writable content"
chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/env -i \
    HOME=/home/echo USER=echo LOGNAME=echo LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    NEUTRONOS_ROOT=/home/echo/NeutronOS /usr/bin/timeout 10 \
    /home/echo/NeutronOS/build/NeutronShell --svg-smoke-test \
    || die "final Qt SVG runtime/atom.svg decode test failed"
NEUTRONSHELL_SMOKE_OUTPUT="$(chroot "$ROOT" /usr/sbin/runuser -u echo -- /usr/bin/env -i \
    HOME=/home/echo USER=echo LOGNAME=echo LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    NEUTRONOS_ROOT=/home/echo/NeutronOS /usr/bin/timeout 75 \
    /home/echo/NeutronOS/build/NeutronShell --smoke-test 2>&1)" \
    || { printf '%s\n' "$NEUTRONSHELL_SMOKE_OUTPUT" >&2; die "final NeutronShell payload/QML destination smoke test failed"; }
printf '%s\n' "$NEUTRONSHELL_SMOKE_OUTPUT"
if grep -Eq 'Permission denied|Failed to create directory|Failed to open|Read-only filesystem|inotify_add_watch\(.*\) failed|AssetManager: failed' \
        <<< "$NEUTRONSHELL_SMOKE_OUTPUT"; then
    die "final NeutronShell smoke reported a filesystem permission error"
fi

# The graphical smoke exercises real writable runtime paths. Reapply factory
# identity state after that final chroot helper, then run the authoritative
# Final factory sterility contract. Nothing below recreates an account/profile.
release_rm var/lib/neutronos/security/users
release_rm var/lib/neutronos/setup/setup.json
assert_factory_sterile "$ROOT" "final staged factory image"

log "Creating release metadata"
if [[ "$GENERATE_SIGNED_UPDATE" == 1 ]]; then
    PAYLOAD_DIR="$WORK/update-payload"; rm -rf "$PAYLOAD_DIR"; mkdir -p "$PAYLOAD_DIR/payload"
    tar -C "$ROOT/home/echo/NeutronOS" -cf - qml themes config scripts services CMakeLists.txt | tar -C "$PAYLOAD_DIR/payload" -xf -
    printf '{"product":"NeutronOS","edition":"Apollo","fullInstall":true,"version":"%s","architecture":"arm64"}\n' "$VERSION" > "$PAYLOAD_DIR/manifest.json"
    tar -C "$PAYLOAD_DIR" -czf "$OUT/NeutronOS-$VERSION-arm64.nosupdate" manifest.json payload
    UPDATE="$OUT/NeutronOS-$VERSION-arm64.nosupdate"
    UPDATE_SHA="$(sha256sum "$UPDATE" | awk '{print $1}')"
    python3 - "$OUT/update-payload.json" "$UPDATE_SHA" "$(stat -c '%s' "$UPDATE")" <<'PY'
import json,sys,datetime
out,sha,size=sys.argv[1:]
json.dump({"product":"NeutronOS","codename":"Apollo","version":"1.0.0-alpha.1","channel":"alpha","architecture":"arm64","artifact":{"url":"NeutronOS-1.0.0-alpha.1-arm64.nosupdate","sha256":sha,"size":int(size)},"releaseNotes":"NeutronOS Apollo Alpha 1","releaseTimestamp":datetime.datetime.now(datetime.timezone.utc).isoformat(),"minimumCompatibleVersion":"1.0.0-alpha.1","minimumUpdaterVersion":"1.0.0","updateFormatVersion":2,"rollbackCompatible":True},open(out,'w'),indent=2,sort_keys=True); open(out,'a').write('\n')
PY
    python3 "$PROJECT/scripts/neutronos-release-sign.py" sign --key "$KEY" --payload "$OUT/update-payload.json" --output "$OUT/neutronos-update-manifest.json" --signature "$OUT/neutronos-update-manifest.json.sig"
    python3 "$PROJECT/scripts/neutronos-release-sign.py" verify --envelope "$OUT/neutronos-update-manifest.json" --public "$ROOT/etc/neutronos/update-public-key"
else
    log "Signed update artifact disabled; no private signing key was accessed"
fi
IMAGE_NAME="$(basename -- "$IMAGE")"
IMAGE_DIR="$(dirname -- "$IMAGE")"
(cd "$IMAGE_DIR" && sha256sum "$IMAGE_NAME") > "$OUT/$IMAGE_NAME.sha256"
printf 'NeutronOS Apollo %s\nArchitecture: arm64\nChannel: alpha\n' "$VERSION" > "$OUT/NeutronOS-Apollo-$VERSION-RELEASE-NOTES.md"

log "Unmounting and final offline checks"
sync
for ((i=${#MOUNTS[@]}-1;i>=0;i--)); do
    umount "${MOUNTS[$i]}" 2>/dev/null || die "could not unmount release resource: ${MOUNTS[$i]}"
done
MOUNTS=()
losetup -d "$LOOP"; LOOP=""
[[ -s "$IMAGE" && -s "$OUT/$IMAGE_NAME.sha256" ]] || die "final artifacts missing"
CHECK_MNT="$WORK/check-mnt"; mkdir -p "$CHECK_MNT"
LOOP="$(losetup --find --show --partscan "$IMAGE")"
mount -o ro "${LOOP}p2" "$CHECK_MNT"; MOUNTS+=("$CHECK_MNT")
[[ -x "$CHECK_MNT/home/echo/NeutronOS/build/NeutronShell" ]] || die "NeutronShell missing from final image"
[[ -d "$CHECK_MNT/home/echo/NeutronOS/qml" ]] || die "QML tree missing from final image"
[[ -f "$CHECK_MNT/etc/neutronos/update-public-key" ]] || die "public update key missing"
grep -q '1.0.0-alpha.1' "$CHECK_MNT/etc/neutronos/version.json" || die "Alpha 1 version missing"
assert_distribution_branding "$CHECK_MNT"
assert_factory_sterile "$CHECK_MNT" "final offline factory image"
[[ ! -e "$CHECK_MNT/home/echo/.codex" && ! -e "$CHECK_MNT/home/echo/NeutronOS/sign key.txt" ]] || die "development state leaked into image"
[[ ! -s "$CHECK_MNT/etc/machine-id" ]] || die "machine-id was not sanitized"
umount "$CHECK_MNT"; MOUNTS=(); losetup -d "$LOOP"; LOOP=""
sfdisk -d "$IMAGE" >/dev/null
log "NeutronOS Apollo $VERSION image build complete: $IMAGE"
