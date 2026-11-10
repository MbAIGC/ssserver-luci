#!/usr/bin/env bash
#
# 把「Lean 的 ddns-go 二进制 + sirpdboy 的 LuCI 界面」打进 Lean 源码树。
#
# 用法：
#   ./apply.sh /path/to/lede                # 用本目录 vendored 的 sirpdboy 副本
#   ./apply.sh --upstream /path/to/lede     # 实时拉取 sirpdboy 最新源码
#   OPENWRT_DIR=/path/to/lede ./apply.sh
#
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SIRPDBOY_REPO="${SIRPDBOY_REPO:-https://github.com/sirpdboy/luci-app-ddns-go.git}"
SIRPDBOY_REF="${SIRPDBOY_REF:-main}"

UPSTREAM=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--upstream|-u) UPSTREAM=1 ;;
		*) ARGS+=("$a") ;;
	esac
done
OPENWRT_DIR="${ARGS[0]:-${OPENWRT_DIR:-}}"

if [ -z "$OPENWRT_DIR" ] || [ ! -d "$OPENWRT_DIR" ]; then
	echo "用法: $0 [--upstream] /path/to/lede （或设置 OPENWRT_DIR）" >&2
	exit 1
fi

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

DDNS_FEED="$OPENWRT_DIR/feeds/packages/net/ddns-go"
LUCI_FEED="$OPENWRT_DIR/feeds/luci/applications"

# ---------------------------------------------------------------- 0. 源码来源
TMPDIR_SRC=""
cleanup() { [ -n "$TMPDIR_SRC" ] && rm -rf "$TMPDIR_SRC"; }
trap cleanup EXIT

if [ "$UPSTREAM" = 1 ]; then
	log "拉取 sirpdboy 最新源码（$SIRPDBOY_REF）"
	TMPDIR_SRC="$(mktemp -d)"
	git clone --depth 1 --branch "$SIRPDBOY_REF" "$SIRPDBOY_REPO" "$TMPDIR_SRC" >/dev/null 2>&1 \
		|| die "克隆失败：$SIRPDBOY_REPO"
	SIRPDBOY_SHA="$(git -C "$TMPDIR_SRC" rev-parse HEAD)"
	log "sirpdboy@${SIRPDBOY_SHA}"
	DDNS_FILES_SRC="$TMPDIR_SRC/ddns-go/files"
	LUCI_PKG_SRC="$TMPDIR_SRC/luci-app-ddns-go"
	# 上游 init 里有一行非标准 procd 参数，去掉更干净
	sed -i '/procd_set_param log_level/d' "$DDNS_FILES_SRC/ddns-go.init"
else
	log "使用本目录 vendored 的 sirpdboy 副本"
	DDNS_FILES_SRC="$HERE/ddns-go-files"
	LUCI_PKG_SRC="$HERE/luci-app-ddns-go"
	SIRPDBOY_SHA="(vendored)"
fi

# ---------------------------------------------------------------- 1. 后端
log "检查 Lean ddns-go 包"
[ -d "$DDNS_FEED" ] || die "找不到 $DDNS_FEED，先执行 ./scripts/feeds update -a && ./scripts/feeds install -a"

log "用 sirpdboy 版 init/conf 覆盖 Lean ddns-go"
install -m 0755 "$DDNS_FILES_SRC/ddns-go.init" "$DDNS_FEED/files/ddns-go.init"
install -m 0644 "$DDNS_FILES_SRC/ddns-go.conf" "$DDNS_FEED/files/ddns-go.conf"

# ---------------------------------------------------------------- 2. 界面
log "移除 Lean feed 的同名界面包（避免覆盖）"
rm -rf "$LUCI_FEED/luci-app-ddns-go" 2>/dev/null || true
rm -rf "$OPENWRT_DIR/package/feeds/luci/luci-app-ddns-go" 2>/dev/null || true
rm -rf "$OPENWRT_DIR/package/feeds/luci/luci-i18n-ddns-go-zh-cn" 2>/dev/null || true

log "安装 sirpdboy 界面到 package/luci-app-ddns-go"
rm -rf "$OPENWRT_DIR/package/luci-app-ddns-go"
mkdir -p "$OPENWRT_DIR/package/luci-app-ddns-go"
cp -a "$LUCI_PKG_SRC/." "$OPENWRT_DIR/package/luci-app-ddns-go/"

# 清掉 Lean 侧可能残留的 i18n 源，避免和 sirpdboy 的 po 打架
rm -rf "$OPENWRT_DIR/feeds/luci/applications/luci-i18n-ddns-go-zh-cn" 2>/dev/null || true

# ---------------------------------------------------------------- 3. 校验
log "校验关键文件"
for f in \
	"$OPENWRT_DIR/package/luci-app-ddns-go/Makefile" \
	"$OPENWRT_DIR/package/luci-app-ddns-go/htdocs/luci-static/resources/view/ddns-go/config.js" \
	"$OPENWRT_DIR/package/luci-app-ddns-go/root/usr/share/rpcd/ucode/luci.ddns-go" \
	"$DDNS_FEED/files/ddns-go.init" \
	"$DDNS_FEED/files/ddns-go.conf"
do
	[ -e "$f" ] || die "缺少: $f"
done

conf_section="$(sed -n 's/^config \([a-z-]*\) .*/\1/p' "$DDNS_FEED/files/ddns-go.conf" | head -n1)"
js_section="$(grep -oE "NamedSection, 'config', '[a-z-]+'" \
	"$OPENWRT_DIR/package/luci-app-ddns-go/htdocs/luci-static/resources/view/ddns-go/config.js" \
	| grep -oE "'[a-z-]+'$" | tr -d "'")"
[ "$conf_section" = "$js_section" ] || die "section 类型不一致：conf=$conf_section js=$js_section"
log "section 类型一致：$conf_section"

yaml_path="$(grep -oE '/etc/ddns-go/[a-z-]+\.yaml' \
	"$OPENWRT_DIR/package/luci-app-ddns-go/htdocs/luci-static/resources/view/ddns-go/config.js" | head -n1)"
yaml_name="$(basename "$yaml_path")"
grep -q "$yaml_name" "$DDNS_FEED/files/ddns-go.init" || die "init 里没有 $yaml_name"
grep -q '^CONFDIR=/etc/ddns-go' "$DDNS_FEED/files/ddns-go.init" || die "init 的 CONFDIR 不是 /etc/ddns-go"
log "yaml 路径一致：/etc/ddns-go/$yaml_name"

# 界面版本
luci_ver="$(sed -n 's/^PKG_VERSION:=//p' "$OPENWRT_DIR/package/luci-app-ddns-go/Makefile")"
luci_rel="$(sed -n 's/^PKG_RELEASE:=//p' "$OPENWRT_DIR/package/luci-app-ddns-go/Makefile")"
log "界面版本：${luci_ver}-${luci_rel}（sirpdboy@${SIRPDBOY_SHA:0:12}）"

# 供 CI/人工核对"编译的是不是最新版"
{
	echo "SIRPDBOY_REPO=$SIRPDBOY_REPO"
	echo "SIRPDBOY_REF=$SIRPDBOY_REF"
	echo "SIRPDBOY_SHA=$SIRPDBOY_SHA"
	echo "LUCI_APP_VERSION=${luci_ver}-${luci_rel}"
	echo "SECTION=$conf_section"
	echo "YAML=$yaml_name"
} > "$OPENWRT_DIR/.mix-info"
log "写入 $OPENWRT_DIR/.mix-info"

log "完成"
