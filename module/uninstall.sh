#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  uninstall.sh
#  零外部依赖：只用 Android 自带的 toybox
#=======================================================================
WORK=/data/adb/mi_thermal
APPLY_DIR=/data/vendor/thermal/config

# 移除所有场景覆写并让 mi_thermald 回到原厂配置
rm -f "$APPLY_DIR"/thermal-*.conf 2>/dev/null
setprop ctl.restart mi_thermald 2>/dev/null

# 解除 CPU / GPU 限频
for p in 0 4 7; do
  f=$(cat /sys/devices/system/cpu/cpufreq/policy${p}/cpuinfo_max_freq 2>/dev/null)
  [ -n "$f" ] && echo "$f" > /sys/devices/system/cpu/cpufreq/policy${p}/scaling_max_freq 2>/dev/null
done
gm=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/hw_max_freq 2>/dev/null)
[ -n "$gm" ] && echo "$gm" > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null

# 解除充电限流
cd=$(ls -d /sys/class/thermal/cooling_device* 2>/dev/null | while read d; do
       [ "$(cat $d/type 2>/dev/null)" = "battery" ] && echo $d && break; done)
[ -n "$cd" ] && echo 0 > "$cd/cur_state" 2>/dev/null

rm -rf "$WORK" 2>/dev/null
