<p align="center">
  <img width="128" height="128" alt="PasteDirect" src="https://github.com/user-attachments/assets/9873c83e-8839-4a49-86a4-aaf9c8439f07" />
</p>

<h1 align="center">PasteDirect</h1>

<p align="center">
  轻量、安全、纯本地的 macOS 剪贴板历史管理工具
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.0-orange" alt="Swift 5.0">
  <img src="https://img.shields.io/badge/version-2.4.0-green" alt="Version 2.4.0">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

## 特性

- 🔒 **纯本地运行** — 所有数据存储在本地 SQLite 数据库，零网络请求，隐私无忧
- 📋 **多格式支持** — 文本、图片、HTML、RTF、富文本、代码片段，通通记录
- 🎨 **颜色识别** — 自动检测剪贴板中的 Hex 颜色值并可视化展示
- ⌨️ **快捷键呼出** — 默认 `⌘⇧V`，支持自定义快捷键
- 🔍 **快速搜索** — 输入关键词即时过滤历史记录
- 🏷️ **多维筛选** — 按类型（文本/图片/颜色）、来源应用、时间范围组合筛选
- 🖱️ **多种粘贴方式** — 双击粘贴、回车粘贴、拖拽到目标位置
- 📝 **纯文本模式** — 一键去除富文本格式，粘贴为纯文本
- 🧹 **自动清理** — 可设置保留时长：1 天 / 1 周 / 1 月
- 🚫 **应用过滤** — 可忽略特定应用（如钥匙串、密码管理器）的剪贴板内容
- 🪟 **适配 macOS 26** — 全面支持液态玻璃（Liquid Glass）效果
<p align="center">
  <img width="2048" alt="PasteDirect 主界面" src="https://github.com/user-attachments/assets/4d0537b6-6a1b-4ca4-941f-ca69c6fd12fd" />
</p>
<p align="center">
  <img width="2048" alt="PasteDirect 图片支持" src="https://github.com/user-attachments/assets/ba789e7e-502a-4ed1-83ef-208447130406" />
</p>

## 安装

### 下载

从 [Releases](https://github.com/nanshanyi/PasteDirect/releases) 下载最新版本的 `.app` 文件，拖入 `/Applications` 目录即可。

### 首次运行

由于使用自签名证书，首次运行需要手动授权：

1. 右键点击 `PasteDirect.app` → 选择「打开」
2. 在弹出的对话框中点击「打开」

或通过终端：

```bash
xattr -cr /Applications/PasteDirect.app
open /Applications/PasteDirect.app
```

首次启动后，系统会提示授予「辅助功能」权限，这是监听剪贴板和模拟粘贴操作所必需的。

### 更新无忧

从 v2.2.0 起，应用采用自签名证书机制，更新时辅助功能权限自动保留，无需重新授权。

## 使用方式

| 操作 | 说明 |
|------|------|
| `⌘⇧V` | 呼出 / 隐藏剪贴板面板（可自定义） |
| 双击 | 粘贴选中项 |
| `Enter` | 粘贴选中项 |
| `Delete` | 删除选中项 |
| 拖拽 | 将条目拖拽到目标位置直接粘贴 |
| 输入文字 | 搜索过滤历史记录 |

<p align="center">
  <img width="629" alt="PasteDirect 设置" src="https://github.com/user-attachments/assets/a315da78-25d5-4382-8d93-4d827ec14a62" />
</p>

## 设置选项

- **开机启动** — 登录时自动运行
- **状态栏图标** — 显示 / 隐藏菜单栏图标
- **直接粘贴** — 选中后自动粘贴到当前应用
- **纯文本粘贴** — 去除格式，仅粘贴纯文本
- **历史保留时长** — 立即 / 1 天 / 1 周 / 1 月
- **忽略应用** — 配置不记录剪贴板的应用列表
- **快捷键** — 自定义全局呼出快捷键

## 从源码构建

### 环境要求

- macOS 13.0+
- Xcode 14+
- Swift 5.0+

### 构建步骤

```bash
git clone https://github.com/nanshanyi/PasteDirect.git
cd PasteDirect
open PasteDirect.xcodeproj
```

在 Xcode 中选择 `PasteDirect` scheme，点击运行即可。依赖通过 Swift Package Manager 自动拉取。

### 依赖项

| 库 | 用途 |
|----|------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 全局快捷键 |
| [SQLite.swift](https://github.com/nicklama/SQLite.swift) | 本地数据库 |
| [SnapKit](https://github.com/SnapKit/SnapKit) | Auto Layout |

## License

MIT License
