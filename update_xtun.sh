#!/bin/bash

# ====================================================
# 脚本功能：自动查找并更新 x-tunnel 二进制文件
# ====================================================

# 1. 查找文件路径
echo "正在全盘查找 x-tunnel 文件..."
OLD_FILE_PATH=$(find / -name "x-tunnel" -type f 2>/dev/null | head -n 1)

if [ -z "$OLD_FILE_PATH" ]; then
    echo "错误：未能在系统中找到名为 x-tunnel 的文件。"
    exit 1
fi

TARGET_DIR=$(dirname "$OLD_FILE_PATH")
echo "找到文件路径: $OLD_FILE_PATH"
echo "目标目录: $TARGET_DIR"

# 2. 识别系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    armv7l)  ARCH_SUFFIX="armv7" ;;
    i386|i686) ARCH_SUFFIX="386" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

echo "检测到系统架构: $ARCH ($ARCH_SUFFIX)"

# 3. 构造下载链接 (转换为 raw 格式)
# 假设你的文件名格式为 x-tunnel-linux-amd64 等
BASE_URL="https://github.com/mygv001/xtun325/raw/main/bin/xt"
DOWNLOAD_URL="${BASE_URL}/x-tunnel-linux-${ARCH_SUFFIX}"

# 4. 备份原文件
echo "正在备份原文件为 x-tunnel.bak..."
mv "$OLD_FILE_PATH" "${OLD_FILE_PATH}.bak"

# 5. 下载新文件
echo "正在从 GitHub 下载新版本..."
wget -q --show-progress -O "${TARGET_DIR}/x-tunnel" "$DOWNLOAD_URL"

if [ $? -eq 0 ]; then
    # 6. 设置权限
    chmod +x "${TARGET_DIR}/x-tunnel"
    echo "-------------------------------------------"
    echo "更新成功！"
    echo "新文件位置: ${TARGET_DIR}/x-tunnel"
    echo "备份文件位置: ${OLD_FILE_PATH}.bak"
    echo "-------------------------------------------"
else
    echo "下载失败，请检查网络连接或 URL 是否正确。"
    echo "正在还原备份..."
    mv "${OLD_FILE_PATH}.bak" "$OLD_FILE_PATH"
    exit 1
fi
