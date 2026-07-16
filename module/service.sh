#!/system/bin/sh
# TieJia v2.0.0 — Parallel boot pipeline
# ============================================================================
# Phase 0 (synchronous):     conflict_scan, dmesg, recovery, selinux — ~0.1s
# Phase 1 (post-boot):      single coordinator waits boot_completed once,
#                            then launches all daemons in parallel groups.
# Phase 2 (bootstrap):      one-shot first-boot init (keybox + pif + config).
# Phase 3 (hourly):         perpetual refresh loop (fingerprint + keybox).
# ============================================================================

MODDIR="${0%/*}"
MODPATH="$MODDIR"
cd "$MODDIR"

set +o standalone 2>/dev/null
unset ASH_STANDALONE

[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"
find_sed

# --- ReZygisk: service trigger for Zygisk modules ---
if [ "$ZYGISK_ENABLED" ]; then
  sed -i "s|^description=|description=[Disable Magisk's built-in Zygisk] |" "$MODDIR/module.prop"
else
  if [ "$(which magisk)" ]; then
    for file in "$MODDIR"/../*; do
      if [ -d "$file" ] && [ -d "$file/zygisk" ] && ! [ -f "$file/disable" ]; then
        if [ -f "$file/service.sh" ]; then
          cd "$file"
          log -p i -t "zygisk-sh" "Manually trigger service.sh for $file"
          sh "$(realpath ./service.sh)" &
          cd "$MODDIR"
        fi
      fi
    done
  fi
fi

# PID tracking for background daemons spawned by this script.
PID_FILE="$MODDIR/.tiejia_bg_pids"
: > "$PID_FILE" 2>/dev/null

track_bg() {
  local _pid=$!
  [ "${_pid:-0}" -gt 0 ] 2>/dev/null && echo "$_pid" >> "$PID_FILE" 2>/dev/null
  return 0
}

init_config

# ============================================================================
# PHASE 0 — Synchronous (no dependency on boot_completed)
# ============================================================================
tiejia_phase0() {
    if [ -x "$MODDIR/logcat_cleanup.sh" ]; then
        sh "$MODDIR/logcat_cleanup.sh" >/dev/null 2>&1 &
        track_bg
    fi

    if [ -w /proc/sys/kernel/dmesg_restrict ]; then
        echo 1 > /proc/sys/kernel/dmesg_restrict 2>/dev/null
    fi

    resetprop_if_match ro.boot.mode recovery unknown
    resetprop_if_match ro.bootmode recovery unknown
    resetprop_if_match ro.boot.bootmode recovery unknown
    resetprop_if_match vendor.boot.mode recovery unknown
    resetprop_if_match vendor.boot.bootmode recovery unknown

    resetprop_if_diff ro.boot.selinux enforcing
    if ! ${SKIPDELPROP:-false}; then
        delprop_if_exist ro.build.selinux 2>/dev/null || true
    fi
    if [ "$(toybox cat /sys/fs/selinux/enforce 2>/dev/null)" = "0" ]; then
        chmod 640 /sys/fs/selinux/enforce
        chmod 440 /sys/fs/selinux/policy
    fi

    if [ -x "$MODDIR/conflict_scan.sh" ]; then
        MODPATH="$MODDIR" sh "$MODDIR/conflict_scan.sh" >/dev/null 2>&1
        n=$?
        [ "$n" -gt 0 ] && log_save "TieJia" "disabled $n conflicting module(s) at boot"
    fi
}
tiejia_phase0

# ============================================================================
# PHASE 1 — Post-boot coordinator
# ============================================================================

# Apply late-boot security properties. Must run before daemons.
tiejia_apply_boot_props() {
    resetprop_if_diff ro.secureboot.lockstate locked
    resetprop_if_diff ro.boot.flash.locked 1
    resetprop_if_diff ro.boot.realme.lockstate 1
    resetprop_if_diff ro.boot.vbmeta.device_state locked
    resetprop_if_diff vendor.boot.verifiedbootstate green
    resetprop_if_diff ro.boot.verifiedbootstate green
    resetprop_if_diff ro.boot.veritymode enforcing
    resetprop_if_diff vendor.boot.veritymode enforcing
    resetprop_if_diff vendor.boot.vbmeta.device_state locked
    if config_get_bool "daemon_oem_unlock_hide" 1; then
        resetprop_if_diff sys.oem_unlock_allowed 0
    fi
    resetprop_if_diff ro.boot.warranty_bit 0
    resetprop_if_diff ro.warranty_bit 0
    resetprop_if_diff ro.secure 1
    resetprop_if_diff ro.adb.secure 1
    resetprop_if_diff service.adb.root 0
    resetprop_if_diff ro.boot.vbmeta.invalidate_on_error yes

    delprop_if_exist persist.sys.usb.config 2>/dev/null || true
    delprop_if_exist persist.sys.usb.ffs.ready 2>/dev/null || true
    delprop_if_exist persist.vendor.usb.config 2>/dev/null || true
    delprop_if_exist persist.usb.config 2>/dev/null || true
    resetprop_if_diff sys.usb.state "mtp"
    resetprop_if_diff sys.usb.config "mtp"
    resetprop_if_diff init.svc.adbd "stopped"
    resetprop_if_diff persist.adb.enable 0
    resetprop_if_diff persist.sys.usb.config "mtp"
    resetprop_if_diff persist.vendor.usb.config "mtp"
    setprop ctl.stop adbd 2>/dev/null || true

    delprop_if_exist persist.logd.logpersistd 2>/dev/null || true
    delprop_if_exist persist.logd.logpersistd.enable 2>/dev/null || true
    resetprop_if_diff ro.force.debuggable 0
    resetprop_if_diff ro.build.type "user"
    resetprop_if_diff ro.build.tags "release-keys"
    resetprop_if_diff ro.build.selinux "1"
    resetprop_if_diff persist.sys.dalvik.vm.lib.2 "libart.so"
    resetprop_if_diff dalvik.vm.dex2oat-filter "speed"
    resetprop_if_diff dalvik.vm.image-dex2oat-filter "speed"
    delprop_if_exist ro.monkey 2>/dev/null || true
    delprop_if_exist ro.boot.monkey 2>/dev/null || true
    delprop_if_exist ro.build.user 2>/dev/null || true
    delprop_if_exist ro.build.host 2>/dev/null || true

    # LineageOS prop scrub
    LV=$(getprop ro.product.vendor.name 2>/dev/null)
    case "$LV" in
        lineage_*) resetprop -n ro.product.vendor.name "${LV#lineage_}" ;;
    esac
    for LP in vendor.camera.aux.packagelist persist.vendor.camera.privapp.list; do
        LCV=$(getprop "$LP" 2>/dev/null)
        case "$LCV" in
            *org.lineageos.aperture*)
                LCV=$(echo "$LCV" | sed -e 's/,org\.lineageos\.aperture//g' \
                                        -e 's/org\.lineageos\.aperture,//g' \
                                        -e 's/^org\.lineageos\.aperture$//')
                resetprop -n "$LP" "$LCV"
                ;;
        esac
    done
    if [ -n "$(getprop init.svc.vendor.lineage_health 2>/dev/null)" ]; then
        stop vendor.lineage_health 2>/dev/null
        resetprop --delete init.svc.vendor.lineage_health 2>/dev/null
    fi

    settings put global development_settings_enabled 0 2>/dev/null || true
}

tiejia_dm_fallback() {
    # Boot hash (bg)
    if [ -x "$MODDIR/boot_hash.sh" ]; then
        MODPATH="$MODDIR" sh "$MODDIR/boot_hash.sh" >/dev/null 2>&1 &
        track_bg
    fi
    # TEE supervisor + daemon
    "$MODDIR/supervisor" "$MODDIR/daemon" "$MODDIR" &
    track_bg

    # ASA watcher with ABI detection
    local AS_ABI
    case "$(uname -m)" in
        aarch64)       AS_ABI=arm64-v8a ;;
        armv7*|armv8l) AS_ABI=armeabi-v7a ;;
        x86_64)        AS_ABI=x86_64 ;;
        i?86)          AS_ABI=x86 ;;
    esac
    local AS_BIN="$MODDIR/bin/$AS_ABI/aswatcher"
    if [ -x "$AS_BIN" ]; then
        { sleep 5; "$AS_BIN" & track_bg; } &
    fi

    # Recovery directory housekeeping
    { sleep 3
      for rdir in TWRP Fox OrangeFox PBRP PitchBlack Recovery; do
          target="/sdcard/$rdir"
          if [ -d "$target" ] && [ "$(ls -A "$target" 2>/dev/null)" ]; then
              mv "$target" "/data/adb/.recovery_backup_${rdir}" 2>/dev/null
          elif [ -d "$target" ]; then
              rmdir "$target" 2>/dev/null
          fi
      done
      rm -f /sdcard/.twrps 2>/dev/null
    } &

    # Staggered background subshells
    if [ -x "$MODDIR/proc_obfuscate.sh" ]; then
        { sleep 10; MODPATH="$MODDIR" sh "$MODDIR/proc_obfuscate.sh" >/dev/null 2>&1 & track_bg; } &
    fi
    if [ -x "$MODDIR/mount_isolation.sh" ]; then
        { sleep 30; MODPATH="$MODDIR" sh "$MODDIR/mount_isolation.sh" >/dev/null 2>&1 & track_bg; } &
    fi
    if [ -x "$MODDIR/prop_unify.sh" ] && config_get_bool "daemon_prop_unify" 1; then
        { sleep 40; MODPATH="$MODDIR" sh "$MODDIR/prop_unify.sh" >/dev/null 2>&1 & track_bg; } &
    fi
    if [ -x "$MODDIR/vbmeta_spoof.sh" ] && config_get_bool "daemon_vbmeta_spoof" 1; then
        { sleep 40; MODPATH="$MODDIR" sh "$MODDIR/vbmeta_spoof.sh" >/dev/null 2>&1 & track_bg; } &
    fi

    # Watchdog
    { local wABI wAS
      case "$(uname -m)" in
          aarch64) wABI=arm64-v8a ;; armv7*|armv8l) wABI=armeabi-v7a ;;
          x86_64) wABI=x86_64 ;; i?86) wABI=x86 ;;
      esac
      wAS="$MODDIR/bin/$wABI/aswatcher"
      while true; do
          sleep 120
          if ! pidof TEESimulator >/dev/null 2>&1 && ! pidof daemon >/dev/null 2>&1; then
              log_save "TieJia" "TEE daemon died, restarting..."
              "$MODDIR/supervisor" "$MODDIR/daemon" "$MODDIR" &
          fi
          if [ -x "$wAS" ] && ! pidof aswatcher >/dev/null 2>&1; then
              log_save "TieJia" "aswatcher died, restarting..."
              "$wAS" &
          fi
      done
    } &
}

tiejia_phase1() {
    until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 1; done
    tiejia_apply_boot_props

    if [ -x "$MODDIR/rom_fp_cleanup.sh" ]; then
        MODPATH="$MODDIR" sh "$MODDIR/rom_fp_cleanup.sh" >/dev/null 2>&1 &
        track_bg
    fi
    if [ -x "$MODDIR/boot_state_props.sh" ]; then
        MODPATH="$MODDIR" sh "$MODDIR/boot_state_props.sh" >/dev/null 2>&1 &
        track_bg
    fi

    DM_BIN="$MODDIR/bin/$(uname -m | sed 's/aarch64/arm64-v8a/;s/armv7.*/armeabi-v7a/;s/x86_64/x86_64/;s/i.86/x86/')/daemon_manager"
    if [ -x "$DM_BIN" ]; then
        "$DM_BIN" "$MODDIR" "$MODDIR/daemon_manager.log" &
        track_bg
        log_save "TieJia" "daemon manager started"
    else
        log_save "TieJia" "daemon_manager not found, using fallback coordinator"
        tiejia_dm_fallback
    fi
}
tiejia_phase1 &

