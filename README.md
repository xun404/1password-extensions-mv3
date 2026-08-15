# 1Password 扩展 — Manifest V3 移植版

[English version / 英文版](README-EN.md)

这是 1Password Chrome 扩展 v4.7.5.90（与 **1Password 6** 桌面端兼容的最后一个版本）的非官方 Manifest V3 移植版。

## 为什么存在

- Chrome 已全面停用 Manifest V2 扩展（提示 *"This extension is no longer supported"*）
- 官方 1Password 扩展（v7+）不再支持 1Password 6 桌面端及其本地保险库格式
- 本移植将原 MV2 扩展打补丁改造为 Manifest V3，保持与 1Password 6 的兼容

## 改动内容

| 文件 | 改动 |
|------|------|
| `manifest.json` | MV2 → MV3：`service_worker`、`action`、`host_permissions` |
| `background-wrapper.js` | 提供 `window` polyfill、`browserAction`→`action` 转发、剥离 `webRequestBlocking` |
| `global.min.js` | 补丁 `contextMenus.create` 显式传入 `id` 并使用 `onClicked`（MV3 service worker 要求） |

## 已知问题

- **Go & Fill 跳转失效** — `webRequest.onBeforeRequest` 重定向依赖已被 MV3 移除的 `webRequestBlocking`。表单填充和原生消息通道不受影响。
- **Service Worker 生命周期** — 空闲时 Chrome 会回收后台 worker，唤醒时会自动重连原生消息，偶有感知延迟。
- **Enhanced Safe Browsing 提示** — 扩展文件与 Web Store 原始哈希不一致会被标记为不受信任，纯外观问题。
- **无后续更新** — 这是静态补丁，不会随 v4.7.5.90 之上有任何新功能或安全修复。
- **自行承担风险** — 非官方、无支持、未经 AgileBits 认可。

## 桌面端修复："Browser's runtime signature invalid (103)"

安装扩展后，1Password 6 桌面端可能拒绝浏览器连接，扩展控制台出现：

```
[AGENT:NM] Unrecoverable state: Browser's runtime signature invalid (103)
```

这**不是扩展的 bug**。1Password 6 桌面端会用硬编码的 2018 年代白名单校验 Chrome 运行进程的代码签名，只认 `Developer ID Application: Google, Inc. (EQHXZ8M8AV)` 证书；现代 Chrome 由 `Google LLC (EQHXZ8M8AV)` 签名，所以桌面端校验失败。

`fix-1password6.sh` 通过修补桌面端的 `OnePasswordCore.framework` 解决：

- 等长替换 2 处硬编码证书名（`Google, Inc.` → `Google LLC`），**保留签名校验**（只放行 Google LLC 签名的 Chrome）
- 校验补丁后的 requirement 可解析、且本机安装的 Chrome 满足它（`SecStaticCodeCheckValidityWithErrors`）
- **只对** `OnePasswordCore.framework` 重新签名（默认 ad-hoc），App 其余部分一律不动

### 用法

```bash
# 先彻底退出 1Password 和菜单栏的 1Password mini
bash fix-1password6.sh
```

三步交互流程：

1. **选择语言** — `1` 中文，`2` English，回车自动检测
2. **流程 + 环境检查**（只读）— 核对后确认继续
3. **最终执行确认** — 确认后自动备份、打补丁、校验、重签

可选参数：

```bash
bash fix-1password6.sh "证书名"     # 用钥匙串证书签名（默认 ad-hoc，无需证书）
bash fix-1password6.sh --lang=zh   # 跳过语言选择
```

遇到非预期版本的文件会安全中止；成功后脚本会打印精确的回滚命令。

### 重要提示

- 打补丁后**绝不要 `codesign --deep` 整包重签**。重签登录项 `2BUA8C4S2C.com.agilebits.onepassword4-helper`（它就是 1Password mini）会破坏 macOS 13+ 的后台项（BTM）注册，launchd 会拒绝拉起 mini，扩展报"1Password 连接至 1Password mini 失败"。只重签框架即可。
- 若因其他签名改动导致 mini 起不来：`sudo sfltool resetbtm`，重启后再打开 1Password。

## 手动安装

1. 从 [Releases](https://github.com/xun404/1password-extensions-mv3/releases) 下载最新 zip
2. 解压到固定目录（**不能删除**，删除后扩展即失效）
3. Chrome 打开 `chrome://extensions`
4. 开启右上角**开发者模式**
5. 点"加载已解压的扩展程序"，选择解压目录
6. 工具栏出现 1Password 扩展图标即成功

> **注意**：扩展目录必须永久保留在磁盘上。加载后不要删除该目录，否则扩展会失效。

### 更新

下载最新 release，覆盖扩展目录中的文件，然后在 `chrome://extensions` 的扩展卡片上点刷新图标。

## 构建 Release

```bash
git tag v4.7.5.91
git push origin v4.7.5.91
```

GitHub Action 会自动打包扩展并创建 release。

## 许可证 / 归属

原始 1Password 扩展是 **AgileBits, Inc.** 所有的专有软件，详见 [LICENSE.md](LICENSE.md)。

本仓库仅用于存档和兼容目的。
