#!/usr/bin/env bash
# Self-owned VPS manager: does not take over existing nginx/Xray/PM2.
set -Eeuo pipefail
umask 077

VERSION="2.3.0-rc1"
REPO_RAW="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main" # RC self-update intentionally disabled
SELF="/opt/myvps/bin/my_vps_manager.sh"
BIN="/opt/myvps/xray/xray"
CONF="/etc/myvps/xray/config.json"
SERVICE="myvps-xray.service"
BACKUP_KEY="/etc/myvps/backup.pass"
TMP_DIR=""
cleanup() { [[ -z "$TMP_DIR" || ! -d "$TMP_DIR" ]] || rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT
msg() { printf '[myvps] %s\n' "$*"; }
die() { printf '[myvps][ERROR] %s\n' "$*" >&2; exit 1; }
require_root() { [[ "$EUID" -eq 0 ]] || die "Run as root."; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1 (run deps-install explicitly)."; }
confirm() {
  [[ -t 0 ]] || die "Interactive confirmation required; no changes made."
  local response
  read -r -p "$1 [type YES]: " response
  [[ "$response" == "YES" ]] || die "Cancelled."
}
make_tmp() { TMP_DIR=$(mktemp -d /tmp/myvps.XXXXXXXX); chmod 700 "$TMP_DIR"; }

basic_status() {
  msg "Manager $VERSION; basic read-only status"
  printf 'OS: '; grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null || true
  printf 'Kernel: '; uname -r
  local service
  for service in nginx xray xray-racknerd-443 "$SERVICE" fail2ban; do
    if command -v systemctl >/dev/null 2>&1; then
      printf '%-24s %s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
    fi
  done
  if command -v ss >/dev/null 2>&1; then
    msg "Listening sockets (443, 15593, 15594, 80)"
    ss -lntup | grep -E '(:443|:15593|:15594|:80)[[:space:]]' || true
  fi
  msg "Owned binary: $([[ -x "$BIN" ]] && echo installed || echo missing)"
  if [[ -x "$BIN" ]]; then "$BIN" version | head -n 2 || true; fi
  msg "Owned config: $([[ -f "$CONF" ]] && echo present || echo missing)"
}

runtime_helper() {
  local helper="/opt/myvps/bin/myvps_runtime.py"
  [[ -r "$helper" ]] || helper="$(cd "$(dirname "$0")" && pwd)/myvps_runtime.py"
  [[ -f "$helper" ]] || die "Runtime helper missing: myvps_runtime.py"
  need python3
  python3 "$helper" "$@"
}
status() {
  msg "MyVPS $VERSION — live read-only status of existing services"
  if [[ -f /opt/myvps/bin/myvps_runtime.py || -f "$(dirname "$0")/myvps_runtime.py" ]]; then
    runtime_helper status
  else
    basic_status
    msg "Install the companion myvps_runtime.py for full live status."
  fi
}
chain_status() { runtime_helper status; }
chain_test() { runtime_helper chain-test; }
backup_status() { runtime_helper backup-status; }
legacy_menu() {
  require_root
  [[ -t 0 ]] || die "Legacy menus require an interactive terminal."
  local which="$1" path
  case "$which" in
    main) path="/root/my_vps_manager.sh" ;;
    exit) path="/root/my_vps_exit_manager.sh" ;;
    cf) path="/root/my_vps_cf_ws_manager.sh" ;;
    *) die "Unknown legacy menu." ;;
  esac
  [[ -f "$path" && -r "$path" ]] || die "Legacy script absent: $which"
  [[ "$(readlink -f "$path")" != "$(readlink -f "$0")" ]] || die "Refusing to recurse into this manager."
  msg "Opening installed legacy $which manager; production ownership remains unchanged."
  /usr/bin/bash "$path"
}

