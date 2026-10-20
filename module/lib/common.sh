#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  common library
#
#  零外部依赖: 只用 Android 自带的 toybox (awk / od / sed / grep ...)。
#  不依赖 Magisk busybox, 所以 Magisk / KernelSU / APatch 都能用,
#  也不需要在模块里塞一个 busybox。
#=======================================================================

MODDIR=${MODDIR:-/data/adb/modules/mi_thermal_tuner}
WORK=/data/adb/mi_thermal
PLAIN_DIR=$WORK/plain
CIPHER_DIR=$WORK/cipher
LOGFILE=$WORK/monitor.log
OVERRIDE_FILE=$WORK/overrides.env
APPLY_DIR=/data/vendor/thermal/config
VENDOR_CONF=/vendor/etc
THERMALD_DUMP=/data/vendor/thermal/thermal.dump
THERMALD_LIVE=/data/vendor/thermal/decrypt.txt

# ---- 工具解析 -------------------------------------------------------------
# awk: AES 是纯算术实现, toybox / busybox / gawk 都能跑
AWK=${AWK:-awk}
# xxd: Android 9+ 自带; 没有就用 od + awk 的 printf "%c" 兜底
if [ -z "$XXD" ]; then
  if [ -x /system/bin/xxd ] || command -v xxd >/dev/null 2>&1; then
    XXD="xxd"
  else
    XXD=""
  fi
fi

# 二进制文件 -> 十六进制文本 (单行, 无空白)
mt_hex_of() {
  if [ -n "$XXD" ]; then
    $XXD -p "$1" 2>/dev/null | tr -d ' \n'
  else
    od -An -v -tx1 "$1" 2>/dev/null | tr -d ' \n'
  fi
}

# 十六进制文本 (stdin) -> 二进制 (stdout)
mt_bin_of() {
  if [ -n "$XXD" ]; then
    tr -d ' \n' | $XXD -r -p 2>/dev/null
  else
    tr -d ' \n' | $AWK '{
      h = $0
      gsub(/[^0-9a-fA-F]/, "", h)
      for (i = 1; i <= length(h); i += 2) {
        a = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
        b = index("0123456789abcdef", tolower(substr(h, i + 1, 1))) - 1
        printf "%c", a * 16 + b
      }
    }'
  fi
}

# ---- known scenario name -> friendly label -------------------------------
scenario_label() {
  case "$1" in
    thermal-normal.conf)      echo "日常 (normal)" ;;
    thermal-mgame.conf)       echo "游戏 (mgame)" ;;
    thermal-tgame.conf)       echo "腾讯游戏 (tgame)" ;;
    thermal-class0.conf)      echo "极致省电 (class0)" ;;
    thermal-video.conf)       echo "视频 (video)" ;;
    thermal-videochat.conf)   echo "视频通话 (videochat)" ;;
    thermal-youtube.conf)     echo "YouTube (youtube)" ;;
    thermal-navigation.conf)  echo "导航 (navigation)" ;;
    thermal-camera.conf)      echo "相机 (camera)" ;;
    thermal-4k.conf)          echo "4K 录制 (4k)" ;;
    thermal-8k.conf)          echo "8K 录制 (8k)" ;;
    thermal-huanji.conf)      echo "环境 (huanji)" ;;
    thermal-phone.conf)       echo "通话 (phone)" ;;
    thermal-nolimits.conf)    echo "不限制 (nolimits)" ;;
    thermal-chg-only.conf)    echo "仅充电 (chg-only)" ;;
    *)                        echo "$1" ;;
  esac
}

# ---- crypto helpers ------------------------------------------------------
# encrypt  $1=plain file  $2=out cipher file
mt_encrypt() {
  mt_hex_of "$1" | $AWK -f "$MODDIR/bin/mtaes.awk" | mt_bin_of > "$2" 2>/dev/null
  [ -s "$2" ]
}

# decrypt  $1=cipher file  $2=out plain file
mt_decrypt() {
  mt_hex_of "$1" | $AWK -f "$MODDIR/bin/mtdec.awk" | mt_bin_of > "$2" 2>/dev/null
  [ -s "$2" ]
}

