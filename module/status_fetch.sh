#!/system/bin/sh
# Fetch the keybox status (e.g. "🟢🟢🟢") and write to
# /data/adb/tricky_store/indicator.txt (read by WebUI + action.sh).
# No longer touches module.prop — avoids KSU tamper-detection false positives.

URL="https://botkey.netlify.app/status"
CONFIG_DIR=/data/adb/tricky_store
INDICATOR="$CONFIG_DIR/indicator.txt"
TIMEOUT=8

MODPATH="${MODPATH:-/data/adb/modules/tricky_store}"
[ -f "$MODPATH/common_func.sh" ] && . "$MODPATH/common_func.sh"

fetch=$(resolve_fetcher "$TIMEOUT")
[ -z "$fetch" ] && exit 2

new=$($fetch "$URL" 2>/dev/null | tr -d '\r\n' | head -c 64)
[ -z "$new" ] && exit 3

# Only write if changed (avoid unnecessary disk writes)
old=$(cat "$INDICATOR" 2>/dev/null)
[ "$old" = "$new" ] && exit 0

mkdir -p "$CONFIG_DIR"
echo "$new" > "$INDICATOR"

