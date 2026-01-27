#!/bin/bash

# 1. 变量初始化
# 优先读取命令行 PORT 变量，默认为 38006
PORT=${PORT:-38006}
WORKDIR="/usr/local/bin"
LOG_FILE="/var/log/mtg.log"

# 2. 自动生成随机 Fake-TLS 密钥 (符合 MTG v2 格式)
# 结构：ee + 32位随机16进制 + hex(cloudflare.com)
RANDOM_HEX=$(openssl rand -hex 16)
DOMAIN_HEX=$(echo -n "cloudflare.com" | xxd -p)
SECRET="ee${RANDOM_HEX}${DOMAIN_HEX}"

# 3. 基础依赖安装
echo "正在安装必要组件 (curl, openssl, xxd, wget)..."
apt-get update && apt-get install -y curl openssl vim xxd wget tar >/dev/null 2>&1

# 4. 自动识别 CPU 架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)  MTG_ARCH="amd64" ;;
    aarch64) MTG_ARCH="arm64" ;;
    *) echo "暂时不支持的架构: $ARCH"; exit 1 ;;
esac

# 5. 清理旧进程
pkill mtg-bin 2>/dev/null
rm -f $WORKDIR/mtg-bin

# 6. 下载并安装 MTG v2.1.7
echo "正在为 $ARCH 架构下载 MTG v2.1.7..."
DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-${MTG_ARCH}.tar.gz"
wget -qO- $DOWNLOAD_URL | tar -xz -C /tmp
mv /tmp/mtg-*/mtg $WORKDIR/mtg-bin
chmod +x $WORKDIR/mtg-bin
rm -rf /tmp/mtg-*

# 7. 获取公网 IP (用于生成链接)
IP=$(curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 api.ipify.org)

# 8. 配置防火墙 (NAT 小鸡通常在面板开启端口，这里尝试在系统内放行)
if command -v ufw >/dev/null 2>&1; then
    ufw allow $PORT/tcp >/dev/null 2>&1
fi
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT >/dev/null 2>&1

# 9. 启动服务 (绑定 0.0.0.0 适用于 NAT 映射)
echo "正在启动 MTProto 服务..."
nohup $WORKDIR/mtg-bin simple-run 0.0.0.0:$PORT $SECRET > $LOG_FILE 2>&1 &

# 10. 设置开机自启 (Crontab 方式)
(crontab -l 2>/dev/null | grep -v "mtg-bin"; echo "@reboot nohup $WORKDIR/mtg-bin simple-run 0.0.0.0:$PORT $SECRET > $LOG_FILE 2>&1 &") | crontab -

# 输出结果
echo "------------------------------------------------"
echo "✅ MTProto 代理部署完成！"
echo "架构: $ARCH"
echo "公网 IP: $IP"
echo "监听端口: $PORT (请确保 NAT 面板已映射此端口)"
echo "密钥: $SECRET"
echo "------------------------------------------------"
echo "🔗 Telegram 一键连接链接:"
echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
echo "------------------------------------------------"
echo "💡 查看运行日志: tail -f $LOG_FILE"
