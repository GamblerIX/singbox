#!/bin/bash
export LANG=en_US.UTF-8

# 静默模式标志
SILENT=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--silent) SILENT=true; shift;;
        *) shift;;
    esac
done

# 颜色
red='\033[31m';green='\033[32m';yellow='\033[33m';blue='\033[36m';bblue='\033[34m';plain='\033[0m'
red(){ echo -e "\033[31;1m$1\033[0m";}
green(){ echo -e "\033[32;1m$1\033[0m";}
yellow(){ echo -e "\033[33;1m$1\033[0m";}
blue(){ echo -e "\033[36;1m$1\033[0m";}
white(){ echo -e "\033[37;1m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}

[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

# 系统检测
release=$(grep -qi 'debian' /etc/issue /etc/os-release 2>/dev/null && echo Debian || \
          grep -qi 'ubuntu' /etc/issue /etc/os-release 2>/dev/null && echo Ubuntu || \
          grep -qi 'centos\|redhat' /etc/redhat-release /etc/os-release 2>/dev/null && echo Centos)
[[ -z $release ]] && red "不支持当前系统" && exit

op=$(cat /etc/redhat-release 2>/dev/null || grep -i pretty_name /etc/os-release | cut -d\" -f2)
vi=$(systemd-detect-virt 2>/dev/null)
hostname=$(hostname)
case $(uname -m) in aarch64) cpu=arm64;; x86_64) cpu=amd64;; *) red "不支持$(uname -m)架构" && exit;; esac
bbr=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}'); [[ -z $bbr ]] && bbr="未启用"

# 首次安装依赖
[[ ! -f sbyg_update ]] && {
    green "安装依赖……"
    command -v apt-get &>/dev/null && apt update -y && apt install -y jq curl openssl tar wget qrencode socat cron
    command -v yum &>/dev/null && yum install -y epel-release jq curl openssl tar wget qrencode socat
    touch sbyg_update
}

v4v6(){ v4=$(curl -s4m5 icanhazip.com -k); v6=$(curl -s6m5 icanhazip.com -k); }

v6(){
    [[ -z $(curl -s4m5 icanhazip.com -k) ]] && { echo "nameserver 2a00:1098:2b::1" > /etc/resolv.conf; ipv=prefer_ipv6; } || ipv=prefer_ipv4
}

chooseport(){
    [[ -z $port ]] && port=$(shuf -i 10000-65535 -n 1)
    while ss -tunlp | grep -qw "$port"; do port=$(shuf -i 10000-65535 -n 1); done
}

# 静默模式 IP 证书申请函数
silentAcmeIP(){
    v4v6
    [[ -z $v4 && -z $v6 ]] && { red "无法获取IP地址"; return 1; }
    [[ -n $v4 ]] && ipaddr=$v4 && ipflag="" || { ipaddr=$v6; ipflag="--listen-v6"; }
    
    # 释放80端口
    if [[ -n $(lsof -i :80 | grep -v "PID") ]]; then
        lsof -i :80 | grep -v "PID" | awk '{print "kill -9",$2}' | sh >/dev/null 2>&1
    fi
    
    # 安装 acme.sh
    mkdir -p /root/ygkkkca
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        auto=$(date +%s%N | md5sum | cut -c 1-6)
        curl -sL https://get.acme.sh | sh -s email=${auto}@gmail.com >/dev/null 2>&1
        bash ~/.acme.sh/acme.sh --upgrade --use-wget --auto-upgrade >/dev/null 2>&1
    fi
    
    # 申请 IP 证书
    yellow "正在申请 IP 证书: $ipaddr"
    bash ~/.acme.sh/acme.sh --issue --standalone -d ${ipaddr} -k ec-256 --server letsencrypt $ipflag --insecure --preferred-chain "ISRG Root X1" --profile shortlived >/dev/null 2>&1
    bash ~/.acme.sh/acme.sh --install-cert -d ${ipaddr} --key-file /root/ygkkkca/private.key --fullchain-file /root/ygkkkca/cert.crt --ecc >/dev/null 2>&1
    
    # 保存证书信息
    echo $ipaddr > /root/ygkkkca/ca.log
    
    # 设置自动续期
    crontab -l 2>/dev/null | grep -v '\-\-cron' > /tmp/crontab.tmp
    echo "0 0 * * * root bash ~/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp && rm -f /tmp/crontab.tmp
}