# Hot reload monitor
if config_get_bool "daemon_hot_reload" 1; then
{
    RELOAD_FILE="$CONFIG_DIR/.reload"
    LAST_MTIME=0
    i=0; while [ ! -f "$CONFIG_DIR/.bootstrapped" ] && [ $i -lt 120 ]; do sleep 1; i=$((i+1)); done
    while true; do
        sleep 5
        if [ -f "$RELOAD_FILE" ]; then
            CUR_MTIME=$(stat -c %Y "$RELOAD_FILE" 2>/dev/null || stat -t "$RELOAD_FILE" 2>/dev/null | grep -oE '[0-9]+' | head -1)
            [ -z "$CUR_MTIME" ] && continue
            if [ "$CUR_MTIME" != "$LAST_MTIME" ]; then
                LAST_MTIME="$CUR_MTIME"
                log_save "TieJia-reload" "hot reload triggered"
                [ -x "$MODDIR/prop_unify.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/prop_unify.sh" >/dev/null 2>&1
                [ -x "$MODDIR/vbmeta_spoof.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/vbmeta_spoof.sh" >/dev/null 2>&1
                log_save "TieJia-reload" "hot reload complete"
            fi
        fi
    done
} &
fi

# ============================================================================
# PHASE 2 — First-boot bootstrap (one-shot per module install)
# ============================================================================
tiejia_phase2_bootstrap() {
    sleep 20
    j=0
    until ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; do
        j=$((j+1)); [ $j -gt 30 ] && break
        sleep 2
    done
    log_save "TieJia-boot" "first boot: starting bootstrap"

    if [ -x "$MODDIR/keybox_fetch.sh" ]; then
        sh "$MODDIR/keybox_fetch.sh" 2>&1 | log -t "TieJia-boot"
        [ -x "$MODDIR/keybox_rotate.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/keybox_rotate.sh" 2>&1 | log -t "TieJia-boot"
    fi

    if [ -x "$MODDIR/pif_native_fetch.sh" ]; then
        sh "$MODDIR/pif_native_fetch.sh" -s -m 2>&1 | log -t "TieJia-boot"
    fi
    [ -f "$MODDIR/sync_patch.sh" ] && sh "$MODDIR/sync_patch.sh" 2>&1 | log -t "TieJia-boot"
    [ -x "$MODDIR/prop_unify.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/prop_unify.sh" 2>&1 | log -t "TieJia-unify"
    [ -x "$MODDIR/vbmeta_spoof.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/vbmeta_spoof.sh" 2>&1 | log -t "TieJia-vbmeta"
    [ -x "$MODDIR/target_cleanup.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/target_cleanup.sh" 2>&1 | log -t "TieJia-boot"

    for CPIF in /data/adb/tricky_store/custom.pif.prop /data/adb/tricky_store/pif.prop; do
        [ -f "$CPIF" ] || continue
        for kv in $SPOOF_SETTINGS; do
            k="${kv%=*}"; v="${kv#*=}"
            if grep -qE "^${k}=" "$CPIF"; then
                $SED "s|^${k}=.*|${k}=${v}|" "$CPIF"
            else
                echo "${k}=${v}" >> "$CPIF"
            fi
        done
        log_save "TieJia-boot" "STRONG enforced on $CPIF"
    done

    killall -9 com.google.android.gms.unstable 2>/dev/null
    killall -9 com.android.vending 2>/dev/null

    config_migrate
    touch "$CONFIG_DIR/.bootstrapped"
    log_save "TieJia-boot" "bootstrap done"
}

if [ ! -f "$CONFIG_DIR/.bootstrapped" ]; then
    { tiejia_phase2_bootstrap; } &
fi

# ============================================================================
# PHASE 3 — Hourly refresh loop (perpetual, config-driven)
# ============================================================================
tiejia_phase3_hourly() {
    export MODPATH="$MODDIR"
    i=0; while [ ! -f "$CONFIG_DIR/.bootstrapped" ] && [ $i -lt 120 ]; do sleep 1; i=$((i+1)); done
    i=0; while [ ! -f "$CONFIG_DIR/device.conf" ] && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done

    while true; do
        INT=$(config_get fp_interval 3600)
        case "$INT" in ''|*[!0-9]*) INT=3600 ;; esac
        [ "$INT" -lt 60 ] && INT=60
        sleep "$INT"

        if config_get_bool fp_auto && [ -x "$MODDIR/pif_native_fetch.sh" ]; then
            ( sh "$MODDIR/pif_native_fetch.sh" -s -m 2>&1 | log -t "TieJia-hourly"
              [ -f "$MODDIR/sync_patch.sh" ] && sh "$MODDIR/sync_patch.sh" 2>&1 | log -t "TieJia-hourly"
              [ -x "$MODDIR/prop_unify.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/prop_unify.sh" 2>&1 | log -t "TieJia-unify"
              [ -x "$MODDIR/vbmeta_spoof.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/vbmeta_spoof.sh" 2>&1 | log -t "TieJia-vbmeta"
            ) &
        fi
        if config_get_bool kb_auto && [ -x "$MODDIR/keybox_fetch.sh" ]; then
            ( kbout=$(sh "$MODDIR/keybox_fetch.sh" 2>&1)
              kbrc=$?
              [ -n "$kbout" ] && echo "$kbout" | log -t "TieJia-hourly"
              if [ "$kbrc" = "0" ]; then
                  [ -x "$MODDIR/keybox_rotate.sh" ] && MODPATH="$MODDIR" sh "$MODDIR/keybox_rotate.sh" 2>&1 | log -t "TieJia-hourly"
                  log_save "TieJia-hourly" "keybox updated, restarting PI"
                  killall -9 com.google.android.gms.unstable 2>/dev/null
                  killall -9 com.android.vending 2>/dev/null
              fi
            ) &
        fi
        wait

        if [ -x "$MODDIR/target_cleanup.sh" ]; then
            LAST_CLEAN=$(cat "$CONFIG_DIR/.last_target_cleanup" 2>/dev/null)
            NOW=$(date +%s)
            if [ -z "$LAST_CLEAN" ] || [ $((NOW - LAST_CLEAN)) -gt 21600 ]; then
                MODPATH="$MODDIR" sh "$MODDIR/target_cleanup.sh" >/dev/null 2>&1
                echo "$NOW" > "$CONFIG_DIR/.last_target_cleanup" 2>/dev/null
            fi
        fi
        if [ -x "$MODDIR/status_fetch.sh" ]; then
            sh "$MODDIR/status_fetch.sh" 2>&1 | log -t "TieJia-hourly"
        fi
        if [ -x "$MODDIR/status_json.sh" ]; then
            sh "$MODDIR/status_json.sh" 2>&1 | log -t "TieJia-hourly"
        fi
    done
}
{
    track_bg
    tiejia_phase3_hourly
} &
