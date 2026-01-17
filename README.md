# Singbox 一键安装脚本

支持 VPS (Root) 平台的 Singbox 多协议一键部署脚本。

## 核心功能
- **协议支持**：Vless-Reality（必选）、Trojan（可选）
- **自动化**：一键安装、自动获取最新版内核、BBR优化、节点信息导出
- **灵活配置**：交互式可选协议，静默模式仅部署 Vless-Reality

## 安装命令

### 交互式安装 (快捷方式: `sb`)
支持选择是否启用 Trojan 协议
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh)
```

### 静默一键安装
无需交互，仅部署 Vless-Reality（端口 25531）
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) -s
```
或
```bash
bash <(curl -Ls https://raw.githubusercontent.com/GamblerIX/singbox/main/sb.sh) --silent
```

## 端口说明

| 协议 | 端口 | 说明 |
|------|------|------|
| Vless-Reality | 25531 | 必选，无需证书 |
| Trojan | 25532 | 可选，使用自签证书 |

## 协议特性

**Vless-Reality**
- 无需域名和证书
- 通过真实 TLS 握手伪装流量
- 安全性极高，难以被检测

**Trojan**
- 伪装成标准 HTTPS 流量
- 兼容性好，支持多种客户端
- 使用自签证书（客户端需允许不安全证书）
