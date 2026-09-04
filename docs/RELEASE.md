# 发版指南

应用自 v3.6.0 起使用 [Sparkle](https://sparkle-project.org/) 实现自动更新：

- **ZIP**（`PasteDirect-x.y.z.zip`）是 Sparkle 自动更新的主包，appcast 指向它；
- **DMG**（`PasteDirect-x.y.z.dmg`）仅用于 GitHub Release 页面给新用户手动安装。

最终方案：**Sparkle 2 + GitHub Actions macOS runner + GitHub Releases + GitHub Pages appcast + 自签名证书 + Sparkle EdDSA 签名**。实施分两个阶段：

- **第一阶段**：用本机脚本 `scripts/make-release.sh` 完成签名与 appcast 生成，本地验证整条链路；
- **第二阶段**：迁到 `.github/workflows/release.yml`，推送 `v*` tag 全自动发版。

## CI 发布顺序（严格固定）

```
构建并签名 App
  → 打 ZIP / DMG
  → EdDSA 签名 ZIP
  → 上传 GitHub Release
  → 校验下载地址可用（curl 期待 200）
  → 最后发布 appcast.xml 到 gh-pages
```

先发 appcast 会让客户端读到尚不存在的下载地址，因此 appcast 永远最后发布。

## 构建号规则

- `CFBundleShortVersionString`（`MARKETING_VERSION`）：用户可见版本，如 `3.6.0`；
- `CFBundleVersion`（构建号）：GitHub Actions 以 `20000 + GITHUB_RUN_NUMBER` 计算，**每次发布严格递增**（大于历史值 `11002`）；本机演练脚本使用当前提交数作为临时构建号。Sparkle 用 appcast 的 `sparkle:version` 与本机 `CFBundleVersion` 比较判断是否有更新，固定不变会导致用户永远收不到更新。仓库里的 `CURRENT_PROJECT_VERSION = 11002` 是本地开发默认值，Release 构建通过 `CURRENT_PROJECT_VERSION` 参数注入真实构建号，不修改工作区文件。

## 一次性配置

### 第一阶段：本地验证链路

1. 生成 Sparkle EdDSA 密钥：

   ```bash
   # 工具随 SPM 依赖附带，可这样定位：
   find ~/Library/Developer/Xcode/DerivedData -path "*SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
   ```

   - 运行 `generate_keys`：私钥入本机钥匙串，**终端打印公钥** → 填入 `PasteDirect/Info.plist` 的 `SUPublicEDKey`（替换 `REPLACE_WITH_EDDSA_PUBLIC_KEY`）。
   - 运行 `generate_keys -x eddsa_private.key` 导出私钥，**务必本地妥善备份**；丢失后无法签名后续更新，所有用户将无法自动升级。

2. 跑一遍本地演练（构建号通过 Xcode build setting 注入，不修改工作区文件）：

   ```bash
   scripts/make-release.sh 3.6.0 v3.6.0
   ```

3. 按「升级测试矩阵」逐项验证。若不想真实发 Release，可把生成器的 `--download-url-prefix` 指向本地 `file://` 目录，并把旧版 App 的 `SUFeedURL` 指向本地 appcast。

### 第二阶段：迁到 GitHub Actions

1. 配置 **release Environment** 与 Secrets：

   仓库 **Settings → Environments → New environment** 创建 `release`（与 workflow 中 `environment: release` 一致），并在该环境中添加 Secrets——只有存放在 Environment 里的签名材料才会被发版任务读取：

   | Secret | 内容 |
   |---|---|
   | `CERTIFICATE_P12` | 自签名证书**含私钥**导出的 .p12 的 base64（`base64 -i cert.p12 \| pbcopy`） |
   | `CERTIFICATE_PASSWORD` | 导出 .p12 时设置的密码 |
   | `EDDSA_PRIVATE_KEY` | `eddsa_private.key` 的文本内容（原样粘贴） |

   > .p12 必须是工程 `CODE_SIGN_IDENTITY`（`PasteDirect Code Signing Certificate`）对应的证书，否则 CI 构建签名失败。

2. **保护发版入口**（仓库设置，一次性）：

   - **Tag 保护**：Settings → Tags → 新增保护规则 `v*`，仅允许维护者创建/推送发布 tag，防止普通协作者伪造发布；
   - workflow 只有 `tags: v*` 一个触发器，**没有 `pull_request` 触发**，PR 构建不会执行本工作流、读不到任何签名 Secret；
   - 两个 action（`actions/checkout`、`setup-xcode`）已**钉死 commit SHA**，防上游投毒；升级时需手动改 SHA 并核对 diff；
   - 证书与私钥只写入 runner 的 `$RUNNER_TEMP`，用完即删，不会出现在日志中（GitHub 也会自动遮蔽 Secret 值）。

3. **GitHub Pages**：首次发版后 workflow 会自动创建 `gh-pages` 分支；到 **Settings → Pages** 把 Source 设为 `gh-pages`。更新源即：

   ```
   https://nanshanyi.github.io/PasteDirect/appcast.xml
   ```

## 日常发版（CI 阶段，三步）

1. **更新 CHANGELOG.md**：新增 `## [x.y.z] - YYYY-MM-DD` 小节（CI 校验存在，并提取为 Release 说明与更新弹窗内容）；若有 `[Unreleased]` 小节直接改名。
2. **改版本号**：Xcode → target PasteDirect → General → Version（`MARKETING_VERSION`）改为 `x.y.z`（CI 校验与 tag 一致）。
3. **打 tag**：

   ```bash
   git tag v3.6.0
   git push origin v3.6.0
   ```

## 升级测试矩阵（每次大版本发布前过一遍）

| 场景 | 预期 |
|---|---|
| `3.5.0` → 新版 | 弹出带 Release Notes 的更新提示，下载→安装→重启成功 |
| 旧版已授予辅助功能权限 | 更新后权限保留，无需重新授权（同签名证书 + 同 Bundle ID） |
| 更新下载中点取消 | 取消下载，旧 App 正常继续使用 |
| 更新包被篡改（改动 zip 内容） | EdDSA 校验失败，**拒绝安装**，旧 App 不受影响 |
| 更新失败/中断后 | 旧 App 仍能正常启动（Sparkle 校验通过才替换，替换原子） |
| 新用户首次安装 | Gatekeeper「无法验证开发者」提示需按 README 指引放行（无 Apple 开发者账号时 Sparkle 无法消除该提示；Sparkle 解决的是已安装用户的安全更新与自动替换） |
| 「自动下载更新」开启 | 后台静默下载，退出 App 时自动安装 |
| 「自动检查更新」关闭 | 不再自动检查；「自动下载更新」开关置灰（Sparkle 规定自动下载依赖自动检查） |

## 机制说明

- **appcast 合并幂等**：同版本重复发布会覆盖旧条目，历史条目保留；
- **重发同一版本**：删除远端 tag 重打即可（Release 资产 `--clobber`、appcast 条目覆盖）；
- **更新界面**：Sparkle 标准用户驱动，自动本地化（含中文）；「Skip This Version」存于 `SUSkippedVersion`；
- **旧设置迁移**：`UpdateCoordinator.startup()` 自动把 v3.5.x 的 `autoCheckUpdate` 迁为 `SUEnableAutomaticChecks`、`ignoredUpdateVersion` 迁为 `SUSkippedVersion`，老用户无感且不被授权弹窗打扰；
- **本地测试 appcast 生成**（不签名快速预览；生产 Feed 必须签名）：

  ```bash
  python3 scripts/generate_appcast.py \
    --archive dist/PasteDirect-x.y.z.zip --tag vx.y.z --version x.y.z --build 20042 \
    --signature 'sparkle:edSignature="..." length="..."' \
    --download-url-prefix file:///absolute/path/to/dist \
    --allow-unsigned-feed \
    --out appcast.xml --notes-out release-notes.md
  ```
