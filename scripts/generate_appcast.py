#!/usr/bin/env python3
"""为 PasteDirect 发布生成/合并 Sparkle appcast.xml。

流程（供 CI 调用，也可本地测试）：
  1. 用 Sparkle 的 sign_update 对更新 ZIP 做 EdDSA 签名
  2. 从 CHANGELOG.md 提取对应版本小节，转成供 Sparkle 弹窗展示的内联 HTML
  3. 对最终 appcast.xml 做 EdDSA 签名
  4. 与已有 appcast 合并（同版本条目幂等覆盖），新条目排在最前

用法示例（Sparkle 更新包推荐用 ZIP，DMG 仅用于 Release 页手动安装）：
  python3 scripts/generate_appcast.py \
      --archive dist/PasteDirect-3.6.0.zip \
      --tag v3.6.0 \
      --version 3.6.0 \
      --build 20042 \
      --key-file eddsa.key \
      --sign-update /path/to/sparkle/bin/sign_update \
      --existing old-appcast.xml \
      --out appcast.xml \
      --notes-out release-notes.md
"""

import argparse
import html
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

REPO_URL = "https://github.com/nanshanyi/PasteDirect"
DOWNLOAD_URL = f"{REPO_URL}/releases/download"
CHANNEL_LINK = "https://nanshanyi.github.io/PasteDirect/appcast.xml"
MIN_SYSTEM_VERSION = "13.0"


def q(name: str) -> str:
    """带 sparkle 命名空间的标签名。"""
    return f"{{{SPARKLE_NS}}}{name}"


ENCLOSURE_TYPES = {
    ".zip": "application/octet-stream",
    ".dmg": "application/octet-stream",
}


def sign_archive(archive: Path, sign_update: str, key_file: str | None) -> tuple[str, int]:
    command = [sign_update, str(archive)]
    if key_file:
        command.extend(["--ed-key-file", key_file])
    result = subprocess.run(
        command,
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"sign_update 失败:\n{result.stdout}\n{result.stderr}")
    match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', result.stdout)
    if not match:
        sys.exit(f"无法解析 sign_update 输出:\n{result.stdout}")
    return match.group(1), int(match.group(2))


def sign_feed(path: Path, sign_update: str, key_file: str | None) -> None:
    command = [sign_update, str(path), "--disable-signing-warning"]
    if key_file:
        command.extend(["--ed-key-file", key_file])
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"sign_update 签名 appcast 失败:\n{result.stdout}\n{result.stderr}")


def parse_signature(raw: str) -> tuple[str, int]:
    match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', raw)
    if not match:
        sys.exit("无法解析 --signature，期望格式: sparkle:edSignature=\"...\" length=\"...\"")
    return match.group(1), int(match.group(2))


def extract_changelog(changelog_path: Path, version: str) -> str:
    text = changelog_path.read_text(encoding="utf-8")
    pattern = rf"^##\s*\[{re.escape(version)}\][^\n]*\n(.*?)(?=^##\s*\[|\Z)"
    match = re.search(pattern, text, re.M | re.S)
    if not match:
        sys.exit(f"CHANGELOG.md 中未找到 [{version}] 小节，请先更新 changelog 再发布")
    return match.group(1).strip()


def markdown_to_html(md: str) -> str:
    """把 changelog 小节转成 Sparkle 更新弹窗可展示的最小 HTML。"""
    html_lines: list[str] = []
    in_list = False

    def close_list():
        nonlocal in_list
        if in_list:
            html_lines.append("</ul>")
            in_list = False

    for line in md.splitlines():
        stripped = line.strip()
        if not stripped:
            close_list()
            continue
        escaped = html.escape(stripped)
        if stripped.startswith("- "):
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            html_lines.append(f"<li>{escaped[2:]}</li>")
        elif stripped.startswith("#"):
            close_list()
            html_lines.append(f"<h4>{escaped.lstrip('#').strip()}</h4>")
        else:
            close_list()
            html_lines.append(f"<p>{escaped}</p>")
    close_list()
    return "\n".join(html_lines)


def parse_existing_items(path: str | None) -> list[ET.Element]:
    if not path:
        return []
    existing = Path(path)
    if not existing.exists():
        print(f"提示: 未找到已有 appcast ({path})，将创建全新文件")
        return []
    tree = ET.parse(existing)
    return list(tree.getroot().findall("./channel/item"))


