#!/bin/bash
# 相关文件: README.md, acme.sh, bbr.sh, sb.sh
# 
# Sing-box 一键安装脚本
# 功能：支持 Vless-Reality, Trojan
# 
export LANG=en_US.UTF-8

# ========================================================
# 1. 变量定义与配置管理
# ========================================================

# 脚本版本
SCRIPT_VERSION="1.1.2"

# 静默模式标志
SILENT=false

# 是否启用 Trojan
ENABLE_TROJAN=false

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
# 3. 网络功能
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

# Vless-Reality 不需要证书配置
# Trojan 证书配置
setup_certificates() {
    if [[ "$ENABLE_TROJAN" != true ]]; then
        return
    fi
    
    yellow "正在生成自签证书（用于 Trojan）..."
    openssl ecparam -genkey -name prime256v1 -out "$SB_CONF_DIR/private.key"
    openssl req -new -x509 -days 36500 -key "$SB_CONF_DIR/private.key" -out "$SB_CONF_DIR/cert.pem" -subj "/CN=www.bing.com"
    
    cert_file="$SB_CONF_DIR/cert.pem"
    key_file="$SB_CONF_DIR/private.key"
    green "自签证书生成成功"
}

# 端口与UUID配置
setup_ports_and_id() {
    # Vless-Reality 固定使用 25531 端口
    port_vl=25531
    
    # Trojan 固定使用 25532 端口
    port_tj=25532
    
    if [[ "$SILENT" != true ]]; then
        echo
        yellow "--- 协议配置 ---"
        readp "是否启用 Trojan 协议？[y/n] (默认: n): " enable_tj
        if [[ "$enable_tj" == "y" || "$enable_tj" == "Y" ]]; then
            ENABLE_TROJAN=true
            green "已启用: Vless-Reality (端口 $port_vl) + Trojan (端口 $port_tj)"
        else
            ENABLE_TROJAN=false
            green "已启用: Vless-Reality (端口 $port_vl)"
        fi
        echo
    else
        green "静默模式: 仅启用 Vless-Reality (端口 $port_vl)"
    fi
    
    uuid=$("$SB_BIN_PATH" generate uuid)
    trojan_password=$("$SB_BIN_PATH" generate rand --hex 16)
    
    if [[ "$ENABLE_TROJAN" = true ]]; then
        blue "Vless UUID: $uuid"
        blue "Trojan 密码: $trojan_password"
    else
        blue "生成的 UUID: $uuid"
    fi
}

# 生成配置文件 sb.json
generate_config() {
    # 根据版本判断是否开启嗅探
    local sb_ver_short=$("$SB_BIN_PATH" version | awk '/version/{print $NF}' | cut -d. -f1,2)
    local sniff_cfg=""
    if [[ "$sb_ver_short" == "1.10" ]]; then
        sniff_cfg='"sniff":true,"sniff_override_destination":true,'
    fi
    
    # 构建 inbounds 数组
    local inbounds='[
    {
      "type": "vless",
      '"${sniff_cfg}"'
      "tag": "vless",
      "listen": "::",
      "listen_port": '"${port_vl}"',
      "users": [
        {
          "uuid": "'"${uuid}"'",
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
          "private_key": "'"${private_key}"'",
          "short_id": [ "'"${short_id}"'" ]
        }
      }
    }'
    
    # 如果启用 Trojan，添加 Trojan inbound
    if [[ "$ENABLE_TROJAN" = true ]]; then
        inbounds+=',
    {
      "type": "trojan",
      '"${sniff_cfg}"'
      "tag": "trojan",
      "listen": "::",
      "listen_port": '"${port_tj}"',
      "users": [
        {
          "name": "user",
          "password": "'"${trojan_password}"'"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "certificate_path": "'"${cert_file}"'",
        "key_path": "'"${key_file}"'"
      }
    }'
    fi
    
    inbounds+='
  ]'
    
    # 写入完整配置
    cat > "$SB_JSON_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": ${inbounds},
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
    local tmp_file="/tmp/sb_tmp"
    yellow "正在下载最新脚本..."
    
    # 优先使用 GitHub API 获取最新内容（绕过 CDN 缓存）
    if command -v base64 &>/dev/null && command -v jq &>/dev/null; then
        local api_response=$(curl -sL "https://api.github.com/repos/GamblerIX/singbox/contents/sb.sh?ref=main")
        if echo "$api_response" | jq -e '.content' &>/dev/null; then
            echo "$api_response" | jq -r '.content' | base64 -d > "$tmp_file"
            chmod +x "$tmp_file"
            rm -f /usr/bin/sb
            mv -f "$tmp_file" /usr/bin/sb
            green "快捷方式 /usr/bin/sb 部署成功（API 模式）"
            return 0
        fi
    fi
    
    # 降级方案：使用 raw 链接
    if curl -sL -o "$tmp_file" "https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh?t=$(date +%s)"; then
        chmod +x "$tmp_file"
        rm -f /usr/bin/sb
        mv -f "$tmp_file" /usr/bin/sb
        green "快捷方式 /usr/bin/sb 部署成功"
    else
        red "脚本下载失败，请检查网络"
        return 1
    fi
}

# ========================================================
# 5. 用户操作函数
# ========================================================

