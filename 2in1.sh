#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：二进制路径与下载逻辑修复版
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

echo -e "${BLUE}--- 1. 识别架构并下载真实二进制 ---${PLAIN}"

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

# 下载 Cloudflared (官方源)
echo -e "${GREEN}正在下载 Cloudflared...${PLAIN}"
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared

# 下载 x-tunnel (注意：必须使用 RAW 链接)
echo -e "${GREEN}正在下载 x-tunnel...${PLAIN}"
# 修正后的 RAW 链接地址
curl -L "https://raw.githubusercontent.com/fxpasst1/xtun/refs/heads/main/bin/x-tunnel-linux-${XTUN_ARCH}" -o /usr/local/bin/x-tunnel

# 下载 Xray (官方源)
echo -e "${GREEN}正在下载 Xray...${PLAIN}"
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip

# 2. 解压与权限修复
echo -e "${BLUE}--- 2. 权限与配置修复 ---${PLAIN}"
# 如果下载到了 HTML (404)，通过文件大小简单判断
XTUN_SIZE=$(wc -c <"/usr/local/bin/x-tunnel")
if [ "$XTUN_SIZE" -lt 10000 ]; then
    echo -e "${RED}错误：x-tunnel 下载到的文件过小，可能是 HTML 404 页面，请检查 GitHub 路径。${PLAIN}"
    exit 1
fi

unzip -o /tmp/xray.zip -d /tmp/xray_temp
mv /tmp/xray_temp/xray /usr/local/bin/xray
chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray
rm -rf /tmp/xray*

# 3. 写入 Xray 配置
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

# 4. 部署 Systemd 服务 (独立化运行)
echo -e "${BLUE}--- 3. 部署 Systemd 服务 ---${PLAIN}"

# Xray
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
User=root
EOF

# x-tunnel
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target

[Service]
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
User=root
EOF

# cloudflared
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
User=root
EOF

# 5. 启动并展示
systemctl daemon-reload
systemctl enable --now nat-xray nat-xtun nat-cf

sleep 3
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}部署完成！当前服务运行状态预览：${PLAIN}"
echo -e "------------------------------------------------------"
printf "%-20s %-15s\n" "nat-xray" "$(systemctl is-active nat-xray)"
printf "%-20s %-15s\n" "nat-xtun" "$(systemctl is-active nat-xtun)"
printf "%-20s %-15s\n" "nat-cf" "$(systemctl is-active nat-cf)"
echo -e "------------------------------------------------------"
echo -e "${BLUE}常用命令：${PLAIN}"
echo -e " 查看状态: ${GREEN}systemctl status nat-xray nat-xtun nat-cf${PLAIN}"
echo -e " 查看 XTun 日志: ${GREEN}journalctl -u nat-xtun -f${PLAIN}"
echo -e " 端口监听情况: ${GREEN}netstat -tlpn${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"
