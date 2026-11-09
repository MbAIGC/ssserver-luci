# SPDX-License-Identifier: MIT
#
# Copyright (C) 2021-2026  sirpdboy  <herboy2008@gmail.com>
# Lua CBI adaptation: 2026  MbAIGC
#
# 这是 luci-app-ddns-go 的 Lua CBI 版本，用于 Lua 派发器的 LuCI
# （LEDE / Lean / luci-compat），不依赖 ucode 与 JS 前端。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ddns-go
PKG_VERSION:=1.6.9
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=sirpdboy <herboy2008@gmail.com>, MbAIGC

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

# 纯文件包：没有源码、没有下载、不需要编译。
# 不覆盖这两个目标的话，默认实现会去 make -C 一个不存在的 PKG_BUILD_DIR。
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI for DDNS-GO (Lua CBI edition)
	DEPENDS:=+luci-base +luci-compat +ddns-go
	PKGARCH:=all
	URL:=https://github.com/MbAIGC/luci-app-ddns-go
endef

define Package/$(PKG_NAME)/description
 DDNS-GO 的 LuCI 界面（Lua CBI 版），适配使用 Lua 派发器的 LuCI
 （LEDE / Lean 等），不依赖 ucode 与 JS 前端。

 提供：控制面板（内嵌 ddns-go Web UI）、基础设置、日志。
 不打包 ddns-go 二进制，依赖系统中已安装的 ddns-go 包。
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-luci-ddns-go $(1)/etc/uci-defaults/99-luci-ddns-go

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/ddns_go.lua $(1)/usr/lib/lua/luci/controller/ddns_go.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/ddns_go
	$(INSTALL_DATA) ./luasrc/model/cbi/ddns_go/config.lua $(1)/usr/lib/lua/luci/model/cbi/ddns_go/config.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/ddns_go
	$(INSTALL_DATA) ./luasrc/view/ddns_go/panel.htm $(1)/usr/lib/lua/luci/view/ddns_go/panel.htm
	$(INSTALL_DATA) ./luasrc/view/ddns_go/log.htm $(1)/usr/lib/lua/luci/view/ddns_go/log.htm
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ -x /etc/uci-defaults/99-luci-ddns-go ] && /etc/uci-defaults/99-luci-ddns-go >/dev/null 2>&1
	rm -f /tmp/luci-indexcache
	/etc/init.d/rpcd restart >/dev/null 2>&1
	[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd reload >/dev/null 2>&1
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
