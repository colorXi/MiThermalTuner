# 小米温控配置格式解析

> 作者：**达人怪** · 微信 `UVWAPP`
> 项目：<https://github.com/colorXi/MiThermalTuner>

本文记录 `mi_thermald` 使用的温控配置文件的结构、字段语义，以及设备端 AES
实现中踩过的坑。全部内容基于 Redmi Note 10 Pro 5G (`2109119BC` / `mona`,
Snapdragon 778G / SM7325) 实测得出，系统为**小米澎湃OS HyperOS
`OS1.0.2.0.TKVCNXM`**（内部 MIUI 版本号 `V816`，基于 Android 13）。

---

## 1. 文件位置与加密

| 路径 | 内容 | 格式 |
|---|---|---|
| `/vendor/etc/thermal-*.conf` | 原厂场景配置 | AES-128-CBC 加密（`thermal-chg-only.conf` 除外，它是明文） |
| `/vendor/etc/thermald-devices.conf` | 散热设备名 ↔ 节点映射 | 明文 |
| `/vendor/etc/thermal-engine.conf` | Qualcomm ATE 配置 | 本机为空文件 |
| `/vendor/etc/thermal-map.conf` | 场景 ID → 文件名映射 | AES-128-CBC 加密 |
| `/data/vendor/thermal/config/` | **覆写目录**，`mi_thermald` 优先读这里 | 同原厂 |
| `/data/vendor/thermal/decrypt.txt` | `mi_thermald` 运行时解密出来的当前配置 | 明文 |
| `/data/vendor/thermal/thermal.dump` | 运行时监控日志（含 VIRTUAL-SENSOR 实测值） | 明文 |

### 加密参数

| 项 | 值 |
|---|---|
| 算法 | AES-128-**CBC** + PKCS#7 padding |
| Key | `thermalopenssl.h` → `74 68 65 72 6d 61 6c 6f 70 65 6e 73 73 6c 2e 68` |
| IV | 与 Key 相同 |
| 密钥来源 | 硬编码在 `/vendor/bin/mi_thermald` 的 `.rodata` |

判定某个 `.conf` 是否加密：**文件大小是否是 16 的整数倍**。是则加密，否则明文。

---

## 2. 配置文件结构

INI 风格，`[节名]` 分节，节内是 `键<空白>值` 的键值对，值可以是空格/制表符分隔的列表。

```
[BAT_SOC]
algo_type	simulated
path		/sys/class/power_supply/battery/capacity
polling		10000

[VIRTUAL-SENSOR]
algo_type	virtual
sensors		quiet_therm	  modem1_pa0	modem1_pa1	charger_therm0	 wifi_therm	cpu_therm	battery
weight		-155		  424		-8              86              -3     	237		288
polling		2000
weight_sum	1000
compensation	2699

[MONITOR-SS-CPU4]
algo_type	ss
sensor		VIRTUAL-SENSOR
device		cpu4
polling		2000
trig		39000		40200		41000		45000		47000
clr		37000		39000		40200		42000		45000
target		1651200		1516800 	1228800		940800		691200
```

### 2.1 `algo_type`

| 值 | 含义 |
|---|---|
| `simulated` | 直接读取某个 sysfs 节点（模拟量），如电池电量 |
| `virtual` | 由多路传感器加权合成一个虚拟温度 |
| `ss` | **Step State**：温度越线就切到 `target` 档位，降温后回退 |
| `monitor` | 温度越线就切到 `target` 值（可以是电流、亮度、状态码等） |

### 2.2 通用字段

| 字段 | 说明 |
|---|---|
| `polling` | 轮询间隔，单位毫秒 |
| `sensor` | 依赖的传感器名（`VIRTUAL-SENSOR` / `BAT_SOC` / `flash_therm` …） |
| `device` | 作用对象 |
| `reverse` | `1` 表示越线时数值越大越安全（用于 BCL） |

### 2.3 `ss` / `monitor` 专用字段

| 字段 | 说明 |
|---|---|
| `trig` | 触发阈值列表（温度为毫摄氏度；`MONITOR-BCL` 里是电量百分比） |
| `clr` | 解除阈值列表，必须与 `trig` 一一对应且更小，形成滞回 |
| `target` | 目标值列表，与 `trig` 一一对应 |

`device` 的常见取值：

| device | 作用 |
|---|---|
| `cpu0` / `cpu4` / `cpu7` | 对应 cpufreq policy 的频率上限 |
| `gpu` | GPU devfreq 档位（`thermal-devfreq-0`） |
| `battery` | 充电电流档位（`cooling_device` type = `battery`） |
| `backlight-clone` | 背光亮度 |
| `market_download_limit` | 应用市场并行下载限制 |
| `modem_ul` / `modem_dl` | 基带上/下行功率限制 |
| `temp_state` | 系统温控状态机（通知、省电模式等） |
| `boost_limit` | 性能 boost 开关 |
| `hotplug_cpu6+hotplug_cpu7` | 直接拔掉这两个核心 |
| `cpu4+hotplug_cpu5+hotplug_cpu6` | 组合动作（`+` 分隔） |

