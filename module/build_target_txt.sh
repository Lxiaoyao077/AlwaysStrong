#!/system/bin/sh
# Build /data/adb/tricky_store/target.txt from all installed packages. — TieJia v2.0.0
#
# Modes (set via --mode or /data/adb/tricky_store/target_mode):
#   auto       – user/OEM apps get no suffix; GMS/GSF/Vending get `!` (default)
#   force      – ALL packages get `!` suffix (hardware keybox for everything)
#   certchain  – ALL packages get `?` suffix (modified cert chain)
#
# Usage:
#   sh build_target_txt.sh [--mode auto|force|certchain] [output_path]

SELF_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)"
. "$SELF_DIR/common_func.sh"
init_config

TRICKY_DIR="$CONFIG_DIR"

# Two-pass arg parse: extract --mode first, remainder is output_path.
MODE="auto"
TGT="${TRICKY_DIR}/target.txt"
has_explicit_mode=0
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                has_explicit_mode=1
                shift
                if [ $# -gt 0 ]; then
                    case "$1" in
                        auto|force|certchain) MODE="$1"; shift ;;
                        *) shift ;;
                    esac
                fi
                ;;
            *)
                TGT="$1"
                shift
                ;;
        esac
    done
}
parse_args "$@"

# Persisted config file overrides default (only if --mode not explicitly given)
if [ "$has_explicit_mode" -eq 0 ] && [ -f "${TRICKY_DIR}/target_mode" ]; then
    CFG_MODE=$(tr -d '\r' < "${TRICKY_DIR}/target_mode" 2>/dev/null)
    case "$CFG_MODE" in
        auto|force|certchain) MODE="$CFG_MODE" ;;
    esac
fi

case "$MODE" in
    force)     SUFFIX="!" ;;
    certchain) SUFFIX="?" ;;
    *)         SUFFIX=""  ;;
esac

pm list packages >/dev/null 2>&1 || exit 1

ALL=$(pm list packages 2>/dev/null | sed 's/^package://')

OEM_LIST="
com.samsung.android.spay
com.samsung.android.samsungpay.gear
com.samsung.android.spaytui
com.samsung.android.app.spage
com.sec.android.app.samsungapps
com.huawei.wallet
com.huawei.android.hwpay
com.miui.securitycenter
com.xiaomi.market
com.oneplus.opbackup
com.oplus.wallet
com.google.android.apps.walletnfcrel
com.google.android.apps.nbu.paisa.user
com.oplus.deepthinker
com.heytap.speechassist
com.coloros.sceneservice
"

FORCED_LIST="
com.android.vending
com.google.android.gms
com.google.android.gsf
"

is_installed() { printf '%s\n' "$ALL" | grep -Fxq "$1"; }

{
    pm list packages -3 2>/dev/null \
        | sed 's/^package://' \
        | grep -Fxv -e com.android.vending \
                    -e com.google.android.gms \
                    -e com.google.android.gsf

    for p in $OEM_LIST; do
        is_installed "$p" && printf '%s\n' "$p"
    done

    for p in $FORCED_LIST; do
        if is_installed "$p"; then
            if [ -n "$SUFFIX" ] && [ "$MODE" != "auto" ]; then
                printf '%s%s\n' "$p" "$SUFFIX"
            else
                printf '%s!\n' "$p"
            fi
        fi
    done
} | while read -r pkg; do
    [ -z "$pkg" ] && continue
    case "$pkg" in *.*) ;; *) continue ;; esac
    case "$pkg" in
        *[?!]) printf '%s\n' "$pkg" ;;
        *)
            if [ "$MODE" = "force" ] || [ "$MODE" = "certchain" ]; then
                printf '%s%s\n' "$pkg" "$SUFFIX"
            else
                printf '%s\n' "$pkg"
            fi
            ;;
    esac
done | sort -u > "${TGT}.tmp" && mv -f "${TGT}.tmp" "$TGT"

mkdir -p "$TRICKY_DIR" 2>/dev/null
printf '%s\n' "$MODE" > "${TRICKY_DIR}/target_mode" 2>/dev/null
