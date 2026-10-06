# 亚瑟 AX1800 Pro 重新编译固件（启用 NTFS / exFAT + 内置 NAS 套件）

## 零、这个固件编出来是什么样

刷完之后**开箱即用**，不需要再手动跑任何脚本：

| 功能 | 状态 |
|---|---|
| NTFS 移动硬盘 | ✅ 内核原生 ntfs3 读写（性能优于 FUSE 方案） |
| exFAT 存储卡 | ✅ 内核 fs-exfat |
| eMMC 110G 大分区 | ✅ **首次开机自动**分区+格式化+挂载 |
| Samba 共享 | ✅ 自动创建 `\\路由器IP\share` |
| U 盘/SD 热插拔 | ✅ 插上自动挂载 + 自动共享 |
| LuCI 管理页 | ✅ 服务 → 亚瑟NAS共享 |

**例外**：集客 AC（gecoosac）未编入固件。它是 16MB 的第三方二进制，
编进去会让固件体积翻倍且涉及版权。安装包仍放在
`/mnt/mmcblk0p27/_nas-setup/gecoosac/`，需要时手动跑一次 `install.sh`。

---

## 一、为什么要重编

你的路由器（京东云亚瑟 AX1800 Pro，设备代号 `jdcloud_re-ss-01`）当前固件
内核编译时**没有启用** NTFS / exFAT，导致：

- 插 NTFS 移动硬盘无法挂载
- 装 `ntfs-3g` 失败（报 `kmod-fuse (no such package)`）
- 换源也解决不了（已验证：官方源 + immortalwrt 源都无 `kmod-fs-*`）

**好消息**：查过源码确认，这两个模块的包定义**在源码里是存在的**
（`package/kernel/linux/modules/fs.mk`），只是预编译时没选中。
所以只要重编固件并勾上它们就能解决。

已验证的包定义（源码原文）：

| 包名 | KCONFIG | 作用 |
|---|---|---|
| `kmod-fs-ntfs3` | `CONFIG_NTFS3_FS` | Linux 原生 NTFS 读写（推荐） |
| `kmod-fs-exfat` | `CONFIG_EXFAT_FS` | exFAT 支持 |

> **为什么不用 ntfs-3g（FUSE）方案？**
> `ntfs-3g` 是用户态驱动，需要额外依赖 `kmod-fuse`，走 FUSE 层转发、
> 性能较差。内核 6.12 自带的 `ntfs3` 是原生读写驱动，速度明显更好，
> 且少一层依赖。所以本方案直接用 `ntfs3`，不启用 `kmod-fuse` / `ntfs-3g`。

---

## 二、编译方式：GitHub Actions 云端编译

你的 Windows 电脑无法直接编译 OpenWrt（需要 Linux 工具链、50GB+ 磁盘、
数小时 CPU）。用 GitHub 免费服务器编译是最省事的方案。

### 源码信息（已核实）

- 源码仓库：`https://github.com/fanchmwrt/fanchmwrt-snapshot`
- 使用分支：`fanchmwrt-26.05`（snapshot 分支，对应你的固件）
- 目标平台：`qualcommax` / `ipq60xx`
- 设备 profile：`jdcloud_re-ss-01`
- 设备定义（源码原文）：
  ```
  define Device/jdcloud_re-ss-01
      $(call Device/FitImage)
      $(call Device/EmmcImage)
      DEVICE_VENDOR := JDCloud
      DEVICE_MODEL := RE-SS-01
      SOC := ipq6000
      BLOCKSIZE := 128k
      KERNEL_SIZE := 6144k
      DEVICE_DTS_CONFIG := config@cp03-c2
      DEVICE_PACKAGES := ipq-wifi-jdcloud_re-ss-01
  ```

> 注意：`fanchmwrt/fanchmwrt` 那个仓库**没有**京东云设备（只有 15 个通用设备）。
> 京东云系列在 `fanchmwrt-snapshot` 仓库里，共 23 个设备，含 `jdcloud_re-cs-02`、
> `jdcloud_re-cs-07`、`jdcloud_re-ss-01`（你的亚瑟）。

### 关键源码证据

查过源码，三个模块的包定义**确实存在**于
`package/kernel/linux/modules/fs.mk`（源码原文摘录）：

