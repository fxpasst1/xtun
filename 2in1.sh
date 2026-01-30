#!/bin/bash

# ========================================================
# NAT 小鸡全能一键脚本：全参数化极致性能版
# 支持：cloudflared (Optimized) + x-tunnel + Xray
# CF_TOKEN=你的CF_Token XTUN_TOKEN=你的XTUN_Token XP=40001 TP=40002 MP=40003 bash <(curl -Ls https://raw.githubusercontent.com/你的用户名/你的仓库/main/2in1.sh)
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 自动从环境变量读取参数
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
# 端口参数化：XP 为 Xray 端口，TP 为 x-tunnel 端口 ,mP 为 Metrics 端口
MY_XP=${XP:-40001}
MY_TP=${TP:-40002}
MY_MP=${TP:-40003}

# 检查必要参数
if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN 或 XTUN_TOKEN！${PLAIN}"
    echo -e "用法示例：${BLUE}CF_TOKEN=xx XTUN_TOKEN=xx XP=40001 TP=40002 bash <(curl ...)${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 开始安装组件 (架构识别) ---${PLAIN}"

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

# 4. 配置 Xray 后端 (监听参数化端口 $MY_XP)
mkdir -p /etc/xray
cat > /etc/xray/config.json <<EOF
{
    "inbounds": [{
        "port": $MY_XP,
        "listen": "127.0.0.1",
        "protocol": "vless",
        "settings": { "clients": [{"id": "$MY_UUID"}], "decryption": "none" },
        "streamSettings": { "network": "ws", "wsSettings": {"path": "/vless"} }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 5. 配置融合 Systemd 服务 (保留优化参数并将端口参数化)
echo -e "${GREEN}配置极致性能 Systemd 服务...${PLAIN}"

cat > /etc/systemd/system/nat-fusion.service <<EOF
[Unit]
Description=Fusion Service (Optimized CF + XTUN + Xray)
After=network.target

[Service]
Type=simple
# 核心启动逻辑：
# - Xray 运行于 $MY_XP
# - x-tunnel 运行于 $MY_TP 使用专属 Token
# - cloudflared 强制 http2 协议
ExecStart=/bin/bash -c " \\
    /usr/local/bin/xray -c /etc/xray/config.json & \\
    /usr/local/bin/x-tunnel  -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN  & \\
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2  --metrics 0.0.0.0:$MY_XP run --token $MY_CF_TOKEN"
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
echo -e "${GREEN}一键全参数化部署完成！${PLAIN}"
echo -e "${BLUE}配置详情：${PLAIN}"
echo -e "1. ${GREEN}Cloudflared (CF Tunnel)${PLAIN}: 协议 http2, 无自动更新。"
echo -e "2. ${GREEN}x-tunnel Service${PLAIN}: 端口 ${BLUE}$MY_TP${PLAIN}, 使用专属 Token。"
echo -e "3. ${GREEN}Xray VLESS+WS${PLAIN}: 端口 ${BLUE}$MY_XP${PLAIN}, UUID ${BLUE}$MY_UUID${PLAIN}。"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "CF 控制台映射建议: ${BLUE}你的域名 -> http://localhost:$MY_XP${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
