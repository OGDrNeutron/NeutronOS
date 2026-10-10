#!/usr/bin/env bash
set -u

EXIT_CODE_PATH="$1"
LOG_PATH="$2"
RUN_USER="$3"
NEUTRON_ROOT="$4"
BROWSER_EXECUTABLE="$5"
shift 5

mkdir -p "$(dirname "$EXIT_CODE_PATH")" "$(dirname "$LOG_PATH")"
: > "$LOG_PATH"

USER_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
[ -n "$USER_HOME" ] || USER_HOME="/home/$RUN_USER"
USER_ID="$(id -u "$RUN_USER")"
RUNTIME_DIR="/run/user/$USER_ID"
CONTROLLER_STATE="$NEUTRON_ROOT/state/apps/browser-controller"
BROWSER_STATE="$NEUTRON_ROOT/state/apps/browser"
BROWSER_PROFILE="$BROWSER_STATE/profile"
BROWSER_CACHE="$BROWSER_STATE/cache"
RUN_GROUP="$(id -gn "$RUN_USER")"

mkdir -p \
    "$RUNTIME_DIR" \
    "$CONTROLLER_STATE" \
    "$BROWSER_PROFILE" \
    "$BROWSER_CACHE" \
    "$USER_HOME/Downloads"

# NeutronShell runs as root and creates BrowserManager's state directories.
# The actual WebEngine process deliberately runs unprivileged, so hand its
# browser-owned profile/cache/session files to that user before launch.
chown -R "$RUN_USER:$RUN_GROUP" \
    "$BROWSER_STATE" \
    "$CONTROLLER_STATE" \
    "$USER_HOME/Downloads" 2>/dev/null || true
chown "$RUN_USER:$RUN_GROUP" "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" "$BROWSER_STATE" "$BROWSER_PROFILE" "$BROWSER_CACHE" 2>/dev/null || true
find "$BROWSER_STATE" -type f -exec chmod 600 {} + 2>/dev/null || true

printf 'Browser runtime user: %s (%s)\n' "$RUN_USER" "$USER_ID" >>"$LOG_PATH"
printf 'Browser profile: %s\n' "$BROWSER_PROFILE" >>"$LOG_PATH"
printf 'Browser cache: %s\n' "$BROWSER_CACHE" >>"$LOG_PATH"

set +e
runuser -u "$RUN_USER" -- env \
    HOME="$USER_HOME" \
    USER="$RUN_USER" \
    LOGNAME="$RUN_USER" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    XDG_SESSION_TYPE=tty \
    QT_QPA_PLATFORM=eglfs \
    QT_QPA_EGLFS_HIDECURSOR=1 \
    QT_QPA_EGLFS_ALWAYS_SET_MODE=1 \
    QT_QUICK_CONTROLS_STYLE=Basic \
    QML_DISABLE_DISK_CACHE=1 \
    NEUTRONOS_ROOT="$NEUTRON_ROOT" \
    NEUTRONOS_STATE_DIR="$CONTROLLER_STATE" \
    QTWEBENGINE_CHROMIUM_FLAGS="--process-per-site --disable-features=Translate,AutofillServerCommunication" \
    "$BROWSER_EXECUTABLE" "$@" >>"$LOG_PATH" 2>&1
CODE=$?
printf '%s\n' "$CODE" > "$EXIT_CODE_PATH"
chmod 600 "$EXIT_CODE_PATH" 2>/dev/null || true
exit 0
