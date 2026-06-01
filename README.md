# RackNerd VPS 管理脚本

自己用的 RackNerd VPS 管理脚本。

这个仓库不是 v2ray-agent 官方项目，也不是 mack-a 原版脚本。它只是一个入口和维护菜单：安装、检测、备份、加固、测速、查看连通性。真正的 v2ray-agent 还是从 mack-a 官方 GitHub 源下载。

## 一行运行

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/i.sh)
```

## 再次打开

```bash
bash /root/racknerd_v2ray_agent_manager.sh
```

进菜单后可以装短命令：

```text
23. 安装 rn 短命令
```

以后直接输入：

```bash
rn
```

## 主要功能

- 检测 v2ray-agent / vasma
- 安装或更新 v2ray-agent
- 打开 vasma
- 放行常用端口或自定义端口
- 开启 BBR
- 调整常用 TCP 参数
- 回滚本脚本写入的网络优化
- 开启 fail2ban 防 SSH 爆破
- 设置 VPS 自身 DNS
- 备份配置
- 查看备份
- 重启 xray / sing-box / nginx
- 检查 xray / sing-box / nginx 配置
- 流媒体、Grok、OpenAI 连通性查看
- 轻量测速
- 安全检查
- 查看 VLESS-Reality 参数参考
- 自更新脚本
- 查看日志

## 建议顺序

第一次跑，建议这样来：

```text
12. 备份配置
22. 建议流程
16. 流媒体/Grok/OpenAI 连通性
18. 安全检查
23. 安装 rn 短命令
```

## 说明

这个脚本本身没有广告。

这个脚本不会保证解锁 Netflix、Grok、OpenAI 或其他平台。能不能用主要看 VPS IP、账号地区、平台风控、客户端 DNS 和分流。

不要把这些东西发到公开仓库或截图给别人：

- UUID
- PrivateKey
- ShortId
- PublicKey
- 节点链接
- 订阅链接
- 证书
- 备份压缩包

如果之前截图露出过节点参数，建议进 `vasma` 重置用户，再重新导入客户端。
