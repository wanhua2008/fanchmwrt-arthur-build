#!/bin/sh /etc/rc.common
. /usr/share/libubox/jshn.sh
. /lib/functions.sh

USE_PROCD=1

APP_DIR="/fwx_data/app_list/ArpTable"
LUCI_DIR="$APP_DIR/luci-apps"


detect_pkg_type()
{
	if command -v apk >/dev/null 2>&1; then
		PKG_TYPE="apk"
	else
		PKG_TYPE="ipk"
	fi
}

luci_app_installed()
{
	if [ "$PKG_TYPE" = "apk" ]; then
		apk info -e "$1" >/dev/null 2>&1
	else
		opkg status "$1" 2>/dev/null | grep -q "Status: install ok installed"
	fi
}

find_luci_pkg_file()
{
	PKG_NAME="$1"
	PKG_FILE="$LUCI_DIR/$PKG_NAME.$PKG_TYPE"
	if [ -f "$PKG_FILE" ]; then
		echo "$PKG_FILE"
		return 0
	fi

	for PKG_FILE in "$LUCI_DIR/$PKG_NAME"_*."$PKG_TYPE"; do
		if [ -f "$PKG_FILE" ]; then
			echo "$PKG_FILE"
			return 0
		fi
	done

	return 1
}

install_luci_app()
{
	PKG_NAME="$1"
	if luci_app_installed "$PKG_NAME"; then
		return 0
	fi

	PKG_FILE="$(find_luci_pkg_file "$PKG_NAME")"
	if [ -z "$PKG_FILE" ]; then
		echo "luci package not found: $PKG_NAME"
		return 1
	fi

	if [ "$PKG_TYPE" = "apk" ]; then
		apk add --allow-untrusted "$PKG_FILE"
	else
		opkg install "$PKG_FILE"
	fi
}

check_and_install_luci_app()
{
	detect_pkg_type
	install_luci_app luci-app-fwx-arp-table|| return 1
	install_luci_app luci-i18n-fwx-arp-table-zh-cn|| return 1
	
}


stop_service(){
	echo "stop"
}

start_service(){
	check_and_install_luci_app
	echo "start"	
}