# 自检: 用模块自带的 AES 解密一个真实场景, 看能不能读出明文。
# 比探测 awk 有没有 xor() 可靠得多 —— 任何一步不通都会失败。
mt_selftest() {
  _f=$VENDOR_CONF/thermal-normal.conf
  [ -f "$_f" ] || return 1
  _t=$WORK/.selftest.$$
  mt_decrypt "$_f" "$_t" || { rm -f "$_t"; return 1; }
  if head -1 "$_t" | grep -q '^\['; then
    rm -f "$_t"
    return 0
  fi
  rm -f "$_t"
  return 1
}

# ---- scenario cache ------------------------------------------------------
# only real thermal scenarios (thermal-engine.conf / thermal-map.conf are not)
mt_all_scenarios() {
  for f in $VENDOR_CONF/thermal-*.conf; do
    [ -e "$f" ] || continue
    b=${f##*/}
    case "$b" in
      thermal-engine.conf|thermal-map.conf) continue ;;
    esac
    echo "$b"
  done
}

# make sure $PLAIN_DIR/$1 holds the decrypted plain text of scenario $1
mt_cache_get() {
  _s=$1
  [ -z "$_s" ] && return 1
  [ -f "$PLAIN_DIR/$_s" ] && return 0
  [ -f "$VENDOR_CONF/$_s" ] || return 1
  mkdir -p "$PLAIN_DIR" "$CIPHER_DIR"
  if mt_is_plain "$_s"; then
    # vendor keeps this one in clear text
    cp -f "$VENDOR_CONF/$_s" "$PLAIN_DIR/$_s" 2>/dev/null || return 1
    return 0
  fi
  mt_decrypt "$VENDOR_CONF/$_s" "$PLAIN_DIR/$_s" || {
    cp "$VENDOR_CONF/$_s" "$PLAIN_DIR/$_s" 2>/dev/null || return 1
  }
  [ -s "$PLAIN_DIR/$_s" ]
}

mt_cache_refresh() {
  mkdir -p "$PLAIN_DIR" "$CIPHER_DIR"
  for s in $(mt_all_scenarios); do
    rm -f "$PLAIN_DIR/$s"
  done
  # 并行解密 (16 个场景串行要 5~8 秒)
  for s in $(mt_all_scenarios); do
    ( mt_cache_get "$s" ) &
  done
  wait
}

# vendor keeps a few scenario files in clear text (size not a multiple of 16)
mt_is_plain() {
  _s=$1
  _sz=$(stat -c %s "$VENDOR_CONF/$_s" 2>/dev/null || echo 0)
  [ $((_sz % 16)) -ne 0 ]
}

# ---- verify ---------------------------------------------------------------
# 确认 mi_thermald 真的加载了我们写下去的配置:
# 把落盘的那份配置解密出来, 和 mi_thermald 运行时解密出的 decrypt.txt 比对。
# 输出 OK / MISMATCH, 供 GUI 做「是否真的生效」的判断。
mt_verify() {
  _sc=$(mt_active_scenario_name)
  if [ -z "$_sc" ]; then
    echo "无法确定当前生效的场景"
    return 1
  fi
  if [ ! -s "$THERMALD_LIVE" ]; then
    echo "mi_thermald 尚未产出 decrypt.txt"
    return 1
  fi
  _src=""
  if [ -f "$APPLY_DIR/$_sc" ]; then
    _src=$APPLY_DIR/$_sc
  else
    _src=$VENDOR_CONF/$_sc
  fi
  [ -f "$_src" ] || { echo "找不到 $_src"; return 1; }
  _a=$WORK/.verify_a.$$
  _b=$WORK/.verify_b.$$
  # mi_thermald 重启后 decrypt.txt 需要 1~2 秒才刷新, 重试几次避免误报
  _try=1
  while [ "$_try" -le 3 ]; do
    if ! mt_decrypt "$_src" "$_a"; then
      rm -f "$_a" "$_b"
      echo "解密落盘配置失败"
      return 1
    fi
    # 只比正文, 忽略空行差异
    grep -v '^[[:space:]]*$' "$_a" > "$_a.n" 2>/dev/null
    grep -v '^[[:space:]]*$' "$THERMALD_LIVE" > "$_b.n" 2>/dev/null
    if cmp -s "$_a.n" "$_b.n" 2>/dev/null; then
      rm -f "$_a" "$_b" "$_a.n" "$_b.n"
      echo "OK"
      return 0
    fi
    _try=$((_try + 1))
    [ "$_try" -le 3 ] && sleep 2
  done
  rm -f "$_a" "$_b" "$_a.n" "$_b.n"
  echo "MISMATCH"
  return 1
}

