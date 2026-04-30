#!/bin/bash

# ==========================================
# 1. 环境变量与初始化 (复刻原始 start.sh)
# ==========================================
export FILE_PATH=${FILE_PATH:-".npm"}
export PORT=${PORT:-3000}  # Node.js 订阅端口
export UUID=${UUID:-"fdeeda45-0a8e-4570-bcc6-d68c995f5830"}
export NAME=${NAME:-"Fixed_Node"}

# 组件开关
export ENABLE_SB=${ENABLE_SB:-true}
export ENABLE_KM=${ENABLE_KM:-true}
export ENABLE_XT=${ENABLE_XT:-true}
export ENABLE_CF=${ENABLE_CF:-true}

# 外部输入变量 (固定隧道与监控)
export ARGO_DOMAIN=${ARGO_DOMAIN:-""}
export ARGO_AUTH=${ARGO_AUTH:-""}
export KOMARI_SERVER=${KOMARI_SERVER:-""}
export KOMARI_KEY=${KOMARI_KEY:-""}
export XT_TOKEN=${XT_TOKEN:-""}
export XT_PORT=${XT_PORT:-"20007"}

# 内部端口分配
export ARGO_PORT=8001
export S5_PORT=20001
export HY2_PORT=20002
export TUIC_PORT=20003
export REALITY_PORT=20004
export ANYTLS_PORT=20005
export ANYREALITY_PORT=20006

export CFIP=${CFIP:-"saas.sin.fan"}
export CFPORT=${CFPORT:-"443"}

[ ! -d "${FILE_PATH}" ] && mkdir -p "${FILE_PATH}"

# ==========================================
# 2. 生成 Node.js 订阅服务 (index.js)
# ==========================================
cat > index.js << EOF
const http = require('http');
const fs = require('fs');
const path = require('path');
const PORT = process.env.PORT || 3000;
const subtxt = path.join(__dirname, '${FILE_PATH}', 'sub.txt');

const server = http.createServer((req, res) => {
    if (req.url === '/sub' || req.url === '/') {
        if (fs.existsSync(subtxt)) {
            res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
            res.end(fs.readFileSync(subtxt, 'utf8'));
        } else {
            res.writeHead(404);
            res.end('Sub file not ready.');
        }
    } else {
        res.writeHead(404); res.end();
    }
});
server.listen(PORT, () => console.log('Node Server Running on ' + PORT));
EOF

