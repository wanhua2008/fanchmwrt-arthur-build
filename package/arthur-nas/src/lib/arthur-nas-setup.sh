#!/bin/sh
# ============================================================
# 京东云亚瑟 NAS 共享 - 一键配置脚本（固件内置版）
# ------------------------------------------------------------
# 本脚本已随固件预装，位于 /usr/lib/arthur-nas/arthur-nas-setup.sh
# LuCI 页面「服务 -> 亚瑟NAS共享」的「一键安装」按钮会调用它。
#
# 与早期版本的区别：
#   - LuCI 插件、USB 自动挂载 已编入固件，无需再安装
#   - 本脚本只负责「分区 -> 格式化 -> 挂载 -> Samba 共享」
#
# 全程幂等：重复执行安全，已完成的步骤自动跳过。
# 用法: sh /usr/lib/arthur-nas/arthur-nas-setup.sh
# ============================================================

DISK="/dev/mmcblk0"
PART="${DISK}p27"
MNT="/mnt/mmcblk0p27"
SHARE_NAME="share"

log() { echo "[arthur-nas] $*"; }
die() { echo "[arthur-nas][错误] $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "请用 root 运行"
[ -b "$DISK" ] || die "找不到 eMMC 设备 $DISK"

# ---------- 包管理器 (新固件 apk / 旧固件 opkg) ----------
if command -v apk >/dev/null 2>&1; then
    PKG="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
else
    PKG=""
fi

pkg_install() {
    [ -n "$PKG" ] || return 1
    log "安装软件包: $* ..."
    $PKG update >/dev/null 2>&1 || true
    $PKG install "$@" || die "安装 $* 失败, 请检查路由器外网连通性"
}

# ---------- 1. 分区 ----------
if [ ! -b "$PART" ]; then
    log "未找到 $PART, 开始在磁盘末尾空闲空间创建分区..."
    command -v fdisk >/dev/null 2>&1 || pkg_install fdisk
    TOTAL=$(cat /sys/block/mmcblk0/size 2>/dev/null) || die "读取磁盘大小失败"
    LAST_END=$(fdisk -l "$DISK" 2>/dev/null | awk '$1 ~ /mmcblk0p[0-9]+$/ { if ($3+0 > m) m=$3+0 } END { print m }')
    [ -n "$LAST_END" ] && [ "$LAST_END" -gt 0 ] || die "解析现有分区表失败, 请手动用 cfdisk $DISK 操作"
    FIRST=$(( ((LAST_END + 2047) / 2048) * 2048 ))
    LAST=$((TOTAL - 2049))
    printf 'n\np\n%d\n%d\nw\n' "$FIRST" "$LAST" | fdisk "$DISK" >/dev/null 2>&1
    sleep 2
    blockdev --rereadpt "$DISK" 2>/dev/null || true
    sleep 1
    [ -b "$PART" ] || die "分区创建失败, 请手动操作: fdisk $DISK"
    log "分区创建成功: $PART (起始扇区 $FIRST)"
else
    log "分区 $PART 已存在, 跳过"
fi

# ---------- 2. 格式化 ----------
NEED_FMT=1
if command -v blkid >/dev/null 2>&1; then
    blkid "$PART" >/dev/null 2>&1 && NEED_FMT=0
fi
if [ "$NEED_FMT" = "1" ]; then
    log "格式化 $PART 为 ext4 (约 110G, 需几分钟, 期间勿断电)..."
    command -v mkfs.ext4 >/dev/null 2>&1 || pkg_install e2fsprogs
    mkfs.ext4 -F -m 0 -L "$SHARE_NAME" "$PART" || die "格式化失败"
else
    log "$PART 已有文件系统, 跳过格式化"
fi

# ---------- 3. 挂载 + 开机自动挂载 ----------
mkdir -p "$MNT"
if ! grep -qs "^$PART " /proc/mounts; then
    mount -t ext4 -o rw,noatime "$PART" "$MNT" || die "挂载 $PART 到 $MNT 失败"
fi
chmod 777 "$MNT"
log "已挂载: $MNT"

if ! grep -q "$MNT" /etc/config/fstab 2>/dev/null; then
    UUID=""
    command -v blkid >/dev/null 2>&1 && UUID=$(blkid -o value -s UUID "$PART" 2>/dev/null)
    [ -n "$UUID" ] || UUID="$PART"
    uci add fstab mount >/dev/null
    uci set fstab.@mount[-1].target="$MNT"
    uci set fstab.@mount[-1].uuid="$UUID"
    uci set fstab.@mount[-1].enabled='1'
    uci commit fstab
    log "已写入开机自动挂载配置 (UUID=$UUID)"
else
    log "自动挂载配置已存在, 跳过"
fi

# ---------- 4. Samba 共享 ----------
if ! command -v smbd >/dev/null 2>&1; then
    pkg_install samba4-server wsdd2
fi

touch /etc/config/samba4
if ! uci -q get samba4."$SHARE_NAME" >/dev/null 2>&1; then
    uci add samba4 sambashare >/dev/null
    uci rename samba4.@sambashare[-1]="$SHARE_NAME"
    log "已创建 Samba 共享 $SHARE_NAME"
fi
uci set samba4."$SHARE_NAME".name="$SHARE_NAME"
uci set samba4."$SHARE_NAME".path="$MNT"
uci set samba4."$SHARE_NAME".read_only='no'
uci set samba4."$SHARE_NAME".guest_ok='yes'
uci set samba4."$SHARE_NAME".create_mask='0666'
uci set samba4."$SHARE_NAME".dir_mask='0777'
uci set samba4."$SHARE_NAME".force_root='1'
uci commit samba4

/etc/init.d/samba4 enable
/etc/init.d/samba4 restart

# ---------- 5. USB/SD 自动挂载（组件已随固件安装, 这里只做校验） ----------
if [ -f /usr/lib/arthur-nas/usb-automount.sh ] \
   && [ -f /etc/hotplug.d/block/20-usb-mount ]; then
    chmod 755 /usr/lib/arthur-nas/usb-automount.sh \
              /etc/hotplug.d/block/20-usb-mount 2>/dev/null
    log "USB/SD 自动挂载已就绪"
else
    log "警告: USB/SD 自动挂载组件缺失（固件可能未包含）"
fi

# ---------- 6. NTFS/exFAT 支持检查 ----------
NTFS_OK=0
grep -qw ntfs3 /proc/filesystems 2>/dev/null && NTFS_OK=1
if [ "$NTFS_OK" = "1" ]; then
    log "NTFS 支持: 已启用 (内核原生 ntfs3)"
else
    log "NTFS 支持: 未启用 (需重编固件启用 kmod-fs-ntfs3)"
fi

# ---------- 7. 清理缓存 ----------
rm -rf /tmp/luci-indexcache* 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1

sleep 3
if netstat -ltn 2>/dev/null | grep -q ':445'; then
    log "Samba 服务已启动 (445 端口监听中)"
else
    log "警告: 445 端口未监听, 建议重启路由器后重试"
fi

log "全部完成! 访问地址: \\\\路由器IP\\$SHARE_NAME   (本机挂载点: $MNT)"
log "LuCI 页面: 服务 -> 亚瑟NAS共享"
