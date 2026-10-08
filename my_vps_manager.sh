#!/usr/bin/env bash
# Self-owned VPS manager: does not take over existing nginx/Xray/PM2.
set -Eeuo pipefail
umask 077

VERSION="2.2.0-rc1"
REPO_RAW="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
SELF="/root/my_vps_manager.sh"
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

status() {
  msg "Manager $VERSION; read-only status"
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
  need bash
  local source
  source=$(readlink -f "$0")
  [[ "$source" != "$SELF" ]] || { msg "Already installed at $SELF"; return; }
  bash -n "$source" || die "Current script does not parse."
  confirm "Install this exact script as $SELF and create /usr/local/bin/myvps?"
  install -m 700 "$source" "$SELF"
  ln -sfn "$SELF" /usr/local/bin/myvps
  msg "Manager installed; services unchanged."
}

self_update() {
  require_root
  need curl
  make_tmp
  curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
    -o "$TMP_DIR/my_vps_manager.sh" "$REPO_RAW/my_vps_manager.sh"
  bash -n "$TMP_DIR/my_vps_manager.sh" || die "Downloaded script failed syntax check."
  grep -q '^# Self-owned VPS manager:' "$TMP_DIR/my_vps_manager.sh" \
    || die "Refusing to install legacy non-owned launcher."
  if grep -Eq 'mack-a/v2ray-agent|vasma' "$TMP_DIR/my_vps_manager.sh"; then
    die "Downloaded script references forbidden legacy installer."
  fi
  local remote_version major minor
  remote_version=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$TMP_DIR/my_vps_manager.sh" | head -n1)
  [[ "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || die "Invalid remote version."
  major=$(cut -d. -f1 <<< "$remote_version")
  minor=$(cut -d. -f2 <<< "$remote_version")
  (( major > 2 || (major == 2 && minor >= 2) )) || die "Refusing legacy main branch below v2.2."
  msg "Available owned version: $remote_version"
  confirm "Replace $SELF with validated main-branch script? .previous is kept."
  [[ ! -f "$SELF" ]] || cp -a "$SELF" "$SELF.previous"
  install -m 700 "$TMP_DIR/my_vps_manager.sh" "$SELF.next"
  mv -f "$SELF.next" "$SELF"
  ln -sfn "$SELF" /usr/local/bin/myvps
  msg "Manager updated without restarting services."
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

backup_init() {
  require_root
  need openssl
  install -d -m 700 /etc/myvps
  [[ ! -e "$BACKUP_KEY" ]] || die "Backup passphrase file already exists: $BACKUP_KEY"
  confirm "Generate backup passphrase? Save an OFFLINE recovery copy."
  openssl rand -base64 48 > "$BACKUP_KEY"
  chmod 600 "$BACKUP_KEY"
  msg "Created $BACKUP_KEY. Save it offline or you cannot restore backups."
}

backup_remote() {
  need rclone
  local remote
  remote="${MYVPS_BACKUP_REMOTE:-}"
  if [[ -z "$remote" ]]; then
    if rclone listremotes | grep -Fxq 'ggdrive:'; then remote="ggdrive:"
    elif rclone listremotes | grep -Fxq 'gdrive:'; then remote="gdrive:"
    else die "Configure ggdrive: or gdrive:, or set MYVPS_BACKUP_REMOTE."; fi
  fi
  [[ "$remote" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]] || die "Invalid rclone remote."
  rclone listremotes | grep -Fxq "$remote" || die "Specified remote not configured."
  printf '%s' "$remote"
}

backup_run() {
  require_root
  local kind="$1" remote destination name now path d
  for d in tar gpg rclone; do need "$d"; done
  [[ -s "$BACKUP_KEY" ]] || die "Run backup-init; keep passphrase offline."
  remote=$(backup_remote)
  now=$(date -u +%Y%m%dT%H%M%SZ)
  name="$(hostname -s)-$kind-$now.tar.gz.gpg"
  make_tmp
  local -a paths=()
  if [[ "$kind" == "vps" ]]; then
    for path in etc root opt var/www usr/local/etc; do
      [[ -e "/$path" ]] && paths+=("$path")
    done
    destination="VPS-Backups/racknerd/full"
  elif [[ "$kind" == "blog" ]]; then
    [[ -d /root/my-blog ]] || die "/root/my-blog not found."
    paths=(root/my-blog)
    [[ -d /root/.pm2 ]] && paths+=(root/.pm2)
    [[ -d /etc/nginx ]] && paths+=(etc/nginx)
    destination="VPS-Backups/racknerd/blog"
  else die "Unknown backup kind"; fi
  [[ "${#paths[@]}" -gt 0 ]] || die "No backup paths."
  msg "Encrypting $kind archive and uploading to $remote$destination"
  tar -C / -czf - --exclude='root/.cache' --exclude='root/my-vps-backup*' \
    --exclude='*/node_modules' --exclude='*/.git' "${paths[@]}" \
    | gpg --batch --yes --pinentry-mode loopback --passphrase-file "$BACKUP_KEY" \
      --symmetric --cipher-algo AES256 -o "$TMP_DIR/$name"
  chmod 600 "$TMP_DIR/$name"
  rclone copyto "$TMP_DIR/$name" "$remote$destination/$name" --retries 3 --transfers 1
  msg "Encrypted backup uploaded: $remote$destination/$name"
  msg "This is FILE-level backup, not database-consistent whole-disk imaging."
}

install_timers() {
  require_root
  [[ -s "$BACKUP_KEY" ]] || die "Run backup-init first."
  need rclone
  backup_remote >/dev/null
  [[ -f "$SELF" ]] || die "Run self-install first."
  confirm "Enable weekly VPS (Sun 02:00) and blog (Sun 03:00) encrypted-backup timers?"
  local kind
  for kind in vps blog; do
    cat > "/etc/systemd/system/myvps-backup-$kind.service" <<EOF
[Unit]
Description=MyVPS encrypted $kind backup
[Service]
Type=oneshot
ExecStart=/usr/bin/bash $SELF backup-$kind
EOF
    chmod 644 "/etc/systemd/system/myvps-backup-$kind.service"
  done
  cat > /etc/systemd/system/myvps-backup-vps.timer <<'EOF'
[Unit]
Description=Weekly encrypted VPS files backup
[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  cat > /etc/systemd/system/myvps-backup-blog.timer <<'EOF'
[Unit]
Description=Weekly encrypted blog files backup
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now myvps-backup-vps.timer myvps-backup-blog.timer
  msg "Timers enabled. Run a manual backup and RESTORE TEST before relying on them."
}

usage() {
  cat <<'USAGE'
myvps v2.2.0-rc1 — self-owned, non-destructive VPS manager
  status          Read-only status (default)
  doctor          Check owned Xray config and nginx syntax
  deps-install    Install prerequisites (confirmation required)
  self-install    Install manager into /root + myvps symlink
  self-update     Fetch syntax-checked main-branch manager
  xray-install    Install SHA256-verified official Xray binary separately
  reality-init    Generate local-only 15594 REALITY instance (no start)
  xray-start      Start ONLY owned myvps-xray service
  backup-init     Create local backup encryption passphrase
  backup-vps      Encrypt and upload VPS files separately
  backup-blog     Encrypt and upload isolated blog files
  backup-timers   Enable separate weekly backup systemd timers
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
9  安装每周备份定时器
10 更新管理脚本（防降级）
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
    0) return ;;
    *) msg "Invalid option"; return 2 ;;
  esac
}

case "${1:-}" in
  "") menu ;;
  status) status ;;
  doctor) doctor ;;
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
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac