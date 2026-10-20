#!/system/bin/sh
#=======================================================================
#  MiThermal Tuner  -  monitoring library
#=======================================================================

# build (once) the thermal-zone index: type -> zone number
MT_ZONE_IDX=$WORK/zone.idx
mt_build_zone_idx() {
  [ -s "$MT_ZONE_IDX" ] && return 0
  mkdir -p "$WORK"
  _tmp=$WORK/.zone.idx.$$
  : > "$_tmp"
  for z in /sys/class/thermal/thermal_zone*; do
    [ -e "$z/type" ] || continue
    t=$(cat "$z/type" 2>/dev/null)
    n=${z##*/thermal_zone}
    echo "$t $n" >> "$_tmp"
  done
  mv -f "$_tmp" "$MT_ZONE_IDX" 2>/dev/null
}

mt_zone() {  # type -> millidegrees
  _t=$1
  [ -s "$MT_ZONE_IDX" ] || mt_build_zone_idx
  _n=$($AWK -v t="$_t" '$1==t {print $2; exit}' "$MT_ZONE_IDX" 2>/dev/null)
  [ -z "$_n" ] && { echo ""; return; }
  cat /sys/class/thermal/thermal_zone${_n}/temp 2>/dev/null
}

mt_c() { cat "$1" 2>/dev/null; }
# ---- collect one sample --------------------------------------------------
# 性能要点: 这里原本有 130 多次 $(cat ...) 的进程 fork (53 个散热设备 + 7 个温区
# + 十几个频率/电池节点), 一次采样要 2.4 秒, App 会被拖得很难看。
# 现在改成用 awk 的 getline 直接读文件, 全程只有 2 个进程。
# MT_S_* globals are filled by mt_sample()
mt_sample() {
  [ -s "$MT_ZONE_IDX" ] || mt_build_zone_idx

  # --- 一次 awk 读完所有传感器/频率/电池/温控状态节点 ---
  _line=$($AWK -v idx="$MT_ZONE_IDX" '
    function rd(f,   l, v) {
      v = ""
      while ((getline l < f) > 0) { v = l; break }
      close(f)
      return v
    }
    BEGIN {
      Z = "/sys/class/thermal/thermal_zone"
      C = "/sys/devices/system/cpu/cpufreq/"
      G = "/sys/class/kgsl/kgsl-3d0/devfreq/"
      P = "/sys/class/power_supply/battery/"
      T = "/sys/class/thermal/thermal_message/"
      q=c=b=ch=w=m0=m1=fl=""
      while ((getline line < idx) > 0) {
        split(line, a, " ")
        t = a[1]; n = a[2]
        if      (t == "quiet_therm")    q  = rd(Z n "/temp")
        else if (t == "cpu_therm")      c  = rd(Z n "/temp")
        else if (t == "battery")        b  = rd(Z n "/temp")
        else if (t == "charger_therm0") ch = rd(Z n "/temp")
        else if (t == "wifi_therm")     w  = rd(Z n "/temp")
        else if (t == "modem1_pa0")     m0 = rd(Z n "/temp")
        else if (t == "modem1_pa1")     m1 = rd(Z n "/temp")
        else if (t == "flash_therm")    fl = rd(Z n "/temp")
      }
      p0  = rd(C "policy0/scaling_cur_freq");  p0m = rd(C "policy0/scaling_max_freq")
      p4  = rd(C "policy4/scaling_cur_freq");  p4m = rd(C "policy4/scaling_max_freq")
      p7  = rd(C "policy7/scaling_cur_freq");  p7m = rd(C "policy7/scaling_max_freq")
      g   = rd(G "cur_freq");  gm = rd(G "max_freq")
      cur = rd(P "current_now");  lvl = rd(P "capacity")
      ts  = rd(T "temp_state");  bs = rd(T "board_sensor_temp")
      bal = rd(T "balance_mode");  bo = rd(T "boost")
      ml  = rd(T "modem_limit");  wl = rd(T "wifi_limit")
      sub(/^[^:]*:/, "", bo)
      printf "%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s\n", \
        q, c, b, ch, w, m0, m1, fl, \
        p0, p0m, p4, p4m, p7, p7m, g, gm, cur, lvl, ts, bs, bal, bo, ml, wl
    }
  ' 2>/dev/null)

  set -- $_line
  MT_S_QUIET=$1;  MT_S_CPU=$2;   MT_S_BAT=$3;   MT_S_CHG=$4
  MT_S_WIFI=$5;   MT_S_M0=$6;    MT_S_M1=$7;    MT_S_FLASH=$8
  MT_S_P0=$9;    MT_S_P0M=${10}; MT_S_P4=${11};  MT_S_P4M=${12}
  MT_S_P7=${13};  MT_S_P7M=${14};MT_S_GPU=${15}; MT_S_GPUM=${16}
  MT_S_CUR=${17}; MT_S_LVL=${18};MT_S_TSTATE=${19}; MT_S_BOARD=${20}
  MT_S_BALMODE=${21}; MT_S_BOOST=${22}; MT_S_MODEMLIM=${23}; MT_S_WIFILIM=${24}

  # --- 生效中的散热设备 (state != 0): 一个 awk 读完 53 个节点 ---
  MT_S_COOL=$(
    for c in /sys/class/thermal/cooling_device*; do
      [ -e "$c/cur_state" ] || continue
      echo "$c"
    done | $AWK '
      function rd(f,   l, v) {
        v = ""
        while ((getline l < f) > 0) { v = l; break }
        close(f)
        return v
      }
      {
        st = rd($0 "/cur_state")
        if (st == "" || st + 0 == 0) next
        ty = rd($0 "/type")
        if (ty != "") print ty "=" st
      }
    ' 2>/dev/null | tr '\n' ' ' | sed 's/ *$//'
  )

  # --- mi_thermald 自己算的虚拟温度 (取 dump 里最后一条) ---
  MT_S_VIRT=""
  if [ -f "$THERMALD_DUMP" ]; then
    MT_S_VIRT=$($AWK '
      { if (match($0, /VIRTUAL-SENSOR -?[0-9]+/)) v = substr($0, RSTART+14, RLENGTH-14) }
      END { print v }
    ' "$THERMALD_DUMP" 2>/dev/null)
  fi
}

mt_c2t() {  # millideg -> "35.4C"
  [ -z "$1" ] && { echo "     --"; return; }
  $AWK -v v="$1" 'BEGIN{ if (v < -1000 || v > 200000) { printf "%7s", "--" } else { printf "%6.1fC", v/1000 } }'
}

mt_khz2m() { $AWK -v v="$1" 'BEGIN{ printf "%.2fGHz", v/1000000 }'; }

# ---- pretty status -------------------------------------------------------
mt_status() {
  mt_build_zone_idx
  mt_sample
  echo "================================================================"
  echo " MiThermal Tuner   $(date '+%Y-%m-%d %H:%M:%S')"
  echo "================================================================"
  printf " 虚拟温度(mi_thermald) : %s\n" "$(mt_c2t "$MT_S_VIRT")"
  printf " 主板/虚拟传感器       : %s\n" "$(mt_c2t "$MT_S_BOARD")"
  echo "----------------------------------------------------------------"
  echo " 传感器:"
  printf "   cpu_therm      %s   battery      %s\n" "$(mt_c2t "$MT_S_CPU")" "$(mt_c2t "$MT_S_BAT")"
  printf "   quiet_therm    %s   charger      %s\n" "$(mt_c2t "$MT_S_QUIET")" "$(mt_c2t "$MT_S_CHG")"
  printf "   wifi_therm     %s   modem1_pa0   %s\n" "$(mt_c2t "$MT_S_WIFI")" "$(mt_c2t "$MT_S_M0")"
  printf "   modem1_pa1     %s   flash        %s\n" "$(mt_c2t "$MT_S_M1")" "$(mt_c2t "$MT_S_FLASH")"
  echo "----------------------------------------------------------------"
  echo " 频率:"
  printf "   policy0 (小核)  cur %8s  max %8s\n" "$MT_S_P0" "$MT_S_P0M"
  printf "   policy4 (大核)  cur %8s  max %8s\n" "$MT_S_P4" "$MT_S_P4M"
  printf "   policy7 (超大)  cur %8s  max %8s\n" "$MT_S_P7" "$MT_S_P7M"
  printf "   GPU             cur %8s  max %8s\n" "$MT_S_GPU" "$MT_S_GPUM"
  echo "----------------------------------------------------------------"
  echo " 电池 / 温控状态:"
  printf "   电流 %8s uA   电量 %s%%\n" "$MT_S_CUR" "$MT_S_LVL"
  printf "   temp_state=%s  balance_mode=%s  boost=%s\n" "$MT_S_TSTATE" "$MT_S_BALMODE" "$MT_S_BOOST"
  printf "   modem_limit=%s  wifi_limit=%s\n" "$MT_S_MODEMLIM" "$MT_S_WIFILIM"
  echo "----------------------------------------------------------------"
  echo " 生效中的散热设备 (state != 0):"
  if [ -z "$MT_S_COOL" ]; then
    echo "   (无)"
  else
    for x in $MT_S_COOL; do printf "   %s\n" "$x"; done
  fi
  echo "----------------------------------------------------------------"
  echo " 当前生效的场景配置:"
  mt_active_scenario
  echo "================================================================"
}

# return the file name of the currently active scenario
mt_active_scenario_name() {
  [ -s "$THERMALD_LIVE" ] || { echo ""; return; }
  # 一次 awk 扫完, 原来是最多 14 次 grep
  $AWK '
    BEGIN {
      n = split("MGAME- NL- CHG- 4k- 8K- CAMERA- CLASS0- HUANJI- NAV- PHONE- VIDEO- YTB- videochat- MONITOR-", P, " ")
      for (i = 1; i <= n; i++) map[P[i]] = i
    }
    /^\[/ {
      p = substr($0, 2, index($0, "]") - 2)
      for (i = 1; i <= n; i++) {
        if (index(p, P[i]) == 1) { print i; exit }
      }
    }
  ' "$THERMALD_LIVE" 2>/dev/null | while read -r i; do
    case "$i" in
      1)  echo thermal-mgame.conf ;;
      2)  echo thermal-nolimits.conf ;;
      3)  echo thermal-chg-only.conf ;;
      4)  echo thermal-4k.conf ;;
      5)  echo thermal-8k.conf ;;
      6)  echo thermal-camera.conf ;;
      7)  echo thermal-class0.conf ;;
      8)  echo thermal-huanji.conf ;;
      9)  echo thermal-navigation.conf ;;
      10) echo thermal-phone.conf ;;
      11) echo thermal-video.conf ;;
      12) echo thermal-youtube.conf ;;
      13) echo thermal-videochat.conf ;;
      14) echo thermal-normal.conf ;;
    esac
  done
}

