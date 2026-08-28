include $(TOPDIR)/rules.mk
PKG_NAME:=luci-app-warp
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=dneese
include $(INCLUDE_DIR)/package.mk
define Package/luci-app-warp
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI WARP Service (standalone, no bot)
  DEPENDS:=+luci-base +curl +wireguard-tools +kmod-wireguard
endef
define Package/luci-app-warp/description
  Standalone LuCI page for Cloudflare WARP — status, connect, delete, all traffic, PBR list, MTU, ping. No Telegram bot needed.
endef
define Build/Compile
endef
define Package/luci-app-warp/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/../files/usr/bin/warp-api.sh $(1)/usr/bin/warp-api.sh
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/warp
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/../files/www/luci-static/resources/view/warp/overview.js $(1)/www/luci-static/resources/view/warp/overview.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/../files/usr/share/luci/menu.d/luci-app-warp.json $(1)/usr/share/luci/menu.d/luci-app-warp.json 2>/dev/null || true
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/../files/usr/share/rpcd/acl.d/luci-app-warp.json $(1)/usr/share/rpcd/acl.d/luci-app-warp.json 2>/dev/null || true
endef
$(eval $(call BuildPackage,luci-app-warp))
