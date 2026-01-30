#!/bin/bash

# ========================================================
# NAT 小鸡全能一键脚本：极致性能双隧道版
# 支持：cloudflared (Optimized) + x-tunnel + Xray
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 自动从环境变量读取参数
# 用法：CF_TOKEN=xxx XTUN_TOKEN=xxx UUID=xxx bash install.sh
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

# 检查必要参数
if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量！${PLAIN}"
    echo -e "用法示例：${BLUE}CF_TOKEN=xx XTUN_TOKEN=xx bash <(curl ...)${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 开始安装组件 ---${PLAIN}"

# 2. 架构识别与环境安装
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 3. 下载二进制文件
echo -e "${GREEN}下载 cloudflared, x-tunnel, xray...${PLAIN}"
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH
wget -O /usr/local/bin/x-tunnel https://github.com/fxpasst1/xtun/raw/main/bin/xtun-linux-$ARCH
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$ARCH.zip
unzip -o /tmp/xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray

# 4. 配置 Xray 后端 (监听本地 40001 端口)
mkdir -p /etc/xray
cat > /etc/xray/config.json <<EOF
{
    "inbounds": [{
        "port": 40001,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": { "clients": [{"id": "$MY_UUID"}], "decryption": "none" },
        "streamSettings": { "network": "ws", "wsSettings": {"path": "/vless"} }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 5. 配置融合 Systemd 服务 (保留 http2 和 no-autoupdate 优化)
echo -e "${GREEN}配置极致性能 Systemd 服务...${PLAIN}"

cat > /etc/systemd/system/nat-fusion.service <<EOF
[Unit]
Description=Fusion Service (Optimized CF + XTUN + Xray)
After=network.target

[Service]
Type=simple
# 核心启动逻辑：
# - Xray 运行于 40001
# - x-tunnel 运行于 40002 使用专属 Token
# - cloudflared 强制 http2 协议并禁用更新
ExecStart=/bin/bash -c " \\
    /usr/local/bin/xray -c /etc/xray/config.json & \\
    /usr/local/bin/x-tunnel -t $MY_XTUN_TOKEN -p 40002 & \\
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 run --token $MY_CF_TOKEN"
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 6. 启动服务
systemctl daemon-reload
systemctl enable --now nat-fusion

# 7. 结果展示
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}一键整合部署完成！${PLAIN}"
echo -e "${BLUE}配置详情：${PLAIN}"
echo -e "1. ${GREEN}Cloudflared (CF Tunnel)${PLAIN}: 使用 Token 连接，http2 模式。"
echo -e "2. ${GREEN}x-tunnel Service${PLAIN}: 独立 Token 运行 (端口 40002)。"
echo -e "3. ${GREEN}Xray VLESS+WS${PLAIN}: UUID 为 ${BLUE}$MY_UUID${PLAIN}，路径 /vless。"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "CF 映射建议: ${BLUE}你的域名 -> http://localhost:40001${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
