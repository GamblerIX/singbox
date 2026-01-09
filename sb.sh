#!/bin/bash
# 相关文件: README.md, acme.sh, bbr.sh, sb.sh
# 
# Sing-box 一键安装脚本
# 功能：支持 Vless-reality, Vmess-ws, Hysteria2, Tuic5
# 
export LANG=en_US.UTF-8

# ========================================================
# 1. 变量定义与配置管理
# ========================================================

# 静默模式标志
SILENT=false

# 颜色定义
red='\033[31m'
green='\033[32m'
yellow='\033[33m'
blue='\033[36m'
bblue='\033[34m'
plain='\033[0m'

# 核心路径
SB_CONF_DIR="/etc/s-box"
SB_BIN_PATH="/etc/s-box/sing-box"
SB_JSON_PATH="/etc/s-box/sb.json"
ACME_CERT_DIR="/root/ygkkkca"

# 快捷函数：彩色打印
red() { echo -e "\033[31;1m$1\033[0m"; }
green() { echo -e "\033[32;1m$1\033[0m"; }
yellow() { echo -e "\033[33;1m$1\033[0m"; }
blue() { echo -e "\033[36;1m$1\033[0m"; }
white() { echo -e "\033[37;1m$1\033[0m"; }
readp() { read -p "$(yellow "$1")" $2; }

# ========================================================
# 2. 基础检测与依赖安装
# ========================================================

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--silent) SILENT=true; shift;;
        *) shift;;
    esac
done

# 权限检测
if [[ $EUID -ne 0 ]]; then
    yellow "请以root模式运行脚本"
    exit 1
fi

# 系统检测
detect_system() {
    release=$(grep -qi 'debian' /etc/issue /etc/os-release 2>/dev/null && echo Debian || \
              grep -qi 'ubuntu' /etc/issue /etc/os-release 2>/dev/null && echo Ubuntu || \
              grep -qi 'centos\|redhat' /etc/redhat-release /etc/os-release 2>/dev/null && echo Centos)
    
    if [[ -z $release ]]; then
        red "不支持当前系统"
        exit 1
    fi

    # 详细系统信息
    op=$(cat /etc/redhat-release 2>/dev/null || grep -i pretty_name /etc/os-release | cut -d\" -f2)
    vi=$(systemd-detect-virt 2>/dev/null)
    hostname=$(hostname)
    
    # CPU架构检测
    case $(uname -m) in
        aarch64) cpu=arm64;;
        x86_64) cpu=amd64;;
        *) red "不支持$(uname -m)架构"; exit 1;;
    esac
    
    # BBR检测
    bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    [[ -z $bbr_status ]] && bbr_status="未启用"
}

# 安装基础依赖
install_dependencies() {
    if [[ ! -f sbyg_update ]]; then
        green "正在安装系统依赖……"
        if command -v apt-get &>/dev/null; then
            apt update -y
            apt install -y jq curl openssl tar wget qrencode socat cron
        elif command -v yum &>/dev/null; then
            yum install -y epel-release jq curl openssl tar wget qrencode socat
        fi
        touch sbyg_update
    fi
}

# ========================================================
# 3. 网络与证书功能
# ========================================================

# 获取公网IP
get_ip() {
    v4=$(curl -s4m5 icanhazip.com -k)
    v6=$(curl -s6m5 icanhazip.com -k)
}

# 检测IPv6优先
check_ipv6() {
    if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
        # 纯IPv6环境，设置DNS
        echo "nameserver 2a00:1098:2b::1" > /etc/resolv.conf
        ipv_strategy="prefer_ipv6"
    else
        ipv_strategy="prefer_ipv4"
    fi
}

# 端口占用检测与随机生成
choose_port() {
    local target_var=$1
    local temp_port
    
    if [[ -z ${!target_var} ]]; then
        temp_port=$(shuf -i 10000-65535 -n 1)
        # 循环直到找到未被占用的端口
        while ss -tunlp | grep -qw "$temp_port"; do
            temp_port=$(shuf -i 10000-65535 -n 1)
        done
        eval "$target_var=$temp_port"
    fi
}

