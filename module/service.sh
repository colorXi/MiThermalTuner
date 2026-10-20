#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  service.sh (late_start service)
#  启动后台温控监控守护进程，并周期性重放实时覆写
#=======================================================================
MODDIR=/data/adb/modules/mi_thermal_tuner
WORK=/data/adb/mi_thermal

mkdir -p "$WORK"

# 首次运行时安装图形界面 App (如果还没装)
APK=$MODDIR/app/MiThermal.apk
if [ -f "$APK" ]; then
  if ! pm list packages 2>/dev/null | grep -q com.opencode.mithermal; then
    pm install -r "$APK" >/dev/null 2>&1
  fi
fi

# 等待系统启动完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 5
done
sleep 20

# 首次运行时解密所有场景配置 (放到后台, 不阻塞监控启动)
if [ ! -s "$WORK/plain/thermal-normal.conf" ]; then
  $MODDIR/bin/mt decrypt >/dev/null 2>&1 &
fi

# 重放上一次会话留下的实时覆写
. $MODDIR/lib/common.sh
mt_ovr_reapply

# 后台监控循环
exec $MODDIR/bin/mt daemon 5