### 2.4 虚拟温度（`algo_type virtual`）

```
virtual = Σ(sensor_i × weight_i) / weight_sum + compensation
```

* `sensors`：参与计算的传感器名，按顺序
* `weight`：对应的权重（可为负）
* `weight_sum`：权重和（1000 = 放大 1000 倍取整）
* `compensation`：常数补偿（毫摄氏度）

以 `thermal-normal.conf` 的 `VIRTUAL-SENSOR` 为例：

```
sensors = quiet_therm, modem1_pa0, modem1_pa1, charger_therm0, wifi_therm, cpu_therm, battery
weight  =   -155,        424,         -8,            86,          -3,       237,      288
```

另有 `VIRTUAL-SENSOR2`，权重差异很大（`modem1_pa0` 权重 1761、`modem1_pa1` 权重 −1612），
从命名看是给不同场景（如游戏）准备的第二套合成方案。

> 厂商实际计算结果与上式会有几十毫摄氏度的偏差，主要来自采样时刻不同
> （`polling = 2000`），不是算法不同。

---

## 3. 场景与场景映射

`thermal-map.conf` 是一张「场景 ID → 文件名」表：

```
[0:thermal-normal.conf]
[1:thermal-high.conf]
[2:thermal-extreme.conf]
[3:thermal-huanji.conf]
...
[20:thermal-mgame.conf]
[21:thermal-video.conf]
[30:thermal-per-normal.conf]     ← per- 前缀是「按人物/按使用场景」的变体
[100:thermal-normal-unfold.conf] ← unfold = 折叠屏/展开屏
```

本机实际部署的只有 15 个场景文件，`thermal-map.conf` 里引用的
`thermal-high.conf`、`thermal-extreme.conf`、`thermal-*-unfold.conf` 等**并不存在**
（属于其它 SKU）。

### 本机可用场景

| 文件 | 场景 | 说明 |
|---|---|---|
| `thermal-normal.conf` | 日常 | 默认场景 |
| `thermal-mgame.conf` | 游戏 | 触发阈值高但一触发就压到底 |
| `thermal-tgame.conf` | 腾讯游戏 | 与 mgame 内容基本一致 |
| `thermal-class0.conf` | 极致省电 | 阈值最低，最激进 |
| `thermal-video.conf` | 视频 | |
| `thermal-videochat.conf` | 视频通话 | |
| `thermal-youtube.conf` | YouTube | |
| `thermal-navigation.conf` | 导航 | |
| `thermal-camera.conf` | 相机 | |
| `thermal-4k.conf` / `thermal-8k.conf` | 4K / 8K 录制 | |
| `thermal-huanji.conf` | 环境（护眼） | 额外监控 cpu0 |
| `thermal-phone.conf` | 通话 | 阈值异常低（27°C 起） |
| `thermal-nolimits.conf` | 不限制 | 几乎不降频 |
| `thermal-chg-only.conf` | 仅充电 | **明文文件** |

### 各场景降频阶梯对比（`MONITOR-SS-CPU4`，normal 为基准）

| 场景 | 触发温度阶梯 (°C) | 最低档频率 |
|---|---|---|
| normal | 39 / 40.2 / 41 / 45 / 47 | 691200 kHz |
| class0 | 35 / 37 / 41 / 43 / 44.5 / 47 | 691200 kHz |
| video | 35 / 38.5 / 41 / 43 / 44.5 / 47 | 691200 kHz |
| youtube | 35 / 37 / 39 / 41 / 43.5 / 47 | 691200 kHz |
| videochat | 35 / 36.5 / 38 / 40 / 42 / 46 | 691200 kHz |
| navigation | 35 / 39 / 41 / 42 / 43.5 / 47 | 691200 kHz |
| huanji | 35 / 39 / 40 / 41 / 42 | 691200 kHz |
| 4k / 8k | 40 / 41 / 42 / 43.5 / 46 | 691200 kHz |
| mgame / tgame | 46（单档） | 691200 kHz |
| nolimits | 51（单档） | 691200 kHz |
| phone | 27 / 32 / 42 | 691200 kHz |
| chg-only | 39 / 41 / 42 / 43.5 / 49 | 691200 kHz |

---

## 4. 内核层

### 温区

89 个 `thermal_zone`，策略分两种：

* `step_wise`（34 个）—— 内核直接按 DT 里的阈值降频
* `user_space`（55 个）—— 由 `mi_thermald` 接管

`step_wise` 的 `trip_point_*_temp` 是内核兜底硬限制，例如：

```
cpu-0-0-step   trip 110000 / 112000
cpu-1-0-step   trip 108000 / 110000
gpuss-0-step   trip 095000
mdmss-*-step   trip 095000 / 105000 / 115000
video-step     trip 100000
camera-0-step  trip 100000
```

