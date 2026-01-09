#!/bin/bash 
export LANG=en_US.UTF-8
red='\033[0;31m'
bblue='\033[0;34m'
plain='\033[0m'
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统" && exit 
fi
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi

v4v6(){
v4=$(curl -s4m5 icanhazip.com -k)
v6=$(curl -s6m5 icanhazip.com -k)
}

if [ ! -f acyg_update ]; then
green "首次安装Acme脚本必要的依赖……"
if [[ x"${release}" == x"alpine" ]]; then
apk add wget curl tar jq tzdata openssl expect git socat iproute2 virt-what
else
if [ -x "$(command -v apt-get)" ]; then
apt update -y
apt install socat -y
apt install cron -y
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install socat -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install socat -y
fi
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if ! command -v "cronie" &> /dev/null; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie
fi
fi
if ! command -v "dig" &> /dev/null; then
if [ -x "$(command -v yum)" ]; then
yum install -y bind-utils
elif [ -x "$(command -v dnf)" ]; then
dnf install -y bind-utils
fi
fi
fi

packages=("curl" "openssl" "lsof" "socat" "dig" "tar" "wget")
inspackages=("curl" "openssl" "lsof" "socat" "dnsutils" "tar" "wget")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage"
elif [ -x "$(command -v yum)" ]; then
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
dnf install -y "$inspackage"
fi
fi
done
fi
touch acyg_update
fi

if [[ -z $(curl -s4m5 icanhazip.com -k) ]]; then
yellow "检测到VPS为纯IPV6，添加dns64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
sleep 2
fi

acme2(){
if [[ -n $(lsof -i :80|grep -v "PID") ]]; then
yellow "检测到80端口被占用，现执行80端口全释放"
sleep 2
lsof -i :80|grep -v "PID"|awk '{print "kill -9",$2}'|sh >/dev/null 2>&1
green "80端口全释放完毕！"
sleep 2
fi
}

acme3(){
readp "请输入注册所需的邮箱（回车跳过则自动生成虚拟gmail邮箱）：" Aemail
if [ -z $Aemail ]; then
auto=`date +%s%N |md5sum | cut -c 1-6`
Aemail=$auto@gmail.com
fi
yellow "当前注册的邮箱名称：$Aemail"
green "开始安装acme.sh申请证书脚本"
bash ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
rm -rf ~/.acme.sh acme.sh
uncronac
wget -N https://github.com/Neilpang/acme.sh/archive/master.tar.gz >/dev/null 2>&1
tar -zxvf master.tar.gz >/dev/null 2>&1
cd acme.sh-master >/dev/null 2>&1
./acme.sh --install >/dev/null 2>&1
cd
curl https://get.acme.sh | sh -s email=$Aemail
if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
green "安装acme.sh证书申请程序成功"
bash ~/.acme.sh/acme.sh --upgrade --use-wget --auto-upgrade
else
red "安装acme.sh证书申请程序失败" && exit
fi
}

