#!/bin/bash
# TT Agro-suoha Token Version

linux_os=("Debian" "Ubuntu" "CentOS" "Fedora" "Alpine")
linux_update=("apt update" "apt update" "yum -y update" "yum -y update" "apk update")
linux_install=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
n=0
for i in `echo ${linux_os[@]}`
do
    if [ "$i" == "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" ]
    then
        break
    else
        n=$[$n+1]
    fi
done
if [ $n == 5 ]
then
    echo 当前系统$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2)没有适配
    echo 默认使用APT包管理器
    n=0
fi
if [ -z $(type -P unzip) ]
then
    ${linux_update[$n]}
    ${linux_install[$n]} unzip
fi
if [ -z $(type -P curl) ]
then
    ${linux_update[$n]}
    ${linux_install[$n]} curl
fi
if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" != "Alpine" ]
then
    if [ -z $(type -P systemctl) ]
    then
        ${linux_update[$n]}
        ${linux_install[$n]} systemctl
    fi
fi

function quicktunnel(){
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
    x86_64 | x64 | amd64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
    ;;
    i386 | i686 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
    ;;
    armv8 | arm64 | aarch64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
    ;;
    armv7l )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
    ;;
    * )
    echo 当前架构$(uname -m)没有适配
    exit
    ;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
rm -rf xray.zip
uuid=$(cat /proc/sys/kernel/random/uuid)
urlpath=$(echo $uuid | awk -F- '{print $1}')
port=$[$RANDOM+10000]
if [ $protocol == 1 ]
then
cat>xray/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$urlpath"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
fi
if [ $protocol == 2 ]
then
cat>xray/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$urlpath"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
fi
./xray/xray run>/dev/null 2>&1 &
./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
sleep 1
n=0
while true
do
n=$[$n+1]
clear
echo 等待cloudflare argo生成临时地址 已等待 $n 秒
argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [ $n == 15 ]
then
    n=0
    if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
    then
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $1}') >/dev/null 2>&1
    else
        kill -9 $(ps -ef | grep cloudflared-linux | grep -v grep | awk '{print $2}') >/dev/null 2>&1
    fi
    rm -rf argo.log
    clear
    echo argo获取超时,重试中
    ./cloudflared-linux tunnel --url http://localhost:$port --no-autoupdate --edge-ip-version $ips --protocol http2 >argo.log 2>&1 &
    sleep 1
elif [ -z "$argo" ]
then
    sleep 1
else
    rm -rf argo.log
    break
fi
done
clear
if [ $protocol == 1 ]
then
    echo -e vmess链接已经生成, www.visa.com.sg 可替换为CF优选IP'\n' > v2ray.txt
    if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
    then
        echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'_tls","tls":"tls","type":"none","v":"2"}' | base64 | awk '{ORS=(NR%76==0?RS:"");}1') >> v2ray.txt
    else
        echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'_tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0) >> v2ray.txt
    fi
    echo -e '\n'端口 443 可改为 2053 2083 2087 2096 8443'\n' >> v2ray.txt
    if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
    then
        echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"80","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"","type":"none","v":"2"}' | base64 | awk '{ORS=(NR%76==0?RS:"");}1') >> v2ray.txt
    else
        echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"80","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"","type":"none","v":"2"}' | base64 -w 0) >> v2ray.txt
    fi
    echo -e '\n'端口 80 可改为 8080 8880 2052 2082 2086 2095 >> v2ray.txt
fi
if [ $protocol == 2 ]
then
    echo -e vless链接已经生成, www.visa.com.sg 可替换为CF优选IP'\n' > v2ray.txt
    echo 'vless://'$uuid'@www.visa.com.sg:443?encryption=none&security=tls&type=ws&host='$argo'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'_tls' >> v2ray.txt
    echo -e '\n'端口 443 可改为 2053 2083 2087 2096 8443'\n' >> v2ray.txt
    echo 'vless://'$uuid'@www.visa.com.sg:80?encryption=none&security=none&type=ws&host='$argo'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'' >> v2ray.txt
    echo -e '\n'端口 80 可改为 8080 8880 2052 2082 2086 2095 >> v2ray.txt
