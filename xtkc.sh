#!/bin/bash

# ==========================================
# 1. 基础配置与环境变量
# ==========================================
export FILE_PATH=${FILE_PATH:-".npm"}
export PORT=${PORT:-3000}  # Nodejs 端口 & 订阅端口
export UUID=${UUID:-"fdeeda45-0a8e-4570-bcc6-d68c995f5830"}
export NAME=${NAME:-"MyNode"}

# 内部端口分配 (可根据需要修改)
export ARGO_PORT=8001
export S5_PORT=20001
export HY2_PORT=20002
export TUIC_PORT=20003
export REALITY_PORT=20004
export ANYTLS_PORT=20005
export ANYREALITY_PORT=20006
export XT_PORT=20007

export CFIP=${CFIP:-"saas.sin.fan"}
export CFPORT=${CFPORT:-"443"}

mkdir -p "${FILE_PATH}"

# ==========================================
# 2. 生成 Node.js 订阅服务端
# ==========================================
cat > index.js << EOF
const http = require('http');
const fs = require('fs');
const path = require('path');
const PORT = process.env.PORT || 3000;
const subtxt = path.join(__dirname, '${FILE_PATH}', 'sub.txt');

const server = http.createServer((req, res) => {
    if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('App is running...');
    } else if (req.url === '/sub') {
        if (fs.existsSync(subtxt)) {
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
            res.end(fs.readFileSync(subtxt, 'utf8'));
        } else {
            res.writeHead(404);
            res.end('Sub file not found yet. Please wait.');
        }
    } else {
        res.writeHead(404);
        res.end();
    }
});

server.listen(PORT, () => {
    console.log('Nodejs server listening on ' + PORT);
});
EOF