# ---- apply ---------------------------------------------------------------
# encrypt $PLAIN_DIR/$1 and hand it to mi_thermald, then restart it
mt_apply() {
  _s=$1
  [ -f "$PLAIN_DIR/$_s" ] || { echo "!! 无明文配置: $_s" >&2; return 1; }
  mkdir -p "$APPLY_DIR"
  if mt_is_plain "$_s"; then
    # clear-text scenario: copy verbatim
    cp -f "$PLAIN_DIR/$_s" "$APPLY_DIR/$_s" || { echo "!! 写入失败" >&2; return 1; }
  else
    mt_encrypt "$PLAIN_DIR/$_s" "$CIPHER_DIR/$_s" || { echo "!! 加密失败" >&2; return 1; }
    cp -f "$CIPHER_DIR/$_s" "$APPLY_DIR/$_s" || { echo "!! 写入 $APPLY_DIR 失败" >&2; return 1; }
  fi
  chown root:system "$APPLY_DIR/$_s" 2>/dev/null
  chmod 644 "$APPLY_DIR/$_s" 2>/dev/null
  setprop ctl.restart mi_thermald
  sleep 3
  if [ -f "$THERMALD_LIVE" ] && [ -s "$THERMALD_LIVE" ]; then
    echo "已应用并重启 mi_thermald"
  else
    echo "已应用 (mi_thermald 重启后暂未产出 decrypt.txt，请检查日志)"
  fi
}

mt_apply_restore() {
  # remove every override so mi_thermald falls back to /vendor/etc
  rm -f "$APPLY_DIR"/thermal-*.conf 2>/dev/null
  setprop ctl.restart mi_thermald
  sleep 2
  echo "已移除所有场景覆写，恢复原厂配置"
}

# ---- section / key editing ----------------------------------------------
# mt_set_key <scenario> <section> <key> <new value...>
mt_set_key() {
  _s=$1; _sec=$2; _key=$3; shift 3
  _val="$*"
  mt_cache_get "$_s" || { echo "!! 找不到场景 $_s" >&2; return 1; }
  _tmp=$WORK/.edit.$$
  $AWK -v sec="$_sec" -v key="$_key" -v val="$_val" '
    $0 ~ "^\\[" {
        cur = ($0 == "[" sec "]")
        print
        next
    }
    cur && match($0, "^[ \t]*" key "[ \t]+") {
        pre = substr($0, 1, RLENGTH)
        printf "%s%s\n", pre, val
        next
    }
    { print }
  ' "$PLAIN_DIR/$_s" > "$_tmp" 2>/dev/null
  if [ ! -s "$_tmp" ]; then rm -f "$_tmp"; echo "!! 编辑失败" >&2; return 1; fi
  if cmp -s "$_tmp" "$PLAIN_DIR/$_s"; then rm -f "$_tmp"; echo "内容无变化"; return 0; fi
  mv -f "$_tmp" "$PLAIN_DIR/$_s"
  echo "[$_s] [$_sec] $_key = $_val"
  mt_apply "$_s"
}

