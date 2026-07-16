#!/system/bin/sh
# TieJia — keybox auto-fetch (multi-source).
#
# Sources are tried in priority order until one succeeds:
#   1. Yurikey  (base64)
#   2. Upstream (hex → base64)
#
# Encoding auto-detected per source. XML validated after decode.
# SHA256 dedup against on-disk /data/adb/tricky_store/keybox.xml.
# Atomic replace on update.
#
# Exit codes:
#   0  keybox updated (new content written)
#   2  no change / skipped (custom keybox active, or bundled up-to-date)
#   1  all sources failed (existing keybox preserved)

init_config
TARGET="$CONFIG_DIR/keybox.xml"

log() { echo "keybox_fetch: $*"; }

if [ -f "$CONFIG_DIR/custom_keybox" ]; then
    log "custom keybox active — skipping fetch."
    exit 2
fi

# Use common_func.sh tool resolvers
SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -z "$SELF_DIR" ] && SELF_DIR=/data/adb/modules/tricky_store
[ -f "$SELF_DIR/common_func.sh" ] && . "$SELF_DIR/common_func.sh"

detect_abi
ASFETCH="${ABI_BIN_DIR:-$SELF_DIR/bin}/asfetch"
find_busybox

# ---- fetch engine cascade ----
run_engine() {
    rm -f "$2"
    case "$1" in
        asfetch) [ -n "${ABI_DIR:-}" ] && [ -x "$ASFETCH" ] && "$ASFETCH" -T 10 -o "$2" "$3" 2>/dev/null ;;
        bb)      [ -n "${BB:-}" ] && "$BB" wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
        curl)    command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --max-time 30 -o "$2" "$3" 2>/dev/null ;;
        wget)    command -v wget >/dev/null 2>&1 && wget -q -T 20 -O "$2" "$3" 2>/dev/null ;;
    esac
    [ -s "$2" ]
}

ENGINE_CACHE="$CONFIG_DIR/.kb_engine"
try_fetch() {
    _o="$1"; _u="$2"
    _first=$(cat "$ENGINE_CACHE" 2>/dev/null)
    for _e in "$_first" asfetch bb curl wget; do
        [ -z "$_e" ] && continue
        if run_engine "$_e" "$_o" "$_u"; then
            [ "$_e" != "$_first" ] && echo "$_e" > "$ENGINE_CACHE" 2>/dev/null
            return 0
        fi
    done
    return 1
}

# ---- decoders (use common_func.sh find_tool) ----
B64=$(find_tool base64 base64 "echo dGVzdA==")
SHA256=$(find_tool sha256sum sha256sum "echo x")

pure_shell_hex_decode() {
    _h="$1"
    if command -v xxd >/dev/null 2>&1; then
        echo "$_h" | xxd -r -p 2>/dev/null && return 0
    fi
    _len=${#_h}; _i=0
    while [ "$_i" -lt "$_len" ]; do
        printf "\\x${_h:$_i:2}"; _i=$((_i + 2))
    done
    return 0
}

decode_payload() {
    _in="$1"; _out="$2"; _enc="$3"
    case "$_enc" in
        xml) cp "$_in" "$_out" 2>/dev/null ;;
        b64)  [ -n "$B64" ] && $B64 < "$_in" > "$_out" 2>/dev/null || return 1 ;;
        hex+b64)
            [ -n "$B64" ] || return 1
            _hex=$(tr -cd '0-9A-Fa-f' < "$_in" | tr -d '\n')
            [ -z "$_hex" ] && return 1
            [ $(( ${#_hex} % 2 )) -ne 0 ] && _hex="${_hex%?}"
            pure_shell_hex_decode "$_hex" | $B64 > "$_out" 2>/dev/null
            ;;
        *) return 1 ;;
    esac
    [ -s "$_out" ]
}

validate_keybox() {
    head -c 4096 "$1" 2>/dev/null | grep -qi -e Keybox -e AndroidAttestation
}

# ---- single source attempt ----
try_one_source() {
    __src="$1"; __url="$2"; __enc="$3"
    log "  trying $__src ..."

    try_fetch "$TMP/raw" "$__url" || { log "    $__src: download failed."; return 1; }
    decode_payload "$TMP/raw" "$TMP/keybox.xml" "$__enc" || { log "    $__src: decode failed."; return 1; }
    validate_keybox "$TMP/keybox.xml" || { log "    $__src: not a valid keybox — skipping."; return 1; }

    log "    $__src: valid keybox ($(wc -c < "$TMP/keybox.xml") bytes)."

    [ -n "$SHA256" ] || { log "    no sha256sum."; return 1; }
    NEW_HASH=$($SHA256 < "$TMP/keybox.xml" | { read -r h _; lowercase "$h"; })
    DISK_HASH=""
    [ -s "$TARGET" ] && DISK_HASH=$($SHA256 < "$TARGET" | { read -r h _; lowercase "$h"; })

    if [ -n "$DISK_HASH" ] && [ "$DISK_HASH" = "$NEW_HASH" ]; then
        log "    $__src: already up to date."
        return 2
    fi

    mv -f "$TMP/keybox.xml" "$TARGET" || { log "    mv to $TARGET failed."; return 1; }
    chmod 600 "$TARGET"
    rm -f "$CONFIG_DIR/.keybox.sha256" 2>/dev/null
    log "  => $TARGET updated from $__src ($(wc -c < "$TARGET") bytes)."
    return 0
}

# ---- Main ----
mkdir -p "$CONFIG_DIR"
TMP="$CONFIG_DIR/.keybox_fetch.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

case "${1:-}" in
    yurikey)
        try_one_source "yurikey" "https://raw.githubusercontent.com/Yurii0307/yurikey/main/key" "b64"
        exit $?
        ;;
    upstream)
        try_one_source "upstream" "https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra" "hex+b64"
        exit $?
        ;;
esac

try_one_source "yurikey" "https://raw.githubusercontent.com/Yurii0307/yurikey/main/key" "b64"
_rc=$?; [ $_rc -eq 0 ] || [ $_rc -eq 2 ] && exit $_rc

try_one_source "upstream" "https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra" "hex+b64"
_rc=$?; [ $_rc -eq 0 ] || [ $_rc -eq 2 ] && exit $_rc

log "all sources exhausted — keybox unchanged."
exit 1
