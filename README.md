# 我的 VPS 一键管理脚本

这个仓库以后主要维护一个脚本：

```text
my_vps_manager.sh
```

它是给我自己的 RackNerd VPS 定制的，不是 v2ray-agent 官方项目，也不是 mack-a 原版脚本。

底层节点安装仍然调用 mack-a/v2ray-agent 官方脚本；这个仓库只做入口、初始化、检测、备份、排查和客户端提示。

## 一行运行

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/my_vps_manager.sh)
```

## 以后打开

第一次运行后，菜单里选：

```text
9. 更新本脚本
```

之后可以直接输入：

```bash
myvps
```

## 菜单功能

只保留实用功能：

```text
1. 首次准备       装工具、修 DNS/时间、防火墙、BBR
2. 安装/管理节点  打开 v2ray-agent，上游菜单只用来装节点
3. 服务和端口     看 443/8443/2053/15593 和核心服务
4. 备份配置       备份节点、Xray、sing-box、nginx
5. AI 检测        看 GPT/Grok 相关出口状态
6. 影视检测       看常见媒体平台出口状态
7. 客户端建议     v2rayN/v2rayNG 专用设置
8. 查看日志       出问题先看这里
9. 更新本脚本     以后只维护这个脚本
0. 退出
```

## 推荐安装方式

重装 Debian 12 后，先运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/my_vps_manager.sh)
```

然后按顺序：

```text
1. 首次准备
2. 安装/管理节点
```

进入 v2ray-agent 后，建议只安装一个主节点：

```text
协议：VLESS Reality Vision
端口：443 优先
备用端口：8443 / 2053 / 15593
flow：xtls-rprx-vision
fingerprint：chrome
Mux：关闭
```

## v2rayN / v2rayNG 建议

```text
先用全局模式测试
Mux 关闭
IPv6 关闭或优先 IPv4
DNS 尽量走节点，不要依赖运营商 DNS
Reality fingerprint 用 chrome
```

如果 v2rayN 测速显示 -1 ms，不要直接判断 VPS 坏了，先看：

```text
3. 服务和端口
8. 查看日志
```

## 说明

这个脚本不承诺任何 AI 或影视平台 100% 解锁。

平台是否可用主要取决于：

```text
VPS IP 信誉
ASN / 机房类型
账号地区
客户端 DNS
运营商线路
平台风控
```

脚本能做的是提高稳定性、减少常见配置问题、让排查更清楚。

## 安全提醒

不要公开这些内容：

```text
UUID
PrivateKey
ShortId
PublicKey
节点链接
订阅链接
证书
备份压缩包
```

如果截图或聊天里泄露过节点参数，建议进 v2ray-agent 重置用户后重新导入客户端。
