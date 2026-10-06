#
# arthur-nas - 京东云亚瑟 NAS 共享套件
#
# 包含三部分：
#   1. eMMC 大分区自动挂载 + Samba 共享（一键配置脚本）
#   2. USB/SD 卡热插拔自动挂载 + 自动并入 Samba 共享
#   3. LuCI 管理页面（服务 -> 亚瑟NAS共享）
#
# 本包只含脚本与 Lua 界面，不含第三方二进制，可安全编入固件。
#
include $(TOPDIR)/rules.mk

PKG_NAME:=arthur-nas
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=FanchmWrt User
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/arthur-nas
  SECTION:=utils
  CATEGORY:=Utilities
  SUBMENU:=Filesystem
  TITLE:=JDCloud Arthur NAS share suite (eMMC + USB/SD auto-mount + Samba)
  DEPENDS:=+samba4-server +block-mount +kmod-usb-storage \
           +kmod-fs-ext4 +kmod-fs-vfat +kmod-fs-ntfs3 +kmod-fs-exfat \
           +kmod-nls-utf8 +kmod-nls-cp936 +luci-compat
  PKGARCH:=all
endef

define Package/arthur-nas/description
  JDCloud Arthur (AX1800 Pro) NAS 共享套件。
  首次开机自动把 eMMC 剩余大分区（约 110G）格式化并挂载为 Samba 共享，
  并支持 U 盘/SD 卡热插拔自动挂载与自动共享。
  提供 LuCI 状态页面（服务 -> 亚瑟NAS共享）。
endef

define Build/Compile
endef

# ---------- 安装 ----------
define Package/arthur-nas/install
	$(INSTALL_DIR) $(1)/usr/lib/arthur-nas
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/arthur_nas
	$(INSTALL_DIR) $(1)/etc/hotplug.d/block
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults

	# ---- 核心脚本 ----
	$(INSTALL_BIN) ./src/lib/arthur-nas-setup.sh  $(1)/usr/lib/arthur-nas/
	$(INSTALL_BIN) ./src/lib/usb-automount.sh     $(1)/usr/lib/arthur-nas/
	$(INSTALL_BIN) ./src/lib/ntfs-watchdog.sh     $(1)/usr/lib/arthur-nas/

	# ---- 热插拔钩子 ----
	$(INSTALL_BIN) ./src/hotplug/20-usb-mount     $(1)/etc/hotplug.d/block/

	# ---- LuCI 界面 ----
	$(INSTALL_DATA) ./src/luci-controller/arthur_nas.lua \
		$(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DATA) ./src/luci-view/page.htm \
		$(1)/usr/lib/lua/luci/view/arthur_nas/

	# ---- 开机初始化脚本 ----
	$(INSTALL_BIN) ./files/arthur-nas.init $(1)/etc/init.d/arthur-nas

	# ---- 首次启动自动配置 (uci-defaults) ----
	$(INSTALL_BIN) ./files/arthur-nas.defaults $(1)/etc/uci-defaults/99-arthur-nas
endef

# ---------- 首次安装/升级后的钩子 ----------
define Package/arthur-nas/postinst
#!/bin/sh
# 仅在真实设备上执行（安装到 rootfs 镜像时 IPKG_INSTROOT 非空，需跳过）
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/arthur-nas enable 2>/dev/null
	rm -rf /tmp/luci-indexcache* 2>/dev/null
	/etc/init.d/rpcd restart 2>/dev/null
fi
exit 0
endef

$(eval $(call BuildPackage,arthur-nas))
