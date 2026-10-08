# MyVPS（自有管理器）— v2.3.1-rc2

这是 RackNerd / Debian VPS 的**非破坏性维护脚本**。目标是对**已稳定运行的 RackNerd VPS**进行兼容维护。当前不迁移生产 REALITY、住宅 SOCKS 链式出站或 Cloudflare WS；保留线上三个旧管理器并提供统一只读巡检和备份入口。

> **当前为维护分支候选版本（RC）**，尚未合并 `main`。2026-10-08 已将新版并行部署到 VPS 的 `/opt/myvps/bin`，可使用 `/usr/local/bin/myvps-next`。原 `/root/my_vps_manager.sh` 仍为 v1.2.0，原 `myvps` 入口不变。备份辅助工具另行部署在 `/opt/myvps/backup`。

## 核心规则

- **不重装系统、不自动清理历史组件**。保留 blog / nginx / PM2 / AdGuardHome / 现有 Cloudflare WebSocket / REALITY 配置。
- **不自动修改 443、nginx SNI、UFW、防火墙、DNS、SSH、证书或已有 Xray systemd 服务**。
- 自有 Xray 的独立二进制路径：`/opt/myvps/xray/xray`。
- 新建测试实例：`127.0.0.1:15594`，服务名 `myvps-xray.service`。必须手动启用；**不会自动并入 nginx SNI 443**。
- 任何公开新节点、Cloudflare XHTTP 或 443 切换必须另行测试和评审。
- 管理脚本只有明确执行相应子命令并确认才会修改系统；默认 `status` 只读。

## 候选分支安全检查（不要直接在生产环境一键运行远程脚本）

从本分支下载到本地审查，新版需要一起下载 `my_vps_manager.sh` 与 `myvps_runtime.py`。**不要一键覆盖线上 `/root/my_vps_manager.sh` 或现有 `myvps`**。

```bash
curl -fL -o my_vps_manager.sh \
  https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/maintenance/v2.2.0-owned-safe/my_vps_manager.sh
bash -n my_vps_manager.sh
bash my_vps_manager.sh help
bash my_vps_manager.sh status
bash my_vps_manager.sh doctor
```

在正式部署之前保留完整快照、nginx stream 配置和 Xray 密钥；`self-install` 只在 `/opt/myvps/bin/` 安装并行测试版，不覆盖现有管理器。额外的 Xray 实例属于可选实验，不应取代正在运行的系统。

## 线上配置适配与兼容边界（2026-10-08 实测）

| 当前生产组件 | 实测状态 | 新管理器行为 |
|---|---|---|
| `/root/my_vps_manager.sh` v1.2.0 | 在线原管理器 | 保持；`legacy-main` 可从交互式会话进入 |
| `/root/my_vps_exit_manager.sh` v1.0.1 | 原生/WARP/住宅出口菜单 | 保持；`legacy-exit` 从交互式会话进入 |
| `/root/my_vps_cf_ws_manager.sh` v1.0.0 | CF-WS 菜单 | 保持；`legacy-cf` 从交互式会话进入 |
| `xray-racknerd-443.service` | active，VLESS+TCP+REALITY | 只读校验；不改 443、私钥、UUID |
| SOCKS 出站 `res-socks` | 已配置且实际 HTTPS 测试通过 | `status` 检测配置；`chain-test` 可重新验证，输出不含账号和 IP |
| nginx stream SNI 分流 | 443 由 nginx 监听 | 不修改 |
| Google Drive AES-256 自动备份 | config/blog 每日定时器启用 | `backup-status` 读取云端备份新鲜度与最近服务结果 |
| 博客 `moyan-blog` | PM2 online、SQLite `blog.db` | 保持现有数据，备份辅助脚本单独维护 |
| Debian 12 / 1 vCPU / 960MiB | 资源紧凑 | 不自动引入 Docker/3X-UI/新面板 |

### XHTTP（2026-10-08 实测）

已在生产 VPS 并行部署 `myvps-xhttp.service`：本机 Xray 监听 `127.0.0.1:18081`，nginx 将 `cf.gooffu.tech` 的随机 XHTTP 路径转发给 Xray；TLS 由现有 nginx 承担，REALITY 与 CF-WS 原配置保留。Cloudflare 公网路径通过临时 Xray 客户端成功访问 HTTPS，返回 HTTP 200。