# ==========================================
# 3. 环境检测与文件下载
# ==========================================
ARCH=$(uname -m)
KM_ARCH="amd64" && [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && KM_ARCH="arm64"

download_file() {
    curl -L -sS -o "$2" "$1" && chmod +x "$2"
    echo -e "\033[32mDownloaded $2\033[0m"
}

[[ ! -x "${FILE_PATH}/sb" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/sb/sb_${KM_ARCH}" "${FILE_PATH}/sb"
[[ ! -x "${FILE_PATH}/cf" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/cf/cloudflared-linux-${KM_ARCH}" "${FILE_PATH}/cf"

# ==========================================
# 4. 证书与密钥生成 (Reality & TLS)
# ==========================================
# 生成 Reality 密钥对
if [ ! -f "${FILE_PATH}/key.txt" ]; then
    "${FILE_PATH}/sb" generate reality-keypair > "${FILE_PATH}/key.txt"
fi
private_key=$(grep "PrivateKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
public_key=$(grep "PublicKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')

# 生成自签名证书 (用于 Tuic/Hy2/AnyTLS)
openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key" 2>/dev/null
openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com" 2>/dev/null

# ==========================================
# 5. 生成 Sing-box 配置文件
# ==========================================
cat > ${FILE_PATH}/config.json << EOF
{
  "log": { "level": "error" },
  "inbounds": [
    { "tag": "vmess-ws-in", "type": "vmess", "listen": "::", "listen_port": ${ARGO_PORT}, "users": [{ "uuid": "${UUID}" }], "transport": { "type": "ws", "path": "/vmess-argo" } },
    { "tag": "socks5-in", "type": "socks", "listen": "::", "listen_port": ${S5_PORT}, "users": [{ "username": "admin", "password": "${UUID:0:8}" }] },
    { "tag": "tuic-in", "type": "tuic", "listen": "::", "listen_port": ${TUIC_PORT}, "users": [{ "uuid": "${UUID}", "password": "admin" }], "congestion_control": "bbr", "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "${FILE_PATH}/cert.pem", "key_path": "${FILE_PATH}/private.key" } },
    { "tag": "hysteria2-in", "type": "hysteria2", "listen": "::", "listen_port": ${HY2_PORT}, "users": [{ "password": "${UUID}" }], "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": "${FILE_PATH}/cert.pem", "key_path": "${FILE_PATH}/private.key" } },
    { "tag": "vless-reality-in", "type": "vless", "listen": "::", "listen_port": ${REALITY_PORT}, "users": [{ "uuid": "${UUID}", "flow": "xtls-rprx-vision" }], "tls": { "enabled": true, "server_name": "www.google.com", "reality": { "enabled": true, "handshake": { "server": "www.google.com", "server_port": 443 }, "private_key": "${private_key}", "short_id": [""] } } },
    { "tag": "anytls-in", "type": "anytls", "listen": "::", "listen_port": ${ANYTLS_PORT}, "users": [{ "password": "${UUID}" }], "tls": { "enabled": true, "certificate_path": "${FILE_PATH}/cert.pem", "key_path": "${FILE_PATH}/private.key" } },
    { "tag": "anyreality-in", "type": "anytls", "listen": "::", "listen_port": ${ANYREALITY_PORT}, "users": [{ "password": "${UUID}" }], "tls": { "enabled": true, "server_name": "www.bing.com", "reality": { "enabled": true, "handshake": { "server": "www.bing.com", "server_port": 443 }, "private_key": "${private_key}", "short_id": [""] } } }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "wireguard", "tag": "warp-out", "server": "engage.cloudflareclient.com", "server_port": 2408, "system_interface": false, "mtu": 1280, "address": ["172.16.0.2/32"], "private_key": "YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=", "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "reserved": [78, 135, 76] }
  ],
  "route": {
    "rules": [
      { "geosite": ["openai", "netflix"], "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF

# ==========================================
# 6. 启动进程与健康检查
# ==========================================
IP=$(curl -sm 3 ipv4.ip.sb || echo "127.0.0.1")
ISP=$(curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://api.ip.sb/geoip" | awk -F\" '{print $(NF-5)}' || echo "ISP")

run_apps() {
    # 启动 Node.js
    pgrep -f "node index.js" > /dev/null || nohup node index.js > /dev/null 2>&1 &
    # 启动 Sing-box
    pgrep -f "${FILE_PATH}/sb run" > /dev/null || nohup "${FILE_PATH}/sb" run -c ${FILE_PATH}/config.json > /dev/null 2>&1 &
    # 启动 Argo (临时隧道)
    pgrep -f "${FILE_PATH}/cf tunnel" > /dev/null || nohup "${FILE_PATH}/cf" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILE_PATH}/boot.log --url http://127.0.0.1:${ARGO_PORT} > /dev/null 2>&1 &
}

# ==========================================
# 7. 生成订阅链接 (循环更新)
# ==========================================
generate_sub() {
    # 等待 Argo 域名
    local argodomain=""
    while [ -z "$argodomain" ]; do
        argodomain=$(sed -n 's|.*https://\([^/]*trycloudflare\.com\).*|\1|p' ${FILE_PATH}/boot.log)
        [ -z "$argodomain" ] && sleep 2
    done

    # 清空列表
    > ${FILE_PATH}/list.txt
    
    # 1. Vmess-Argo
    VMESS="{\"v\":\"2\",\"ps\":\"${NAME}_Argo\",\"add\":\"${CFIP}\",\"port\":\"${CFPORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${argodomain}\",\"path\":\"/vmess-argo?ed=2560\",\"tls\":\"tls\",\"sni\":\"${argodomain}\"}"
    echo "vmess://$(echo -n "$VMESS" | base64 -w 0)" >> ${FILE_PATH}/list.txt
    
    # 2. Vless-Reality
    echo "vless://${UUID}@${IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.google.com&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${NAME}_Reality" >> ${FILE_PATH}/list.txt
    
    # 3. Hysteria2
    echo "hysteria2://${UUID}@${IP}:${HY2_PORT}/?sni=bing.com&alpn=h3&insecure=1#${NAME}_Hy2" >> ${FILE_PATH}/list.txt
    
    # 4. Tuic
    echo "tuic://${UUID}:admin@${IP}:${TUIC_PORT}?sni=bing.com&alpn=h3&congestion_control=bbr#${NAME}_Tuic" >> ${FILE_PATH}/list.txt
    
    # 5. AnyTLS
    echo "anytls://${UUID}@${IP}:${ANYTLS_PORT}?security=tls&sni=bing.com&fp=chrome&allowInsecure=1#${NAME}_AnyTLS" >> ${FILE_PATH}/list.txt
    
    # 6. Socks5
    echo "socks://$(echo -n "admin:${UUID:0:8}" | base64)@${IP}:${S5_PORT}#${NAME}_S5" >> ${FILE_PATH}/list.txt

    # 导出 Base64 订阅
    base64 -w 0 ${FILE_PATH}/list.txt > ${FILE_PATH}/sub.txt
    echo "Subscription updated: https://${argodomain}/sub"
}

# ==========================================
# 8. 主守护进程逻辑
# ==========================================
echo "Starting Watchdog..."
while true; do
    run_apps
    # 只有 sub.txt 不存在或者需要更新时才重新生成 (简单起见每 5 分钟更新一次域名检测)
    generate_sub
    sleep 300
done
