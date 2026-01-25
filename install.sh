#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# ================= 配置区域 =================
XTUN_REPO_BASE="https://raw.githubusercontent.com/fxpasst1/xtun/main/bin"
CF_REPO_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"
BIN_DIR="/usr/local/bin"
# ===========================================

usage() {
    echo -e "${GREEN}使用方法:${PLAIN}"
    echo "  ./install.sh -p <wsport> -t <xtun_token> -k <cf_token> [-m <metrics_port>] [-f]"
    echo "  ./install.sh -u (卸载)"
    echo ""
    echo "参数说明:"
    echo "  -p : x-tunnel 端口 (wsport)"
    echo "  -t : x-tunnel Token"
    echo "  -k : Cloudflared Tunnel Token"
    echo "  -m : Metrics 监控端口 (默认 2000)"
    echo "  -f : 强制重新下载所有二进制文件"
    echo "  -u : 卸载并清理系统"
    exit 1
}

# 架构检测
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        s390x) echo "s390x" ;;
        *) echo -e "${RED}不支持的架构: $arch${PLAIN}"; exit 1 ;;
    esac
}

# 下载逻辑
download_files() {
    local ARCH=$(get_arch)
    # 处理 x-tunnel
    if [[ "$FORCE_UPDATE" == "true" ]] || [[ ! -f "$BIN_DIR/x-tunnel" ]]; then
        echo -e "${YELLOW}下载 x-tunnel...${PLAIN}"
        curl -L "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel"
        chmod +x "$BIN_DIR/x-tunnel"
    fi
    # 处理 cloudflared
    if [[ "$FORCE_UPDATE" == "true" ]] || [[ ! -f "$BIN_DIR/cloudflared" ]]; then
        echo -e "${YELLOW}从官网下载最新版 cloudflared...${PLAIN}"
        curl -L "$CF_REPO_BASE/cloudflared-linux-$ARCH" -o "$BIN_DIR/cloudflared"
        chmod +x "$BIN_DIR/cloudflared"
    fi
}

# 卸载逻辑
uninstall() {
    echo -e "${YELLOW}正在卸载...${PLAIN}"
    systemctl stop xtunnel cf-tunnel 2>/dev/null
    systemctl disable xtunnel cf-tunnel 2>/dev/null
    rm -f /etc/systemd/system/xtunnel.service /etc/systemd/system/cf-tunnel.service
    systemctl daemon-reload
    rm -f "$BIN_DIR/x-tunnel" "$BIN_DIR/cloudflared"
    echo -e "${GREEN}卸载完成。${PLAIN}"
    exit 0
}

# 解析命令行参数
METRICS_PORT=36443
FORCE_UPDATE=false

while getopts "p:t:k:m:ufh" opt; do
    case $opt in
        p) WSPORT=$OPTARG ;;
        t) XTUN_TOKEN=$OPTARG ;;
        k) CF_TOKEN=$OPTARG ;;
        m) METRICS_PORT=$OPTARG ;;
        u) uninstall ;;
        f) FORCE_UPDATE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# 检查必要参数
if [[ -z "$WSPORT" || -z "$XTUN_TOKEN" || -z "$CF_TOKEN" ]]; then
    echo -e "${RED}错误：缺少必要参数 (-p, -t, -k)${PLAIN}"
    usage
fi

# 执行安装过程
[[ $EUID -ne 0 ]] && echo "请使用 root 运行" && exit 1
download_files

# 部署 Systemd 服务
cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/x-tunnel -wsport $WSPORT -token $XTUN_TOKEN
Restart=on-failure
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
ExecStart=$BIN_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 run --token $CF_TOKEN --metrics 0.0.0.0:$METRICS_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xtunnel
systemctl enable --now cf-tunnel

echo -e "${GREEN}静默安装完成！服务已在后台运行。${PLAIN}"
