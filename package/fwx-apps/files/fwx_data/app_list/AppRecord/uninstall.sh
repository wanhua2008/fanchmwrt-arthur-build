#!/bin/sh

detect_pkg_type() {
	if command -v apk >/dev/null 2>&1; then
		PKG_TYPE="apk"
	else
		PKG_TYPE="ipk"
	fi
}

remove_luci_app() {
	if [ "$PKG_TYPE" = "apk" ]; then
		apk del "$1"
	else
		opkg remove "$1"
	fi
}

detect_pkg_type
remove_luci_app luci-app-fwx-app-record