# ==========================================
# 3. 环境检测与二进制下载
# ==========================================
ARCH=$(uname -m)
KM_ARCH="amd64" && [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && KM_ARCH="arm64"

download_file() {
    curl -L -sS -o "$2" "$1" && chmod +x "$2"
    echo -e "\033[32mDownloaded $2\033[0m"
}

# 下载各组件
[ "$ENABLE_SB" = "true" ] && [[ ! -x "${FILE_PATH}/sb" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/sb/sb_${KM_ARCH}" "${FILE_PATH}/sb"
[ "$ENABLE_CF" = "true" ] && [[ ! -x "${FILE_PATH}/cf" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/cf/cloudflared-linux-${KM_ARCH}" "${FILE_PATH}/cf"
[ "$ENABLE_KM" = "true" ] && [[ ! -x "${FILE_PATH}/km" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/km/komari-agent-linux-${KM_ARCH}" "${FILE_PATH}/km"
[ "$ENABLE_XT" = "true" ] && [[ ! -x "${FILE_PATH}/xt" ]] && download_file "https://raw.githubusercontent.com/mygv001/xtun325/main/bin/xt/x-tunnel-linux-${KM_ARCH}" "${FILE_PATH}/xt"

# ==========================================
# 4. 证书与配置文件生成 (Sing-box & Argo)
# ==========================================
# Sing-box 密钥与证书
if [ ! -f "${FILE_PATH}/key.txt" ]; then "${FILE_PATH}/sb" generate reality-keypair > "${FILE_PATH}/key.txt"; fi
private_key=$(grep "PrivateKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
public_key=$(grep "PublicKey:" "${FILE_PATH}/key.txt" | awk '{print $2}')
openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key" 2>/dev/null
openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com" 2>/dev/null

# 生成 Sing-box 配置
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
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF

# Argo 固定隧道 Ingress 配置
if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo "$ARGO_AUTH" > ${FILE_PATH}/tunnel.json
    TUNNEL_ID=$(grep -oP '"TunnelID":"\K[^"]+' ${FILE_PATH}/tunnel.json)
    cat > tunnel.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: ${FILE_PATH}/tunnel.json
protocol: http2
ingress:
  - hostname: $ARGO_DOMAIN
    path: /sub
    service: http://127.0.0.1:$PORT
  - hostname: $ARGO_DOMAIN
    path: /vmess-argo
    service: http://127.0.0.1:$ARGO_PORT
  - hostname: $ARGO_DOMAIN
    service: http://127.0.0.1:$XT_PORT
  - service: http_status:404
EOF
    ARGO_ARGS="tunnel --config tunnel.yml run"
else
    ARGO_ARGS="tunnel --no-autoupdate run --token ${ARGO_AUTH}"
fi

# ==========================================
# 5. 进程启动逻辑与守护
# ==========================================
run_apps() {
    # 1. Node.js
    pgrep -f "node index.js" > /dev/null || nohup node index.js > /dev/null 2>&1 &
    
    # 2. Sing-box
    [ "$ENABLE_SB" = "true" ] && (pgrep -f "${FILE_PATH}/sb run" > /dev/null || nohup "${FILE_PATH}/sb" run -c ${FILE_PATH}/config.json > /dev/null 2>&1 &)
    
    # 3. Argo Tunnel
    [ "$ENABLE_CF" = "true" ] && [ -n "$ARGO_AUTH" ] && (pgrep -f "${FILE_PATH}/cf tunnel" > /dev/null || nohup "${FILE_PATH}/cf" $ARGO_ARGS > /dev/null 2>&1 &)
    
    # 4. Komari Agent
    [ "$ENABLE_KM" = "true" ] && [ -n "$KOMARI_SERVER" ] && (pgrep -f "${FILE_PATH}/km" > /dev/null || (export TMPDIR=$(pwd) && nohup "${FILE_PATH}/km" -e "${KOMARI_SERVER}" -t "${KOMARI_KEY}" -u > /dev/null 2>&1 &))
    
    # 5. X-tunnel
    [ "$ENABLE_XT" = "true" ] && [ -n "$XT_TOKEN" ] && (pgrep -f "${FILE_PATH}/xt" > /dev/null || nohup "${FILE_PATH}/xt" -l ws://127.0.0.1:${XT_PORT} -token ${XT_TOKEN} > /dev/null 2>&1 &)
}

# ==========================================
# 6. 订阅生成 (复刻 list.txt 逻辑)
# ==========================================
generate_sub() {
    IP=$(curl -sm 3 ipv4.ip.sb || echo "127.0.0.1")
    ISP=$(curl -sm 3 -H "User-Agent: Mozilla/5.0" "https://api.ip.sb/geoip" | awk -F\" '{print $(NF-5)}' || echo "ISP")
    NODE_NAME="${NAME}_${ISP}"
    
    > ${FILE_PATH}/list.txt
    if [ "$ENABLE_SB" = "true" ]; then
        # Vmess Argo
        VMESS="{\"v\":\"2\",\"ps\":\"${NODE_NAME}_Argo\",\"add\":\"${CFIP}\",\"port\":\"${CFPORT}\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"none\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${ARGO_DOMAIN}\",\"path\":\"/vmess-argo?ed=2560\",\"tls\":\"tls\",\"sni\":\"${ARGO_DOMAIN}\"}"
        echo "vmess://$(echo -n "$VMESS" | base64 -w 0)" >> ${FILE_PATH}/list.txt
        # 其他协议
        echo "vless://${UUID}@${IP}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.google.com&fp=chrome&pbk=${public_key}&type=tcp#${NODE_NAME}_Reality" >> ${FILE_PATH}/list.txt
        echo "hysteria2://${UUID}@${IP}:${HY2_PORT}/?sni=bing.com&alpn=h3&insecure=1#${NODE_NAME}_Hy2" >> ${FILE_PATH}/list.txt
        echo "tuic://${UUID}:admin@${IP}:${TUIC_PORT}?sni=bing.com&alpn=h3&congestion_control=bbr#${NODE_NAME}_Tuic" >> ${FILE_PATH}/list.txt
        echo "anytls://${UUID}@${IP}:${ANYTLS_PORT}?security=tls&sni=bing.com&fp=chrome&allowInsecure=1#${NODE_NAME}_AnyTLS" >> ${FILE_PATH}/list.txt
        echo "socks://$(echo -n "admin:${UUID:0:8}" | base64)@${IP}:${S5_PORT}#${NODE_NAME}_S5" >> ${FILE_PATH}/list.txt
    fi
    base64 -w 0 ${FILE_PATH}/list.txt > ${FILE_PATH}/sub.txt
}

# ==========================================
# 7. 主执行循环
# ==========================================
echo "Deployment logic starting..."
generate_sub

while true; do
    run_apps
    # 每 5 分钟检查并更新一次订阅（同步 IP 变化等）
    sleep 300
    generate_sub
done