# ---- profile transform ---------------------------------------------------
# mt_profile_apply <profile-file>
# profile file format:
#   trig_delta=<millideg C>   shift every trig/clr threshold
#   min_freq=<kHz>            clamp the lowest "target" of ss sections (0 = off)
mt_profile_apply() {
  _pf=$1
  [ -f "$_pf" ] || { echo "!! 找不到预设 $_pf" >&2; return 1; }
  _delta=0; _minf=0
  while IFS='=' read -r k v; do
    case "$k" in
      trig_delta) _delta=$v ;;
      min_freq)   _minf=$v ;;
    esac
  done < "$_pf"
  echo "预设参数: trig_delta=${_delta}m°C  min_freq=${_minf}kHz"
  for s in $(mt_all_scenarios); do
    mt_cache_get "$s" || continue
    _tmp=$WORK/.prof.$$
    $AWK -v d="$_delta" -v mf="$_minf" '
      function vals(line,   n, a, i, m, out) {
        n = split(line, a, /[ \t]+/)
        m = 0
        for (i = 1; i <= n; i++) if (a[i] != "") { m++; b[m] = a[i] }
        out = ""
        for (i = 1; i <= m; i++) out = (out == "" ? b[i] : out " " b[i])
        return out
      }
      function shift(vs,   n, a, i, m, out, v) {
        n = split(vs, a, /[ \t]+/)
        m = 0
        for (i = 1; i <= n; i++) if (a[i] != "") { m++; b[m] = a[i] }
        if (m == 0) return vs
        # only touch values that look like millidegree temperatures
        if ((b[1] + 0) < 10000) return vs
        out = ""
        for (i = 1; i <= m; i++) { v = b[i] + 0; v = v + d; out = (out == "" ? v : out " " v) }
        return out
      }
      function clamp(vs,   n, a, i, m, out, last) {
        n = split(vs, a, /[ \t]+/)
        m = 0
        for (i = 1; i <= n; i++) if (a[i] != "") { m++; b[m] = a[i] }
        if (m == 0) return vs
        last = b[m] + 0
        if (last > 0 && last < mf) b[m] = mf
        out = ""
        for (i = 1; i <= m; i++) out = (out == "" ? b[i] : out " " b[i])
        return out
      }
      {
        line = $0
        if (match(line, /^[ \t]*[^ \t]+/)) {
          ke = substr(line, RSTART, RLENGTH)
          rest = substr(line, RSTART + RLENGTH)
          k = ke; sub(/^[ \t]+/, "", k)
          if (k == "algo_type") { atype = vals(rest); printf "%s%s\n", ke, rest; next }
          if (k == "device")    { dev   = vals(rest); printf "%s%s\n", ke, rest; next }
          if (k == "trig" || k == "clr") {
            printf "%s\t%s\n", ke, shift(rest); next
          }
          if (k == "target" && mf > 0 && atype == "ss" && dev ~ /^cpu/) {
            printf "%s\t%s\n", ke, clamp(rest); next
          }
        }
        print line
      }
    ' "$PLAIN_DIR/$s" > "$_tmp" 2>/dev/null
    if [ -s "$_tmp" ]; then
      mv -f "$_tmp" "$PLAIN_DIR/$s"
    else
      rm -f "$_tmp"
    fi
  done

  # --- 第二步: 加密并落盘 (并行, 16 个场景从十几秒压到 1 秒左右) ---
  for s in $(mt_all_scenarios); do
    [ -f "$PLAIN_DIR/$s" ] || continue
    (
      if mt_is_plain "$s"; then
        cp -f "$PLAIN_DIR/$s" "$APPLY_DIR/$s" 2>/dev/null
      else
        mt_encrypt "$PLAIN_DIR/$s" "$CIPHER_DIR/$s" && \
          cp -f "$CIPHER_DIR/$s" "$APPLY_DIR/$s" 2>/dev/null
      fi
      chown root:system "$APPLY_DIR/$s" 2>/dev/null
      chmod 644 "$APPLY_DIR/$s" 2>/dev/null
    ) &
  done
  wait

  setprop ctl.restart mi_thermald
  sleep 3
  echo "预设已应用并重启 mi_thermald"
}

