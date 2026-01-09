#!/usr/bin/env bash

_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

_info() {
    _green "[Info] "
    printf -- "%s" "$1"
    printf "\n"
}

_error() {
    _red "[Error] "
    printf -- "%s" "$1"
    printf "\n"
    exit 1
}

_exists() {
    local cmd="$1"
    if eval type type > /dev/null 2>&1; then
        eval type "$cmd" > /dev/null 2>&1
    elif command > /dev/null 2>&1; then
        command -v "$cmd" > /dev/null 2>&1
    else
        which "$cmd" > /dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

_os_full() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

_version_ge(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

check_bbr_status() {
    local param=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [[ x"${param}" == x"bbr" ]]; then
        return 0
    else
        return 1
    fi
}

check_kernel_version() {
    local kernel_version=$(uname -r | cut -d- -f1)
    if _version_ge ${kernel_version} 4.9; then
        return 0
    else
        return 1
    fi
}

check_virt() {
    if _exists "virt-what"; then
        virt="$(virt-what)"
    elif _exists "systemd-detect-virt"; then
        virt="$(systemd-detect-virt)"
    fi
    if [ -n "${virt}" -a "${virt}" = "lxc" ]; then
        _error "虚拟化方式为LXC，不支持BBR。"
    fi
    if [ -n "${virt}" -a "${virt}" = "openvz" ] || [ -d "/proc/vz" ]; then
        _error "虚拟化方式为OpenVZ，不支持BBR。"
    fi
}

sysctl_config() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

install_bbr() {
    check_virt
    if check_bbr_status; then
        echo
        _info "TCP BBR 已启用，无需操作..."
        exit 0
    fi
    if check_kernel_version; then
        echo
        _info "内核版本大于4.9，直接设置TCP BBR..."
        sysctl_config
        _info "TCP BBR 设置完成..."
        exit 0
    fi
    _error "内核版本低于4.9，不支持BBR，请升级内核后重试。"
}

[[ $EUID -ne 0 ]] && _error "此脚本必须以root权限运行"
opsy=$( _os_full )
arch=$( uname -m )
lbit=$( getconf LONG_BIT )
kern=$( uname -r )

clear
echo "---------- 系统信息 ----------"
echo " 系统    : $opsy"
echo " 架构    : $arch ($lbit Bit)"
echo " 内核    : $kern"
echo "------------------------------"
echo " TCP BBR 一键启用脚本"
echo "------------------------------"
echo
echo "按任意键开始...或按 Ctrl+C 取消"
char=$(get_char)

install_bbr
