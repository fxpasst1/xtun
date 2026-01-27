#!/bin/bash

# --- 检查 Root 权限 ---
if [ "$EUID" -ne 0 ]; then 
    echo -e "\e[1;91m请使用 root 用户或 sudo 运行此脚本！\033[0m"
    exit 1
fi

# --- 颜色定义 ---
green() { echo -e "\e[1;32m$1\033[0m"; }
red() { echo -e "\e[1;91m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

# --- 1. 参数解析 ---
for arg in "$@"; do
    case $arg in
        port=*) MTP_PORT="${arg#*=}" ;;
        *) [[ "$arg" =~ ^[0-9]+$ ]] && MTP_PORT="$arg" ;;
    esac
done

if [[ -z "$MTP_PORT" ]]; then
    red "错误: 未指定端口！使用方式: bash $0 port=38006"
    exit 1
fi

# --- 2. 环境准备 ---
WORKDIR="/usr/local/bin/mtp"
mkdir -p "$WORKDIR"
systemctl stop mtg >/dev/null 2>&1
pgrep -x mtg > /dev/null && pkill -9 mtg >/dev/null 2>&1

# --- 3. 架构检测与下载 ---
arch_type=$(uname -m)
case "$arch_type" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) arch="amd64" ;;
esac

URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-$arch.tar.gz"

green "正在为 $arch 架构下载 mtg (v2.1.7)..."
wget -qO- "$URL" | tar xz -C "$WORKDIR" --strip-components=1

if [ ! -f "${WORKDIR}/mtg" ]; then
    red "下载失败，请检查网络！"
    exit 1
fi
chmod +x "${WORKDIR}/mtg"

# --- 4. 生成带 ee 前缀的混淆密钥 ---
# 生成 32 位随机 16 进制字符，并在开头添加 ee
RANDOM_HEX=$(openssl rand -hex 16)
SECRET="ee${RANDOM_HEX}"

# --- 5. 配置 Systemd 服务 ---
cat <<EOF > /etc/systemd/system/mtg.service
[Unit]
Description=MTProxy mtg Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WORKDIR
ExecStart=$WORKDIR/mtg run $SECRET -b 0.0.0.0:$MTP_PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- 6. 启动并设置开机自启 ---
systemctl daemon-reload
systemctl enable mtg
systemctl start mtg

sleep 2

if systemctl is-active --quiet mtg; then
    # --- 7. 获取公网 IP 并生成链接 ---
    IP=$(curl -s https://api.ipify.org || curl -s ip.sb)
    LINK="tg://proxy?server=$IP&port=$MTP_PORT&secret=$SECRET"
    
    purple "\n================ 安装成功 ================"
    green "监听端口: $MTP_PORT"
    green "混淆密钥: $SECRET (Fake-TLS)"
    purple "\nTG 分享链接 (已启用混淆):"
    green "$LINK"
    purple "\n服务管理命令:"
    echo "查看状态: systemctl status mtg"
    echo "停止服务: systemctl stop mtg"
    echo "启动服务: systemctl start mtg"
    purple "=========================================="
    
    echo "$LINK" > "$WORKDIR/link.txt"
else
    red "启动失败！请检查端口 $MTP_PORT 是否被占用或防火墙是否放行。"
fi