# 静默申请 IP 证书 (Let's Encrypt)
silent_acme_ip() {
    get_ip
    if [[ -z $v4 && -z $v6 ]]; then
        red "无法获取IP地址"
        return 1
    fi
    
    # 确定主IP和ACME标志
    if [[ -n $v4 ]]; then
        ipaddr=$v4
        ipflag=""
    else
        ipaddr=$v6
        ipflag="--listen-v6"
    fi
    
    # 释放80端口防止冲突
    if [[ -n $(lsof -i :80 | grep -v "PID") ]]; then
        lsof -i :80 | grep -v "PID" | awk '{print "kill -9",$2}' | sh >/dev/null 2>&1
    fi
    
    # 安装 acme.sh
    mkdir -p "$ACME_CERT_DIR"
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        local auto=$(date +%s%N | md5sum | cut -c 1-6)
        curl -sL https://get.acme.sh | sh -s email=${auto}@gmail.com >/dev/null 2>&1
        bash ~/.acme.sh/acme.sh --upgrade --use-wget --auto-upgrade >/dev/null 2>&1
    fi
    
    # 申请 IP 证书 (使用 shortlived 模式，无须域名)
    yellow "正在为 IP 申请证书: $ipaddr"
    bash ~/.acme.sh/acme.sh --issue --standalone -d "${ipaddr}" -k ec-256 --server letsencrypt $ipflag --insecure --preferred-chain "ISRG Root X1" --profile shortlived >/dev/null 2>&1
    bash ~/.acme.sh/acme.sh --install-cert -d "${ipaddr}" --key-file "$ACME_CERT_DIR/private.key" --fullchain-file "$ACME_CERT_DIR/cert.crt" --ecc >/dev/null 2>&1
    
    # 记录证书域名/IP
    echo "$ipaddr" > "$ACME_CERT_DIR/ca.log"
    
    # 设置证书自动续期任务
    crontab -l 2>/dev/null | grep -v '\-\-cron' > /tmp/crontab.tmp
    echo "0 0 * * * root bash ~/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /tmp/crontab.tmp
    crontab /tmp/crontab.tmp && rm -f /tmp/crontab.tmp
}

# ========================================================
# 4. Sing-box 安装与配置
# ========================================================

# 下载并安装内核
install_sb_core() {
    # 获取最新内核版本号
    sb_version=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [[ -z "$sb_version" ]]; then
        red "获取最新版本失败"
        exit 1
    fi
    
    yellow "正在下载 Sing-box v$sb_version ($cpu)..."
    mkdir -p "$SB_CONF_DIR"
    curl -L -o "$SB_CONF_DIR/sing-box.tar.gz" -# --retry 2 "https://github.com/SagerNet/sing-box/releases/download/v$sb_version/sing-box-$sb_version-linux-$cpu.tar.gz"
    
    # 解压并部署
    tar xzf "$SB_CONF_DIR/sing-box.tar.gz" -C "$SB_CONF_DIR"
    mv "$SB_CONF_DIR/sing-box-$sb_version-linux-$cpu/sing-box" "$SB_BIN_PATH"
    rm -rf "$SB_CONF_DIR/sing-box-$sb_version-linux-$cpu" "$SB_CONF_DIR/sing-box.tar.gz"
    
    chmod +x "$SB_BIN_PATH"
    if [[ ! -f "$SB_BIN_PATH" ]]; then
        red "内核安装失败"
        exit 1
    fi
    blue "内核已安装，版本：$("$SB_BIN_PATH" version | awk '/version/{print $NF}')"
}

