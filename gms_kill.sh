#!/system/bin/sh
# gms_kill.sh — GMS/DroidGuard 强制停止 + Play Store 缓存清理
# AlwaysStrong v1.3.0
# keybox 更换或 PI 属性变更后，GMS 缓存旧的完整性状态。
# 不杀 GMS 进程的话，App 读 PI 会拿到过期结果（可能仍是失败状态）。

MODDIR="${0%/*}"
[ -f "$MODDIR/common_func.sh" ] && . "$MODDIR/common_func.sh"

log_save "AlwaysStrong: GMS kill started"

# 目标进程列表
TARGET_PKGS="com.google.android.gms com.android.vending"
TARGET_PROCESSES="com.google.android.gms.persistent com.google.android.gms.unstable com.google.android.gms:snet com.google.android.gms.droidguard"

killed_count=0

# ---- 1. 停止目标包 ----
for pkg in $TARGET_PKGS; do
    if pm list packages 2>/dev/null | grep -q "$pkg"; then
        am force-stop "$pkg" 2>/dev/null
        killed_count=$((killed_count + 1))
        log_save "AlwaysStrong: force-stopped $pkg"
    fi
done

# ---- 2. 精确定点杀 DroidGuard 和相关进程 ----
# DroidGuard 是 GMS 中负责 PI 认证的子进程，仅杀它不会影响其他 GMS 功能
for proc in $TARGET_PROCESSES; do
    pid="$(pgrep -f "$proc" 2>/dev/null)"
    if [ -n "$pid" ]; then
        kill -9 $pid 2>/dev/null
        log_save "AlwaysStrong: killed $proc ($pid)"
    fi
done

# ---- 3. 清理 Play Store 数据 ----
# 不清存储（会退出账号），只清缓存
pm clear --cache-only com.android.vending 2>/dev/null
log_save "AlwaysStrong: cleared Play Store cache"

# ---- 4. 清理 GMS 缓存 ----
# 仅清缓存不触发账号退出
pm clear --cache-only com.google.android.gms 2>/dev/null

# ---- 5. 清理 GMS 的 PI 相关 shared_prefs（更精细，不触发全局清理）----
GMS_PREFS="/data/data/com.google.android.gms/shared_prefs"
if [ -d "$GMS_PREFS" ]; then
    # 只清理 integrity 和 droidguard 相关的 prefs，不动其他
    find "$GMS_PREFS" -name "*integrity*" -delete 2>/dev/null
    find "$GMS_PREFS" -name "*droidguard*" -delete 2>/dev/null
    find "$GMS_PREFS" -name "*safetynet*" -delete 2>/dev/null
    find "$GMS_PREFS" -name "*attest*" -delete 2>/dev/null
    log_save "AlwaysStrong: cleaned PI-related GMS prefs"
fi

# ---- 6. 通知 GMS 重新初始化 ----
# 触发 GMS 的 broadcast 让其在下次 PI 请求时重新获取状态
am broadcast -a com.google.android.gms.INITIALIZE -n com.google.android.gms/.chimera.GmsIntentOperationService 2>/dev/null
am broadcast -a com.google.gms.phenotype.FLAG_OVERRIDE 2>/dev/null

# ---- 7. 等待后确认 ----
sleep 2

# 验证 DroidGuard 是否已死
if pgrep -f droidguard >/dev/null 2>&1; then
    log_save "AlwaysStrong: WARNING — DroidGuard still alive after kill"
else
    log_save "AlwaysStrong: DroidGuard terminated successfully"
fi

log_save "AlwaysStrong: GMS kill done ($killed_count packages)"

unset TARGET_PKGS TARGET_PROCESSES GMS_PREFS killed_count pkg proc pid
