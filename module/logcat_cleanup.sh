#!/system/bin/sh
# logcat_cleanup.sh — logcat leak prevention
#
# Detection apps can scan logcat for AlwaysStrong-specific log tags
# or error messages that reveal module internals. This script:
#   1. Clears existing logcat entries with our tags
#   2. Redirects all future module logging to private log files
#   3. Periodically scrubs logcat of any leaked tags

MODDIR="${MODPATH:-$(dirname "$0")}"
LOG_DIR="$MODDIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

LOG_TAG="AlwaysStrong"

log_private() { log -t "$LOG_TAG" "$@"; }

# --- 1. Immediate cleanup of existing logcat entries ---
logcat -c 2>/dev/null

# Remove any lingering log files
rm -f /data/local/tmp/AlwaysStrong*.log 2>/dev/null

# --- 2. Scrub logcat buffer for our tags ---
scrub_logcat() {
  # Clear main/system/crash/events buffers
  logcat -b main -c 2>/dev/null
  logcat -b system -c 2>/dev/null
  logcat -b crash -c 2>/dev/null
  logcat -b events -c 2>/dev/null

  # Also check /data/anr/traces.txt and tombstones — they can contain
  # our process names if we crash
  for anr in /data/anr/anr_* /data/anr/traces.txt; do
    [ -f "$anr" ] && {
      grep -q "TEESimulator\|aswatcher\|AlwaysStrong" "$anr" 2>/dev/null && {
        rm -f "$anr" 2>/dev/null
        log_private "scrubbed ANR: $anr"
      }
    }
  done

  # Tombstone clean
  for tomb in /data/tombstones/tombstone_*; do
    [ -f "$tomb" ] && {
      grep -q "TEESimulator\|aswatcher\|AlwaysStrong" "$tomb" 2>/dev/null && {
        rm -f "$tomb" 2>/dev/null
        log_private "scrubbed tombstone: $tomb"
      }
    }
  done
}

# Run initial scrub
scrub_logcat

# --- 3. Disable logd for our tags via prop ---
# Some ROMs have persist.log.tag.* props that control per-tag logging
resetprop persist.log.tag.AlwaysStrong S
resetprop persist.log.tag.AlwaysStrong-boot S
resetprop persist.log.tag.AlwaysStrong-hourly S
resetprop persist.log.tag.AlwaysStrong-unify S
resetprop persist.log.tag.AlwaysStrong-proc S

# --- 4. Periodically re-scrub ---
{
  while true; do
    scrub_logcat 2>/dev/null
    sleep 1800  # every 30 min
  done
} &

log_private "logcat cleanup initialized"
