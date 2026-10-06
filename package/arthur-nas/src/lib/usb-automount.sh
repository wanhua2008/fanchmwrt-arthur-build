#!/bin/sh
# ============================================================
# USB/SD 存储设备自动挂载 + Samba 共享
# 适用: 亚瑟 FanchmWrt (OpenWrt) — 挂载 => /mnt/<设备名>
#      并自动在 Samba 中增加/移除同名共享
# 触发: /etc/hotplug.d/block/20-usb-mount (热插拔)
# 也可手动执行: sh usb-automount.sh <add|remove> <devname>
# ============================================================

LOG_TAG="usb-mount"
log() { logger -t "$LOG_TAG" "$*"; echo "[$LOG_TAG] $*"; }

ACTION="$1"
DEVNAME="$2"          # 例如 sda1
[ -n "$ACTION" ] && [ -n "$DEVNAME" ] || { log "用法: $0 <add|remove> <devname>"; exit 1; }

DEV="/dev/$DEVNAME"
MNT="/mnt/$DEVNAME"
SHARE="usb_$DEVNAME"

# 忽略非 USB/SD 设备 (只处理 sd*)
case "$DEVNAME" in
	sd*) ;;
	*) exit 0 ;;
esac

# ---------- 移除 ----------
if [ "$ACTION" = "remove" ]; then
	log "检测到拔出: $DEVNAME"
	# 从 Samba 移除共享
	uci -q delete samba4."$SHARE" 2>/dev/null
	uci commit samba4 2>/dev/null
	/etc/init.d/samba4 reload >/dev/null 2>&1
	umount "$MNT" 2>/dev/null || umount -l "$MNT" 2>/dev/null
	rmdir "$MNT" 2>/dev/null
	log "$DEVNAME 已卸载, Samba 共享 $SHARE 已移除"
	exit 0
fi

[ "$ACTION" = "add" ] || exit 0

# ---------- 挂载 ----------
# 等待设备节点就绪
i=0
while [ ! -b "$DEV" ] && [ $i -lt 10 ]; do
	sleep 0.5
	i=$((i + 1))
done
[ -b "$DEV" ] || { log "$DEV 不存在, 放弃"; exit 1; }

# 已经是挂载状态就跳过
if grep -qs "^$DEV " /proc/mounts; then
	log "$DEV 已挂载, 跳过"
	exit 0
fi

mkdir -p "$MNT"

# 自动探测文件系统类型
#   vfat/ext4/f2fs 为内核基础支持
#   ntfs3 / exfat 由本次编译启用（kmod-fs-ntfs3 / kmod-fs-exfat）
FSTYPE=""
if command -v blkid >/dev/null 2>&1; then
	FSTYPE=$(blkid -o value -s TYPE "$DEV" 2>/dev/null)
fi

MOUNTOPT="rw,noatime"
case "$FSTYPE" in
	vfat|msdos) MOUNTOPT="rw,noatime,utf8" ;;
	ext4|ext3|ext2|f2fs) MOUNTOPT="rw,noatime" ;;
	ntfs)
		# 内核原生 ntfs3 驱动（读写，无需 FUSE）
		if grep -qw ntfs3 /proc/filesystems 2>/dev/null; then
			FSTYPE="ntfs3"
			MOUNTOPT="rw,noatime,iocharset=utf8,windows_names"
		else
			FSTYPE=""
		fi
		;;
	ntfs3) MOUNTOPT="rw,noatime,iocharset=utf8,windows_names" ;;
	exfat)
		if grep -qw exfat /proc/filesystems 2>/dev/null; then
			MOUNTOPT="rw,noatime,iocharset=utf8"
		else
			FSTYPE=""
		fi
		;;
esac

# blkid 未识别 或 识别出的类型内核不支持 -> 逐个尝试
if [ -z "$FSTYPE" ]; then
	for t in ext4 vfat f2fs exfat ntfs3; do
		grep -qw "$t" /proc/filesystems 2>/dev/null || continue
		if mount -t "$t" -o rw,noatime "$DEV" "$MNT" 2>/dev/null; then
			FSTYPE="$t"; break
		fi
	done
	if [ -z "$FSTYPE" ]; then
		log "$DEV 无法识别或不受支持的文件系统"
		# 兜底：写提示文件，方便用户排查
		if [ -x /usr/lib/arthur-nas/ntfs-watchdog.sh ]; then
			/usr/lib/arthur-nas/ntfs-watchdog.sh "$DEVNAME" >/dev/null 2>&1
		fi
		rmdir "$MNT" 2>/dev/null
		exit 1
	fi
fi

if ! grep -qs "^$DEV " /proc/mounts; then
	mount -t "$FSTYPE" -o "$MOUNTOPT" "$DEV" "$MNT" 2>/dev/null || {
		# ntfs 可能因 Windows 非正常拔出而拒绝挂载，用 force 再试一次
		if [ "$FSTYPE" = "ntfs3" ]; then
			mount -t ntfs3 -o rw,noatime,iocharset=utf8,force "$DEV" "$MNT" 2>/dev/null || {
				log "$DEV 挂载失败 (类型=$FSTYPE)"
				[ -x /usr/lib/arthur-nas/ntfs-watchdog.sh ] && \
					/usr/lib/arthur-nas/ntfs-watchdog.sh "$DEVNAME" >/dev/null 2>&1
				rmdir "$MNT" 2>/dev/null
				exit 1
			}
		else
			log "$DEV 挂载失败 (类型=$FSTYPE)"
			rmdir "$MNT" 2>/dev/null
			exit 1
		fi
	}
fi

grep -qs "^$DEV " /proc/mounts || { log "$DEV 最终未挂载"; exit 1; }
chmod 777 "$MNT" 2>/dev/null
log "$DEV 已挂载到 $MNT (类型=${FSTYPE:-auto})"

# ---------- 加入 Samba 共享 ----------
touch /etc/config/samba4
uci -q delete samba4."$SHARE"
uci add samba4 sambashare >/dev/null
uci rename samba4.@sambashare[-1]="$SHARE"
uci set samba4."$SHARE".name="$SHARE"
uci set samba4."$SHARE".path="$MNT"
uci set samba4."$SHARE".read_only='no'
uci set samba4."$SHARE".guest_ok='yes'
uci set samba4."$SHARE".create_mask='0666'
uci set samba4."$SHARE".dir_mask='0777'
uci set samba4."$SHARE".force_root='1'
uci commit samba4
/etc/init.d/samba4 reload >/dev/null 2>&1
log "Samba 共享已添加: \\\\路由器IP\\$SHARE"
