# MyVPS（自有管理器）— v2.2.1-rc2

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
| `backup-init` | 初始化第二 Google Drive 远端和加密密钥 | 是，需要确认 |
| `backup-vps` | AES-256 加密 VPS 文件级归档并上传 | 是 |
| `backup-blog` | 单独加密备份 `/root/my-blog` 及其相关配置 | 是 |
| `backup-timers` | 安装每天双任务 systemd timer | 是，需要确认 |

### 为什么没有直接提供 XHTTP 一键切换

现有 Cloudflare-WS 尚可使用；XHTTP 能否走 CDN 取决于客户端、Cloudflare、nginx、回源链路和 Xray 版本的匹配。**不会在未经测试时替换正在工作的 WS/443 配置**。后续应新增独立节点、对比故障率/吞吐/延迟，通过再迁移。

## VPS 实测适配：独立 Google Drive AES-256 备份（v2.2.1-rc2）

2026-10-08 已核实：Debian 12 / 1 vCPU / 960MiB；REALITY、nginx、SOCKS 链式出口正常。博客目录约 36MB，使用 SQLite `blog.db`。两个 Google Drive 远端中，第 2 个可读取云端 `VPS-Backups`；旧备份最后更新于 2026-06-09。

因此备份采用**独立辅助脚本** `myvps_backup.sh`，安装于 `/opt/myvps/backup/myvps_backup.sh`，**不覆盖**线上旧管理器、代理、nginx 或任何旧备份。

- `init`：选择已检查可访问的第二个 rclone 远端，并生成 `/etc/myvps/backup.pass` 加密口令。**必须将口令单独保存到离线安全位置，否则 VPS 丢失后无法恢复云端归档。**
- `probe`：上传加密测试文件、核对远端校验和、删除测试文件（仅操作新建文件）。
- `run config`：归档系统 `/etc` 和已知 VPS 管理脚本、rclone 与 ACME 配置；**不包含备份密钥**。
- `run blog`：在隔离临时目录复制 `/root/my-blog`（排除 `node_modules`、`.git`），对 SQLite 库使用 Python `sqlite3.backup()` 生成一致性快照。
- `restore-test config` / `restore-test blog`：从云端下载最新文件并解密、校验 tar 内容，不覆盖线上文件。
- `timers`：北京时间每日 02:00 备份系统配置、02:30 备份博客，通过 systemd timer 自动执行。

备份加密方式 GPG AES256，目标为**已经存在的** `VPS-Backups/`；通过 `myvps-config-` 与 `myvps-blog-` 文件名前缀区分两类备份，以减少 Google Drive API 的目录创建请求。上传采用 rclone，随后进行云端文件校验和比对。所有操作默认不触及旧目录对象。

运行方式：
```bash
sudo bash /opt/myvps/backup/myvps_backup.sh init
sudo bash /opt/myvps/backup/myvps_backup.sh probe
sudo bash /opt/myvps/backup/myvps_backup.sh run config
sudo bash /opt/myvps/backup/myvps_backup.sh run blog
sudo bash /opt/myvps/backup/myvps_backup.sh restore-test config
sudo bash /opt/myvps/backup/myvps_backup.sh restore-test blog
sudo bash /opt/myvps/backup/myvps_backup.sh timers
systemctl list-timers --all 'myvps-backup-*'
```

**注意**：当前只备份系统配置和博客内容，并非完整硬盘镜像；不包含外部数据库。首次上线必须验证上传和恢复。暂不自动清理旧备份对象；需要单独配置容量监测和保留策略。

## 回滚边界

- `self-update` 更新前保留 `/root/my_vps_manager.sh.previous`，并且不会触碰正在运行的服务。
- `xray-install` 更新前保留 `/opt/myvps/xray/xray.previous`，**不会自动重启**已有/新建服务。
- REALITY 初始化绝不覆盖已有的 `/etc/myvps/xray/config.json`，不创建对外监听和防火墙规则。
- 对服务器部署之前务必保留**提供商快照**；脚本提供的是局部回滚措施，不等于生产环境一键全量回滚。

## 安全与隐私

绝对不要提交 UUID、REALITY PrivateKey、Short ID、订阅地址、证书、rclone 配置、备份口令；对外发布诊断日志前请人工检查。新实例的凭据仅保存在 root 控制的 VPS 配置内。

## 开发验收

仓库内 `tests/smoke.sh` 和 GitHub Actions 执行 Bash 语法、帮助菜单及只读状态检查。候选分支在 VPS 实测、备份恢复验证及 nginx/Reality 连通性验证前不得合并为正式发布。