doctor() {
  status
  if [[ -x "$BIN" && -f "$CONF" ]]; then
    msg "Testing owned Xray configuration"
    XRAY_LOCATION_ASSET=/opt/myvps/xray/assets "$BIN" run -test -config "$CONF" \
      && msg "Owned Xray config: PASS" || msg "Owned Xray config: FAIL"
  fi
  if [[ -f /etc/xray-racknerd-443/config.json ]]; then
    local legacy_bin=""
    if [[ -x /usr/local/bin/xray ]]; then legacy_bin="/usr/local/bin/xray"
    elif command -v xray >/dev/null 2>&1; then legacy_bin=$(command -v xray); fi
    if [[ -n "$legacy_bin" ]]; then
      msg "Validating existing /etc/xray-racknerd-443/config.json (read-only)"
      "$legacy_bin" run -test -config /etc/xray-racknerd-443/config.json \
        && msg "Existing REALITY config: PASS" || msg "Existing REALITY config: FAIL"
    else
      msg "Existing REALITY config found, but no old Xray binary found for validation."
    fi
  fi
  if command -v nginx >/dev/null 2>&1; then
    msg "Checking nginx syntax (read-only)"
    nginx -t 2>&1 || true
  fi
  msg "This does NOT diagnose public-IP reachability or GFW filtering."
}

deps_install() {
  require_root
  need apt-get
  confirm "Install curl jq unzip ca-certificates openssl gnupg rclone tar iproute2? No DNS/firewall changes."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl ca-certificates jq unzip openssl gnupg rclone tar iproute2
}

self_install() {
  require_root
  local source helper source_dir
  source=$(readlink -f "$0")
  source_dir=$(dirname "$source")
  helper="$source_dir/myvps_runtime.py"
  [[ -f "$helper" ]] || die "Install requires myvps_runtime.py beside the manager."
  need python3
  bash -n "$source" || die "Bash syntax invalid."
  python3 -m py_compile "$helper" || die "Python diagnostics syntax invalid."
  confirm "Install parallel command myvps-next only? Existing /root/my_vps_manager.sh and myvps are kept."
  install -d -m 755 /opt/myvps/bin
  if [[ -f "$SELF" ]]; then cp -a "$SELF" "$SELF.previous"; fi
  install -m 700 "$source" "$SELF.next"
  install -m 700 "$helper" /opt/myvps/bin/myvps_runtime.py.next
  mv -f "$SELF.next" "$SELF"
  mv -f /opt/myvps/bin/myvps_runtime.py.next /opt/myvps/bin/myvps_runtime.py
  ln -sfn "$SELF" /usr/local/bin/myvps-next
  msg "Installed myvps-next in parallel; live myvps and all network services unchanged."
}
self_update() {
  die "RC update disabled: the published main branch is not the candidate. Review and install a pinned tested release; no changes made."
}

