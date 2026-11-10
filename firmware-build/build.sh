#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede.git}"
SOURCE_COMMIT="${SOURCE_COMMIT:-27d57f45e01459e0d498efbf44532bfe0dfc1d40}"
BUILD_DIR="${BUILD_DIR:-$HERE/lede}"
CONFIG_FILE="${CONFIG_FILE:-$HERE/config.buildinfo}"
FEEDS_FILE="${FEEDS_FILE:-$HERE/feeds.conf}"

if [ ! -d "$BUILD_DIR/.git" ]; then
  git init "$BUILD_DIR"
  git -C "$BUILD_DIR" remote add origin "$REPO_URL"
fi

git -C "$BUILD_DIR" fetch --depth 1 origin "$SOURCE_COMMIT"
git -C "$BUILD_DIR" checkout --detach FETCH_HEAD

cp "$FEEDS_FILE" "$BUILD_DIR/feeds.conf"
cd "$BUILD_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p package/ssserver-luci package/luci-app-ddns-go
cp -a "$HERE/../ssserver-luci/." package/ssserver-luci/
cp -a "$HERE/../luci-app-ddns-go/." package/luci-app-ddns-go/

cp "$CONFIG_FILE" .config
for opt in \
  CONFIG_PACKAGE_luci-compat=y \
  CONFIG_PACKAGE_ddns-go=y \
  CONFIG_PACKAGE_ssserver-luci=y \
  CONFIG_PACKAGE_luci-app-ddns-go=y \
  CONFIG_PACKAGE_kmod-wireguard=y \
  CONFIG_PACKAGE_kmod-udptunnel4=y \
  CONFIG_PACKAGE_kmod-udptunnel6=y \
  CONFIG_PACKAGE_wireguard-tools=y \
  CONFIG_PACKAGE_luci-proto-wireguard=y
do
  grep -qxF "$opt" .config || echo "$opt" >> .config
done

make defconfig
./scripts/diffconfig.sh > "$HERE/config.actual.diffconfig" || true
cp .config "$HERE/config.actual"

make download -j"$(nproc)"
make -j"$(nproc)" V=s

echo "== image =="
ls -lh bin/targets/x86/64/*combined-efi.img.gz
