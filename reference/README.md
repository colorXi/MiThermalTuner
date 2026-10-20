# reference/decrypted

这里是从**使用者本人设备**上解密出来的 16 个场景配置明文，仅用于研究格式与对比。

* 由 `tools/mt_editor.py pull` 或模块里的 `mt decrypt` 生成
* 文件名与 `/vendor/etc/thermal-*.conf` 一一对应
* `thermal-chg-only.conf` 在原厂就是明文，解密结果与原文件相同
* `thermal-engine.conf` / `thermal-map.conf` 不属于场景配置：
  前者是空的 Qualcomm ATE 模板，后者是场景 ID 映射表

这些内容属于小米 / 高通，**不随本项目授权**。
仓库里保留它们是为了让后来者能看懂格式、能对比不同场景的差异，
不需要的话可以随时删掉 —— 工具本身不依赖这个目录。
