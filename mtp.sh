#!/bin/bash

# 设置变量
PORT=38006
SECRET="eeffdd62b0c4f2aa82ee53090998bdb27f7777772e636c6f7564666c6172652e636f6d"
IP=$(curl -s ifconfig.me)
WORKDIR="/usr/local/bin"

echo "正在优化系统并准备安装 MTProto (ARM64)..."

# 1. 自动识别并安装依赖
apt-get update && apt-get install -y wget tar curl net-tools

# 2. 清理旧进程和文件
pkill mtg-bin
rm -f $WORKDIR/mtg-bin $WORKDIR/mtg-2.1.7-linux-arm64.tar.gz

# 3. 下载并设置 MTG v2.1.7
cd $WORKDIR
wget https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-arm64.tar.gz
tar -xvf mtg-2.1.7-linux-arm64.tar.gz
mv mtg-2.1.7-linux-arm64/mtg ./mtg-bin
chmod +x mtg-bin
rm -rf mtg-2.1.7-linux-arm64*

# 4. 放行防火墙 (针对常用防火墙)
ufw allow $PORT/tcp >/dev/null 2>&1
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT >/dev/null 2>&1

# 5. 后台启动
nohup ./mtg-bin simple-run 0.0.0.0:$PORT $SECRET > /var/log/mtg.log 2>&1 &

# 6. 设置开机自启
(crontab -l 2>/dev/null | grep -v "mtg-bin"; echo "@reboot nohup $WORKDIR/mtg-bin simple-run 0.0.0.0:$PORT $SECRET > /var/log/mtg.log 2>&1 &") | crontab -

echo "------------------------------------------------"
echo "✅ MTProto 代理已部署成功！"
echo "服务器 IP: $IP"
echo "内部端口: $PORT"
echo "------------------------------------------------"
echo "🔗 Telegram 一键连接链接:"
echo "tg://proxy?server=$IP&port=$PORT&secret=$SECRET"
echo "------------------------------------------------"
