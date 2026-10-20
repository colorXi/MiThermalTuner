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
  _n=$($BB awk -v t="$_t" '$1==t {print $2; exit}' "$MT_ZONE_IDX" 2>/dev/null)
  [ -z "$_n" ] && { echo ""; return; }
  cat /sys/class/thermal/thermal_zone${_n}/temp 2>/dev/null
}

mt_c() { cat "$1" 2>/dev/null; }

# ---- collect one sample --------------------------------------------------
# MT_S_* globals are filled by mt_sample()
mt_sample() {
  MT_S_QUIET=$(mt_zone quiet_therm)
  MT_S_CPU=$(mt_zone cpu_therm)
  MT_S_BAT=$(mt_zone battery)
  MT_S_WIFI=$(mt_zone wifi_therm)
  MT_S_M0=$(mt_zone modem1_pa0)
  MT_S_M1=$(mt_zone modem1_pa1)
  MT_S_CHG=$(mt_zone charger_therm0)
  MT_S_FLASH=$(mt_zone flash_therm)

  MT_S_P0=$(mt_c /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq)
  MT_S_P0M=$(mt_c /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq)
  MT_S_P4=$(mt_c /sys/devices/system/cpu/cpufreq/policy4/scaling_cur_freq)
  MT_S_P4M=$(mt_c /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq)
  MT_S_P7=$(mt_c /sys/devices/system/cpu/cpufreq/policy7/scaling_cur_freq)
  MT_S_P7M=$(mt_c /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq)

  MT_S_GPU=$(mt_c /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq)
  MT_S_GPUM=$(mt_c /sys/class/kgsl/kgsl-3d0/devfreq/max_freq)

  MT_S_CUR=$(mt_c /sys/class/power_supply/battery/current_now)
  MT_S_LVL=$(mt_c /sys/class/power_supply/battery/capacity)
  MT_S_TSTATE=$(mt_c /sys/class/thermal/thermal_message/temp_state)
  MT_S_BOARD=$(mt_c /sys/class/thermal/thermal_message/board_sensor_temp)
  MT_S_BALMODE=$(mt_c /sys/class/thermal/thermal_message/balance_mode)
  MT_S_BOOST=$(mt_c /sys/class/thermal/thermal_message/boost)
  case "$MT_S_BOOST" in
    *:*) MT_S_BOOST=${MT_S_BOOST##*:} ;;
  esac
  MT_S_MODEMLIM=$(mt_c /sys/class/thermal/thermal_message/modem_limit)
  MT_S_WIFILIM=$(mt_c /sys/class/thermal/thermal_message/wifi_limit)

  # active cooling devices (state != 0)
  MT_S_COOL=""
  for c in /sys/class/thermal/cooling_device*; do
    [ -e "$c/cur_state" ] || continue
    st=$(mt_c "$c/cur_state")
    [ -z "$st" ] && continue
    [ "$st" = "0" ] && continue
    ty=$(mt_c "$c/type")
    MT_S_COOL="$MT_S_COOL $ty=$st"
  done

  # mi_thermald's own reported virtual temperature (last line of its dump)
  MT_S_VIRT=""
  if [ -f "$THERMALD_DUMP" ]; then
    MT_S_VIRT=$($BB grep -a -o 'VIRTUAL-SENSOR [0-9-]*' "$THERMALD_DUMP" 2>/dev/null | tail -1 | cut -d' ' -f2)
  fi
}

mt_c2t() {  # millideg -> "35.4C"
  [ -z "$1" ] && { echo "     --"; return; }
  $BB awk -v v="$1" 'BEGIN{ if (v < -1000 || v > 200000) { printf "%7s", "--" } else { printf "%6.1fC", v/1000 } }'
}

mt_khz2m() { $BB awk -v v="$1" 'BEGIN{ printf "%.2fGHz", v/1000000 }'; }

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
  for p in MGAME- NL- CHG- 4k- 8K- CAMERA- CLASS0- HUANJI- NAV- \
           PHONE- VIDEO- YTB- videochat- MONITOR-; do
    if $BB grep -aq "^\[$p" "$THERMALD_LIVE" 2>/dev/null; then
      case "$p" in
        MGAME-*)     echo thermal-mgame.conf ;;
        NL-*)        echo thermal-nolimits.conf ;;
        CHG-*)       echo thermal-chg-only.conf ;;
        4k-*)        echo thermal-4k.conf ;;
        8K-*)        echo thermal-8k.conf ;;
        CAMERA-*)    echo thermal-camera.conf ;;
        CLASS0-*)    echo thermal-class0.conf ;;
        HUANJI-*)    echo thermal-huanji.conf ;;
        NAV-*)       echo thermal-navigation.conf ;;
        PHONE-*)     echo thermal-phone.conf ;;
        VIDEO-*)     echo thermal-video.conf ;;
        YTB-*)       echo thermal-youtube.conf ;;
        videochat-*) echo thermal-videochat.conf ;;
        MONITOR-*)   echo thermal-normal.conf ;;
      esac
      return
    fi
  done
  echo ""
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
  $BB awk '
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
    "$(echo $MT_S_COOL | $BB awk '{for(i=1;i<=NF;i++) printf "%s%s", (i>1?";":""), $i}')"
}

mt_log_header() {
  echo "# time,virtual,quiet,cpu,batt,charger,wifi,m0,m1,cpu0,cpu4,cpu7,gpu,current_uA,level,temp_state,cooling"
}

mt_log_rotate() {
  [ -f "$LOGFILE" ] || return 0
  _sz=$($BB stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
  [ "${_sz:-0}" -gt 2000000 ] && mv -f "$LOGFILE" "$LOGFILE.1"
  return 0
}
