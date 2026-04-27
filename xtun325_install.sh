#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# ================= 配置区域 =================
BIN_DIR="/usr/local/bin"
XTUN_REPO_BASE="https://raw.githubusercontent.com/mygv001/xtun325/main/bin/xt"
# ===========================================

[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行${PLAIN}" && exit 1

# --- 核心系统检测 ---
if [ -f /etc/alpine-release ]; then
    OS="alpine"
    echo -e "${YELLOW}检测到系统类型: Alpine Linux (OpenRC)${PLAIN}"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    OS="debian"
    echo -e "${YELLOW}检测到系统类型: Debian/Ubuntu (Systemd)${PLAIN}"
else
    # 默认兜底尝试 Systemd
    OS="debian"
    echo -e "${YELLOW}未知系统，尝试以 Systemd 模式运行${PLAIN}"
fi

usage() {
    echo -e "${YELLOW}使用方法:${PLAIN}"
    echo "  bash $0 -p <wsport> -t <token>"
    echo "  bash $0 -u (卸载)"
    exit 1
}

# 1. 架构检测
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        s390x) echo "s390x" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; exit 1 ;;
    esac
}

# 2. 准备基础环境 (安装 curl)
prepare_env() {
    if [ "$OS" == "alpine" ]; then
        echo -e "正在安装依赖: curl, bash, ca-certificates..."
        apk add --no-cache curl bash ca-certificates
    else
        if ! command -v curl &> /dev/null; then
            apt-get update && apt-get install -y curl ca-certificates
        fi
    fi
}

# 3. 下载二进制
download_binaries() {
    local ARCH=$(get_arch)
    mkdir -p $BIN_DIR
    echo -e "${YELLOW}正在下载 x-tunnel ($ARCH)...${PLAIN}"
    curl -L -f "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败，请检查网络连接${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/x-tunnel"
}

# 4. 卸载逻辑
uninstall() {
    echo -e "${YELLOW}正在清理服务...${PLAIN}"
    if [ "$OS" == "alpine" ]; then
        rc-service xtunnel stop 2>/dev/null
        rc-update del xtunnel default 2>/dev/null
        rm -f /etc/init.d/xtunnel
    else
        systemctl disable --now xtunnel 2>/dev/null
        rm -f /etc/systemd/system/xtunnel.service
        systemctl daemon-reload
    fi
    rm -f "$BIN_DIR/x-tunnel"
    echo -e "${GREEN}卸载完成！${PLAIN}"
    exit 0
}

# 5. 参数处理
while getopts "p:t:u" opt; do
    case $opt in
        p) WSPORT=$OPTARG ;;
        t) XTUN_TOKEN=$OPTARG ;;
        u) uninstall ;;
        *) usage ;;
    esac
done

[[ -z "$WSPORT" || -z "$XTUN_TOKEN" ]] && usage

prepare_env
download_binaries

# 6. 服务配置与启动
echo -e "${YELLOW}正在配置启动项...${PLAIN}"

if [ "$OS" == "debian" ]; then
    # Systemd 写入
    cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/x-tunnel -l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xtunnel
    STATUS=$(systemctl is-active xtunnel)

else
    # Alpine OpenRC 写入
    cat > /etc/init.d/xtunnel <<EOF
#!/sbin/openrc-run
description="X-Tunnel Service"
command="$BIN_DIR/x-tunnel"
command_args="-l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/xtunnel
    rc-update add xtunnel default
    rc-service xtunnel restart
    STATUS=$(rc-service xtunnel status | awk '{print $3}')
fi

echo -e "------------------------------------------------"
echo -e "${GREEN}安装完成！${PLAIN}"
echo -e "运行模式: $OS"
echo -e "监听端口: $WSPORT"
echo -e "x-tunnel 状态: $STATUS"
echo -e "------------------------------------------------"
