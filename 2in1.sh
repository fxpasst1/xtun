#!/bin/bash

# ========================================================
# NAT 小鸡全能一键脚本：服务独立化极致性能版
# 支持：cloudflared + x-tunnel + Xray (独立 Service 管理)
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 参数读取
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
MY_XP=${XP:-40001}
MY_TP=${TP:-40002}
MY_MP=${MP:-40003}

# 检查必要参数
if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN 或 XTUN_TOKEN！${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 1. 安装环境与组件 ---${PLAIN}"
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 下载二进制
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH
wget -O /usr/local/bin/x-tunnel https://github.com/fxpasst1/xtun/raw/main/bin/xtun-linux-$ARCH
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$ARCH.zip
unzip -o /tmp/xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray

echo -e "${BLUE}--- 2. 配置 Xray ---${PLAIN}"
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

echo -e "${BLUE}--- 3. 部署独立 Systemd 服务 ---${PLAIN}"

# 服务 1: Xray
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray -c /etc/xray/config.json
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 服务 2: x-tunnel
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 服务 3: cloudflared (性能优化版)
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动所有服务
systemctl daemon-reload
systemctl enable --now nat-xray nat-xtun nat-cf

# 5. 结果展示
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}一键独立化部署完成！${PLAIN}"
echo -e "${BLUE}服务状态预览：${PLAIN}"
printf "%-20s %-10s\n" "服务名称" "状态"
printf "%-20s %-10s\n" "nat-xray (Xray)" "$(systemctl is-active nat-xray)"
printf "%-20s %-10s\n" "nat-xtun (XTun)" "$(systemctl is-active nat-xtun)"
printf "%-20s %-10s\n" "nat-cf (CF)" "$(systemctl is-active nat-cf)"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "${BLUE}常用维护命令 (UI 提示)：${PLAIN}"
echo -e " 查看状态: ${GREEN}systemctl status nat-xray nat-xtun nat-cf${PLAIN}"
echo -e " 查看日志: ${GREEN}journalctl -u nat-cf -f${PLAIN} (以CF为例)"
echo -e " 重启服务: ${GREEN}systemctl restart nat-xray${PLAIN}"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "CF 映射: 域名 -> ${BLUE}http://localhost:$MY_XP${PLAIN}"
echo -e "Metrics: ${BLUE}http://小鸡IP:$MY_MP/metrics${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
