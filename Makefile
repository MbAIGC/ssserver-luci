#
# Copyright (C) 2026 ssserver-luci contributors
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#
# 派生自 9566618/shadowproxy（GPLv3），已移除 sslocal 二进制、TProxy、
# DNS 分流、ACL 与全部防火墙逻辑，仅保留 Shadowsocks 服务端管理。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ssserver-luci
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=ssserver-luci contributors

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
	TITLE:=LuCI for Shadowsocks Rust server (ssserver)
	DEPENDS:=+luci-base
	PKGARCH:=all
	URL:=https://github.com/9566618/shadowproxy
endef

define Package/$(PKG_NAME)/description
 LuCI 界面，用于管理系统中已安装的 Shadowsocks Rust 服务端（ssserver）。

 只负责 UCI 配置、服务启停、运行状态、日志与开机自启。
 不打包 ssserver 二进制，不创建、不修改、不删除任何防火墙规则。
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/ssserver
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/ssserver $(1)/etc/config/ssserver

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/ssserver $(1)/etc/init.d/ssserver

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/90-ssserver-luci $(1)/etc/uci-defaults/90-ssserver-luci

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/ssserver-luci.json $(1)/usr/share/luci/menu.d/ssserver-luci.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/ssserver-luci.json $(1)/usr/share/rpcd/acl.d/ssserver-luci.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/ssserver
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/ssserver/overview.js $(1)/www/luci-static/resources/view/ssserver/overview.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/ssserver/settings.js $(1)/www/luci-static/resources/view/ssserver/settings.js
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/ssserver/advanced.js $(1)/www/luci-static/resources/view/ssserver/advanced.js
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ -x /etc/uci-defaults/90-ssserver-luci ] && /etc/uci-defaults/90-ssserver-luci >/dev/null 2>&1
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload >/dev/null 2>&1
	if [ -x /etc/rc.d/S95ssserver ]; then
		/etc/init.d/ssserver start >/dev/null 2>&1
	fi
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/ssserver stop >/dev/null 2>&1
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /etc/rc.d/S95ssserver /etc/rc.d/K10ssserver
	rm -rf /var/etc/ssserver
}
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
