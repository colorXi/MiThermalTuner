#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  post-fs-data.sh
#  开机早期：准备目录、确保 mi_thermald 配置覆写目录存在
#=======================================================================
MODDIR=/data/adb/modules/mi_thermal_tuner
WORK=/data/adb/mi_thermal
BB=/data/adb/magisk/busybox

mkdir -p "$WORK" "$WORK/plain" "$WORK/cipher"
mkdir -p /data/vendor/thermal/config 2>/dev/null
chmod 771 /data/vendor/thermal/config 2>/dev/null

# 确认 awk 可用（busybox awk 提供 xor/lshift，toybox awk 不支持）
if ! $BB awk 'BEGIN{ exit !(xor(1,2)==3) }' 2>/dev/null; then
  echo "MiThermalTuner: busybox awk 缺少 xor()，AES 功能不可用" > $WORK/error.txt
fi