fi
rm -rf argo.log
cat v2ray.txt
echo -e '\n'信息已经保存在 /root/v2ray.txt,再次查看请运行 cat /root/v2ray.txt
echo -e 注意：梭哈模式重启服务器后失效！！！
}

function installtunnel(){
mkdir -p /opt/suoha/ >/dev/null 2>&1
rm -rf xray cloudflared-linux xray.zip
case "$(uname -m)" in
    x86_64 | x64 | amd64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared-linux
    ;;
    i386 | i686 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-32.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386 -o cloudflared-linux
    ;;
    armv8 | arm64 | aarch64 )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm64-v8a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o cloudflared-linux
    ;;
    armv7l )
    curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-arm32-v7a.zip -o xray.zip
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared-linux
    ;;
    * )
    echo 当前架构$(uname -m)没有适配
    exit
    ;;
esac
mkdir xray
unzip -d xray xray.zip
chmod +x cloudflared-linux xray/xray
mv cloudflared-linux /opt/suoha/
mv xray/xray /opt/suoha/
rm -rf xray xray.zip

# 获取用户输入的 Token 和 域名
read -p "请输入 Cloudflare Tunnel Token: " tunnel_token
if [ -z "$tunnel_token" ]; then
    echo "Token 不能为空!"
    exit 1
fi
echo "$tunnel_token" > /opt/suoha/token.txt

read -p "请输入该隧道绑定的域名 (例如 node.example.com): " domain
if [ -z "$domain" ]; then
    echo "域名不能为空!"
    exit 1
fi

uuid=$(cat /proc/sys/kernel/random/uuid)
#urlpath=$(echo $uuid | awk -F- '{print $1}')
#port=$[$RANDOM+10000]

urlpath="vless"
port=8001

# 生成 Xray 配置
if [ $protocol == 1 ]
then
cat>/opt/suoha/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$urlpath"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
fi
if [ $protocol == 2 ]
then
cat>/opt/suoha/config.json<<EOF
{
    "inbounds": [
        {
            "port": $port,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$urlpath"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
fi

# 生成链接文件
if [ $protocol == 1 ]
then
    echo -e vmess链接已经生成, www.visa.com.sg 可替换为CF优选IP'\n' >/opt/suoha/v2ray.txt
    echo 'vmess://'$(echo '{"add":"www.visa.com.sg","aid":"0","host":"'$domain'","id":"'$uuid'","net":"ws","path":"'$urlpath'","port":"443","ps":"'$(echo $isp | sed -e 's/_/ /g')'","tls":"tls","type":"none","v":"2"}' | base64 -w 0) >>/opt/suoha/v2ray.txt
fi
if [ $protocol == 2 ]
then
    echo -e vless链接已经生成, saas.sin.fan 可替换为CF优选IP'\n' >/opt/suoha/v2ray.txt
    echo 'vless://'$uuid'@saas.sin.fan:443?encryption=none&security=tls&type=ws&host='$domain'&path='$urlpath'#'$(echo $isp | sed -e 's/_/%20/g' -e 's/,/%2C/g')'_tls' >>/opt/suoha/v2ray.txt
fi

# 配置服务
if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
then
cat>/etc/local.d/cloudflared.start<<EOF
/opt/suoha/cloudflared-linux tunnel --no-autoupdate  --protocol http2   run --token $tunnel_token &
EOF
cat>/etc/local.d/xray.start<<EOF
/opt/suoha/xray run -config /opt/suoha/config.json &
EOF
chmod +x /etc/local.d/cloudflared.start /etc/local.d/xray.start
rc-update add local
/etc/local.d/cloudflared.start >/dev/null 2>&1
/etc/local.d/xray.start >/dev/null 2>&1
else
# Systemd 服务
cat>/lib/systemd/system/cloudflared.service<<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/opt/suoha/cloudflared-linux tunnel --no-autoupdate  --protocol http2   run --token $tunnel_token
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
cat>/lib/systemd/system/xray.service<<EOF
[Unit]
Description=Xray
After=network.target

[Service]
Type=simple
ExecStart=/opt/suoha/xray run -config /opt/suoha/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable cloudflared.service >/dev/null 2>&1
systemctl enable xray.service >/dev/null 2>&1
systemctl daemon-reload
systemctl start cloudflared.service
systemctl start xray.service
fi

# 生成管理脚本
if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]
then
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
while true
do
[ \$(ps -ef | grep cloudflared-linux | grep -v grep | wc -l) == 0 ] && argostatus=stop || argostatus=running
[ \$(ps -ef | grep xray | grep -v grep | wc -l) == 0 ] && xraystatus=stop || xraystatus=running
echo "argo \$argostatus | xray \$xraystatus"
echo "1.启动服务 2.停止服务 3.重启服务 4.卸载服务 5.查看链接 0.退出"
read -p "选择: " menu
case \$menu in
    1) /etc/local.d/cloudflared.start; /etc/local.d/xray.start ;;
    2) killall cloudflared-linux xray ;;
    3) killall cloudflared-linux xray; sleep 1; /etc/local.d/cloudflared.start; /etc/local.d/xray.start ;;
    4) killall cloudflared-linux xray; rm -rf /opt/suoha /etc/local.d/cloudflared.start /etc/local.d/xray.start /usr/bin/suoha; exit ;;
    5) cat /opt/suoha/v2ray.txt ;;
    0) exit ;;
