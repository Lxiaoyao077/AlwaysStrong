#!/system/bin/sh
# adb_harden.sh — ADB/调试开关 + Recovery 残留清理
# AlwaysStrong v1.3.0
# 关闭 USB 调试选项，清理 Recovery 残留目录，减少可检测攻击面

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_save "AlwaysStrong: ADB hardening started"

# 1. 关闭 USB 调试
settings put global adb_enabled 0 2>/dev/null
settings put global development_settings_enabled 0 2>/dev/null

# 2. 关闭无线调试
settings put global adb_wifi_enabled 0 2>/dev/null

# 3. 关闭 OEM 解锁开关
settings put global oem_unlock_enabled 0 2>/dev/null

# 4. 关闭安装未知来源（增强安全性）
settings put secure install_non_market_apps 0 2>/dev/null

# 5. 停止 adbd 服务
setprop ctl.stop adbd 2>/dev/null
stop adbd 2>/dev/null

# 6. 重置 USB 默认配置
resetprop persist.sys.usb.config none 2>/dev/null || true
resetprop sys.usb.config none 2>/dev/null || true
resetprop sys.usb.state none 2>/dev/null || true

# 7. 清理 Recovery 残留目录
RECOVERY_DIRS="
/sdcard/TWRP
/storage/emulated/0/TWRP
/data/media/0/TWRP
/sdcard/Fox
/data/media/0/Fox
/sdcard/OrangeFox
/storage/emulated/0/OrangeFox
/sdcard/PBRP
/data/media/0/PBRP
/cache/recovery
/data/cache/recovery
"

for rdir in $RECOVERY_DIRS; do
    if [ -d "$rdir" ]; then
        rm -rf "$rdir" 2>/dev/null
        log_save "AlwaysStrong: removed recovery dir $rdir"
    fi
done

# 8. 清理常见 recovery 日志/标记文件
RECOVERY_FILES="
/cache/recovery/log
/cache/recovery/last_log
/cache/recovery/last_locale
/cache/recovery/command
/data/cache/recovery/log
/data/cache/recovery/last_log
"

for rfile in $RECOVERY_FILES; do
    if [ -f "$rfile" ]; then
        rm -f "$rfile" 2>/dev/null
    fi
done

# 9. 禁用 bugreport/bugreportz（避免生成可被检测的系统快照）
settings put global bugreport_in_power_menu 0 2>/dev/null

# 10. 强制 SEAndroid Enforcing
current_enforce="$(getenforce 2>/dev/null)"
if [ "$current_enforce" != "Enforcing" ]; then
    setenforce 1 2>/dev/null
    log_save "AlwaysStrong: set SELinux enforcing"
fi

log_save "AlwaysStrong: ADB hardening done"

unset RECOVERY_DIRS RECOVERY_FILES rdir rfile current_enforce
