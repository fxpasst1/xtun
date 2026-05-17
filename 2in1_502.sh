#!/bin/bash

# ========================================================
# NAT 小鸡全能脚本：双隧道 + Xray 极致修正版 (支持 Debian/Alpine)
# 支持：cloudflared + x-tunnel + Xray
# ========================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 1. 自动识别系统架构与发行版
if [ -f /etc/alpine-release ]; then
    OS="alpine"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ] || [ -f /etc/os-release ]; then
    OS="debian"
else
    echo -e "${RED}错误：不支持的系统类型！仅支持 Debian/Ubuntu 或 Alpine。${PLAIN}"
    exit 1
fi

# 参数提取与默认值
MY_CF_TOKEN=${CF_TOKEN}
MY_XTUN_TOKEN=${XTUN_TOKEN}
MY_DOMAIN=${DOMAIN}            
MY_BEST_CF=${BEST_CF:-"cf.090227.xyz"} 
MY_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
MY_XP=${XP:-40001}             
MY_TP=${TP:-40002}             
MY_MP=${MP:-40003}             
MY_PATH="/vless"

# 必填检查
if [ -z "$MY_CF_TOKEN" ] || [ -z "$MY_XTUN_TOKEN" ] || [ -z "$MY_DOMAIN" ]; then
    echo -e "${RED}错误：缺失必要环境变量 CF_TOKEN, XTUN_TOKEN 或 DOMAIN！${PLAIN}"
    exit 1
fi

echo -e "${BLUE}--- 1. 识别架构与环境准备 (系统类型: $OS) ---${PLAIN}"
case "$(uname -m)" in
    x86_64 | x64 | amd64 ) XRAY_ARCH="64"; CF_ARCH="amd64"; XTUN_ARCH="amd64" ;;
    arm64 | aarch64 )      XRAY_ARCH="arm64-v8a"; CF_ARCH="arm64"; XTUN_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $(uname -m)${PLAIN}"; exit 1 ;;
esac

# 根据不同系统安装依赖 (Alpine 额外安装 gcompat 运行库以兼容 glibc 二进制)
if [ "$OS" = "debian" ]; then
    apt update && apt install -y curl wget jq tar unzip sudo file
elif [ "$OS" = "alpine" ]; then
    apk update && apk add curl wget jq tar unzip bash file gcompat openrc
fi

# 2. 下载并安装二进制组件
echo -e "${GREEN}正在下载并提取二进制组件...${PLAIN}"

# Cloudflared
curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared

# x-tunnel
curl -L "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/xt/x-tunnel-linux-${XTUN_ARCH}" -o /usr/local/bin/x-tunnel
if [ $(wc -c <"/usr/local/bin/x-tunnel") -ln 10000 ]; then
    echo -e "${RED}错误：x-tunnel 下载失败，请检查仓库路径。${PLAIN}"
    exit 1
fi

# Xray
curl -L "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip
mkdir -p /tmp/xray_temp
unzip -q -o /tmp/xray.zip -d /tmp/xray_temp
XRAY_BIN_PATH=$(find /tmp/xray_temp -type f -name "xray" | head -n 1)
if [ -n "$XRAY_BIN_PATH" ]; then
    cp -f "$XRAY_BIN_PATH" /usr/local/bin/xray
else
    echo -e "${RED}错误：未能在压缩包中找到 xray 二进制文件。${PLAIN}"
    exit 1
fi

chmod +x /usr/local/bin/cloudflared /usr/local/bin/x-tunnel /usr/local/bin/xray
rm -rf /tmp/xray*

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

# 4. 守护进程服务部署 (分系统处理以支持开机自启)
echo -e "${BLUE}--- 3. 部署自启守护服务 ---${PLAIN}"

if [ "$OS" = "debian" ]; then
    # ================= Debian/Ubuntu (Systemd) =================
    cat > /etc/systemd/system/nat-xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
RestartSec=5s
User=root
EOF

    cat > /etc/systemd/system/nat-xtun.service <<EOF