esac
done
EOF
else
cat>/opt/suoha/suoha.sh<<EOF
#!/bin/bash
while true
do
echo argo \$(systemctl is-active cloudflared.service)
echo xray \$(systemctl is-active xray.service)
echo "1.启动 2.停止 3.重启 4.卸载 5.查看链接 0.退出"
read -p "选择: " menu
case \$menu in
    1) systemctl start cloudflared xray ;;
    2) systemctl stop cloudflared xray ;;
    3) systemctl restart cloudflared xray ;;
    4) systemctl stop cloudflared xray; systemctl disable cloudflared xray; rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha; systemctl daemon-reload; exit ;;
    5) cat /opt/suoha/v2ray.txt ;;
    0) exit ;;
esac
done
EOF
fi
chmod +x /opt/suoha/suoha.sh
ln -sf /opt/suoha/suoha.sh /usr/bin/suoha
}

# --- 主程序入口 ---
clear
echo "欢迎使用 TT Agro-suoha Token 增强版"
echo "1. 梭哈模式 (临时隧道, 无需域名)"
echo "2. 安装服务 (固定隧道, 需提供 CF Token)"
echo "3. 卸载所有服务"
echo "5. 管理服务"
echo "0. 退出"
read -p "请选择模式: " mode
[ -z "$mode" ] && mode=1

if [ $mode == 1 ] || [ $mode == 2 ]; then
    read -p "选择协议 (1.vmess 2.vless, 默认1): " protocol
    [ -z "$protocol" ] && protocol=2
    read -p "连接模式 (4/6, 默认4): " ips
    [ -z "$ips" ] && ips=4
    isp=$(curl -$ips -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
fi

case $mode in
    1)
        quicktunnel
        ;;
    2)
        installtunnel
        cat /opt/suoha/v2ray.txt
        echo "服务安装完成, 管理命令: suoha"
        ;;
    3)
        # 卸载逻辑（兼容性处理）
        if [ "$(grep -i PRETTY_NAME /etc/os-release | cut -d \" -f2 | awk '{print $1}')" == "Alpine" ]; then
            killall cloudflared-linux xray 2>/dev/null
        else
            systemctl stop cloudflared xray 2>/dev/null
            systemctl disable cloudflared xray 2>/dev/null
        fi
        rm -rf /opt/suoha /lib/systemd/system/cloudflared.service /lib/systemd/system/xray.service /usr/bin/suoha /etc/local.d/cloudflared.start /etc/local.d/xray.start
        echo "卸载完成。"
        ;;
    5)
        if [ -f "/usr/bin/suoha" ]; then suoha; else echo "未安装服务"; fi
        ;;
    *)
        exit
        ;;
esac