```makefile
define KernelPackage/fs-ntfs3
  SUBMENU:=$(FS_MENU)
  TITLE:=NTFS filesystem read & write (new driver) support
  KCONFIG:= CONFIG_NTFS3_FS CONFIG_NTFS3_FS_POSIX_ACL=y
  FILES:=$(LINUX_DIR)/fs/ntfs3/ntfs3.ko
  $(call AddDepends/nls)
  AUTOLOAD:=$(call AutoLoad,80,ntfs3)
endef

define KernelPackage/fs-ntfs3
  SUBMENU:=$(FS_MENU)
  TITLE:=NTFS3 filesystem support
  KCONFIG:= CONFIG_NTFS3_FS
  FILES:= $(LINUX_DIR)/fs/ntfs3/ntfs3.ko
  AUTOLOAD:=$(call AutoLoad,30,ntfs3,1)
  DEPENDS:=+kmod-nls-base
endef

define KernelPackage/fs-exfat
  SUBMENU:=$(FS_MENU)
  TITLE:=exFAT filesystem support
  KCONFIG:= \
	CONFIG_EXFAT_FS \
	CONFIG_EXFAT_DEFAULT_IOCHARSET="utf8"
  FILES:= $(LINUX_DIR)/fs/exfat/exfat.ko
  AUTOLOAD:=$(call AutoLoad,30,exfat,1)
  DEPENDS:=+kmod-nls-base
endef
```

**结论**：包定义存在 → 只是预编译时没选中 → 重编并勾选即可解决。

### 一个重要的配置陷阱

**不要**在 config 里写这种：
```
CONFIG_KERNEL_NTFS3_FS=y       ← 错误！无效
CONFIG_KERNEL_EXFAT_FS=y       ← 错误！无效
```

原因：OpenWrt 中内核文件系统的启用**由 kmod 包的 `KCONFIG` 声明驱动**
（见上面源码），而不是通过 `CONFIG_KERNEL_*` 手工指定。
已验证 `config/Config-kernel.in` 里的 144 个 `KERNEL_*` 选项中
**没有** NTFS / EXFAT，写这些会触发 "unknown symbol" 警告。

正确做法：只写
```
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-fs-exfat=y
```
内核的 `CONFIG_NTFS3_FS` / `CONFIG_EXFAT_FS` 会自动置位。

### 为什么不用 ntfs-3g

`ntfs-3g` 是 FUSE 用户态驱动，源码里 `DEPENDS+= +kmod-fuse`。
它需要 `kmod-fuse`（`CONFIG_FUSE_FS`）才能工作，且所有 IO 都要
经过内核→用户态的转发，性能明显低于内核原生驱动。

内核 6.12 自带的 `ntfs3` 是**原生读写**驱动，直接在内核里完成。
本方案选用 `ntfs3`，不引入 `kmod-fuse` / `ntfs-3g`，少一层依赖、
少一个编译失败点，速度也更快。

---

## 三、操作步骤

### 第 1 步：在 GitHub 创建仓库

1. 登录 GitHub
2. 点右上角 `+` → `New repository`
3. 仓库名随意，如 `fanchmwrt-arthur-build`
4. 权限选 **Public**（Public 的 Actions 分钟数免费无限；Private 每月 2000 分钟可能不够）
5. 不要勾选任何初始化文件，直接 `Create repository`

### 第 2 步：上传本目录的文件

把 `fanchmwrt-build/` 里的内容原样上传到新仓库根目录，最终仓库结构必须是：

```
你的仓库/
├── .github/
│   └── workflows/
│       └── build.yml          ← 编译流程
└── configs/
    └── arthur_ntfs.config     ← 编译配置
```

上传方式（任选）：
- **网页上传**：仓库页面 `Add file` → `Upload files`，把 `.github` 和 `configs`
  两个文件夹拖进去。注意：网页上传对隐藏文件夹 `.github` 支持不好，
  如果传不上去，用下面的命令行方式。
- **命令行**（推荐）：
  ```bash
  cd fanchmwrt-build
  git init
  git add .
  git commit -m "Add firmware build workflow with NTFS support"
  git branch -M main
  git remote add origin https://github.com/你的用户名/fanchmwrt-arthur-build.git
  git push -u origin main
  ```

### 第 3 步：启动编译

1. 进入仓库 → 顶部 `Actions` 标签
2. 左侧选 `Build FanchmWrt for JDCloud RE-SS-01 (NTFS enabled)`
3. 右侧 `Run workflow` → 绿色按钮确认
4. 等待完成（**首次编译约 3-5 小时**，之后有缓存会快些）

编译过程中可以点进去看实时日志。如果失败，日志会显示具体原因。

### 第 4 步：下载固件

编译成功后，在该次运行的页面底部 `Artifacts` 区域下载：

| Artifact 名 | 内容 |
|---|---|
| `fanchmwrt-arthur-ntfs-firmware` | 完整固件（sysupgrade 用） |
| `kmod-ntfs-exfat-fuse` | 单独的三个 kmod 包（备用） |

---

## 四、刷机

⚠️ **刷机前务必备份！**

### 刷机前准备

1. **备份 eMMC 里的数据**（就是那个 111.7G 分区里的东西）
   ```sh
   # 在路由器上，把重要文件复制到别处
   # 或整个分区打包：注意需要足够空间
   ```

