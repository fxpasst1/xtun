#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：双隧道 + Xray + 极致优化版
# 支持：cloudflared (Optimized) + x-tunnel + Xray
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 参数提取与默认值
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_DOMAIN=${DOMAIN}            # 您的 CF 隧道固定域名 (如 ushevless.gcpsg.tk)
MY_BEST_CF=${BEST_CF:-"cf.090227.xyz"} # 优选域名连接地址
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
MY_XP=${XP:-40001}             # Xray 监听端口
MY_TP=${TP:-40002}             # x-tunnel 监听端口
MY_MP=${MP:-40003}             # Metrics 监控端口
MY_PATH="/vless"

# 必填检查
if [[ -z "$MY_CF_TOKEN" || -z "$MY_XTUN_TOKEN" || -z "$MY_DOMAIN" ]]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN, XTUN_TOKEN 或 DOMAIN！${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 1. 架构识别与环境准备 ---${PLAIN}"
case "$(uname -m)" in
    x86_64 | x64 | amd64 ) XRAY_ARCH="64"; CF_ARCH="amd64"; XTUN_ARCH="amd64" ;;
    arm64 | aarch64 )      XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64"; XTUN_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $(uname -m)${PLAIN}"; exit 1 ;;
esac

apt update && apt install -y curl wget jq tar unzip sudo || apk add curl wget jq tar unzip bash

# 2. 二进制组件下载
echo -e "${GREEN}正在下载二进制组件...${PLAIN}"

# Cloudflared
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared

# x-tunnel (使用 RAW 链接并校验)
curl -L "https://raw.githubusercontent.com/fxpasst1/xtun/main/bin/xtun-linux-${XTUN_ARCH}" -o /usr/local/bin/x-tunnel
if [ $(wc -c <"/usr/local/bin/x-tunnel") -lt 10000 ]; then
    echo -e "${RED}错误：x-tunnel 下载失败 (HTML 404)，请检查仓库路径。${PLAIN}"
    exit 1
fi

# Xray (官方 64 位命名规则修复)
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip
unzip -o /tmp/xray.zip -d /tmp/xray_temp
mv /tmp/xray_temp/xray /usr/local/bin/xray
rm -rf /tmp/xray*

chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray

# 3. 配置文件生成
echo -e "${BLUE}--- 2. 生成配置文件 ---${PLAIN}"
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

# 4. 独立服务部署
echo -e "${BLUE}--- 3. 部署独立 Systemd 服务 ---${PLAIN}"

# Xray 服务
cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
User=root
EOF

# x-tunnel 服务 (参数修正)
cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target
[Service]
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
User=root
EOF

# cloudflared 服务 (性能优化)
cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target
[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
User=root
EOF

systemctl daemon-reload
systemctl enable --now nat-xray nat-xtun nat-cf

# 5. 生成 VLESS 链接
# URL 编码备注
REMARKS=$(echo "CF_Tunnel_NAT" | sed -e 's/_/%20/g' -e 's/,/%2C/g')
# 链接构造逻辑
VLESS_LINK="vless://${MY_UUID}@${MY_BEST_CF}:443?encryption=none&security=tls&type=ws&host=${MY_DOMAIN}&sni=${MY_DOMAIN}&path=${MY_PATH}#${REMARKS}_tls"

# 6. 安装结果展示
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}部署完成！服务运行状态预览：${PLAIN}"
echo -e "------------------------------------------------------"
printf "%-20s %-15s\n" "nat-xray (Xray):" "$(systemctl is-active nat-xray)"
printf "%-20s %-15s\n" "nat-xtun (XTun):" "$(systemctl is-active nat-xtun)"
printf "%-20s %-15s\n" "nat-cf (CF):"     "$(systemctl is-active nat-cf)"
echo -e "------------------------------------------------------"
echo -e "${GREEN}您的 VLESS 节点链接 (直接复制导入)：${PLAIN}"
echo -e "${BLUE}${VLESS_LINK}${PLAIN}"
echo -e "------------------------------------------------------"
echo -e "${BLUE}维护命令提示：${PLAIN}"
echo -e " 查看状态: ${GREEN}systemctl status nat-xray nat-xtun nat-cf${PLAIN}"
echo -e " 查看 CF 日志: ${GREEN}journalctl -u nat-cf -f${PLAIN}"
echo -e " 查看 Xray 端口: ${GREEN}netstat -tlpn | grep $MY_XP${PLAIN}"
echo -e "${BLUE}======================================================${PLAIN}"

# 保存备份
echo $VLESS_LINK > v2ray.txt