xray_install() {
  require_root
  local d release url digest actual expected
  for d in curl jq unzip sha256sum; do need "$d"; done
  [[ "$(uname -m)" == "x86_64" ]] || die "This release candidate supports x86_64 only."
  confirm "Install verified official Xray-core binary separately (no existing unit changes)?"
  make_tmp
  release=$(curl -fsSL --connect-timeout 10 --max-time 25 \
    https://api.github.com/repos/XTLS/Xray-core/releases/latest)
  url=$(jq -r '.assets[] | select(.name=="Xray-linux-64.zip") | .browser_download_url' <<< "$release" | head -n1)
  digest=$(jq -r '.assets[] | select(.name=="Xray-linux-64.zip") | .digest' <<< "$release" | head -n1)
  [[ "$url" == https://github.com/XTLS/Xray-core/releases/download/* ]] || die "Unexpected release URL."
  [[ "$digest" =~ ^sha256:[[:xdigit:]]{64}$ ]] || die "No official SHA-256 release digest; aborting."
  expected=$(printf '%s' "$digest" | cut -d: -f2)
  curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$TMP_DIR/xray.zip" "$url"
  actual=$(sha256sum "$TMP_DIR/xray.zip" | awk '{print $1}')
  [[ "${actual,,}" == "${expected,,}" ]] || die "Xray release SHA-256 mismatch."
  mkdir -p "$TMP_DIR/unpacked"
  unzip -q "$TMP_DIR/xray.zip" -d "$TMP_DIR/unpacked"
  [[ -f "$TMP_DIR/unpacked/xray" ]] || die "Xray binary absent in archive."
  chmod 700 "$TMP_DIR/unpacked/xray"
  "$TMP_DIR/unpacked/xray" version >/dev/null || die "Downloaded binary cannot execute."
  if [[ -f "$CONF" ]]; then
    XRAY_LOCATION_ASSET="$TMP_DIR/unpacked" \
      "$TMP_DIR/unpacked/xray" run -test -config "$CONF" || die "New binary rejects owned config."
  fi
  install -d -m 755 /opt/myvps/xray /opt/myvps/xray/assets
  if [[ -e "$BIN" ]]; then cp -a "$BIN" "$BIN.previous"; fi
  install -m 755 "$TMP_DIR/unpacked/xray" "$BIN.next"
  mv -f "$BIN.next" "$BIN"
  local asset
  for asset in geoip.dat geosite.dat; do
    if [[ -f "$TMP_DIR/unpacked/$asset" ]]; then
      install -m 644 "$TMP_DIR/unpacked/$asset" "/opt/myvps/xray/assets/$asset"
    fi
  done
  msg "Verified Xray installed; running services NOT restarted."
}

ensure_user() {
  if ! id myvpsxray >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin myvpsxray
  fi
}

reality_init() {
  require_root
  need jq; need openssl
  [[ -x "$BIN" ]] || die "Run xray-install first."
  [[ ! -e "$CONF" ]] || die "Owned config exists: refusing to overwrite."
  [[ -t 0 ]] || die "Interactive initialization only."
  local target sni keys private uuid short
  read -r -p "REALITY target hostname [dl.google.com]: " target
  target=$(printf '%s' "$target" | tr -d '\r')
  target="${target:-dl.google.com}"
  [[ "$target" =~ ^[a-zA-Z0-9.-]+$ ]] || die "Invalid hostname."
  sni="$target"
  keys=$("$BIN" x25519)
  private=$(printf '%s\n' "$keys" | awk -F': ' '/Private/ { print $2; exit }')
  [[ -n "$private" ]] || die "Cannot parse x25519 private key."
  uuid=$(cat /proc/sys/kernel/random/uuid)
  short=$(openssl rand -hex 8)
  msg "LOCAL test 127.0.0.1:15594 only. No public 443, nginx or Cloudflare changes."
  confirm "Generate owned REALITY test config and disabled service?"
  ensure_user
  install -d -m 750 -o root -g myvpsxray /etc/myvps/xray
  jq -n --arg id "$uuid" --arg private "$private" --arg target "$target" --arg sni "$sni" --arg sid "$short" '{
    log:{loglevel:"warning"},
    inbounds:[{
      tag:"reality-loopback",listen:"127.0.0.1",port:15594,protocol:"vless",
      settings:{clients:[{id:$id,flow:"xtls-rprx-vision"}],decryption:"none"},
      streamSettings:{network:"tcp",security:"reality",
        realitySettings:{show:false,target:($target+":443"),serverNames:[$sni],privateKey:$private,shortIds:[$sid]}
      }
    }],
    outbounds:[{tag:"direct",protocol:"freedom"}]
  }' > /etc/myvps/xray/config.json.next
  chown root:myvpsxray /etc/myvps/xray/config.json.next
  chmod 640 /etc/myvps/xray/config.json.next
  XRAY_LOCATION_ASSET=/opt/myvps/xray/assets \
    "$BIN" run -test -config /etc/myvps/xray/config.json.next \
    || die "Invalid candidate; left .next for inspection."
  mv /etc/myvps/xray/config.json.next "$CONF"
  cat > /etc/systemd/system/myvps-xray.service <<'UNIT'
[Unit]
Description=Owned Xray loopback test instance
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=myvpsxray
Group=myvpsxray
Environment=XRAY_LOCATION_ASSET=/opt/myvps/xray/assets
ExecStart=/opt/myvps/xray/xray run -config /etc/myvps/xray/config.json
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
  chmod 644 /etc/systemd/system/myvps-xray.service
  systemctl daemon-reload
  msg "Created local-only 15594 instance. Service DISABLED and STOPPED until xray-start."
  msg "Keep UUID/keys secret; do not alter public 443 until separately tested."
}

xray_start() {
  require_root
  [[ -x "$BIN" && -f "$CONF" ]] || die "Owned Xray not initialized."
  XRAY_LOCATION_ASSET=/opt/myvps/xray/assets "$BIN" run -test -config "$CONF" \
    || die "Configuration test failed."
  confirm "Enable/start ONLY myvps-xray.service?"
  systemctl enable --now "$SERVICE"
  systemctl --no-pager status "$SERVICE" | head -n 15 || true
}

backup_helper() {
  require_root
  local helper="/opt/myvps/backup/myvps_backup.sh"
  [[ -f "$helper" ]] || helper="$(cd "$(dirname "$0")" && pwd)/myvps_backup.sh"
  [[ -f "$helper" ]] || die "Backup companion missing; install myvps_backup.sh first."
  /usr/bin/bash "$helper" "$@"
}
backup_init() { backup_helper init; }
backup_run() {
  local kind="$1"
  [[ "$kind" != vps ]] || kind=config
  backup_helper run "$kind"
}
install_timers() { backup_helper timers; }

usage() {
  cat <<'USAGE'
myvps-next v2.3.0-rc1 — live-VPS-aware, non-destructive manager
  status          Read-only live nginx/REALITY/SOCKS/backup status (default)
  chain-test      End-to-end SOCKS5 authenticated HTTPS test (no credentials printed)
  backup-status   Check daily timers, cloud backup ages and recent success
  legacy-main     Open existing v1.2.0 VPS manager (interactive)
  legacy-exit     Open existing exit/chain manager (interactive)
  legacy-cf       Open existing CF-WS manager (interactive)
  doctor          Check owned Xray config and nginx syntax
  deps-install    Install prerequisites (confirmation required)
  self-install    Install parallel myvps-next; preserve the existing myvps command
  self-update     Disabled in release candidate to prevent main/RC mismatch
  xray-install    Install SHA256-verified official Xray binary separately
  reality-init    Generate local-only 15594 REALITY instance (no start)
  xray-start      Start ONLY owned myvps-xray service
  backup-init     Configure working GDrive remote and create offline recovery key
  backup-vps      Snapshot/encrypt/upload config files to GDrive
  backup-blog     SQLite-consistent blog archive to GDrive
  backup-timers   Enable daily backups 02:00/02:30 Asia/Shanghai
  backup-test     Encrypted test upload/check/delete (does not touch existing backups)
  backup-restore-config  Download/decrypt/verify latest config archive
  backup-restore-blog    Download/decrypt/verify latest blog archive
  help            This usage message

Safety: No automatic DNS, UFW, nginx, 443, legacy Xray, PM2, or Cloudflare changes.
XHTTP requires separately tested server/client/CDN integration, not automatic migration.
USAGE
}
menu() {
  if [[ ! -t 0 ]]; then status; return; fi
  cat <<'MENU'
============ MyVPS v2.2 RC ============
1  只读状态与端口
2  只读诊断（含旧 REALITY / nginx）
3  安装官方校验版 Xray（独立）
4  初始化本机 REALITY 测试节点
5  启动自有测试节点
6  VPS 加密备份到 Google Drive
7  博客独立加密备份
8  初始化加密备份口令
9  检查/安装每天备份定时器
10 检查 GitHub 更新（候选版本禁用）
11 查看当前链式代理配置
12 测试 SOCKS5 链式出口
13 查看云端备份日期
14 进入旧版 VPS 管理菜单
15 进入住宅/WARP 出口管理
16 进入 CF-WS 管理菜单
0  退出
=======================================
MENU
  local choice
  read -r -p "请选择: " choice
  case "$choice" in
    1) status ;;
    2) doctor ;;
    3) xray_install ;;
    4) reality_init ;;
    5) xray_start ;;
    6) backup_run vps ;;
    7) backup_run blog ;;
    8) backup_init ;;
    9) install_timers ;;
    10) self_update ;;
    11) chain_status ;;
    12) chain_test ;;
    13) backup_status ;;
    14) legacy_menu main ;;
    15) legacy_menu exit ;;
    16) legacy_menu cf ;;
    0) return ;;
    *) msg "Invalid option"; return 2 ;;
  esac
}

case "${1:-}" in
  "") menu ;;
  status) status ;;
  doctor) doctor ;;
  chain-status) chain_status ;;
  chain-test) chain_test ;;
  backup-status) backup_status ;;
  legacy-main) legacy_menu main ;;
  legacy-exit) legacy_menu exit ;;
  legacy-cf) legacy_menu cf ;;
  deps-install) deps_install ;;
  self-install) self_install ;;
  self-update) self_update ;;
  xray-install) xray_install ;;
  reality-init) reality_init ;;
  xray-start) xray_start ;;
  backup-init) backup_init ;;
  backup-vps) backup_run vps ;;
  backup-blog) backup_run blog ;;
  backup-timers) install_timers ;;
  backup-test) backup_helper probe ;;
  backup-restore-config) backup_helper restore-test config ;;
  backup-restore-blog) backup_helper restore-test blog ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac