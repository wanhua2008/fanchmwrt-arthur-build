#!/bin/bash
# ============================================================
# 一键推送到 GitHub 并触发编译
# ------------------------------------------------------------
# 用法（在本目录下打开 Git Bash 执行）：
#     ./push-and-build.sh https://github.com/你的用户名/仓库名.git
#
# 前提：仓库已在 GitHub 网页端创建好（Public，不要勾选任何初始化文件）
# ============================================================
set -e

REPO="$1"
if [ -z "$REPO" ]; then
    echo "用法: $0 <仓库地址>"
    echo "例如: $0 https://github.com/zhangsan/fanchmwrt-arthur-build.git"
    exit 1
fi

cd "$(dirname "$0")"

echo "=== 1. 检查本地仓库 ==="
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "错误：当前目录不是 git 仓库"; exit 1; }
echo "  提交: $(git log -1 --oneline)"

echo ""
echo "=== 2. 关联远程仓库 ==="
if git remote | grep -q '^origin$'; then
    git remote set-url origin "$REPO"
    echo "  已更新 origin -> $REPO"
else
    git remote add origin "$REPO"
    echo "  已添加 origin -> $REPO"
fi

echo ""
echo "=== 3. 推送到 GitHub ==="
echo "  提示：会弹出登录窗口，或用 Personal Access Token 作为密码"
git push -u origin main

echo ""
echo "=== 4. 完成！接下来手动触发编译 ==="
echo "  1) 打开仓库的 Actions 页面"
echo "  2) 左侧选 'Build FanchmWrt for JDCloud RE-SS-01 (NTFS enabled)'"
echo "  3) 右侧 'Run workflow' -> 分支选 main -> 绿色按钮"
echo "  4) 等待约 3-5 小时，产物在 Artifacts 里下载"
echo ""
echo "  仓库 Actions 直达链接（把 <用户>/<仓库> 换成你的）："
echo "  https://github.com/<用户>/<仓库>/actions"