### 散热设备

53 个 `cooling_device`。与降频相关的主要是：

| type | max_state | 说明 |
|---|---|---|
| `thermal-cpufreq-0` | 8 | policy0（小核） |
| `thermal-cpufreq-4` | 9 | policy4（大核） |
| `thermal-cpufreq-7` | 9 | policy7（超大核） |
| `thermal-devfreq-0` | 2 | GPU |
| `cpu-hotplug0..7` | 1 | 拔核 |
| `cpu-isolate0..7` | 1 | 隔离核 |
| `battery` | 16 | 充电电流档位 |
| `panel0-backlight` | 4095 | 背光 |
| `modem_*` | 3 / 255 | 基带功率 |

---

## 5. 设备端 AES 实现

### 为什么要自己实现

设备上没有 `openssl`、没有 `python`、没有 `perl`。
Magisk 自带的 busybox 有 `awk`，且 busybox awk 提供 `xor()` / `and()` /
`lshift()` / `rshift()` —— 够写一个 AES。

### 两个致命坑

**坑 1：`/system/bin/awk` 不是 busybox awk**

Android 自带的 `/system/bin/awk`（toybox）**没有** `xor()`，直接调用会报
`awk: calling undefined function xor`。
必须显式用 `/data/adb/magisk/busybox awk`。

**坑 2：awk 里的 `^` 是幂运算**

awk 的 `^` 是乘方，不是异或。异或必须用 `xor()` 函数。
写成 `a ^ b` 会得到天文数字（实测 `0x7FFFFFFF` 饱和值），
最终把整个 state 算成 0。

### 其它实现要点

* **InvMixColumns 的第 4 行**用 `3·a0`，不是 `3·a3`：
  `b3 = 3·a0 ⊕ a1 ⊕ a2 ⊕ 2·a3`
* **CBC 解密**最后一步才是 `P = D(C) ⊕ IV`，且 `IV` 要更新为上一块密文
* **CBC 加密**是 `C = E(P ⊕ IV)`，注意 `E` 的入参已经是异或过 IV 的明文
* **PKCS#7 去填充**：最后一个字节的值就是填充长度
* awk 数组下标是字符串，`W[i*4+j]` 与 `W[i*4 + j]` 等价，但别写成
  `W[i*4+j]` 和 `W[i*(4+j)]` 混用

### 正确性验证

```bash
# 明文 → 本实现加密 → 应与原厂密文逐字节相同
xxd -p <明文> | tr -d ' \n' | busybox awk -f mtaes.awk | tr -d '\n' | xxd -r -p > /tmp/out
cmp /tmp/out /vendor/etc/thermal-normal.conf   # 完全一致
```

---

## 6. 覆写生效机制

`mi_thermald` 是 init 服务：

```
# /vendor/etc/init/hw/init.mi_thermald.rc
service mi_thermald /system/vendor/bin/mi_thermald
    class main
    user root
    group system
    seclabel u:r:mi_thermald:s0
```

配置查找顺序：

1. `/data/vendor/thermal/config/<scenario>.conf`  ← 覆写目录，**优先**
2. `/vendor/etc/thermal-<scenario>.conf`          ← 原厂，回退

init 在 `post-fs-data` 阶段以 `0771 root:system` 创建 `/data/vendor/thermal/config`，
这个目录就是留给用户覆写用的。

改完配置后需要让它重新加载：

```bash
setprop ctl.restart mi_thermald
```

它会在 ~1-2 秒内解密并重新应用，加载结果写在 `/data/vendor/thermal/decrypt.txt`。

> 注意：`mi_thermald` 启动时尝试 `setprop vendor.sys.thermal.data.path` 会被
> SELinux 拒绝（`mi_thermald` 域没有 `vendor_default_prop` 写权限）。
> 这不影响功能 —— 它会回退到硬编码路径 `/data/vendor/thermal/`。

---

## 7. 实时覆写（绕过配置文件）

配置文件改的是「策略」，而直接写 sysfs 是「结果」。两者可以叠加使用：

```bash
# 压大核频率上限
echo 1516800 > /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq

# 压 GPU
echo 315000000 > /sys/class/kgsl/kgsl-3d0/devfreq/max_freq

# 充电限流档位
echo 3 > /sys/class/thermal/cooling_device24/cur_state

# 强制系统温控状态
echo 2 > /sys/class/thermal/thermal_message/temp_state
```

`cooling_device*/cur_state` **可写**（`0644 root:root`），
`max_state` 只读。注意 `mi_thermald` 会周期性覆写 `cur_state`，
所以要长期生效必须持续重放 —— 这正是 `module/service.sh` 里的守护进程在做的事。

`kgsl` 的 devfreq **没有** `hw_max_freq` 节点，原厂上限要靠
`available_frequencies` 的最大值推算。