# detect which scenario mi_thermald currently runs (by section prefix)
mt_active_scenario() {
  if [ ! -s "$THERMALD_LIVE" ]; then
    echo "   (无法确定: $THERMALD_LIVE 不可读)"
    return
  fi
  _s=$(mt_active_scenario_name)
  if [ -z "$_s" ]; then
    echo "   未知场景"
    return
  fi
  _ov=""
  [ -f "$APPLY_DIR/$_s" ] && _ov="   [已被本模块覆写]"
  echo "   $_s  ($(scenario_label "$_s"))$_ov"
}

# ---- JSON output for the GUI app ----------------------------------------
mt_json() {
  mt_build_zone_idx
  mt_sample
  _c=""
  for x in $MT_S_COOL; do
    _ty=${x%%=*}
    _st=${x##*=}
    [ -n "$_c" ] && _c="$_c,"
    _c="$_c{\"type\":\"$_ty\",\"state\":$_st}"
  done
  _sc=$(mt_active_scenario_name)
  _ov=false
  [ -n "$_sc" ] && [ -f "$APPLY_DIR/$_sc" ] && _ov=true
  _lbl=""
  [ -n "$_sc" ] && _lbl=$(scenario_label "$_sc")
  _oj=""
  if [ -f "$OVERRIDE_FILE" ] && [ -s "$OVERRIDE_FILE" ]; then
    while IFS='=' read -r k v; do
      [ -z "$k" ] && continue
      [ -n "$_oj" ] && _oj="$_oj,"
      _oj="$_oj{\"k\":\"$k\",\"v\":\"$v\"}"
    done < "$OVERRIDE_FILE"
  fi
  printf '{"virtual":%s,"quiet":%s,"cpu":%s,"batt":%s,"charger":%s,"wifi":%s,"m0":%s,"m1":%s,' \
    "${MT_S_VIRT:-0}" "${MT_S_QUIET:-0}" "${MT_S_CPU:-0}" "${MT_S_BAT:-0}" "${MT_S_CHG:-0}" \
    "${MT_S_WIFI:-0}" "${MT_S_M0:-0}" "${MT_S_M1:-0}"
  printf '"cpu0":%s,"cpu0max":%s,"cpu4":%s,"cpu4max":%s,"cpu7":%s,"cpu7max":%s,' \
    "${MT_S_P0:-0}" "${MT_S_P0M:-0}" "${MT_S_P4:-0}" "${MT_S_P4M:-0}" "${MT_S_P7:-0}" "${MT_S_P7M:-0}"
  printf '"gpu":%s,"gpumax":%s,"current":%s,"level":%s,"tempstate":%s,"balance":%s,"boost":%s,' \
    "${MT_S_GPU:-0}" "${MT_S_GPUM:-0}" "${MT_S_CUR:-0}" "${MT_S_LVL:-0}" "${MT_S_TSTATE:-0}" \
    "${MT_S_BALMODE:-0}" "${MT_S_BOOST:-0}"
  printf '"modemlimit":%s,"wifilimit":%s,' "${MT_S_MODEMLIM:-0}" "${MT_S_WIFILIM:-0}"
  printf '"scenario":"%s","label":"%s","overridden":%s,' "$_sc" "$_lbl" "$_ov"
  printf '"cooling":[%s],"overrides":[%s]}' "$_c" "$_oj"
}

# list sections + editable keys of a scenario as JSON
mt_json_sections() {
  mt_cache_get "$1" || { echo "[]"; return; }
  $AWK '
    /^[[:space:]]*\[/ {
      if (sec != "") printf "%s{\"name\":\"%s\",\"keys\":\"%s\"}", sep, sec, keys
      sep = ","
      sec = $0
      gsub(/^[[:space:]]*\[/, "", sec)
      gsub(/\][[:space:]]*$/, "", sec)
      keys = ""
      next
    }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      if (sec == "") next
      line = $0
      if (match(line, /^[ \t]*[^ \t]+/)) {
        k = substr(line, RSTART, RLENGTH)
        sub(/^[ \t]+/, "", k)
        if (k != "" && index(" " keys " ", " " k " ") == 0) keys = keys k " "
      }
    }
    END {
      if (sec != "") printf "%s{\"name\":\"%s\",\"keys\":\"%s\"}", sep, sec, keys
    }
  ' "$PLAIN_DIR/$1" 2>/dev/null | sed 's/^,//' | { read -r x; [ -z "$x" ] && echo "[]" || echo "[$x]"; }
}

# ---- CSV log line --------------------------------------------------------
mt_log_line() {
  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "$(date '+%m-%d %H:%M:%S')" \
    "${MT_S_VIRT:-0}" "${MT_S_QUIET:-0}" "${MT_S_CPU:-0}" "${MT_S_BAT:-0}" \
    "${MT_S_CHG:-0}" "${MT_S_WIFI:-0}" "${MT_S_M0:-0}" "${MT_S_M1:-0}" \
    "${MT_S_P0:-0}" "${MT_S_P4:-0}" "${MT_S_P7:-0}" "${MT_S_GPU:-0}" \
    "${MT_S_CUR:-0}" "${MT_S_LVL:-0}" "${MT_S_TSTATE:-0}" \
    "$(echo $MT_S_COOL | $AWK '{for(i=1;i<=NF;i++) printf "%s%s", (i>1?";":""), $i}')"
}

mt_log_header() {
  echo "# time,virtual,quiet,cpu,batt,charger,wifi,m0,m1,cpu0,cpu4,cpu7,gpu,current_uA,level,temp_state,cooling"
}

mt_log_rotate() {
  [ -f "$LOGFILE" ] || return 0
  _sz=$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
  [ "${_sz:-0}" -gt 2000000 ] && mv -f "$LOGFILE" "$LOGFILE.1"
  return 0
}
