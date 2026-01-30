#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：修正下载逻辑与参数版
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

echo -e "${BLUE}--- 1. 识别架构并下载组件 ---${PLAIN}"

# 架构判定逻辑
case "$(uname -m)" in
    x86_64 | x64 | amd64 )
        XRAY_ARCH="64"
        CF_ARCH="amd64"
        XTUN_ARCH="amd64"
        ;;
    arm64 | aarch64 )
        XRAY_ARCH="arm64-v8a"
        CF_ARCH="arm64"
        XTUN_ARCH="arm64"
        ;;
    *)
        echo -e "${RED}不支持的架构: $(uname -m)${PLAIN}"
        exit 1
        ;;
esac

apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 下载 Cloudflared
echo -e "${GREEN}正在下载 Cloudflared...${PLAIN}"
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared

# 下载 x-tunnel
echo -e "${GREEN}正在下载 x-tunnel...${PLAIN}"
curl -L "https://github.com/fxpasst1/xtun/raw/main/bin/xtun-linux-${XTUN_ARCH}" -o /usr/local/bin/x-tunnel

# 下载 Xray (使用修正后的 64 位命名规则)
echo -e "${GREEN}正在下载 Xray...${PLAIN}"
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip

# 2. 解压与权限
unzip -o /tmp/xray.zip -d /tmp/xray_temp
mv /tmp/xray_temp/xray /usr/local/bin/xray
chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray
rm -rf /tmp/xray*

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

# Xray Service
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
User=root
EOF

# x-tunnel Service (修正参数)
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
User=root
EOF

# cloudflared Service
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
User=root
EOF

# 4. 启动与展示
systemctl daemon-reload
systemctl enable --now nat-xray nat-xtun nat-cf

sleep 3
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}部署完成！当前服务运行状态预览：${PLAIN}"
echo -e "------------------------------------------------------"
check_status() {
    status=$(systemctl is-active $1)
    if [ "$status" == "active" ]; then
        echo -e "$1: ${GREEN}● $status${PLAIN}"
    else
        echo -e "$1: ${RED}○ $status${PLAIN}"
    fi
}
check_status "nat-xray"
check_status "nat-xtun"
check_status "nat-cf"
echo -e "------------------------------------------------------"
echo -e "${BLUE}常用命令 UI 提示：${PLAIN}"
echo -e " 查看 Xray 日志: ${GREEN}journalctl -u nat-xray -f${PLAIN}"
echo -e " 查看 XTun 日志: ${GREEN}journalctl -u nat-xtun -f${PLAIN}"
echo -e " 查看 CF 日志:   ${GREEN}journalctl -u nat-cf -f${PLAIN}"
echo -e " 查看所有端口:   ${GREEN}netstat -tlpn${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
