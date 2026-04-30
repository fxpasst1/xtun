#!/bin/bash

# --- 默认参数设置 ---
CF_TOKEN=${CF_TOKEN:-""}
XTUN_TOKEN=${XTUN_TOKEN:-""}
DOMAIN=${DOMAIN:-""}
UUID=${UUID:-"bc986ffe-5604-41b8-9c6b-6148ebbce4e4"}
XP=${XP:-40001}
TP=${TP:-40002}
MP=${MP:-40003}
PATH_URL=${PATH_URL:-"/vless"}
BEST_CF=${BEST_CF:-"saas.sin.fan"}
BIN_DIR="./bin"

# --- 颜色输出 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -c CF_TOKEN    Cloudflare Tunnel Token (必需)"
    echo "  -x XTUN_TOKEN  X-Tunnel Token (必需)"
    echo "  -d DOMAIN      你的域名 (必需)"
    echo "  -u UUID        VLESS UUID (可选)"
    echo "  -p PORT        Xray 端口 (默认 40001)"
    echo "  -h             显示帮助"
    exit 1
}

# 解析命令行参数
while getopts "c:x:d:u:p:h" opt; do
    case $opt in
        c) CF_TOKEN=$OPTARG ;;
        x) XTUN_TOKEN=$OPTARG ;;
        d) DOMAIN=$OPTARG ;;
        u) UUID=$OPTARG ;;
        p) XP=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$CF_TOKEN" || -z "$XTUN_TOKEN" || -z "$DOMAIN" ]]; then
    echo -e "${RED}[错误] 必须提供 CF_TOKEN, XTUN_TOKEN 和 DOMAIN${NC}"
    usage
fi

# --- 1. 环境检查与架构适配 ---
mkdir -p "$BIN_DIR"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  XRAY_ARCH="64"; CF_ARCH="amd64"; XTUN_ARCH="amd64" ;;
    aarch64) XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64"; XTUN_ARCH="arm64" ;;
    armv7l)  XRAY_ARCH="arm32-v7a"; CF_ARCH="arm"; XTUN_ARCH="arm" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# --- 2. 下载二进制文件 (如果不存在) ---
download_bins() {
    echo "[1/3] 正在检查并下载组件..."
    
    if [ ! -f "$BIN_DIR/cloudflared" ]; then
        curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o "$BIN_DIR/cloudflared"
    fi
    
    if [ ! -f "$BIN_DIR/x-tunnel" ]; then
        curl -L "https://raw.githubusercontent.com/fxpasst1/xtun/main/bin/x-tunnel-linux-${XTUN_ARCH}" -o "$BIN_DIR/x-tunnel"
    fi

    if [ ! -f "$BIN_DIR/xray" ]; then
        curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o "$BIN_DIR/xray.zip"
        unzip -q -o "$BIN_DIR/xray.zip" -d "$BIN_DIR/xray_temp"
        mv "$BIN_DIR/xray_temp/xray" "$BIN_DIR/xray"
        rm -rf "$BIN_DIR/xray.zip" "$BIN_DIR/xray_temp"
    fi
    
    chmod +x "$BIN_DIR/"*
}

# --- 3. 生成配置 ---
gen_config() {
    echo "[2/3] 生成 Xray 配置..."
    cat > config.json <<EOF
{
    "inbounds": [{
        "port": $XP, "listen": "127.0.0.1", "protocol": "vless",
        "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" },
        "streamSettings": { "network": "ws", "wsSettings": {"path": "$PATH_URL"} }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# --- 4. 启动与守护逻辑 ---
run_and_monitor() {
    echo "[3/3] 启动服务并进入守护模式..."
    REMARKS="NAT_Node_$(date +%m%d)"
    VLESS_LINK="vless://${UUID}@${BEST_CF}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&sni=${DOMAIN}&path=${PATH_URL}#${REMARKS}"
    
    echo -e "------------------------------------------------------"
    echo -e "${GREEN}节点链接:${NC} $VLESS_LINK"
    echo -e "------------------------------------------------------"
    echo "提示: 脚本将持续运行以监控进程。如需完全后台运行，请使用: nohup ./deploy.sh [参数] > log.txt 2>&1 &"

    # 清理旧进程
    pkill -f "cloudflared"
    pkill -f "x-tunnel"
    pkill -f "xray"

    while true; do
        # Xray 守护
        if ! pgrep -f "$BIN_DIR/xray" > /dev/null; then
            echo "[$(date)] 重启 Xray..."
            nohup "$BIN_DIR/xray" run -c config.json > /dev/null 2>&1 &
        fi

        # x-tunnel 守护
        if ! pgrep -f "$BIN_DIR/x-tunnel" > /dev/null; then
            echo "[$(date)] 重启 x-tunnel..."
            nohup "$BIN_DIR/x-tunnel" -l ws://127.0.0.1:$TP -token "$XTUN_TOKEN" > /dev/null 2>&1 &
        fi

        # Cloudflared 守护
        if ! pgrep -f "$BIN_DIR/cloudflared" > /dev/null; then
            echo "[$(date)] 重启 Cloudflared..."
            nohup "$BIN_DIR/cloudflared" tunnel --no-autoupdate --protocol http2 run --token "$CF_TOKEN" > /dev/null 2>&1 &
        fi

        sleep 10
    done
}

# --- 执行流程 ---
download_bins
gen_config
run_and_monitor