inssb(){
    # 获取最新版本
    sbcore=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    [[ -z "$sbcore" ]] && { red "获取最新版本失败"; exit; }
    yellow "正在安装 Sing-box v$sbcore..."
    curl -L -o /etc/s-box/sing-box.tar.gz -# --retry 2 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/sing-box-$sbcore-linux-$cpu.tar.gz
    tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box && mv /etc/s-box/sing-box-*/sing-box /etc/s-box && rm -rf /etc/s-box/sing-box-* /etc/s-box/*.tar.gz
    chmod +x /etc/s-box/sing-box; [[ ! -f /etc/s-box/sing-box ]] && red "内核安装失败" && exit
    blue "内核：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
}

inscert(){
    # 生成自签证书作为默认
    openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
    openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
    
    # 静默模式：自动申请IP证书
    if [[ "$SILENT" = true ]]; then
        yellow "静默模式：自动申请IP证书..."
        silentAcmeIP
        if [[ -f /root/ygkkkca/cert.crt && -s /root/ygkkkca/cert.crt ]]; then
            tlsyn=true; certc='/root/ygkkkca/cert.crt'; certp='/root/ygkkkca/private.key'
            green "IP证书申请成功"
        else
            yellow "IP证书申请失败，使用自签证书"
            tlsyn=false; certc='/etc/s-box/cert.pem'; certp='/etc/s-box/private.key'
        fi
        return
    fi
    
    # 交互模式：检测已有证书
    if [[ -f /root/ygkkkca/cert.crt && -s /root/ygkkkca/cert.crt ]]; then
        yellow "检测到已申请的证书 1:自签(默认) 2:使用已申请的证书"; readp "选择：" m
        [[ "$m" = "2" ]] && { tlsyn=true; certc='/root/ygkkkca/cert.crt'; certp='/root/ygkkkca/private.key'; return; }
    fi
    tlsyn=false; certc='/etc/s-box/cert.pem'; certp='/etc/s-box/private.key'
}

insport(){
    # 静默模式：使用固定端口25531-25534
    if [[ "$SILENT" = true ]]; then
        port_vl=25531; port_vm=25532; port_hy=25533; port_tu=25534
    else
        for i in {1..4}; do port=""; chooseport; ports[$i]=$port; done
        port_vl=${ports[1]}; port_hy=${ports[3]}; port_tu=${ports[4]}
        [[ $tlsyn == "true" ]] && port_vm=8443 || port_vm=8080
    fi
    uuid=$(/etc/s-box/sing-box generate uuid)
    blue "端口 VL:$port_vl VM:$port_vm HY:$port_hy TU:$port_tu UUID:$uuid"
}

insjson(){
    sbnh=$(/etc/s-box/sing-box version | awk '/version/{print $NF}' | cut -d. -f1,2)
    [[ "$sbnh" == "1.10" ]] && sniff='"sniff":true,"sniff_override_destination":true,' || sniff=''
cat > /etc/s-box/sb.json <<EOF
{"log":{"level":"info","timestamp":true},"inbounds":[
{"type":"vless",${sniff}"tag":"vless","listen":"::","listen_port":${port_vl},"users":[{"uuid":"${uuid}","flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":"apple.com","reality":{"enabled":true,"handshake":{"server":"apple.com","server_port":443},"private_key":"$private_key","short_id":["$short_id"]}}},
{"type":"vmess",${sniff}"tag":"vmess","listen":"::","listen_port":${port_vm},"users":[{"uuid":"${uuid}","alterId":0}],"transport":{"type":"ws","path":"${uuid}-vm","max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"},"tls":{"enabled":${tlsyn},"server_name":"www.bing.com","certificate_path":"$certc","key_path":"$certp"}},
{"type":"hysteria2",${sniff}"tag":"hy2","listen":"::","listen_port":${port_hy},"users":[{"password":"${uuid}"}],"tls":{"enabled":true,"alpn":["h3"],"certificate_path":"$certc","key_path":"$certp"}},
{"type":"tuic",${sniff}"tag":"tuic","listen":"::","listen_port":${port_tu},"users":[{"uuid":"${uuid}","password":"${uuid}"}],"congestion_control":"bbr","tls":{"enabled":true,"alpn":["h3"],"certificate_path":"$certc","key_path":"$certp"}}
],"outbounds":[{"type":"direct","tag":"direct","domain_strategy":"$ipv"},{"type":"block","tag":"block"}],"route":{"rules":[${sniff:+"{\"action\":\"sniff\"},"}{"protocol":["quic","stun"],"outbound":"block"}]}}
EOF
}

sbservice(){
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
Restart=on-failure
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now sing-box >/dev/null 2>&1
}

lnsb(){ curl -sL -o /usr/bin/sb https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh && chmod +x /usr/bin/sb; }

# 1.安装
install(){
    [[ -f /etc/systemd/system/sing-box.service ]] && red "已安装" && exit
    mkdir -p /etc/s-box; v6; inssb; inscert; insport
    key=$(/etc/s-box/sing-box generate reality-keypair)
    private_key=$(echo "$key" | awk '/PrivateKey/{print $2}')
    public_key=$(echo "$key" | awk '/PublicKey/{print $2}'); echo "$public_key" > /etc/s-box/public.key
    short_id=$(/etc/s-box/sing-box generate rand --hex 4)
    insjson; sbservice; lnsb
    curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/version | head -1 > /etc/s-box/v
    green "安装成功！快捷方式：sb"; sbshare
}

# 2.卸载
unins(){
    systemctl disable --now sing-box >/dev/null 2>&1
    rm -rf /etc/systemd/system/sing-box.service /etc/s-box sbyg_update /usr/bin/sb
    green "卸载完成"
}

# 3.暂停/重启
stclre(){
    [[ ! -f /etc/s-box/sb.json ]] && red "未安装" && exit
    yellow "1:重启 2:关闭"; readp "选择：" m
    [[ "$m" = "1" ]] && systemctl restart sing-box && green "已重启" || { systemctl stop sing-box; green "已关闭"; }
}

# 4.更新脚本
upsbyg(){ lnsb; curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/version | head -1 > /etc/s-box/v; green "已更新" && sleep 2 && sb; }

# 5.更新内核
upcore(){
    [[ ! -f /etc/s-box/sb.json ]] && red "未安装" && exit
    lat=$(curl -sL https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -oE '"[0-9.]+",' | head -1 | tr -d '",')
    ins=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
    green "当前:$ins 最新:$lat"; yellow "1:更新 0:返回"; readp "选择：" m; [[ "$m" != "1" ]] && sb && return
    curl -L -o /etc/s-box/sb.tar.gz -# https://github.com/SagerNet/sing-box/releases/download/v$lat/sing-box-$lat-linux-$cpu.tar.gz
    tar xzf /etc/s-box/sb.tar.gz -C /etc/s-box && mv /etc/s-box/sing-box-*/sing-box /etc/s-box && rm -rf /etc/s-box/sing-box-* /etc/s-box/*.tar.gz
    chmod +x /etc/s-box/sing-box && systemctl restart sing-box
    green "已更新:$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
}

# 6.输出节点
sbshare(){
    [[ ! -f /etc/s-box/sb.json ]] && red "未安装" && exit
    v4v6; ip=${v4:-$v6}; [[ "$ip" =~ : ]] && sip="[$ip]" || sip=$ip
    cfg=$(sed 's://.*::g' /etc/s-box/sb.json)
    uuid=$(echo "$cfg" | jq -r '.inbounds[0].users[0].uuid')
    vl_p=$(echo "$cfg" | jq -r '.inbounds[0].listen_port')
    vm_p=$(echo "$cfg" | jq -r '.inbounds[1].listen_port')
    hy_p=$(echo "$cfg" | jq -r '.inbounds[2].listen_port')
    tu_p=$(echo "$cfg" | jq -r '.inbounds[3].listen_port')
    ws=$(echo "$cfg" | jq -r '.inbounds[1].transport.path')
    tls=$(echo "$cfg" | jq -r '.inbounds[1].tls.enabled')
    pk=$(cat /etc/s-box/public.key)
    sid=$(echo "$cfg" | jq -r '.inbounds[0].tls.reality.short_id[0]')
    hkey=$(echo "$cfg" | jq -r '.inbounds[2].tls.key_path')
    # 自签证书使用bing.com作为SNI，ACME证书使用实际IP/域名
    [[ "$hkey" = '/etc/s-box/private.key' ]] && sni="www.bing.com" && ins=1 || { sni=$(cat /root/ygkkkca/ca.log 2>/dev/null); [[ "$sni" =~ ^[0-9.]+$ || "$sni" =~ : ]] && ins=0 || ins=0; }
    [[ "$tls" = "false" ]] && vmtls="" || vmtls="tls"
    
    vl="vless://$uuid@$sip:$vl_p?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pk&sid=$sid&type=tcp#vl-$hostname"
    vm="vmess://$(echo '{"add":"'$ip'","aid":"0","host":"www.bing.com","id":"'$uuid'","net":"ws","path":"'$ws'","port":"'$vm_p'","ps":"vm-'$hostname'","tls":"'$vmtls'","type":"none","v":"2"}' | base64 -w0)"
    hy="hysteria2://$uuid@$sip:$hy_p?security=tls&alpn=h3&insecure=$ins&sni=$sni#hy2-$hostname"
    tu="tuic://$uuid:$uuid@$sip:$tu_p?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$sni&allow_insecure=$ins#tu5-$hostname"
    
    for n l in "Vless-Reality" "$vl" "Vmess-WS" "$vm" "Hysteria2" "$hy" "Tuic5" "$tu"; do
        white "═══════════════════════════════════════"; red "🚀 $n"; echo -e "${yellow}$l${plain}"; qrencode -o- -tANSIUTF8 "$l" 2>/dev/null
    done
    white "═══════════════════════════════════════"; red "🚀 聚合订阅"
    echo -e "${yellow}$(echo -e "$vl\n$vm\n$hy\n$tu" | base64 -w0)${plain}"
}

# 7.日志
sblog(){ red "Ctrl+C退出"; journalctl -u sing-box -o cat -f; }

# 8.BBR
bbr(){ bash <(curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/bbr.sh); }

# 9.Acme
acme(){ bash <(curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/acme.sh); }

# 主菜单
sb(){
clear
white "══════════════════════════════════════════════════"
white "         Sing-box 管理脚本 | 快捷方式: sb"
white "══════════════════════════════════════════════════"
echo -e "${green} 1.安装  2.卸载  3.重启/停止  4.更新脚本  5.更新内核${plain}"
echo -e "${green} 6.节点  7.日志  8.BBR  9.Acme  0.退出${plain}"
white "══════════════════════════════════════════════════"
v4v6; echo -e "系统:${blue}$op${plain} 架构:${blue}$cpu${plain} BBR:${blue}$bbr${plain}"
echo -e "IPv4:${blue}${v4:-无}${plain} IPv6:${blue}${v6:-无}${plain}"
systemctl is-active sing-box &>/dev/null && echo -e "状态:${blue}运行中${plain} 内核:${blue}$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')${plain}" || \
    { [[ -f /etc/s-box/sb.json ]] && echo -e "状态:${yellow}已停止${plain}" || echo -e "状态:${red}未安装${plain}"; }
white "══════════════════════════════════════════════════"
readp "选择[0-9]:" i
case "$i" in 1)install;;2)unins;;3)stclre;;4)upsbyg;;5)upcore;;6)sbshare;;7)sblog;;8)bbr;;9)acme;;*)exit;;esac
}

# 静默模式直接安装，否则显示菜单
if [[ "$SILENT" = true ]]; then
    green "静默一键安装模式..."
    install
else
    sb
fi