# 证书配置逻辑
setup_certificates() {
    # 默认生成一套自签证书作为兜底
    openssl ecparam -genkey -name prime256v1 -out "$SB_CONF_DIR/private.key"
    openssl req -new -x509 -days 36500 -key "$SB_CONF_DIR/private.key" -out "$SB_CONF_DIR/cert.pem" -subj "/CN=www.bing.com"
    
    if [[ "$SILENT" = true ]]; then
        yellow "静默模式：尝试自动申请 IP 证书..."
        silent_acme_ip
        if [[ -f "$ACME_CERT_DIR/cert.crt" && -s "$ACME_CERT_DIR/cert.crt" ]]; then
            tls_ready=true
            cert_file="$ACME_CERT_DIR/cert.crt"
            key_file="$ACME_CERT_DIR/private.key"
            green "IP 证书申请成功"
        else
            yellow "IP 证书申请失败，切换至自签证书"
            tls_ready=false
            cert_file="$SB_CONF_DIR/cert.pem"
            key_file="$SB_CONF_DIR/private.key"
        fi
        return
    fi
    
    # 交互模式
    if [[ -f "$ACME_CERT_DIR/cert.crt" && -s "$ACME_CERT_DIR/cert.crt" ]]; then
        yellow "检测到已申请的证书："
        echo "1. 使用自签证书 (默认)"
        echo "2. 使用已申请的 ACME 证书"
        readp "请选择 [1/2]: " cert_choice
        if [[ "$cert_choice" = "2" ]]; then
            tls_ready=true
            cert_file="$ACME_CERT_DIR/cert.crt"
            key_file="$ACME_CERT_DIR/private.key"
            return
        fi
    fi
    
    tls_ready=false
    cert_file="$SB_CONF_DIR/cert.pem"
    key_file="$SB_CONF_DIR/private.key"
}

# 端口与UUID配置
setup_ports_and_id() {
    if [[ "$SILENT" = true ]]; then
        port_vl=25531
        port_vm=25532
        port_hy=25533
        port_tu=25534
    else
        # 随机分配端口
        port_vl=""; choose_port port_vl
        port_hy=""; choose_port port_hy
        port_tu=""; choose_port port_tu
        
        # Vmess 端口特殊处理 (TLS默认8443, 非TLS默认8080)
        if [[ "$tls_ready" = "true" ]]; then
            port_vm=8443
        else
            port_vm=8080
        fi
    fi
    
    uuid=$("$SB_BIN_PATH" generate uuid)
    blue "配置信息 -> VL:$port_vl | VM:$port_vm | HY:$port_hy | TU:$port_tu | UUID:$uuid"
}

