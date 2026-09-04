#!/bin/bash
# 本地端到端发版演练脚本（第一阶段：验证签名/appcast 链路，再迁移到 GitHub Actions）
#
# 用法:
#   scripts/make-release.sh <版本号> <tag>
#   例如: scripts/make-release.sh 3.6.0 v3.6.0
#
# 产物（输出到 dist/）:
#   PasteDirect-<版本>.zip      Sparkle 自动更新主包（已 EdDSA 签名）
#   PasteDirect-<版本>.dmg      Release 页手动安装包
#   appcast.xml                 与 dist/ 下已有 appcast 合并后的更新源
#   release-notes.md            从 CHANGELOG.md 提取的发布说明
#
# 前置条件:
#   - 已按 docs/RELEASE.md 生成 Sparkle 密钥：
#     公钥已填入 Info.plist 的 SUPublicEDKey；
#     私钥在本机钥匙串（generate_keys 已运行），或通过 EDDSA_KEY_FILE 指定私钥文件
#   - CHANGELOG.md 已包含对应版本小节（## [x.y.z] - 日期）

set -euo pipefail

VERSION="${1:?用法: make-release.sh <版本号，如 3.6.0> <tag，如 v3.6.0>}"
TAG="${2:?用法: make-release.sh <版本号，如 3.6.0> <tag，如 v3.6.0>}"
cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

if [[ "$VERSION" != "${TAG#v}" ]]; then
  echo "错误: 版本号 ($VERSION) 应与 tag ($TAG) 前缀一致（v3.6.0 ↔ 3.6.0）" >&2
  exit 1
fi

PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" PasteDirect/Info.plist 2>/dev/null || true)
if [[ -z "$PUBLIC_KEY" || "$PUBLIC_KEY" == REPLACE_* ]]; then
  echo "错误: PasteDirect/Info.plist 尚未配置有效的 SUPublicEDKey，请先运行 Sparkle generate_keys" >&2
  exit 1
fi

# 构建号与 CI 保持同一规则: 20000 + 提交数（严格递增，Sparkle 据此判断更新）
BUILD=$((20000 + $(git rev-list --count HEAD)))

DERIVED_DATA="$REPO_ROOT/.build/release"

echo "==> 构建号: ${BUILD}，开始 Release 构建..."
xcodebuild -project PasteDirect.xcodeproj \
  -scheme PasteDirect \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  build
APP="$DERIVED_DATA/Build/Products/Release/PasteDirect.app"

BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "错误: 工程版本号 ($BUILT_VERSION) 与参数 ($VERSION) 不一致，请先更新 MARKETING_VERSION" >&2
  exit 1
fi

echo "==> 打包 ZIP（Sparkle 更新主包）与 DMG（手动安装）..."
mkdir -p dist
rm -f "dist/PasteDirect-$VERSION.zip" "dist/PasteDirect-$VERSION.dmg" "dist/release-notes.md"
ditto -c -k --keepParent "$APP" "dist/PasteDirect-$VERSION.zip"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "PasteDirect $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "dist/PasteDirect-$VERSION.dmg"
rm -rf "$STAGING"

# 定位 SPM 检出的 Sparkle 工具（本地演练也支持发布版 tarball 的 bin，通过 SIGN_UPDATE 环境变量指定）
if [[ -z "${SIGN_UPDATE:-}" ]]; then
  SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData "$REPO_ROOT/.build" \
    -path "*SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    -type f -perm -111 2>/dev/null | head -1)"
fi
if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "错误: 未找到 sign_update，请先在 Xcode 中解析一次 Sparkle 依赖，或设置 SIGN_UPDATE=/path/to/sign_update" >&2
  exit 1
fi

echo "==> EdDSA 签名 ZIP 并生成 appcast..."
GENERATE_ARGS=(
  scripts/generate_appcast.py
  --archive "dist/PasteDirect-$VERSION.zip"
  --tag "$TAG"
  --version "$VERSION"
  --build "$BUILD"
  --sign-update "$SIGN_UPDATE"
  --out dist/appcast.xml
  --notes-out dist/release-notes.md
)
if [[ -n "${EDDSA_KEY_FILE:-}" ]]; then
  GENERATE_ARGS+=(--key-file "$EDDSA_KEY_FILE")
fi
# 使用已有 appcast 合并历史条目；生成器会在最终写出后签名整个 Feed。
if [[ -f "dist/appcast.xml" ]]; then
  GENERATE_ARGS+=(--existing dist/appcast.xml)
fi
python3 "${GENERATE_ARGS[@]}"

cat <<EOF

完成。产物在 dist/:
  PasteDirect-$VERSION.zip   (Sparkle 更新主包)
  PasteDirect-$VERSION.dmg   (手动安装包)
  appcast.xml / release-notes.md

本地验证更新链路（不必真实发 Release）:
  1. 安装一个"旧版本" app 到 /Applications（辅助功能权限已授予的状态）
  2. 用本地更新源启动检查（终端执行）:
     defaults write com.nanshanyi.PasteDirect SUFeedURL "file://$REPO_ROOT/dist/appcast.xml"
  3. 启动 App → "检查更新..."，应弹出带 Release Notes 的新版提示
  4. 验证完成后清理:
     defaults delete com.nanshanyi.PasteDirect SUFeedURL

真实发布（或迁移到 GitHub Actions 前的最后演练）:
  gh release create "$TAG" "dist/PasteDirect-$VERSION.zip" "dist/PasteDirect-$VERSION.dmg" \\
    --title "PasteDirect $VERSION" --notes-file dist/release-notes.md
  然后再把 dist/appcast.xml 发布到 gh-pages。
EOF
