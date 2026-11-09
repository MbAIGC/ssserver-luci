#!/bin/sh
#
# 本地/CI 通用的静态检查：不依赖 OpenWrt SDK。
#

set -e

cd "$(dirname "$0")/.."

echo "== shell 语法 =="
for f in root/etc/init.d/ssserver root/etc/uci-defaults/90-ssserver-luci; do
	sh -n "$f"
	echo "ok  $f"
done

echo "== JSON 语法 =="
python3 - <<'PY'
import glob
import json
import sys

bad = 0
for f in sorted(glob.glob('root/usr/share/**/*.json', recursive=True)):
    try:
        with open(f, encoding='utf-8') as fh:
            json.load(fh)
        print('ok  ' + f)
    except Exception as exc:
        bad = 1
        print('ERR ' + f + ': ' + str(exc))
sys.exit(bad)
PY

echo "== LuCI 视图语法 =="
if command -v node >/dev/null 2>&1; then
	# LuCI 视图顶层有 'return view.extend(...)'，不是合法的 CommonJS，
	# 因此用 new Function() 包一层再校验。
	node -e '
		const fs = require("fs");
		for (const f of process.argv.slice(1)) {
			new Function(fs.readFileSync(f, "utf8"));
			console.log("ok  " + f);
		}
	' htdocs/luci-static/resources/view/ssserver/*.js
else
	echo "skip: 未安装 node"
fi

echo "== 防火墙关键词检查（应无输出） =="
if grep -rnE '\b(iptables|ip6tables|nft|nftables|fw3|fw4|tproxy)\b' root/ htdocs/ 2>/dev/null; then
	echo "错误：检测到防火墙相关代码" >&2
	exit 1
fi

echo "全部检查通过"