# 卸载
do_uninstall() {
    systemctl disable --now sing-box >/dev/null 2>&1
    rm -rf /etc/systemd/system/sing-box.service "$SB_CONF_DIR" sbyg_update /usr/bin/sb
    green "Sing-box 已彻底卸载"
}

# 重启或停止
do_restart_stop() {
    if [[ ! -f "$SB_JSON_PATH" ]]; then
        red "未检测到安装"
        return
    fi
    yellow "1. 重启服务"
    yellow "2. 停止服务"
    readp "请选择: " choice
    if [[ "$choice" = "1" ]]; then
        systemctl restart sing-box
        green "已重启"
    else
        systemctl stop sing-box
        green "已停止"
    fi
}

# 更新脚本
do_update_script() {
    yellow "正在更新管理脚本..."
    setup_shortcut
    green "脚本更新成功"
    echo
    read -p "按 Enter 键以重新启动脚本并应用更新..."
    # 使用完整路径防止快捷键尚未生效
    exec /usr/bin/sb
}

# 更新内核
do_update_core() {
    if [[ ! -f "$SB_JSON_PATH" ]]; then
        red "未安装，无法更新内核"
        return
    fi
    local latest_ver=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    local current_ver=$("$SB_BIN_PATH" version 2>/dev/null | awk '/version/{print $NF}')
    
    green "当前内核版本: $current_ver"
    green "最新内核版本: $latest_ver"
    
    if [[ "$current_ver" == "$latest_ver" ]]; then
        yellow "当前已是最新版本"
    fi
    
    readp "是否更新并重启？[y/n]: " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        install_sb_core
        systemctl restart sing-box
        green "内核更新完成"
    fi
}

# 查看节点信息
show_nodes() {
    if [[ ! -f "$SB_JSON_PATH" ]]; then
        red "未安装，无节点信息"
        return
    fi
    
    # 刷新并获取 IP
    get_ip
    local current_ip=${v4:-$v6}
    local formatted_ip=$current_ip
    [[ "$current_ip" =~ : ]] && formatted_ip="[$current_ip]"
    
    # 解析配置
    local cfg=$(sed 's://.*::g' "$SB_JSON_PATH")
    local uuid=$(echo "$cfg" | jq -r '.inbounds[0].users[0].uuid')
    local p_vl=$(echo "$cfg" | jq -r '.inbounds[0].listen_port')
    local pub_key=$(cat "$SB_CONF_DIR/public.key" 2>/dev/null)
    local s_id=$(echo "$cfg" | jq -r '.inbounds[0].tls.reality.short_id[0]')
    
    # 生成 Vless-Reality 链接
    local link_vl="vless://$uuid@$formatted_ip:$p_vl?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=$pub_key&sid=$s_id&type=tcp#vl-$hostname"
    
    # 打印 Vless 节点
    white "═══════════════════════════════════════"
    red "🚀 Vless-Reality"
    echo -e "${yellow}${link_vl}${plain}"
    qrencode -o- -tANSIUTF8 "${link_vl}" 2>/dev/null
    white "═══════════════════════════════════════"
    
    # 检查是否有 Trojan
    local tj_count=$(echo "$cfg" | jq '[.inbounds[] | select(.type=="trojan")] | length')
    if [[ "$tj_count" -gt 0 ]]; then
        local p_tj=$(echo "$cfg" | jq -r '.inbounds[] | select(.type=="trojan") | .listen_port')
        local tj_pwd=$(echo "$cfg" | jq -r '.inbounds[] | select(.type=="trojan") | .users[0].password')
        
        # 生成 Trojan 链接
        local link_tj="trojan://$tj_pwd@$formatted_ip:$p_tj?security=tls&sni=www.bing.com&alpn=http/1.1&type=tcp&allowInsecure=1#tj-$hostname"
        
        white "═══════════════════════════════════════"
        red "🚀 Trojan"
        echo -e "${yellow}${link_tj}${plain}"
        qrencode -o- -tANSIUTF8 "${link_tj}" 2>/dev/null
        white "═══════════════════════════════════════"
    fi
}

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
    
    white "══════════════════════════════════════════════════"
    green "        开始 Singbox 交互式安装流程"
    white "══════════════════════════════════════════════════"
    
    detect_system
    install_dependencies
    check_ipv6
    
    # 1. 下载内核
    install_sb_core || { red "内核下载失败，请检查网络"; return 1; }
    
    # 2. 端口与 ID 配置
    setup_ports_and_id
    
    # 3. 证书配置（如果启用 Trojan）
    setup_certificates
    
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
        white "      Singbox 管理脚本 v${SCRIPT_VERSION} | 快捷方式: sb"
        white "══════════════════════════════════════════════════"
        echo -e "${green} 1. 安装Singbox服务         2. 卸载Singbox服务${plain}"
        echo -e "${green} 3. 重启/停止Singbox服务    4. 更新Singbox管理脚本${plain}"
        echo -e "${green} 5. 更新Singbox内核版本     6. 查看Singbox节点链接${plain}"
        echo -e "${green} 7. 查看实时日志            8. BBR 加速优化${plain}"
        echo -e "${green} 0. 退出脚本${plain}"
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
    # 从菜单进入时，确保关闭静默模式
    SILENT=false
    main_menu
fi
