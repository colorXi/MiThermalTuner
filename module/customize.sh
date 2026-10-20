#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  customize.sh (Magisk 安装脚本)
#=======================================================================
SKIPUNZIP=0
BB=/data/adb/magisk/busybox
MODDIR=/data/adb/modules/mi_thermal_tuner
WORK=/data/adb/mi_thermal

ui_print " "
ui_print "  MiThermal Tuner  安装中..."
ui_print "  ------------------------------------"

# ---- 环境检查 -----------------------------------------------------------
if [ ! -f /vendor/bin/mi_thermald ]; then
  abort "! 未找到 mi_thermald，本模块只适用于搭载小米温控守护进程的小米设备"
fi

if ! $BB awk 'BEGIN{ exit !(xor(1,2)==3) }' 2>/dev/null; then
  abort "! busybox awk 缺少 xor() 运算支持，无法使用 AES 加解密"
fi

for f in bin/mt bin/mtaes.awk bin/mtdec.awk lib/common.sh lib/monitor.sh; do
  [ -f "$MODPATH/$f" ] || abort "! 模块文件缺失: $f"
done

chmod 755 "$MODPATH/bin/mt" "$MODPATH/service.sh" "$MODPATH/post-fs-data.sh" \
           "$MODPATH/uninstall.sh" "$MODPATH/customize.sh" 2>/dev/null
chmod 644 "$MODPATH/bin/mtaes.awk" "$MODPATH/bin/mtdec.awk" \
           "$MODPATH/lib/common.sh" "$MODPATH/lib/monitor.sh" "$MODPATH/module.prop" 2>/dev/null

mkdir -p "$WORK" "$WORK/plain" "$WORK/cipher"
mkdir -p /data/vendor/thermal/config 2>/dev/null
chmod 771 /data/vendor/thermal/config 2>/dev/null

# ---- 解密全部场景配置（验证 AES 实现正确性） -----------------------------
ui_print "  正在解密场景配置..."
_ok=0; _bad=""
for s in $(ls /vendor/etc/thermal-*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null); do
  if $MODPATH/bin/mt show "$s" >/dev/null 2>&1; then
    _ok=$((_ok+1))
  else
    _bad="$bad $s"
  fi
done
ui_print "  解密成功: $_ok 个场景"
[ -n "$_bad" ] && ui_print "  失败:$_bad"

# ---- 安装图形界面 App ---------------------------------------------------
if [ -f "$MODPATH/app/MiThermal.apk" ]; then
  ui_print "  正在安装温控面板 App..."
  if pm install -r "$MODPATH/app/MiThermal.apk" >/dev/null 2>&1; then
    ui_print "  App 安装完成 (首次打开请授予 Root 权限)"
  else
    ui_print "  ! App 安装失败, 可手动安装: $MODPATH/app/MiThermal.apk"
  fi
fi

ui_print "  ------------------------------------"
ui_print "  图形界面: 桌面图标 '温控面板'"
ui_print "  命令行 (adb shell su):"
ui_print "    mt status                 实时温控状态快照"
ui_print "    mt watch                  前台实时监控"
ui_print "    mt scenarios              列出场景"
ui_print "    mt show thermal-normal.conf   查看某场景明文配置"
ui_print "    mt profile list           列出预设 (cool/mild/unlock/game)"
ui_print "    mt profile apply unlock   应用预设"
ui_print "    mt restore                恢复原厂"
ui_print "    mt cap cpu 4 1516800      限制大核上限"
ui_print "    mt cap gpu 315000000      限制 GPU 上限"
ui_print "  日志: /data/adb/mi_thermal/monitor.log"
ui_print " "
