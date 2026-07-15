#!/system/bin/sh
# logcat_cleanup.sh — logcat leak prevention
#
# Detection apps can scan logcat for AlwaysStrong-specific log tags
# or error messages that reveal module internals. This script:
#   1. Suppresses our log tags via persist.log.tag.* props
#   2. Sanitizes ANR/tombstone files by removing only our references

MODDIR="${MODPATH:-$(dirname "$0")}"
LOG_DIR="$MODDIR/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

# Source shared helpers (log_save, find_sed)
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"
find_sed

# --- 1. Suppress our log tags via prop ---
# Some ROMs have persist.log.tag.* props that control per-tag logging.
# 'S' = suppress — logd drops all log messages with this tag before
# they reach the buffer, which is cleaner than post-hoc scrubbing.
resetprop persist.log.tag.AlwaysStrong S
resetprop persist.log.tag.AlwaysStrong-boot S
resetprop persist.log.tag.AlwaysStrong-hourly S
resetprop persist.log.tag.AlwaysStrong-unify S
resetprop persist.log.tag.AlwaysStrong-proc S

# Remove any lingering temp log files from previous runs
rm -f /data/local/tmp/AlwaysStrong*.log 2>/dev/null

# --- 2. Per-tag logcat scrub (no full-buffer clear) ---
# Clearing entire logcat buffers (logcat -c) is itself a detection signal —
# only root can do it, and apps check for "recently cleared logcat".
# Instead, we only remove lines matching our tags using sed via logcat -d.
# The -d flag dumps and exits (non-blocking), safe for periodic use.

scrub_logcat() {
  local changed=0

  # persist.log.tag.* suppression (above) already prevents new logcat lines
  # from our tags. For existing lines in the ring buffer (~64KB per buffer),
  # we let them age out naturally — clearing buffers is itself a detection
  # signal and writing restored lines to /dev/kmsg puts them in dmesg (which
  # some OEMs still expose), creating a second detection vector.
  # Only scrub persistent files: ANR traces and tombstones.

  # ANR traces — remove lines containing our processes (sed, not rm)
  for anr in /data/anr/anr_* /data/anr/traces.txt; do
    [ -f "$anr" ] && {
      grep -q "TEESimulator\|aswatcher\|AlwaysStrong" "$anr" 2>/dev/null && {
        $SED '/TEESimulator\|aswatcher\|AlwaysStrong\|libinject\|libTEESimulator/d' "$anr" 2>/dev/null
        log_save "AlwaysStrong" "sanitized ANR: $anr"
        changed=1
      }
    }
  done

  # Tombstones — remove lines containing our processes (sed, not rm)
  for tomb in /data/tombstones/tombstone_*; do
    [ -f "$tomb" ] && {
      grep -q "TEESimulator\|aswatcher\|AlwaysStrong" "$tomb" 2>/dev/null && {
        $SED '/TEESimulator\|aswatcher\|AlwaysStrong\|libinject\|libTEESimulator/d' "$tomb" 2>/dev/null
        log_save "AlwaysStrong" "sanitized tombstone: $tomb"
        changed=1
      }
    }
  done

  [ "$changed" = 1 ] && log_save "AlwaysStrong" "logcat scrubbed"
}

# --- 3. Periodic scrub daemon ---
{
  while true; do
    scrub_logcat 2>/dev/null
    sleep 1800  # every 30 min
  done
} &

log_save "AlwaysStrong" "logcat cleanup initialized"