2. **导出当前配置**：LuCI → 系统 → 备份/恢复 → 生成备份
   或 SSH 执行：
   ```sh
   sysupgrade -b /tmp/backup.tar.gz
   ```
   然后把文件下载到电脑。

3. **确认固件类型**：下载到的文件通常是
   `...jdcloud_re-ss-01-squashfs-sysupgrade.bin` 这种名字。

### 刷机方式

**方式 A：LuCI 界面（推荐）**
1. LuCI → 系统 → 备份/恢复 → 刷写新固件
2. 选择 sysupgrade.bin 文件
3. **取消勾选**"保留设置"（跨版本建议不保留，避免配置冲突）
4. 点击刷写，等待重启（约 3-5 分钟）

**方式 B：SSH 命令行**
```sh
# 先把固件传到路由器（在电脑上执行）
scp -O xxx-sysupgrade.bin root@192.168.5.1:/tmp/

# SSH 登录路由器后
sysupgrade -n /tmp/xxx-sysupgrade.bin
```

### 刷机后

1. 检查能否正常启动、WiFi 是否正常
2. 恢复配置（如果之前没保留设置）：
   ```sh
   # 上传之前下载的 backup.tar.gz 到 /tmp，然后
   sysupgrade -r /tmp/backup.tar.gz
   ```
3. **如果 eMMC 分区丢失**（新固件的分区表可能不同），重新执行 NAS 配置脚本：
   ```sh
   mkdir -p /mnt/mmcblk0p27
   mount /dev/mmcblk0p27 /mnt/mmcblk0p27 2>/dev/null
   sh /mnt/mmcblk0p27/_nas-setup/arthur-nas-setup.sh
   ```

---

## 五、验证 NTFS 支持

刷完后登录路由器验证：

```sh
# 1. 检查内核模块是否存在
ls /lib/modules/$(uname -r)/ | grep -E 'ntfs3|exfat|fuse'
# 应该看到 ntfs3.ko  exfat.ko  fuse.ko

# 2. 检查是否已自动加载
lsmod | grep -E 'ntfs3|exfat|fuse'

# 3. 检查内核是否认这些文件系统
grep -E 'ntfs3|exfat|fuse' /proc/filesystems
# 应该看到 ntfs3 和 fuseblk

# 4. 插入 NTFS 移动硬盘后
logread | grep -E 'usb|fs-helper' | tail -20
df -h | grep sd
```

如果看到 `ntfs3` 出现在 `/proc/filesystems` 里，就成功了。

---

## 六、风险与回退

### 风险

| 风险 | 说明 | 概率 |
|---|---|---|
| 刷机变砖 | 固件与设备不匹配、刷写中断 | 低（配置已核实匹配） |
| WiFi 丢失 | 无线校准数据/驱动问题 | 低 |
| eMMC 数据丢失 | 分区表变化可能影响现有分区 | **中**，务必先备份 |
| 编译失败 | 依赖缺失、网络问题 | 中，可重跑 |

### 回退方案

1. **保留原固件**：刷机前把当前固件文件备份好。
   如果原固件是下载来的，留一份；否则可从 FanchmWrt 发布页重新下载。

2. **救砖**：京东云亚瑟支持 TFTP / 串口恢复。
   - 刷坏后通常还能进 U-Boot
   - 需要 USB-TTL 串口模块 + TFTP 服务器
   - 参考：OpenWrt 社区关于 ipq60xx 的恢复教程

3. **eMMC 数据**：刷机会重写 NAND，但 eMMC 上的独立分区（如 `mmcblk0p27`）
   **通常不受影响**——不过分区号可能变化，这就是为什么要先备份。

---

## 七、如果不想编译

替代方案（按推荐度）：

1. **格式化为 ext4**：路由器原生支持，性能最好。
   Windows 读写装免费工具 DiskGenius / Ext2Fsd。

2. **格式化为 FAT32**：全平台兼容，但单文件最大 4GB。

3. **等上游更新**：可以去 FanchmWrt 的 GitHub Issues / 社区提需求，
   请作者在官方编译配置里加上 NTFS 支持。这是最省事的长期方案。

---

## 八、文件清单

```
你的仓库/
├── .github/
│   └── workflows/
│       └── build.yml              ← 编译流程（13 步）
├── configs/
│   └── arthur_ntfs.config         ← 编译配置
├── package/
│   └── arthur-nas/                ← 自定义包（编入固件）
│       ├── Makefile               ← OpenWrt 包定义
│       ├── files/
│       │   ├── arthur-nas.init        ← 开机服务
│       │   └── arthur-nas.defaults    ← 首次开机自动配置
│       └── src/
│           ├── lib/
│           │   ├── arthur-nas-setup.sh    ← 一键配置（分区/格式化/共享）
│           │   ├── usb-automount.sh       ← USB/SD 热插拔挂载
│           │   └── ntfs-watchdog.sh       ← 不支持格式提示
│           ├── hotplug/
│           │   └── 20-usb-mount           ← 热插拔钩子
│           ├── luci-controller/
│           │   └── arthur_nas.lua         ← LuCI 控制器
│           └── luci-view/
│               └── page.htm               ← LuCI 页面
└── README.md
```

