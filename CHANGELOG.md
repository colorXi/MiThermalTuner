# Changelog

> 作者：**达人怪** · 微信 `UVWAPP`
> 仓库：<https://github.com/colorXi/MiThermalTuner>

All notable changes to this project are documented here.

## [Unreleased]

## [v1.2.0] - 2026-10-20

### Added

- **写操作全部有加载动画 + 超时 + 失败兜底**
  - 全屏遮罩 + 转圈动画，显示当前操作（例：「正在应用预设 **unlock** 到全部 16 个场景…」）
  - 三层超时：原生调用 12 秒看门狗（Java）、JS 侧 15 秒兜底、单个操作 30 秒（预设 90 秒）
  - 失败时弹出**具体原因**（超时 / 命令报错 / 未生效），不再只是「失败」两个字
- **生效校验：确保设置真的成功**
  - 新增 `mt verify` —— 把落盘配置解密出来，和 `mi_thermald` 运行时加载的
    `decrypt.txt` 逐字节比对，输出 `OK` / `MISMATCH`（带 3 次重试，
    避免 mi_thermald 重启后 decrypt.txt 还没刷新造成误报）
  - App 在预设应用、配置保存、频率限制之后都会做校验；
    频率类操作还会回读 sysfs 实际值再比对
- `mt selftest` —— 一键自检（解密 + 加密往返，与原厂密文逐字节比对）

### Fixed

- **彻底去掉对 busybox 的依赖**（KernelSU 用户反馈的安装失败）
  - 之前硬编码 `/data/adb/magisk/busybox`，在 KernelSU / APatch 上根本不存在
  - 之前用 `awk` 的 `xor()` / `and()` / `lshift()` 扩展，而 Android 自带的
    toybox awk **没有**这些函数 → 安装直接 abort
  - 现在 AES 改成**纯算术位运算**（4 位查表），任何 awk 都能跑
  - 十六进制转换不再依赖 `xxd`，改用 `od` + awk 的 `printf "%c"`，并保留 xxd 快路径
  - 安装自检从「探测 awk 有没有 xor()」改成**功能自检**：真的解密一个场景看能不能读出明文
- **App 闪「读取失败」的bug**
  - 根因：`mt_sample` 里有 130 多次 `$(cat ...)` 进程 fork，一次采样要 **2.4 秒**；
    App 切后台时进程被冻结，飞行中的那次调用返回空结果 → 弹一次错误
  - 改用 awk `getline` 一次读完所有节点，**2400ms → 280ms（快 7 倍）**
  - App 侧：原生调用加 12 秒超时看门狗、JS 侧加 15 秒兜底、
    后台暂停轮询 / 回前台静默刷新、连续失败 3 次才提示、防止请求堆积
- 性能：16 个场景的加解密改**并行**执行，`mt decrypt` 5.7s → **1.6s**

### Changed

- 全部场景配置解密耗时 7.7 秒 → 1.6 秒

## [v1.1.1] - 2026-10-20

### Added

- **仓库内提供预编译成品**，不想自己编译的直接下载：
  - `releases/MiThermalTuner-v1.1.1.zip` —— Magisk / KernelSU 模块
  - `releases/MiThermal-v1.1.1.apk` —— 独立图形界面 App
  - `releases/SHA256SUMS.txt` —— 完整性校验
- README 顶部新增「⬇ 直接下载」板块，含安装步骤与推送命令
- `tools/make_release.py` —— 一键生成成品目录与 SHA256 校验文件

### Changed

- 模块版本升到 v1.1.1 / 10101

## [v1.1.0] - 2026-10-20

### Changed

- 项目作者信息统一为 **达人怪**（微信 `UVWAPP`）
  - `module.prop` 的 `author` / `description`
  - README 抬头、联系表、作者区块与英文摘要
  - App「关于」弹窗与界面底部署名
  - 打包脚本的证书 DN
  - GitHub 仓库简介与 Release 说明

## [v1.0.0] - 2026-10-20

### Added

- **MiThermalTuner** Magisk 模块
  - 设备端 busybox awk 实现的 AES-128-CBC 加解密器，与 `mi_thermald` 原厂密文逐字节一致
  - 16 个场景配置的解密 / 查看 / 修改 / 回写
  - 5 个预设档位：`cool` / `mild` / `game` / `unlock` / `stock`
  - 实时 sysfs 覆写：CPU policy、GPU、充电限流、系统温控状态
  - 常驻监控守护进程，CSV 日志自动轮转
- **温控面板** 原生 App
  - WebView + HTML/CSS/JS 深色界面
  - 虚拟温度环形仪表盘 + 温度历史曲线
  - 7 路传感器条形图、CPU/GPU 频率对比
  - 预设一键切换、频率滑块、充电限流档位、温控状态分段按钮
  - 场景 → 节 → 键 三级联动配置编辑器
  - 命令白名单：仅允许 `mt` 的指定子命令，拒绝含 `; | & $ > <` 的输入
- **PC 端工具**
  - `tools/mt_editor.py` —— 批量解密 / 编辑 / 推送场景配置
  - `tools/build_apk.py` —— 免 Gradle 手工构建 APK
  - `tools/build_module_zip.py` —— 打包 Magisk 模块 zip
- **文档**
  - `docs/thermal-config-format.md` —— 配置格式、字段语义、虚拟温度算法、覆盖生效机制
  - `reference/decrypted/` —— 16 个场景的明文配置

### Notes

- 模块只写 `/data/vendor/thermal/config/`，从不修改 `/vendor/etc/`，卸载即回原厂
- Magisk 30.x 已移除模块 WebUI 支持，故图形界面改为独立 App
- 需要 busybox awk 提供 `xor()`（toybox awk 不满足）
