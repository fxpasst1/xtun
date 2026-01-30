#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：双隧道+Xray 参数修正版
# ========================================================

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 参数提取
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
MY_XP=${XP:-40001}
MY_TP=${TP:-40002}
MY_MP=${MP:-40003}

if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN 或 XTUN_TOKEN！${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 1. 下载并安装二进制 (强制覆盖) ---${PLAIN}"
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# Cloudflared
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH
# X-tunnel (确保文件名一致)
wget -O /usr/local/bin/x-tunnel https://github.com/fxpasst1/xtun/raw/main/bin/xtun-linux-$ARCH
# Xray (精确提取)
wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$ARCH.zip
unzip -o /tmp/xray.zip -d /tmp/xray_temp
mv /tmp/xray_temp/xray /usr/local/bin/xray
rm -rf /tmp/xray*

chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray

echo -e "${BLUE}--- 2. 生成 Xray 配置 ---${PLAIN}"
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
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
User=root
EOF

# 服务 2: x-tunnel (参数修正)
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target

[Service]
# 使用您指定的参数格式
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
User=root
EOF

# 服务 3: cloudflared
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
User=root
EOF

# 4. 启动并验证
systemctl daemon-reload
systemctl stop nat-xray nat-xtun nat-cf 2>/dev/null
systemctl enable nat-xray nat-xtun nat-cf
systemctl start nat-xray nat-xtun nat-cf

echo -e "${GREEN}服务已尝试启动，等待 5 秒检查状态...${PLAIN}"
sleep 5
clear
echo -e "${BLUE}======================================================${PLAIN}"
printf "%-20s %-15s\n" "服务名称" "当前状态"
echo -e "------------------------------------------------------"
printf "%-20s %-15s\n" "nat-xray" "$(systemctl is-active nat-xray)"
printf "%-20s %-15s\n" "nat-xtun" "$(systemctl is-active nat-xtun)"
printf "%-20s %-15s\n" "nat-cf" "$(systemctl is-active nat-cf)"
echo -e "------------------------------------------------------"
echo -e "${BLUE}如果状态不是 active，请手动运行以下命令排错：${PLAIN}"
echo -e "Xray 报错: ${GREEN}journalctl -u nat-xray --no-pager -n 20${PLAIN}"
echo -e "XTun 报错: ${GREEN}journalctl -u nat-xtun --no-pager -n 20${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