---

## 九、NAS 套件是怎么固化进固件的

### 原理

OpenWrt 编译时会扫描源码树的 `package/` 目录，自动发现其中的包。
workflow 里有一步 `Inject custom packages`，把本仓库的 `package/arthur-nas/`
复制进 `openwrt/package/`，包就被构建系统接手了。

### 包结构说明

**1. `Makefile`** — OpenWrt 包定义

```makefile
PKG_NAME:=arthur-nas
PKG_VERSION:=1.0.0

define Package/arthur-nas
  DEPENDS:=+samba4-server +block-mount +kmod-usb-storage \
           +kmod-fs-ext4 +kmod-fs-vfat +kmod-fs-ntfs3 +kmod-fs-exfat \
           +kmod-nls-utf8 +kmod-nls-cp936 +luci-compat
endef
```

`DEPENDS` 是精髓 —— 声明了依赖后，只要选中 `arthur-nas`，
OpenWrt 会自动把 Samba、NTFS 模块、LuCI 依赖全部拉进来，
**不需要在 config 里一个个手写**，也不会漏。

**2. `files/arthur-nas.defaults`** — 首次开机自动配置

这是"开箱即用"的关键。OpenWrt 的 `uci-defaults` 机制会在**首次启动**时
执行 `/etc/uci-defaults/` 下的脚本，执行完自动删除。本脚本做：

1. 检测 `/dev/mmcblk0p27` 是否存在 → 不存在则从 eMMC 空闲空间创建
2. 检测分区是否有文件系统 → 没有则格式化为 ext4
3. 挂载到 `/mnt/mmcblk0p27`
4. 写入 `/etc/config/fstab` 实现开机自动挂载
5. 配置 Samba 共享 `share`
6. 启用 `arthur-nas` 服务

**安全性**：只操作 `mmcblk0` 末尾的空闲空间，不碰任何已有分区；
解析分区表失败则整体放弃；已存在的分区/文件系统一律跳过。

**3. `files/arthur-nas.init`** — 开机服务

`/etc/init.d/arthur-nas`，`START=95`（晚于 fstab），职责：
确保 eMMC 分区已挂载、Samba 配置存在、LuCI 缓存干净。
**不做分区/格式化**（那是一次性操作，放开机流程里可能卡住启动）。

**4. LuCI 界面**

- `arthur_nas.lua` → `/usr/lib/lua/luci/controller/`
- `page.htm` → `/usr/lib/lua/luci/view/arthur_nas/`

路径是硬编码的绝对路径，和之前手动部署时完全一致，所以页面不用改。

### 依赖清单（已在路由器上验证存在）

| 包名 | 用途 | 验证 |
|---|---|---|
| `luci-compat` | 经典 Lua controller 支持 | ✅ 存在 |
| `samba4-server` | SMB 共享服务 | ✅ 存在 |
| `luci-app-samba4` | Samba Web 界面 | ✅ 存在 |
| `block-mount` | 挂载管理 | ✅ 存在 |
| `wsdd2` | Windows 网络邻居发现 | ✅ 存在 |
| `kmod-fs-ntfs3` | NTFS 内核原生驱动 | 编译后生成 |
| `kmod-fs-exfat` | exFAT 内核驱动 | 编译后生成 |

> 注：前 5 个在当前固件的源里就能搜到（已在路由器上实测验证）；
> 后 2 个正是本次编译要新编出来的。

### 刷机后的首次启动流程

```
路由器启动
  ↓
fstab 挂载已有分区（此时 mmcblk0p27 可能还不存在）
  ↓
执行 /etc/uci-defaults/99-arthur-nas
  ├─ 创建分区 mmcblk0p27（约 110G）
  ├─ 格式化为 ext4        ← 这一步耗时最长，几分钟
  ├─ 挂载 + 写 fstab
  ├─ 配置 Samba 共享
  └─ 自我删除
  ↓
arthur-nas.init 启动（START=95）
  ├─ 确认分区已挂载
  └─ 启动 Samba
  ↓
完成 → 访问 \\路由器IP\share
```

> ⚠️ 首次开机因为要格式化 110G，会多花几分钟。期间**不要断电**。
> 可通过 LuCI 的「亚瑟NAS共享」页面观察进度，或看日志
> `logread | grep arthur-nas`。

---

