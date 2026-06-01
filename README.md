# RackNerd v2ray-agent Manager

Clean Edition 个性化 VPS 管理脚本。

## 功能

- 检测是否安装 mack-a/v2ray-agent
- 下载并运行官方 v2ray-agent 脚本
- 打开 `vasma` 管理菜单
- 配置 UFW 防火墙
- 开启 BBR
- 安全速度优化：BBR + TCP 参数
- 安全加固：fail2ban 防 SSH 爆破
- DNS 优化
- 备份 v2ray-agent / Xray / sing-box / nginx 配置
- 修复/重启 xray / sing-box / nginx
- Netflix / Grok / AI 服务连通性检测
- VLESS-Reality 客户端参数模板

## 最短运行

```bash
bash <(curl -Ls git.io)
```

上面这个太短但不可用，只是示例。请使用下面这个稳定命令：

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

## 说明

本脚本本身不加入广告、推广链接或无关输出。

本脚本不会保证解锁 Netflix、Grok 或其他平台。流媒体和 AI 服务可用性主要取决于 VPS IP 地区、IP 信誉、平台风控、账号地区、客户端 DNS 和分流设置。

本脚本通过官方 GitHub 源下载 v2ray-agent，不魔改官方项目版权、许可证或作者信息。

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
