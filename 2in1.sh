#!/bin/bash

# ========================================================
# NAT 小鸡全能一键脚本：服务独立化修复版
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

echo -e "${BLUE}--- 1. 深度清理与环境准备 ---${PLAIN}"
# 清理旧服务防止冲突
systemctl stop nat-xray nat-xtun nat-cf >/dev/null 2>&1
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 2. 下载并赋予执行权限
echo -e "${GREEN}正在下载二进制文件...${PLAIN}"
# Cloudflared
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH
# X-tunnel (确保路径正确)
wget -O /usr/local/bin/x-tunnel https://github.com/fxpasst1/xtun/raw/main/bin/xtun-linux-$ARCH
# Xray (解压出二进制)
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$ARCH.zip
unzip -o /tmp/xray.zip -d /tmp/xray_dist
mv /tmp/xray_dist/xray /usr/local/bin/xray
chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray

# 3. 重新生成 Xray 配置文件
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

# 服务 1: Xray (增加工作目录指定)
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

# 服务 2: x-tunnel (修正启动参数)
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target

[Service]
Type=simple
# 修正：根据 xtun 逻辑，-p 是端口，-t 是 token
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token  $MY_XTUN_TOKEN
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 服务 3: cloudflared
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 4. 强制重载并启动
systemctl daemon-reload
systemctl enable nat-xray nat-xtun nat-cf
systemctl start nat-xray nat-xtun nat-cf

# 5. 状态检查 UI
sleep 3
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}服务部署状态检查：${PLAIN}"
echo -e "------------------------------------------------------"
check_service() {
    if systemctl is-active --quiet $1; then
        echo -e "$1: ${GREEN}运行中 (Running)${PLAIN}"
    else
        echo -e "$1: ${RED}已停止 (Stopped)${PLAIN}"
        echo -e "   原因查看: journalctl -u $1 -n 20 --no-pager"
    fi
}

check_service "nat-xray"
check_service "nat-xtun"
check_service "nat-cf"
echo -e "------------------------------------------------------"
echo -e "${BLUE}常用调试命令：${PLAIN}"
echo -e "查看 Xray 日志: ${GREEN}journalctl -u nat-xray -f${PLAIN}"
echo -e "查看 XTun 日志: ${GREEN}journalctl -u nat-xtun -f${PLAIN}"
echo -e "查看 CF   日志: ${GREEN}journalctl -u nat-cf -f${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