# ---- live sysfs overrides -----------------------------------------------
mt_ovr_save() {
  mkdir -p "$WORK"
  touch "$OVERRIDE_FILE"
}
mt_ovr_set() {  # key value
  mt_ovr_save
  sed -i "/^$1=/d" "$OVERRIDE_FILE" 2>/dev/null
  echo "$1=$2" >> "$OVERRIDE_FILE"
}
mt_ovr_get() {
  [ -f "$OVERRIDE_FILE" ] || return 1
  grep "^$1=" "$OVERRIDE_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}
mt_ovr_del() {
  [ -f "$OVERRIDE_FILE" ] || return 0
  sed -i "/^$1=/d" "$OVERRIDE_FILE" 2>/dev/null
}

mt_cap_cpu() {  # policy khz | off
  _p=$1; _f=$2
  _fmax=$(cat /sys/devices/system/cpu/cpufreq/policy${_p}/cpuinfo_max_freq 2>/dev/null)
  if [ "$_f" = "off" ] || [ -z "$_f" ]; then
    [ -n "$_fmax" ] && echo "$_fmax" > /sys/devices/system/cpu/cpufreq/policy${_p}/scaling_max_freq 2>/dev/null
    mt_ovr_del "cpu${_p}"
    echo "CPU$_p 上限已解除"
  else
    echo "$_f" > /sys/devices/system/cpu/cpufreq/policy${_p}/scaling_max_freq 2>/dev/null
    mt_ovr_set "cpu${_p}" "$_f"
    echo "CPU$_p 上限 -> ${_f} kHz"
  fi
}

mt_gpu_hw_max() {
  # kgsl devfreq 没有 hw_max_freq，用 available_frequencies 的最大值代替
  tr ' ' '\n' < /sys/class/kgsl/kgsl-3d0/devfreq/available_frequencies 2>/dev/null \
    | grep -E '^[0-9]+$' | sort -n | tail -1
}

mt_cap_gpu() {  # khz | off
  _f=$1
  if [ "$_f" = "off" ] || [ -z "$_f" ]; then
    _fmax=$(mt_ovr_get gpu_orig)
    [ -z "$_fmax" ] && _fmax=$(mt_gpu_hw_max)
    [ -n "$_fmax" ] && echo "$_fmax" > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null
    mt_ovr_del "gpu"
    mt_ovr_del "gpu_orig"
    echo "GPU 上限已解除 -> ${_fmax:-?}"
  else
    _orig=$(mt_ovr_get gpu_orig)
    [ -z "$_orig" ] && _orig=$(mt_gpu_hw_max)
    [ -n "$_orig" ] && mt_ovr_set "gpu_orig" "$_orig"
    echo "$_f" > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null
    mt_ovr_set "gpu" "$_f"
    echo "GPU 上限 -> ${_f} kHz (原厂 ${_orig:-?})"
  fi
}

mt_cap_charge() {  # state | off
  _s=$1
  _cd=$(ls -d /sys/class/thermal/cooling_device* 2>/dev/null | while read d; do
          [ "$(cat $d/type 2>/dev/null)" = "battery" ] && echo $d && break; done)
  if [ -z "$_cd" ]; then echo "!! 找不到 battery cooling device" >&2; return 1; fi
  if [ "$_s" = "off" ] || [ -z "$_s" ]; then
    echo 0 > "$_cd/cur_state" 2>/dev/null
    mt_ovr_del "charge"
    echo "充电限流覆写已解除"
  else
    echo "$_s" > "$_cd/cur_state" 2>/dev/null
    mt_ovr_set "charge" "$_s"
    echo "充电限流档位 -> $_s ($_cd)"
  fi
}

mt_tempstate() {  # n | off
  _n=$1
  if [ "$_n" = "off" ] || [ -z "$_n" ]; then
    mt_ovr_del "tempstate"
    echo "温控状态覆写已解除"
  else
    echo "$_n" > /sys/class/thermal/thermal_message/temp_state 2>/dev/null
    mt_ovr_set "tempstate" "$_n"
    echo "temp_state -> $_n"
  fi
}

# re-apply persisted overrides (called by the daemon each cycle)
mt_ovr_reapply() {
  [ -f "$OVERRIDE_FILE" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in
      cpu[0-9]*)  echo "$v" > /sys/devices/system/cpu/cpufreq/policy${k#cpu}/scaling_max_freq 2>/dev/null ;;
      gpu)        echo "$v" > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq 2>/dev/null ;;
      charge)    _cd=$(ls -d /sys/class/thermal/cooling_device* 2>/dev/null | while read d; do
                        [ "$(cat $d/type 2>/dev/null)" = "battery" ] && echo $d && break; done)
                 [ -n "$_cd" ] && echo "$v" > "$_cd/cur_state" 2>/dev/null ;;
      tempstate) echo "$v" > /sys/class/thermal/thermal_message/temp_state 2>/dev/null ;;
    esac
  done < "$OVERRIDE_FILE"
}

mt_ovr_list() {
  if [ ! -f "$OVERRIDE_FILE" ] || [ ! -s "$OVERRIDE_FILE" ]; then
    echo "当前没有实时覆写"
    return 0
  fi
  cat "$OVERRIDE_FILE"
}
