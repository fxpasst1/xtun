#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# ================= 配置区域 =================
# 统一使用 /usr/local/bin，避免 LXC 在 /root 下的权限限制
BIN_DIR="/usr/local/bin"
XTUN_REPO_BASE="https://raw.githubusercontent.com/fxpasst1/xtun/main/bin"
CF_REPO_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"
# ===========================================

[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行${PLAIN}" && exit 1

usage() {
    echo -e "${YELLOW}使用方法:${PLAIN}"
    echo "  bash install.sh -p <wsport> -t <token> -k <cf_token> [-m <metrics_port>]"
    echo "  bash install.sh -u (卸载)"
    exit 1
}

# 1. 架构检测
get_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        s390x) echo "s390x" ;;
        *) echo "不支持的架构: $arch"; exit 1 ;;
    esac
}

# 2. 下载并严格校验
download_binaries() {
    local ARCH=$(get_arch)
    mkdir -p $BIN_DIR

    echo -e "${YELLOW}正在同步二进制文件 ($ARCH)...${PLAIN}"

    # 下载 x-tunnel
    echo -e "下载 x-tunnel..."
    curl -L -f "$XTUN_REPO_BASE/x-tunnel-linux-$ARCH" -o "$BIN_DIR/x-tunnel"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误：x-tunnel 下载失败，请检查网络或 GitHub 链接是否正确。${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/x-tunnel"

    # 下载 cloudflared
    echo -e "下载 cloudflared..."
    curl -L -f "$CF_REPO_BASE/cloudflared-linux-$ARCH" -o "$BIN_DIR/cloudflared"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误：cloudflared 下载失败。${PLAIN}"
        exit 1
    fi
    chmod +x "$BIN_DIR/cloudflared"

    echo -e "${GREEN}下载并校准权限成功。文件位置: $BIN_DIR${PLAIN}"
}

# 3. 卸载逻辑
uninstall() {
    echo -e "${YELLOW}停止服务并清理...${PLAIN}"
    systemctl stop xtunnel cf-tunnel 2>/dev/null
    systemctl disable xtunnel cf-tunnel 2>/dev/null
    rm -f /etc/systemd/system/xtunnel.service
    rm -f /etc/systemd/system/cf-tunnel.service
    systemctl daemon-reload
    rm -f "$BIN_DIR/x-tunnel" "$BIN_DIR/cloudflared"
    echo -e "${GREEN}卸载完成。${PLAIN}"
    exit 0
}

# 4. 参数处理
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

download_binaries

# 5. 写入 Systemd 服务 (采用绝对路径和修正后的参数)
echo -e "${YELLOW}正在配置 Systemd 服务...${PLAIN}"

cat > /etc/systemd/system/xtunnel.service <<EOF
[Unit]
Description=X-Tunnel Service
After=network.target

[Service]
Type=simple
User=root
# 根据你报错中的命令格式修正：使用 -l 参数指向本地 ws 地址
ExecStart=$BIN_DIR/x-tunnel -l ws://127.0.0.1:$WSPORT -token $XTUN_TOKEN
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
User=root
ExecStart=$BIN_DIR/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2  --metrics 0.0.0.0:$METRICS_PORT run --token $CF_TOKEN
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xtunnel
systemctl enable --now cf-tunnel

echo -e "------------------------------------------------"
echo -e "${GREEN}安装成功！${PLAIN}"
echo -e "二进制路径: $BIN_DIR/x-tunnel"
echo -e "x-tunnel 状态: $(systemctl is-active xtunnel)"
echo -e "cloudflared 状态: $(systemctl is-active cf-tunnel)"
echo -e "------------------------------------------------"