checktls(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key ]] && [[ -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
cronac
green "证书申请成功或已存在！证书（cert.crt）和密钥（private.key）已保存到 /root/ygkkkca文件夹内" 
yellow "公钥文件crt路径如下，可直接复制"
green "/root/ygkkkca/cert.crt"
yellow "密钥文件key路径如下，可直接复制"
green "/root/ygkkkca/private.key"
ym=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
echo $ym > /root/ygkkkca/ca.log
if [[ -f '/etc/s-box/sb.json' ]]; then
blue "检测到Sing-box内核代理，证书将自动应用到Sing-box"
fi
else
bash ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
rm -rf /root/ygkkkca
rm -rf ~/.acme.sh acme.sh
uncronac
red "遗憾，证书申请失败，建议如下："
yellow "1、对于域名证书：请确保CF中的CDN黄云已关闭，解析的IP必须是VPS的本地IP"
echo
yellow "2、对于IP证书：请确保80端口可访问，且IP未被频繁申请"
echo
yellow "3、因为同个IP连续多次申请证书有时间限制，等一段时间再重试" && exit
fi
}

installCA(){
bash ~/.acme.sh/acme.sh --install-cert -d ${ym} --key-file /root/ygkkkca/private.key --fullchain-file /root/ygkkkca/cert.crt --ecc
}

checkip(){
v4v6
if [[ -z $v4 ]]; then
vpsip=$v6
elif [[ -n $v4 && -n $v6 ]]; then
vpsip="$v6 或者 $v4"
else
vpsip=$v4
fi
domainIP=$(dig @8.8.8.8 +time=2 +short "$ym" 2>/dev/null | grep -m1 '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+')
if echo $domainIP | grep -q "network unreachable\|timed out" || [[ -z $domainIP ]]; then
domainIP=$(dig @2001:4860:4860::8888 +time=2 aaaa +short "$ym" 2>/dev/null | grep -m1 ':')
fi
if echo $domainIP | grep -q "network unreachable\|timed out" || [[ -z $domainIP ]] ; then
red "未解析出IP，请检查域名是否输入有误" 
yellow "是否尝试手动输入强行匹配？"
yellow "1：是！输入域名解析的IP"
yellow "2：否！退出脚本"
readp "请选择：" menu
if [ "$menu" = "1" ] ; then
green "VPS本地的IP：$vpsip"
readp "请输入域名解析的IP，与VPS本地IP($vpsip)保持一致：" domainIP
else
exit
fi
elif [[ -n $(echo $domainIP | grep ":") ]]; then
green "当前域名解析到的IPV6地址：$domainIP"
else
green "当前域名解析到的IPV4地址：$domainIP"
fi
if [[ ! $domainIP =~ $v4 ]] && [[ ! $domainIP =~ $v6 ]]; then
yellow "当前VPS本地的IP：$vpsip"
red "当前域名解析的IP与当前VPS本地的IP不匹配！！！"
green "建议如下："
if [[ "$v6" == "2a09"* || "$v4" == "104.28"* ]]; then
yellow "WARP未能自动关闭，请手动关闭！"
else
yellow "1、请确保CDN小黄云关闭状态(仅限DNS)，其他域名解析网站设置同理"
yellow "2、请检查域名解析网站设置的IP是否正确"
fi
exit 
else
green "IP匹配正确，申请证书开始…………"
fi
}

checkacmeca(){
if [[ "${ym}" == *ip6.arpa* ]]; then
red "目前不支持ip6.arpa域名申请证书" && exit
fi
nowca=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
if [[ $nowca == $ym ]]; then
red "经检测，输入的域名已有证书申请记录，不用重复申请"
red "证书申请记录如下："
bash ~/.acme.sh/acme.sh --list
yellow "如果一定要重新申请，请先执行删除证书选项" && exit
fi
}

ACMEstandaloneDNS(){
v4v6
readp "请输入解析完成的域名:" ym
green "已输入的域名:$ym" && sleep 1
checkacmeca
checkip
if [[ $domainIP = $v4 ]]; then
bash ~/.acme.sh/acme.sh --issue -d ${ym} --standalone -k ec-256 --server letsencrypt --insecure
fi
if [[ $domainIP = $v6 ]]; then
bash ~/.acme.sh/acme.sh --issue -d ${ym} --standalone -k ec-256 --server letsencrypt --listen-v6 --insecure
fi
installCA
checktls
}

ACMEstandaloneDNScheck(){
wgcfv6=$(curl -s6m6 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m6 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ACMEstandaloneDNS
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ACMEstandaloneDNS
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

# IP证书申请函数 - 使用 Let's Encrypt shortlived profile
ACMEstandaloneIP(){
v4v6
if [[ -z $v4 && -z $v6 ]]; then
    red "无法获取VPS的IP地址" && exit
fi
# 优先使用IPv4
if [[ -n $v4 ]]; then
    ipaddr=$v4
    green "使用IPv4地址申请证书: $ipaddr"
    ipflag=""
else
    ipaddr=$v6
    green "使用IPv6地址申请证书: $ipaddr"
    ipflag="--listen-v6"
fi
# 检查是否已有相同IP的证书
checkacmecaIP
yellow "正在申请IP证书，使用 shortlived profile（有效期约6天，自动续期）..."
# 使用 http-01 验证和 shortlived profile 申请IP证书
bash ~/.acme.sh/acme.sh --issue --standalone -d ${ipaddr} -k ec-256 --server letsencrypt $ipflag --insecure --preferred-chain "ISRG Root X1" --profile shortlived
installCAIP
checktlsIP
}

checkacmecaIP(){
nowca=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
if [[ $nowca == $ipaddr ]]; then
red "经检测，该IP已有证书申请记录，不用重复申请"
red "证书申请记录如下："
bash ~/.acme.sh/acme.sh --list
yellow "如果一定要重新申请，请先执行删除证书选项" && exit
fi
}

installCAIP(){
bash ~/.acme.sh/acme.sh --install-cert -d ${ipaddr} --key-file /root/ygkkkca/private.key --fullchain-file /root/ygkkkca/cert.crt --ecc
}

checktlsIP(){
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key ]] && [[ -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
cronac
green "IP证书申请成功！证书（cert.crt）和密钥（private.key）已保存到 /root/ygkkkca文件夹内" 
yellow "注意：IP证书有效期约6天，acme.sh会自动续期"
yellow "公钥文件crt路径："
green "/root/ygkkkca/cert.crt"
yellow "密钥文件key路径："
green "/root/ygkkkca/private.key"
echo $ipaddr > /root/ygkkkca/ca.log
if [[ -f '/etc/s-box/sb.json' ]]; then
blue "检测到Sing-box内核代理，证书将自动应用到Sing-box"
fi
else
bash ~/.acme.sh/acme.sh --uninstall >/dev/null 2>&1
rm -rf /root/ygkkkca
rm -rf ~/.acme.sh acme.sh
uncronac
red "IP证书申请失败，可能原因："
yellow "1、80端口被占用或无法访问"
yellow "2、该IP近期申请次数过多，请等待一段时间"
yellow "3、Let's Encrypt服务器暂时不可用" && exit
fi
}

acmeIP(){
mkdir -p /root/ygkkkca
acme2 && acme3 && ACMEstandaloneIP
}

acme(){
mkdir -p /root/ygkkkca
acme2 && acme3 && ACMEstandaloneDNScheck
}

Certificate(){
[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh证书申请，无法执行" && exit 
green "Main_Domainc下显示的域名就是已申请成功的域名证书，Renew下显示对应域名证书的自动续期时间点"
bash ~/.acme.sh/acme.sh --list
}

acmeshow(){
if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
caacme1=`bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'`
if [[ -n $caacme1 && ! $caacme1 == "Main_Domain" ]] && [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
caacme=$caacme1
else
caacme='无证书申请记录'
fi
else
caacme='未安装acme'
fi
}

cronac(){
uncronac
crontab -l > /tmp/crontab.tmp
echo "0 0 * * * root bash ~/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}

uncronac(){
crontab -l > /tmp/crontab.tmp
sed -i '/--cron/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp
}

acmerenew(){
[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh证书申请，无法执行" && exit 
green "以下显示的域名就是已申请成功的域名证书"
bash ~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}'
echo
green "开始续期证书…………" && sleep 3
bash ~/.acme.sh/acme.sh --cron -f
checktls
}

uninstall(){
[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh证书申请，无法执行" && exit 
curl https://get.acme.sh | sh
bash ~/.acme.sh/acme.sh --uninstall
rm -rf /root/ygkkkca
rm -rf ~/.acme.sh acme.sh
sed -i '/acme.sh.env/d' ~/.bashrc 
source ~/.bashrc
uncronac
[[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && green "acme.sh卸载完毕" || red "acme.sh卸载失败"
}

clear
yellow "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
green "Acme脚本 - 证书申请工具"
yellow "提示："
yellow "一、脚本不支持多IP的VPS，SSH登录的IP与VPS共网IP必须一致"
yellow "二、80端口模式需确保80端口可访问，支持自动续期"
yellow "三、IP证书使用 Let's Encrypt shortlived profile，有效期约6天，自动续期"
yellow "公钥文件crt保存路径：/root/ygkkkca/cert.crt"
yellow "密钥文件key保存路径：/root/ygkkkca/private.key"
echo
red "========================================================================="
acmeshow
blue "当前已申请成功的证书（域名/IP）："
yellow "$caacme"
echo
red "========================================================================="
green " 1. 申请域名证书（需要域名解析到VPS）"
green " 2. 申请IP证书（无需域名，直接使用VPS的IP）"
green " 3. 查询已申请成功的证书及自动续期时间点 "
green " 4. 手动一键证书续期 "
green " 5. 删除证书并卸载ACME脚本 "
green " 0. 退出 "
echo
readp "请输入数字:" NumberInput
case "$NumberInput" in     
1 ) acme;;
2 ) acmeIP;;
3 ) Certificate;;
4 ) acmerenew;;
5 ) uninstall;;
* ) exit      
esac
