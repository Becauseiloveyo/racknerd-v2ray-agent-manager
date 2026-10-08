# MyVPS（自有管理器）— v2.2.0-rc1

这是 RackNerd / Debian VPS 的**非破坏性维护脚本**。目标是逐步迁移到自有 Xray-core 管理，不再调用 `mack-a/v2ray-agent` 的安装菜单。

> **当前为独立分支上的候选版本（RC）**，尚未部署到你的 VPS，**也未进入 main**。实际运行版本及线上 nginx/REALITY 配置仍需在 VPS 上单独核验。

## 核心规则

- **不重装系统、不自动清理历史组件**。保留 blog / nginx / PM2 / AdGuardHome / 现有 Cloudflare WebSocket / REALITY 配置。
- **不自动修改 443、nginx SNI、UFW、防火墙、DNS、SSH、证书或已有 Xray systemd 服务**。
- 自有 Xray 的独立二进制路径：`/opt/myvps/xray/xray`。
- 新建测试实例：`127.0.0.1:15594`，服务名 `myvps-xray.service`。必须手动启用；**不会自动并入 nginx SNI 443**。
- 任何公开新节点、Cloudflare XHTTP 或 443 切换必须另行测试和评审。
- 管理脚本只有明确执行相应子命令并确认才会修改系统；默认 `status` 只读。

## 候选分支安全检查（不要直接在生产环境一键运行远程脚本）

从本分支下载到本地审查；**不要直接在现有 VPS 上执行**，先在测试机验证。

```bash
curl -fL -o my_vps_manager.sh \
  https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/maintenance/v2.2.0-owned-safe/my_vps_manager.sh
bash -n my_vps_manager.sh
bash my_vps_manager.sh help
bash my_vps_manager.sh status
bash my_vps_manager.sh doctor
```

正式部署前，先制作完整快照、保存 nginx stream 配置和 Xray 密钥。仅在明确准备好之后，再执行 `self-install`、`xray-install` 或 `reality-init`。

## 命令清单

| 命令 | 功能 | 是否修改 |
|---|---|---|
| `status` | 系统、端口和服务状态 | 否 |
| `doctor` | nginx -t 与自有 Xray 配置验证 | 否 |
| `deps-install` | apt 安装依赖 | 是，需要确认 |
| `self-install` | 安装管理器及 `myvps` 命令 | 是，需要确认 |
| `self-update` | 从 main 获取并验证管理器（不得降级） | 是，需要确认 |
| `xray-install` | 从 XTLS 官方 release 下载并比对 SHA-256，安装隔离的二进制 | 是，需要确认 |
| `reality-init` | 生成 localhost 15594 的独立 REALITY 配置及停止状态的 systemd 单元 | 是，需要确认 |
| `xray-start` | 仅启动 `myvps-xray.service` | 是，需要确认 |
| `backup-init` | 初始化备份加密口令 | 是，需要确认 |
| `backup-vps` | AES-256 加密 VPS 文件级归档并上传 | 是 |
| `backup-blog` | 单独加密备份 `/root/my-blog` 及其相关配置 | 是 |
| `backup-timers` | 安装每周独立备份 timer | 是，需要确认 |

### 为什么没有直接提供 XHTTP 一键切换

现有 Cloudflare-WS 尚可使用；XHTTP 能否走 CDN 取决于客户端、Cloudflare、nginx、回源链路和 Xray 版本的匹配。**不会在未经测试时替换正在工作的 WS/443 配置**。后续应新增独立节点、对比故障率/吞吐/延迟，通过再迁移。

## 加密备份：Google Drive（VPS 与博客分开）

支持已配置的 rclone 远端 `ggdrive:`，若不存在则使用 `gdrive:`；可通过 `MYVPS_BACKUP_REMOTE` 指定其他现有远端。备份**先在本地经 GnuPG AES-256 加密，再上传**，即使目标 remote 是普通 Google Drive 也不会上传明文归档。

- VPS 文件：`VPS-Backups/racknerd/full/`
- 博客文件：`VPS-Backups/racknerd/blog/`
- VPS 归档包含 `/etc`、`/root`、`/opt`、`/var/www`、`/usr/local/etc`（仅存在路径；排除 cache/node_modules/.git）。
- 博客归档包含 `/root/my-blog`、`/root/.pm2`、`/etc/nginx`（仅存在路径）。
- 备份密钥在 `/etc/myvps/backup.pass`，权限 600。**务必另存离线恢复副本**，不要提交 GitHub、聊天或明文云盘。
- 定时任务需要显式执行 `backup-timers`，每周日以 VPS 本地时区 02:00（VPS）和 03:00（blog）运行。

> 文件级备份不等于整机磁盘镜像，不保证数据库的一致性；实际 MySQL/PostgreSQL 数据库应有独立的事务一致备份。执行备份后必须实测解密与恢复。云备份运行依赖 root 环境可以使用的 rclone 配置及授权。

离线恢复思路（**仅在隔离测试机执行**）：
```bash
gpg --batch --pinentry-mode loopback --passphrase-file /path/to/offline/backup.pass \
  --decrypt -o restored.tar.gz encrypted-backup.tar.gz.gpg
tar -tzf restored.tar.gz | head
```

## 回滚边界

- `self-update` 更新前保留 `/root/my_vps_manager.sh.previous`，并且不会触碰正在运行的服务。
- `xray-install` 更新前保留 `/opt/myvps/xray/xray.previous`，**不会自动重启**已有/新建服务。
- REALITY 初始化绝不覆盖已有的 `/etc/myvps/xray/config.json`，不创建对外监听和防火墙规则。
- 对服务器部署之前务必保留**提供商快照**；脚本提供的是局部回滚措施，不等于生产环境一键全量回滚。

## 安全与隐私

绝对不要提交 UUID、REALITY PrivateKey、Short ID、订阅地址、证书、rclone 配置、备份口令；对外发布诊断日志前请人工检查。新实例的凭据仅保存在 root 控制的 VPS 配置内。

## 开发验收

仓库内 `tests/smoke.sh` 和 GitHub Actions 执行 Bash 语法、帮助菜单及只读状态检查。候选分支在 VPS 实测、备份恢复验证及 nginx/Reality 连通性验证前不得合并为正式发布。
