#!/bin/sh
# ==========================================================
# 不支持的文件系统处理钩子 (亚瑟 AX1800 Pro / FanchmWrt)
# ==========================================================
# 背景：NTFS / exFAT 需要内核 kmod 支持。若固件未编译
#       kmod-fs-ntfs3 / kmod-fs-exfat / kmod-fuse，则这类
#       移动硬盘无法挂载。
#
#   本固件（arthur-nas 套件已编入）已包含上述模块，
#   正常情况下 NTFS/exFAT 会被 usb-automount.sh 直接挂载。
#
#   本脚本是「兜底」：当设备仍然挂载失败时，写日志并在共享
#   根目录生成一份说明文件，告诉用户怎么处理。
#
# 调用：ntfs-watchdog.sh <devname>   例如 sda1
# ==========================================================

DEV="$1"
[ -z "$DEV" ] && exit 0
case "$DEV" in sd*) ;; *) exit 0 ;; esac

LOG_TAG="fs-helper"
INFO_DIR="/mnt/mmcblk0p27/_插盘提示"

FS=$(blkid -o value -s TYPE "/dev/$DEV" 2>/dev/null)
[ -z "$FS" ] && FS="unknown"

case "$FS" in
    ntfs|ntfs3|exfat)
        logger -t "$LOG_TAG" "设备 /dev/$DEV 是 $FS，未能自动挂载，写入提示文件"
        mkdir -p "$INFO_DIR"
        {
            echo "检测到设备：/dev/$DEV"
            echo "文件系统  ：$FS"
            echo ""
            echo "本设备未能自动挂载。请按下面顺序排查："
            echo ""
            echo "--------------------------------------------------"
            echo "1) 先看内核是否支持该文件系统"
            echo "--------------------------------------------------"
            echo "   在路由器 SSH 里执行："
            echo "     cat /proc/filesystems | grep -E 'ntfs|exfat'"
            echo "   正常应能看到 ntfs3 和 exfat。"
            echo "   如果没有，说明固件缺少对应内核模块，需要重编固件。"
            echo ""
            echo "--------------------------------------------------"
            echo "2) Windows 上的 NTFS 盘常见原因：非正常拔出"
            echo "--------------------------------------------------"
            echo "   在 Windows 里对该盘执行一次「安全弹出」，"
            echo "   或运行 chkdsk X: /f 修复后再插回路由器。"
            echo ""
            echo "--------------------------------------------------"
            echo "3) 手动挂载测试（把 sda1 换成你的设备名）"
            echo "--------------------------------------------------"
            echo "   mkdir -p /mnt/sda1"
            echo "   mount -t ntfs3 /dev/sda1 /mnt/sda1"
            echo "   # 若报错，把错误信息记下来"
            echo ""
            echo "--------------------------------------------------"
            echo "4) 换一种文件系统（最省事）"
            echo "--------------------------------------------------"
            echo "   ext4：性能最好，Windows 需装 Ext2Fsd / DiskGenius 才能读写。"
            echo "   exFAT：Windows/Mac/Linux 通吃，单文件可超 4GB，推荐移动硬盘用。"
            echo "   FAT32：全兼容但单文件最大 4GB。"
            echo ""
            echo "生成时间：$(date '+%Y-%m-%d %H:%M:%S')"
        } > "$INFO_DIR/插盘提示.txt" 2>/dev/null
        chmod 644 "$INFO_DIR/插盘提示.txt" 2>/dev/null
        ;;
    *)
        logger -t "$LOG_TAG" "设备 /dev/$DEV 文件系统 $FS，交由自动挂载处理"
        ;;
esac

exit 0
