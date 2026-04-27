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
    echo -e "${RED}不支持的操作系统，仅支持 Debian/Ubuntu 或 Alpine${PLAIN}"
    exit 1
fi

usage() {
    echo -e "${YELLOW}使用方法:${PLAIN}"
    echo "  bash $0 -p <wsport> -t <token> -k <cf_token> [-m <metrics_port>]"
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

# 2. 环境准备 (安装 curl 等)
prepare_env() {
    echo -e "${YELLOW}检查依赖环境...${PLAIN}"
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
        echo -e "${RED}错误：x-tunnel 下载失败${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/x-tunnel"

    # 下载 cloudflared
    curl -L -f "$CF_REPO_BASE/cloudflared-linux-$ARCH" -o "$BIN_DIR/cloudflared"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误：cloudflared 下载失败${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/cloudflared"

    echo -e "${GREEN}下载成功。位置: $BIN_DIR${PLAIN}"
}

# 4. 卸载逻辑
uninstall() {
    echo -e "${YELLOW}正在卸载服务...${PLAIN}"
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

# 5. 参数处理
METRICS_PORT=2000
while getopts "p:t:k:m:u" opt; do
    case $opt in
        p) WSPORT=$OPTARG ;;
        t) XTUN_TOKEN=$OPTARG ;;
        k) CF_TOKEN=$OPTARG ;;
        m) METRICS_PORT=$OPTARG ;;
        u) uninstall ;;
        *) usage ;;
    esac
done

[[ -z "$WSPORT" || -z "$XTUN_TOKEN" || -z "$CF_TOKEN" ]] && usage

prepare_env
download_binaries

# 6. 写入服务配置
echo -e "${YELLOW}正在配置 $OS 服务管理...${PLAIN}"

if [ "$OS" == "debian" ]; then
    # Systemd 逻辑
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

    cat > /etc/systemd/system/cf-tunnel.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 --metrics 0.0.0.0:$METRICS_PORT run --token $CF_TOKEN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xtunnel cf-tunnel

elif [ "$OS" == "alpine" ]; then
    # OpenRC 逻辑
    # xtunnel init script
    cat > /etc/init.d/xtunnel <<EOF
#!/sbin/openrc-run
description="X-Tunnel Service"
command="$BIN_DIR/x-tunnel"
command_args="-l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
restart_delay=5
respawn_delay=5

depend() {
    need net
}
EOF
    # cf-tunnel init script
    cat > /etc/init.d/cf-tunnel <<EOF
#!/sbin/openrc-run
description="Cloudflare Tunnel"
command="$BIN_DIR/cloudflared"
command_args="tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 --metrics 0.0.0.0:$METRICS_PORT run --token $CF_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
restart_delay=5
respawn_delay=5

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/xtunnel /etc/init.d/cf-tunnel
    rc-update add xtunnel default
    rc-update add cf-tunnel default
    rc-service xtunnel start
    rc-service cf-tunnel start
fi

echo -e "------------------------------------------------"
echo -e "${GREEN}安装成功！系统类型: $OS${PLAIN}"
echo -e "二进制路径: $BIN_DIR"
if [ "$OS" == "debian" ]; then
    echo -e "x-tunnel 状态: $(systemctl is-active xtunnel)"
    echo -e "cloudflared 状态: $(systemctl is-active cf-tunnel)"
else
    echo -e "x-tunnel 状态: $(rc-service xtunnel status | awk '{print $3}')"
    echo -e "cloudflared 状态: $(rc-service cf-tunnel status | awk '{print $3}')"
fi
echo -e "------------------------------------------------"