[Unit]
Description=x-tunnel Service
After=network.target
[Service]
ExecStart=/usr/local/bin/x-tunnel -l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN
Restart=on-failure
RestartSec=5s
User=root
EOF

    cat > /etc/systemd/system/nat-cf.service <<EOF
[Unit]
Description=Cloudflared Tunnel
After=network.target
[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN
Restart=on-failure
RestartSec=5s
User=root
EOF

    systemctl daemon-reload
    systemctl enable --now nat-xray nat-xtun nat-cf

elif [ "$OS" = "alpine" ]; then
    # ================= Alpine Linux (OpenRC) =================
    # Xray OpenRC 脚本
    cat > /etc/init.d/nat-xray <<EOF
#!/sbin/openrc-run
name="nat-xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
depend() {
    need net
}
EOF

    # x-tunnel OpenRC 脚本
    cat > /etc/init.d/nat-xtun <<EOF
#!/sbin/openrc-run
name="nat-xtun"
description="x-tunnel Service"
command="/usr/local/bin/x-tunnel"
command_args="-l ws://127.0.0.1:$MY_TP -token $MY_XTUN_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
depend() {
    need net
}
EOF

    # Cloudflared OpenRC 脚本
    cat > /etc/init.d/nat-cf <<EOF
#!/sbin/openrc-run
name="nat-cf"
description="Cloudflared Tunnel"
command="/usr/local/bin/cloudflared"
command_args="tunnel --no-autoupdate --protocol http2 --metrics 0.0.0.0:$MY_MP run --token $MY_CF_TOKEN"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
depend() {
    need net
}
EOF

    # 授权、添加开机自启并启动
    chmod +x /etc/init.d/nat-xray /etc/init.d/nat-xtun /etc/init.d/nat-cf
    rc-update add nat-xray default
    rc-update add nat-xtun default
    rc-update add nat-cf default
    rc-service nat-xray start
    rc-service nat-xtun start
    rc-service nat-cf start
fi

# 5. 生成 VLESS 链接
REMARKS=$(echo "CF_Tunnel_NAT" | sed -e 's/_/%20/g' -e 's/,/%2C/g')
VLESS_LINK="vless://${MY_UUID}@${MY_BEST_CF}:443?encryption=none&security=tls&type=ws&host=${MY_DOMAIN}&sni=${MY_DOMAIN}&path=${MY_PATH}#${REMARKS}_tls"

# 服务状态获取函数
get_status() {
    local service=$1
    if [ "$OS" = "debian" ]; then
        systemctl is-active "$service"
    else
        if rc-service "$service" status 2>/dev/null | grep -q "started"; then
            echo "active (running)"
        else
            echo "inactive (stopped)"
        fi
    fi
}

# 6. 安装结果展示
clear
echo -e "${BLUE}======================================================${PLAIN}"
echo -e "${GREEN}部署完成！服务运行状态预览：${PLAIN}"
echo -e "------------------------------------------------------"
printf "%-25s %-15s\n" "nat-xray (Xray Core):" "$(get_status nat-xray)"
printf "%-25s %-15s\n" "nat-xtun (XTun Tunnel):" "$(get_status nat-xtun)"
printf "%-25s %-15s\n" "nat-cf   (CF Tunnel):"   "$(get_status nat-cf)"
echo -e "------------------------------------------------------"
echo -e "${GREEN}您的 VLESS 节点链接 (直接复制导入)：${PLAIN}"
echo -e "${BLUE}${VLESS_LINK}${PLAIN}"
echo -e "------------------------------------------------------"
echo -e "${BLUE}管理命令提示：${PLAIN}"
if [ "$OS" = "debian" ]; then
    echo -e " 查看所有状态:  ${GREEN}systemctl status nat-xray nat-xtun nat-cf${PLAIN}"
    echo -e " 查看 Xray 日志: ${GREEN}journalctl -u nat-xray -f${PLAIN}"
else
    echo -e " 查看状态示例:  ${GREEN}rc-service nat-xray status${PLAIN}"
    echo -e " 重启服务示例:  ${GREEN}rc-service nat-xray restart${PLAIN}"
fi
echo -e "======================================================"

echo $VLESS_LINK > v2ray.txt
