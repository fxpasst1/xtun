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
    OS="debian"
    echo -e "${YELLOW}未知系统，尝试以 Systemd 模式运行${PLAIN}"
fi

usage() {
    echo -e "${YELLOW}使用方法:${PLAIN}"
    echo "  bash $0 -p <wsport> -t <token>"
    echo "  bash $0 -u (卸载)"
    exit 1
}

get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        s390x) echo "s390x" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; exit 1 ;;
    esac
}

prepare_env() {
    if [ "$OS" == "alpine" ]; then
        echo -e "正在安装基础依赖..."
        # 确保安装了 openrc 和 ca-certificates
        apk add --no-cache curl bash ca-certificates openrc
    else
        if ! command -v curl &> /dev/null; then
            apt-get update && apt-get install -y curl ca-certificates
        fi
    fi
}

download_binaries() {
    local ARCH=$(get_arch)
    mkdir -p $BIN_DIR
    echo -e "${YELLOW}正在同步二进制文件...${PLAIN}"
    curl -L -f "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败${PLAIN}"; exit 1
    fi
    chmod +x "$BIN_DIR/x-tunnel"
}

uninstall() {
    echo -e "${YELLOW}正在卸载服务...${PLAIN}"
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

echo -e "${YELLOW}正在配置增强保活服务...${PLAIN}"

if [ "$OS" == "debian" ]; then
    # Systemd 优化：增加内存限制，防止 OOM 拖累整机
    cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/x-tunnel -l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN
Restart=always
RestartSec=3
# 128M 小鸡建议限制单个进程占用
# MemoryLimit=128M

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xtunnel
    STATUS=$(systemctl is-active xtunnel)

else
    # Alpine 优化：使用 supervise-daemon 实现强力拉起
    cat > /etc/init.d/xtunnel <<EOF
#!/sbin/openrc-run

# 使用 supervise-daemon 监控进程
supervisor="supervise-daemon"
name="x-tunnel"
description="X-Tunnel Service with Auto-Restart"

command="$BIN_DIR/x-tunnel"
command_args="-l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN"

# 崩溃后延迟 5 秒重启，无限次重试
respawn_delay=5
respawn_max=0

depend() {
    need net
}

start_pre() {
    # 确保运行目录存在
    checkpath --directory --mode 0755 /run/xtunnel
}
EOF
    chmod +x /etc/init.d/xtunnel
    rc-update add xtunnel default
    rc-service xtunnel restart
    sleep 1
    STATUS=$(rc-service xtunnel status | awk '{print $3}')
fi

echo -e "------------------------------------------------"
echo -e "${GREEN}优化版安装完成！${PLAIN}"
echo -e "系统环境: $OS (128M NAT Optimized)"
echo -e "保活机制: $([ "$OS" == "alpine" ] && echo "supervise-daemon" || echo "systemd-restart")"
echo -e "服务状态: $STATUS"
echo -e "------------------------------------------------"
