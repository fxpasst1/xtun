#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：双隧道 + Xray + 自动生成配置
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 参数提取与交互
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_DOMAIN=${DOMAIN} # 您的 Cloudflare 固定域名
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
MY_XP=${XP:-40001}
MY_TP=${TP:-40002}
MY_MP=${MP:-40003}
MY_PATH="/vless"

if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" || -z "$MY_DOMAIN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN, XTUN_TOKEN 或 DOMAIN！${PLAIN}"
    echo -e "用法示例：${BLUE}CF_TOKEN=xx XTUN_TOKEN=xx DOMAIN=v.abc.com bash <(curl ...)${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 1. 环境准备与架构识别 ---${PLAIN}"
case "$(uname -m)" in
    x86_64 | x64 | amd64 ) XRAY_ARCH="64"; CF_ARCH="amd64"; XTUN_ARCH="amd64" ;;
    arm64 | aarch64 )      XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64"; XTUN_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构${PLAIN}"; exit 1 ;;
esac

apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 2. 真实二进制下载 (修正 RAW 链接)
echo -e "${GREEN}正在下载二进制文件...${PLAIN}"
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared
curl -L "https://raw.githubusercontent.com/fxpasst1/xtun/main/bin/xtun-linux-${XTUN_ARCH}" -o /usr/local/bin/x-tunnel
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip

# 解压 Xray
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
        "streamSettings": { "network": "ws", "wsSettings": {"path": "$MY_PATH"} }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 4. 部署独立 Systemd 服务
echo -e "${BLUE}--- 2. 部署 Systemd 服务 ---${PLAIN}"

# Xray
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
User=root
[Install]
WantedBy=multi-user.target
EOF

# x-tunnel (参数严格修正)
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

# cloudflared
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

systemctl daemon-reload
systemctl enable --now nat-xray nat-xtun nat-cf

# 5. 生成 VLESS 链接
# 参考用户模板，进行 URL 编码处理
ISP_NAME="CF_Tunnel_NAT"
REMARKS=$(echo $ISP_NAME | sed -e 's/_/%20/g' -e 's/,/%2C/g')
# 构造 vless 链接
# 注意：Address 填域名，Port 填 443，开启 TLS，Host 和 SNI 均为域名
VLESS_LINK="vless://${MY_UUID}@$cf.090227.xyz:443?encryption=none&security=tls&type=ws&host=${MY_DOMAIN}&sni=${MY_DOMAIN}&path=${MY_PATH}#${REMARKS}_tls"

# 6. 最终界面展示
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}部署完成！服务运行状态：${PLAIN}"
echo -e "nat-xray: $(systemctl is-active nat-xray)"
echo -e "nat-xtun: $(systemctl is-active nat-xtun)"
echo -e "nat-cf:   $(systemctl is-active nat-cf)"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "${GREEN}您的 VLESS 节点链接 (复制到 v2rayN 即可使用)：${PLAIN}"
echo -e "${BLUE}${VLESS_LINK}${PLAIN}"
echo -e "${BLUE}------------------------------------------------------${PLAIN}"
echo -e "管理命令提示："
echo -e " 查看状态: systemctl status nat-xray nat-xtun nat-cf"
echo -e " 查看日志: journalctl -u nat-cf -f"
echo -e "${BLUE}======================================================${PLAIN}"

# 同时保存到本地文件
echo $VLESS_LINK > v2ray.txt
