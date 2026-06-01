# RackNerd v2ray-agent Manager

Clean Edition v1.1 个性化 VPS 管理脚本。

## 功能

- 检测是否安装 mack-a/v2ray-agent
- 下载并运行官方 v2ray-agent 脚本
- 打开 `vasma` 管理菜单
- 配置 UFW 常用防火墙端口
- 自定义放行端口
- 开启 BBR
- 安全速度优化：BBR + TCP 参数
- 回滚本脚本速度优化
- 安全加固：fail2ban 防 SSH 爆破
- DNS 优化
- 备份 v2ray-agent / Xray / sing-box / nginx 配置
- 查看备份列表
- 修复/重启 xray / sing-box / nginx
- 核心配置语法检查
- Netflix / Grok / AI 服务连通性检测
- 轻量网络测速
- 安全体检
- VLESS-Reality 客户端参数模板
- 推荐优化流程：备份 + 优化 + 安全
- 安装短命令 `rn`
- 自更新本管理脚本
- 查看脚本日志

## 最短运行

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/i.sh)
```

## 保存到 VPS 后运行

```bash
curl -fsSL -o /root/rn.sh https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/i.sh && bash /root/rn.sh
```

## 再次运行

```bash
bash /root/racknerd_v2ray_agent_manager.sh
```

进入脚本后可以选择：

```text
23. 安装短命令 rn
```

安装后以后直接输入：

```bash
rn
```

## 建议使用顺序

首次使用建议：

```text
12. 备份 v2ray-agent/Xray/sing-box/nginx 配置
22. 推荐优化流程：备份 + 优化 + 安全
16. 流媒体 / Grok / AI 连通性检测
18. 安全体检
```

## 说明

本脚本本身不加入广告、推广链接或无关输出。

本脚本不会保证解锁 Netflix、Grok 或其他平台。流媒体和 AI 服务可用性主要取决于 VPS IP 地区、IP 信誉、平台风控、账号地区、客户端 DNS 和分流设置。

本脚本通过官方 GitHub 源下载 v2ray-agent，不魔改官方项目版权、许可证或作者信息。

v1.1 版本吸收的是常见优秀 VPS 脚本的功能思路，例如自更新、日志、备份、回滚、健康检查、敏感信息提醒和轻量测速；没有复制其他作者源码。

## 安全提醒

不要把以下内容上传到公开仓库或发给别人：

- UUID
- PrivateKey
- ShortId
- PublicKey
- 节点链接
- 订阅链接
- 证书和备份压缩包

如果之前截图或分享过节点参数，建议在 `vasma` 里删除/重置用户，重新生成节点并导入客户端。
