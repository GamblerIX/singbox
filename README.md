# Singbox 一键安装脚本

支持 VPS (Root) 平台的 Singbox 多协议一键部署脚本。

## 核心功能
- **协议支持**：Vless-reality、Vmess-ws、Hysteria-2、Tuic-v5。
- **自动化**：一键安装、自动获取最新版内核、BBR优化、证书管理、节点信息导出。
- **证书支持**：自签证书、域名证书、IP证书（Let's Encrypt shortlived profile）。

## 安装命令

### 交互式安装 (快捷方式: `sb`)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh)
```

### 静默一键安装
无需交互，自动申请 IP 证书，固定端口：VL(25531)、VM(25532)、HY(25533)、TU(25534)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) -s
```
或
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) --silent
```

## 证书申请

### Acme 证书申请工具
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/acme.sh)
```

支持两种证书类型：
1. **域名证书**：需要将域名解析到 VPS 的 IP
2. **IP证书**：无需域名，直接使用 VPS 的公网 IP（使用 Let's Encrypt shortlived profile，有效期约6天，自动续期）

## 端口说明

| 协议 | 交互式安装 | 静默安装 |
|------|----------|---------|
| Vless-Reality | 随机 | 25531 |
| Vmess-WS | 8080/8443 | 25532 |
| Hysteria2 | 随机 | 25533 |
| Tuic5 | 随机 | 25534 |
