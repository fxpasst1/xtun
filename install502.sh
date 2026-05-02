#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# ================= 配置区域 =================
BIN_DIR="/usr/local/bin"
XTUN_REPO_BASE="https://raw.githubusercontent.com/mygv001/xtun325/main/bin/xt"
CF_REPO_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"
# ===========================================

[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行${PLAIN}" && exit 1

# 检测系统类型
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
    OS="debian"
else
    echo -e "${RED}不支持的操作系统${PLAIN}"
    exit 1
fi

# 架构检测
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; exit 1 ;;
    esac
}

# 环境准备
prepare_env() {
    echo -e "${YELLOW}检查依赖环境...${PLAIN}"
    if [ "$OS" == "alpine" ]; then
        # 安装 supervise-daemon 用于可靠的进程守护
        apk add --no-cache curl ca-certificates bash openrc
    else
        apt-get update && apt-get install -y curl ca-certificates
    fi
}

# 下载
download_binaries() {
    local ARCH=$(get_arch)
    mkdir -p $BIN_DIR
    echo -e "${YELLOW}正在同步二进制文件 ($ARCH)...${PLAIN}"
    curl -L -f "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel" && chmod +x "$BIN_DIR/x-tunnel"
    curl -L -f "$CF_REPO_BASE/cloudflared-linux-$ARCH" -o "$BIN_DIR/cloudflared" && chmod +x "$BIN_DIR/cloudflared"
}

# 卸载逻辑
uninstall() {
    echo -e "${YELLOW}正在卸载...${PLAIN}"
    if [ "$OS" == "alpine" ]; then
        rc-service xtunnel stop 2>/dev/null
        rc-service cf-tunnel stop 2>/dev/null
        rc-update del xtunnel default 2>/dev/null
        rc-update del cf-tunnel default 2>/dev/null
        rm -f /etc/init.d/xtunnel /etc/init.d/cf-tunnel
    else
        systemctl disable --now xtunnel cf-tunnel 2>/dev/null
        rm -f /etc/systemd/system/xtunnel.service /etc/systemd/system/cf-tunnel.service
        systemctl daemon-reload
    fi
    rm -f "$BIN_DIR/x-tunnel" "$BIN_DIR/cloudflared"
    echo -e "${GREEN}卸载完成。${PLAIN}"
    exit 0
}

# 参数处理
METRICS_PORT=2000
while getopts "p:t:k:m:u" opt; do
    case $opt in
        p) WSPORT=$OPTARG ;;
        t) XTUN_TOKEN=$OPTARG ;;
        k) CF_TOKEN=$OPTARG ;;
        m) METRICS_PORT=$OPTARG ;;
        u) uninstall ;;
        *) exit 1 ;;
    esac
done

[[ -z "$WSPORT" || -z "$XTUN_TOKEN" || -z "$CF_TOKEN" ]] && echo "缺少参数" && exit 1

prepare_env
download_binaries

# --- 核心改进：写入服务配置 ---

if [ "$OS" == "debian" ]; then
    # Systemd 增加内存限制与更激进的重启策略
    cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/x-tunnel -l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN
Restart=always
RestartSec=3
# 限制内存使用，防止拖垮整个系统
MemoryLimit=40M

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/cf-tunnel.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
# 增加 --protocol http2 减少资源占用
ExecStart=$BIN_DIR/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 127.0.0.1:$METRICS_PORT run --token $CF_TOKEN
Restart=always
RestartSec=3
MemoryLimit=60M

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xtunnel cf-tunnel

elif [ "$OS" == "alpine" ]; then
    # Alpine 使用 supervise-daemon 实现强力自动重启
    cat > /etc/init.d/xtunnel <<EOF
#!/sbin/openrc-run
supervisor="supervise-daemon"
name="xtunnel"
command="$BIN_DIR/x-tunnel"
command_args="-l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN"
# 崩溃后 5 秒重启
respawn_delay=5
respawn_max=0

depend() {
    need net
}
EOF

    cat > /etc/init.d/cf-tunnel <<EOF
#!/sbin/openrc-run
supervisor="supervise-daemon"
name="cf-tunnel"
command="$BIN_DIR/cloudflared"
# 优化参数：限制 http2 协议，关闭不必要的指标收集广播
command_args="tunnel --no-autoupdate --protocol http2 --metrics 127.0.0.1:$METRICS_PORT run --token $CF_TOKEN"
respawn_delay=5
respawn_max=0

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/xtunnel /etc/init.d/cf-tunnel
    rc-update add xtunnel default
    rc-update add cf-tunnel default
    rc-service xtunnel restart
    rc-service cf-tunnel restart
fi

echo -e "${GREEN}优化版安装成功！${PLAIN}"