# 生成配置文件 sb.json
generate_config() {
    # 根据版本判断是否开启嗅探
    local sb_ver_short=$("$SB_BIN_PATH" version | awk '/version/{print $NF}' | cut -d. -f1,2)
    local sniff_cfg=""
    if [[ "$sb_ver_short" == "1.10" ]]; then
        sniff_cfg='"sniff":true,"sniff_override_destination":true,'
    fi
    
    # 构建复杂的 JSON 配置
    cat > "$SB_JSON_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      ${sniff_cfg}
      "tag": "vless",
      "listen": "::",
      "listen_port": ${port_vl},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "apple.com",
            "server_port": 443
          },
          "private_key": "${private_key}",
          "short_id": [ "${short_id}" ]
        }
      }
    },
    {
      "type": "vmess",
      ${sniff_cfg}
      "tag": "vmess",
      "listen": "::",
      "listen_port": ${port_vm},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${uuid}-vm",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      },
      "tls": {
        "enabled": ${tls_ready},
        "server_name": "www.bing.com",
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    },
    {
      "type": "hysteria2",
      ${sniff_cfg}
      "tag": "hy2",
      "listen": "::",
      "listen_port": ${port_hy},
      "users": [
        {
          "password": "${uuid}"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    },
    {
      "type": "tuic",
      ${sniff_cfg}
      "tag": "tuic",
      "listen": "::",
      "listen_port": ${port_tu},
      "users": [
        {
          "uuid": "${uuid}",
          "password": "${uuid}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "${cert_file}",
        "key_path": "${key_file}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_strategy": "${ipv_strategy}"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      ${sniff_cfg:+"{ \"action\": \"sniff\" }," }
      {
        "protocol": [ "quic", "stun" ],
        "outbound": "block"
      }
    ]
  }
}
EOF
}

# 管理服务
setup_service() {
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${SB_CONF_DIR}
ExecStart=${SB_BIN_PATH} run -c ${SB_JSON_PATH}
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now sing-box >/dev/null 2>&1
}

# 部署快捷入口
setup_shortcut() {
    curl -sL -o /usr/bin/sb https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh
    chmod +x /usr/bin/sb
}

# ========================================================
# 5. 用户操作函数
# ========================================================

# ========================================================
# 6. 主逻辑与菜单循环
# ========================================================

# 安装全流程
do_install() {
    if [[ -f /etc/systemd/system/sing-box.service ]]; then
        red "Sing-box 已安装，请勿重复安装"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return
    fi
    
    detect_system
    install_dependencies
    check_ipv6
    
    # 1. 下载内核
    install_sb_core || { red "内核下载失败，请检查网络"; return 1; }
    
    # 2. 证书配置
    setup_certificates
    
    # 3. 端口与 ID
    setup_ports_and_id
    
    # 4. 生成 REALITY 密钥对
    yellow "正在生成 REALITY 密钥对..."
    local key_pair=$("$SB_BIN_PATH" generate reality-keypair 2>/dev/null)
    private_key=$(echo "$key_pair" | awk '/PrivateKey/{print $2}')
    public_key=$(echo "$key_pair" | awk '/PublicKey/{print $2}')
    
    if [[ -z "$private_key" ]]; then
        red "密钥对生成失败，内核可能无法在该系统运行"
        return 1
    fi
    echo "$public_key" > "$SB_CONF_DIR/public.key"
    short_id=$("$SB_BIN_PATH" generate rand --hex 4)
    
    # 5. 写入配置与启动服务
    generate_config
    if [[ ! -f "$SB_JSON_PATH" ]]; then
        red "配置文件写入失败"
        return 1
    fi
    
    setup_service
    setup_shortcut
    
    # 记录版本
    curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/version | head -1 > "$SB_CONF_DIR/v" 2>/dev/null
    
    green "Sing-box 安装成功并已启动！"
    white "快捷命令：sb"
    
    echo
    read -p "是否立即显示节点分享链接？[y/n]: " show_choice
    if [[ "$show_choice" == "y" || "$show_choice" == "Y" || -z "$show_choice" ]]; then
        show_nodes
    fi
    
    echo
    read -n 1 -s -r -p "安装完成。按任意键返回主菜单..."
}

main_menu() {
    while true; do
        clear
        white "══════════════════════════════════════════════════"
        white "         Sing-box 管理脚本 | 快捷方式: sb"
        white "══════════════════════════════════════════════════"
        echo -e "${green} 1. 安装服务 (New)    2. 卸载服务${plain}"
        echo -e "${green} 3. 重启/停止服务     4. 更新管理脚本${plain}"
        echo -e "${green} 5. 更新内核版本      6. 查看节点链接${plain}"
        echo -e "${green} 7. 查看实时日志      8. BBR 加速优化${plain}"
        echo -e "${green} 9. Acme 证书工具     0. 退出脚本${plain}"
        white "══════════════════════════════════════════════════"
        
        detect_system
        get_ip
        local status_str
        local version_str="未知"
        
        if systemctl is-active sing-box &>/dev/null; then
            status_str="${blue}运行中${plain}"
            version_str=$("$SB_BIN_PATH" version 2>/dev/null | awk '/version/{print $NF}')
        elif [[ -f "$SB_JSON_PATH" ]]; then
            status_str="${yellow}已停止${plain}"
        else
            status_str="${red}未安装${plain}"
        fi
        
        echo -e "系统: ${blue}$op${plain} | 架构: ${blue}$cpu${plain} | BBR: ${blue}$bbr_status${plain}"
        echo -e "IPv4: ${blue}${v4:-无}${plain} | IPv6: ${blue}${v6:-无}${plain}"
        echo -e "状态: $status_str | 内核: ${blue}$version_str${plain}"
        white "══════════════════════════════════════════════════"
        
        readp "请选择 [0-9]: " choice
        case "$choice" in
            1) do_install ;;
            2) do_uninstall; read -n 1 -s -r -p "按任意键返回..." ;;
            3) do_restart_stop; sleep 1 ;;
            4) do_update_script ;;
            5) do_update_core; read -n 1 -s -r -p "按任意键返回..." ;;
            6) show_nodes; echo; read -n 1 -s -r -p "按任意键返回..." ;;
            7) red "按 Ctrl+C 退出日志查看"; journalctl -u sing-box -o cat -f ;;
            8) bash <(curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/bbr.sh) ;;
            9) bash <(curl -sL https://raw.githubusercontent.com/GamblerIX/singbox/main/acme.sh) ;;
            0) exit 0 ;;
            *) exit 0 ;;
        esac
    done
}

# 进入主程序
if [[ "$SILENT" = true ]]; then
    green "启动静默安装模式..."
    do_install
else
    # 首次运行确保检测系统
    detect_system
    main_menu
fi
