#!/bin/bash

# --- 参数化配置 (可根据需要修改默认值) ---
ARGO_TOKEN=${1:-"你的_CLOUDFLARE_TUNNEL_TOKEN"}
ARGO_DOMAIN=${2:-"node.example.com"}
WS_PORT=${3:-8001}
WS_PATH=${4:-"/vless"}
UUID=$(cat /proc/sys/kernel/random/uuid)

# --- 1. 环境准备与架构检测 ---
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|x64|amd64) X_ARCH="64"; CF_ARCH="amd64" ;;
    arm64|aarch64) X_ARCH="arm64-v8a"; CF_ARCH="arm64" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

mkdir -p /opt/suoha && cd /opt/suoha

# --- 2. 清理旧进程 (确保重新安装时干净) ---
pkill -9 xray 2>/dev/null
pkill -9 cloudflared 2>/dev/null

# --- 3. 下载二进制文件 ---
echo "正在下载 Xray 和 Cloudflared..."
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$X_ARCH.zip" -o xray.zip
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH" -o cloudflared
unzip -o xray.zip && chmod +x xray cloudflared && rm -f xray.zip

# --- 4. 生成 Xray 配置文件 (仅 VLESS) ---
cat > config.json <<EOF
{
    "inbounds": [{
        "port": $WS_PORT,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$UUID"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": { "path": "$WS_PATH" }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

# --- 5. 后台直接运行 ---
nohup ./xray run -config config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --no-autoupdate run --token $ARGO_TOKEN > cf.log 2>&1 &

# --- 6. 生成并显示节点链接 ---
echo -e "\n==============================================="
echo "VLESS 节点信息："
echo "VLESS 链接: vless://$UUID@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host=$ARGO_DOMAIN&path=$WS_PATH#Argo_VLESS"
echo "==============================================="
echo "服务已在后台运行。"
echo "日志目录: /opt/suoha/"
echo "停止服务请运行: pkill -9 xray cloudflared"