def make_item(
    version: str,
    build: str,
    download_url_prefix: str,
    archive: Path,
    signature: str,
    length: int,
    notes_html: str,
) -> ET.Element:
    item = ET.Element("item")

    def sub(name: str, text: str) -> ET.Element:
        element = ET.SubElement(item, name)
        element.text = text
        return element

    sub("title", f"Version {version}")
    sub(q("shortVersionString"), version)
    sub(q("version"), str(build))
    sub("pubDate", format_datetime(datetime.now(timezone.utc)))
    sub(q("minimumSystemVersion"), MIN_SYSTEM_VERSION)
    if notes_html:
        sub("description", notes_html)
    enclosure_url = f"{download_url_prefix.rstrip('/')}/{archive.name}"
    enclosure_type = ENCLOSURE_TYPES.get(archive.suffix)
    if enclosure_type is None:
        sys.exit(f"不支持的更新包类型: {archive.name}（仅支持 .zip / .dmg）")
    ET.SubElement(item, "enclosure", {
        "url": enclosure_url,
        q("edSignature"): signature,
        "length": str(length),
        "type": enclosure_type,
    })
    return item


def build_appcast(new_item: ET.Element, old_items: list[ET.Element], version: str) -> ET.Element:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    for name, text in [
        ("title", "PasteDirect"),
        ("link", CHANNEL_LINK),
        ("description", "PasteDirect 更新记录"),
        ("language", "zh-Hans"),
    ]:
        sub = ET.SubElement(channel, name)
        sub.text = text

    # 同版本幂等覆盖（重复发布/重跑 CI 时替换旧条目）
    kept = [old for old in old_items if old.findtext(q("shortVersionString")) != version]
    channel.append(new_item)
    for old in kept:
        channel.append(old)
    return rss


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--archive", required=True, help="Sparkle 更新包路径（推荐 .zip，也支持 .dmg）")
    parser.add_argument("--tag", required=True, help="发布 tag，如 v3.6.0")
    parser.add_argument("--download-url-prefix", help="更新包下载地址前缀；默认使用该 tag 的 GitHub Release 地址")
    parser.add_argument("--version", required=True, help="营销版本号，如 3.6.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion 构建号")
    parser.add_argument("--key-file", help="EdDSA 私钥文件路径；不传则从 Sparkle Keychain 读取")
    parser.add_argument("--sign-update", default="sign_update", help="sign_update 可执行文件路径")
    parser.add_argument("--signature", help='直接传入签名（跳过 sign_update），格式: sparkle:edSignature="..." length="..."')
    parser.add_argument("--changelog", default="CHANGELOG.md", help="CHANGELOG 路径")
    parser.add_argument("--existing", help="已有 appcast.xml 路径（用于合并）")
    parser.add_argument("--out", default="appcast.xml", help="输出 appcast 路径")
    parser.add_argument("--notes-out", help="同时把该版本的 changelog 原文写到该文件（供 gh release 用）")
    parser.add_argument("--allow-unsigned-feed", action="store_true", help="仅用于本地预览，跳过 appcast 签名")
    args = parser.parse_args()

    archive = Path(args.archive)
    if not archive.exists():
        sys.exit(f"更新包不存在: {archive}")

    if args.signature:
        signature, length = parse_signature(args.signature)
    else:
        signature, length = sign_archive(archive, args.sign_update, args.key_file)

    notes_markdown = extract_changelog(Path(args.changelog), args.version)
    notes_html = markdown_to_html(notes_markdown)

    old_items = parse_existing_items(args.existing)
    download_url_prefix = args.download_url_prefix or f"{DOWNLOAD_URL}/{args.tag}"
    item = make_item(args.version, args.build, download_url_prefix, archive, signature, length, notes_html)
    rss = build_appcast(item, old_items, args.version)

    tree = ET.ElementTree(rss)
    try:
        ET.indent(tree, space="    ")
    except AttributeError:
        pass  # Python < 3.9，跳过美化
    tree.write(args.out, encoding="utf-8", xml_declaration=True)

    if not args.allow_unsigned_feed:
        sign_feed(Path(args.out), args.sign_update, args.key_file)

    if args.notes_out:
        Path(args.notes_out).write_text(notes_markdown + "\n", encoding="utf-8")

    print(f"已生成 {args.out}（版本 {args.version}, build {args.build}, {length} 字节），"
          f"合并历史条目 {len(old_items) - sum(1 for o in old_items if o.findtext(q('shortVersionString')) == args.version)} 条")


if __name__ == "__main__":
    main()
