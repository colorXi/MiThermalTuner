#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  post-fs-data.sh
#  开机早期：准备目录、确保 mi_thermald 配置覆写目录存在
#  零外部依赖：只用 Android 自带的 toybox
#=======================================================================
MODDIR=/data/adb/modules/mi_thermal_tuner
WORK=/data/adb/mi_thermal

mkdir -p "$WORK" "$WORK/plain" "$WORK/cipher"
mkdir -p /data/vendor/thermal/config 2>/dev/null
chmod 771 /data/vendor/thermal/config 2>/dev/null
