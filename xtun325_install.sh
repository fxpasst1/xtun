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

# --- 系统检测 ---
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    OS="debian"
else
    # 默认为 Systemd 类系统尝试运行
    OS="debian"
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

# 2. 依赖安装
prepare_env() {
    echo -e "${YELLOW}正在检查基础依赖...${PLAIN}"
    if [ "$OS" == "alpine" ]; then
        apk add --no-cache curl ca-certificates bash
    else
        apt-get update && apt-get install -y curl ca-certificates
    fi
}

# 3. 下载二进制文件
download_binaries() {
    local ARCH=$(get_arch)
    mkdir -p $BIN_DIR

    echo -e "${YELLOW}正在同步二进制文件 ($ARCH)...${PLAIN}"

    # 下载 x-tunnel
    curl -L -f "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误：x-tunnel 下载失败，请检查网络。${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/x-tunnel"

    echo -e "${GREEN}下载成功。文件位置: $BIN_DIR/x-tunnel${PLAIN}"
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
    echo -e "${GREEN}卸载完成。${PLAIN}"
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

# 6. 配置并启动服务
echo -e "${YELLOW}正在为 $OS 配置服务启动项...${PLAIN}"

if [ "$OS" == "debian" ]; then
    # Systemd 模式
    cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/x-tunnel -l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xtunnel
    STATUS=$(systemctl is-active xtunnel)

elif [ "$OS" == "alpine" ]; then
    # OpenRC 模式
    cat > /etc/init.d/xtunnel <<EOF
#!/sbin/openrc-run
description="X-Tunnel Service"
command="$BIN_DIR/x-tunnel"
command_args="-l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
restart_delay=5

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/xtunnel
    rc-update add xtunnel default
    rc-service xtunnel start
    STATUS=$(rc-service xtunnel status | awk '{print $3}')
fi

echo -e "------------------------------------------------"
echo -e "${GREEN}安装成功！系统类型: $OS${PLAIN}"
echo -e "运行参数: -p $WSPORT -t $XTUN_TOKEN"
echo -e "x-tunnel 状态: $STATUS"
echo -e "------------------------------------------------"
