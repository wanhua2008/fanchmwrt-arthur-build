#
# Copyright (C) 2026
# License: GPL-2.0
#
# 将 FanchmWrt 应用中心的应用（含 UserSession 内核模块）预置进固件。
# 应用本体是 ADBd 格式 apk 缓存，首次开机由 uci-defaults 注册进 apk 数据库。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=fwx-apps
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/fwx-apps
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=FanchmWrt app center applications (pre-cached)
  DEPENDS:=
  PKGARCH:=all
endef

define Package/fwx-apps/description
  Pre-cached FanchmWrt app center applications:
  HarborFile, AppRecord, ArpTable, NetworkCheck, OPAssistant, UserSession.
  Files land in /fwx_data and /fwx_root; registered into the apk
  database on first boot via uci-defaults (idempotent).
endef

define Build/Compile
endef

define Package/fwx-apps/install
	$(CP) ./files/fwx_root $(1)/
	$(CP) ./files/fwx_data $(1)/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./uci-defaults/99-fwx-apps $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,fwx-apps))