XHTTP UUID、路径和客户端连接参数仅保存在 VPS 的 `/etc/myvps/xhttp/client-info.json`（权限 `600`），**没有写入 GitHub 或 Actions 日志**。可以在自己的 SSH 交互式终端运行 `myvps-next xhttp-client` 查看；不要公开该内容。新增命令 `myvps-next xhttp-status` 仅输出脱敏状态。

### 自动备份健康监测

新增 `myvps_backup_watch.py`：每次核对两个 systemd 定时器、上次执行结果和 Google Drive 新备份时间。任一类备份超过 36 小时未更新，会记录 `BACKUP_ALERT` 并返回非零退出状态。

监测日志目前仅保留在 VPS 的 systemd journal 中，**不等于已经向手机、邮箱或 GitHub 发送通知**。可在确定接收渠道后进一步接入外发告警。

### 新增只读命令

```bash
myvps-next status
myvps-next doctor
myvps-next backup-status
myvps-next chain-test
```

生产 VPS 已通过以下实测：`status`、`backup-status`、`chain-test` 均成功；SOCKS5 认证、第二跳 TLS/HTTPS 均通过；线上原三份脚本 SHA-256 前后相同，nginx、REALITY、Fail2ban 保持 active。 [查看验收记录](https://github.com/Becauseiloveyo/blog/actions/runs/37742216241)。

需要打开已有菜单时，只在人工交互式终端运行 `myvps-next legacy-main`、`myvps-next legacy-exit` 或 `myvps-next legacy-cf`。新版本候选阶段 `self-update` **禁用**，防止从尚未更新的 `main` 意外覆盖。

`status` 和 `backup-status` 不打印 SOCKS 账号密码、真实上游地址或 REALITY 密钥；`chain-test` 会使用现有 SOCKS 凭据进行短暂 HTTPS 请求，但不打印凭据。

## 命令清单

| 命令 | 功能 | 是否修改 |
|---|---|---|
| `status` | 生产服务、路由、备份定时器的脱敏状态 | 否 |
| `chain-test` | 住宅 SOCKS 出站、TLS 与 HTTP 端到端测试 | 否（会建立网络连接） |
| `backup-status` | 云端归档新鲜度、最近执行结果 | 否 |
| `legacy-main` / `legacy-exit` / `legacy-cf` | 显式打开现有菜单 | 取决于人工菜单操作 |
| `doctor` | nginx -t 与自有 Xray 配置验证 | 否 |
| `deps-install` | apt 安装依赖 | 是，需要确认 |
| `self-install` | 并行安装为 `myvps-next`，不替换原 `myvps` | 是，需要确认 |
| `self-update` | 候选版禁用，避免从 main 错误覆盖 | 否 |
| `xray-install` | 从 XTLS 官方 release 下载并比对 SHA-256，安装隔离的二进制 | 是，需要确认 |
| `reality-init` | 生成 localhost 15594 的独立 REALITY 配置及停止状态的 systemd 单元 | 是，需要确认 |
| `xray-start` | 仅启动 `myvps-xray.service` | 是，需要确认 |
| `backup-init` | 初始化第二 Google Drive 远端和加密密钥 | 是，需要确认 |
| `backup-vps` | AES-256 加密 VPS 文件级归档并上传 | 是 |
| `backup-blog` | 单独加密备份 `/root/my-blog` 及其相关配置 | 是 |
| `backup-timers` | 安装每天双任务 systemd timer | 是，需要确认 |

### 为什么没有直接提供 XHTTP 一键切换

现有 Cloudflare-WS 尚可使用；XHTTP 能否走 CDN 取决于客户端、Cloudflare、nginx、回源链路和 Xray 版本的匹配。**不会在未经测试时替换正在工作的 WS/443 配置**。后续应新增独立节点、对比故障率/吞吐/延迟，通过再迁移。

## VPS 实测适配：独立 Google Drive AES-256 备份（v2.3.1-rc2）

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

仓库内 `tests/smoke.sh` 和 GitHub Actions 执行 Bash 语法、帮助菜单及只读状态检查。VPS 已通过并行部署、备份云端恢复验证和链式 SOCKS5 HTTPS 测试。正式替换原 `myvps` 命令之前，还需审查旧功能兼容性和新版本发布流程；不建议仅凭当前并行测试即直接覆盖。
