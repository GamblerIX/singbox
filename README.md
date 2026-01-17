# Singbox 一键安装脚本

支持 VPS (Root) 平台的 Singbox Vless-Reality 一键部署脚本。

## 核心功能
- **协议支持**：Vless-Reality（无需证书，安全性高）
- **自动化**：一键安装、自动获取最新版内核、BBR优化、节点信息导出
- **简洁高效**：专注于 Reality 协议，配置简单，性能优异

## 安装命令

### 交互式安装 (快捷方式: `sb`)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh)
```

### 静默一键安装
无需交互，自动部署 Vless-Reality（端口 25531）
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) -s
```
或
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) --silent
```

## 端口说明

| 协议 | 端口 |
|------|------|
| Vless-Reality | 25531（固定） |

## 特性说明

- **Reality 协议**：无需证书，通过真实 TLS 握手伪装流量，安全性极高
- **默认端口 443**：使用标准 HTTPS 端口，降低被识别风险
- **自动优化**：支持 BBR 加速，提升传输性能
