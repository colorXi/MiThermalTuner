# Changelog

> 作者：**达人怪** · 微信 `UVWAPP`
> 仓库：<https://github.com/colorXi/MiThermalTuner>

All notable changes to this project are documented here.

## [Unreleased]

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
