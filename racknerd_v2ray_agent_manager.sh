#!/usr/bin/env bash
# racknerd_v2ray_agent_manager.sh
# Clean Edition v1.1：个性化 VPS 管理脚本。
# 功能：检测/安装/启动 mack-a v2ray-agent，速度优化、安全加固、备份回滚、连通性检测和自更新。
# 适用：Debian 12 / Ubuntu / 常见 RHEL 系。
# 说明：
# 1) 本脚本本身不加入广告、推广链接或无关输出。
# 2) 本脚本不会“保证解锁”任何平台；流媒体/AI 可用性主要取决于 IP 地区、IP 信誉、平台风控和客户端设置。
# 3) 本脚本通过官方 GitHub 源下载 v2ray-agent，不魔改官方项目版权/许可信息。
# 4) 本版本吸收的是常见优秀 VPS 脚本的“功能思路”：自更新、日志、备份、回滚、健康检查、敏感信息提醒、轻量测速；没有复制其他作者源码。

set -Eeuo pipefail

# ===== 版本和下载地址 =====
VERSION="1.1.0-clean"
REPO_RAW_BASE="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
SELF_URL="$REPO_RAW_BASE/racknerd_v2ray_agent_manager.sh"
SHORT_INSTALL_URL="$REPO_RAW_BASE/i.sh"
V2RAY_AGENT_URL="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"

# ===== 个性化配置 =====
SERVER_NAME="RackNerd-Debian12"
INSTALL_PATH="/root/install.sh"
SELF_PATH="/root/racknerd_v2ray_agent_manager.sh"
AGENT_DIR="/etc/v2ray-agent"
LOG_FILE="/var/log/racknerd_v2ray_agent_manager.log"
BACKUP_DIR="/root/vps-backups"
LOCK_FILE="/tmp/racknerd_v2ray_agent_manager.lock"
ALIAS_PATH="/usr/local/bin/rn"

# 你的常用 VLESS-Reality 客户端模板；不要把 UUID/ShortId/PrivateKey 写进公开脚本。
CLIENT_PORT_DEFAULT="15593"
CLIENT_FLOW_DEFAULT="xtls-rprx-vision"
CLIENT_NETWORK_DEFAULT="tcp"
CLIENT_SECURITY_DEFAULT="reality"
CLIENT_FINGERPRINT_DEFAULT="chrome"
CLIENT_MUX_DEFAULT="off"

# 常用放行端口；按你的实际方案修改。
OPEN_PORTS=(22 80 443 15593)

# 站点连通性检测列表：只做可达性/地区提示，不保证平台放行。
CHECK_SITES=(
  "Netflix|https://www.netflix.com/"
  "Fast/Netflix测速|https://fast.com/"
  "Disney+|https://www.disneyplus.com/"
  "PrimeVideo|https://www.primevideo.com/"
  "YouTube|https://www.youtube.com/"
  "Grok|https://grok.com/"
  "xAI|https://x.ai/"
  "X/Twitter|https://x.com/"
  "OpenAI|https://chat.openai.com/"
)

# ===== 基础输出 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true
  echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

ok() { log "${GREEN}✅ $*${NC}"; }
warn() { log "${YELLOW}⚠️  $*${NC}"; }
err() { log "${RED}❌ $*${NC}"; }
info() { log "${BLUE}ℹ️  $*${NC}"; }
title() { echo -e "${CYAN}========== $* ==========${NC}"; }

on_error() {
  local line="$1"
  local cmd="$2"
  err "脚本在第 ${line} 行出错：${cmd}"
  err "日志位置：$LOG_FILE"
}
trap 'on_error ${LINENO} "$BASH_COMMAND"' ERR

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    err "已有一个管理脚本正在运行，请先关闭另一个窗口。"
    exit 1
  fi
fi

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 执行：sudo bash $0"
    exit 1
  fi
}

pause() {
  read -rp "按回车继续..." _ || true
}

confirm() {
  local prompt="$1"
  local ans
  read -rp "$prompt [y/N]: " ans || true
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

os_pretty() {
  grep -PRE '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Unknown"
}

pkg_install() {
  local pkgs=("$@")
  if has_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${pkgs[@]}"
  elif has_cmd dnf; then
    dnf install -y "${pkgs[@]}"
  elif has_cmd yum; then
    yum install -y "${pkgs[@]}"
  else
    warn "未识别 apt/dnf/yum，请手动安装：${pkgs[*]}"
  fi
}

install_base_tools() {
  info "安装/检查基础工具..."
  if has_cmd apt-get; then
    pkg_install curl wget ca-certificates unzip tar socat cron lsof ufw net-tools dnsutils jq iproute2 sudo util-linux fail2ban openssl
    systemctl enable --now cron >/dev/null 2>&1 || true
  elif has_cmd dnf || has_cmd yum; then
    pkg_install curl wget ca-certificates unzip tar socat cronie lsof net-tools bind-utils jq iproute sudo util-linux fail2ban openssl
    systemctl enable --now crond >/dev/null 2>&1 || true
  else
    warn "未识别包管理器，请手动安装 curl/wget/socat/cron/jq/fail2ban。"
  fi
}

download_file() {
  local url="$1"
  local out="$2"
  if has_cmd curl; then
    curl -fsSL --connect-timeout 10 --max-time 60 -o "$out" "$url"
  elif has_cmd wget; then
    wget -q --timeout=30 -O "$out" "$url"
  else
    err "缺少 curl/wget，请先安装。"
    return 1
  fi
}

show_version() {
  clear
  title "版本信息"
  echo "脚本版本: $VERSION"
  echo "脚本路径: $SELF_PATH"
  echo "短命令:   $ALIAS_PATH"
  echo "仓库 RAW: $REPO_RAW_BASE"
  echo "日志文件: $LOG_FILE"
}

install_self_alias() {
  clear
  need_root
  title "安装短命令 rn"
  cat >"$ALIAS_PATH" <<EOF
#!/usr/bin/env bash
bash "$SELF_PATH" "\$@"
EOF
  chmod +x "$ALIAS_PATH"
  ok "已安装短命令：rn"
  echo
  echo "以后直接输入："
  echo "  rn"
}

self_update() {
  clear
  need_root
  title "自更新管理脚本"
  local tmp="/tmp/racknerd_v2ray_agent_manager.$$.sh"
  info "下载最新版：$SELF_URL"
  download_file "$SELF_URL" "$tmp"
  if ! bash -n "$tmp"; then
    err "新版脚本语法检查失败，已取消更新。"
    rm -f "$tmp"
    return 1
  fi
  cp -a "$SELF_PATH" "$SELF_PATH.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  install -m 700 "$tmp" "$SELF_PATH"
  rm -f "$tmp"
  ok "自更新完成。重新打开菜单即可使用新版。"
}

show_server_info() {
  clear
  title "$SERVER_NAME 系统信息"
  echo "主机名: $(hostname)"
  echo "系统: $(os_pretty)"
  echo "内核: $(uname -r)"
  echo "架构: $(uname -m)"
  echo "CPU: $(nproc) 核"
  echo
  echo "内存:"
  free -h || true
  echo
  echo "磁盘:"
  df -h / || true
  echo
  echo "公网 IP:"
  echo -n "IPv4: "; curl -4 -s --max-time 5 https://api.ipify.org || true; echo
  echo -n "IPv6: "; curl -6 -s --max-time 5 https://api64.ipify.org || true; echo
  echo
  echo "IP 地区/ASN："
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)\n时区: \(.timezone)"' 2>/dev/null || true
}

check_v2ray_agent() {
  clear
  title "v2ray-agent 检测"

  if has_cmd vasma; then
    ok "发现脚本快捷命令：$(command -v vasma)"
  else
    warn "未发现 vasma 命令"
  fi

  if has_cmd vasmad; then
    ok "发现 Docker Reality 快捷命令：$(command -v vasmad)"
  else
    warn "未发现 vasmad 命令"
  fi

  if [[ -d "$AGENT_DIR" ]]; then
    ok "发现目录：$AGENT_DIR"
    ls -la "$AGENT_DIR" | sed 's/^/  /'
  else
    warn "未发现目录：$AGENT_DIR"
  fi

  echo
  echo "核心服务状态："
  for svc in xray sing-box nginx hysteria-server tuic fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      echo "--- $svc ---"
      systemctl --no-pager --lines=4 status "$svc" || true
    fi
  done

  echo
  echo "端口监听："
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
}

open_agent_menu() {
  if has_cmd vasma; then
    vasma
  elif [[ -x "$AGENT_DIR/install.sh" ]]; then
    bash "$AGENT_DIR/install.sh"
  else
    err "未找到 vasma 或 $AGENT_DIR/install.sh，请先安装。"
    pause
  fi
}

download_agent() {
  info "下载 v2ray-agent 官方脚本..."
  rm -f "$INSTALL_PATH"
  download_file "$V2RAY_AGENT_URL" "$INSTALL_PATH"
  chmod 700 "$INSTALL_PATH"
  ok "脚本已保存：$INSTALL_PATH"
}

install_or_update_agent() {
  clear
  need_root
  install_base_tools
  download_agent
  info "即将运行官方 v2ray-agent 安装/管理脚本。"
  info "进入官方菜单后，按你的需求选择 Reality / Vision / Hysteria2 / TUIC 等安装方案。"
  bash "$INSTALL_PATH"
}

configure_firewall() {
  clear
  need_root
  title "配置 UFW 防火墙"
  if ! has_cmd ufw; then
    install_base_tools
  fi

  for port in "${OPEN_PORTS[@]}"; do
    ufw allow "${port}/tcp" || true
    ufw allow "${port}/udp" || true
  done

  ufw --force enable
  ufw status verbose
  ok "防火墙配置完成。当前放行端口：${OPEN_PORTS[*]}"
}

custom_firewall_port() {
  clear
  need_root
  title "自定义放行端口"
  if ! has_cmd ufw; then
    install_base_tools
  fi
  local port proto
  read -rp "输入要放行的端口，例如 443 或 15593: " port
  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( port < 1 || port > 65535 )); then
    err "端口不合法。"
    return 1
  fi
  read -rp "协议 tcp/udp/both [both]: " proto
  proto="${proto:-both}"
  case "$proto" in
    tcp) ufw allow "${port}/tcp" ;;
    udp) ufw allow "${port}/udp" ;;
    both) ufw allow "${port}/tcp"; ufw allow "${port}/udp" ;;
    *) err "协议不合法。"; return 1 ;;
  esac
  ufw --force enable
  ufw status verbose
  ok "端口 $port 已放行。"
}

enable_bbr() {
  clear
  need_root
  title "开启 BBR"
  cat >/etc/sysctl.d/99-racknerd-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system
  echo
  sysctl net.ipv4.tcp_congestion_control || true
  lsmod | grep bbr || true
  ok "BBR 设置完成。"
}

speed_tune_safe() {
  clear
  need_root
  title "安全速度优化"
  warn "这是通用 TCP/队列优化，不会修改 v2ray-agent 节点配置。"
  cp -a /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  cat >/etc/sysctl.d/98-racknerd-speed-safe.conf <<'EOF'
# RackNerd VPS safe network tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_mtu_probing=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
  sysctl --system
  ok "速度优化已应用。"
  echo
  echo "当前拥塞控制："
  sysctl net.ipv4.tcp_congestion_control || true
}

rollback_speed_tune() {
  clear
  need_root
  title "回滚速度优化"
  rm -f /etc/sysctl.d/98-racknerd-speed-safe.conf /etc/sysctl.d/99-racknerd-bbr.conf
  sysctl --system || true
  ok "已移除本脚本写入的 sysctl 优化文件。"
}

install_fail2ban_safe() {
  clear
  need_root
  title "SSH 防爆破保护"
  install_base_tools
  mkdir -p /etc/fail2ban/jail.d
  cat >/etc/fail2ban/jail.d/racknerd-sshd.conf <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  fail2ban-client status sshd || true
  ok "fail2ban SSH 防爆破已启用。"
}

optimize_dns_safe() {
  clear
  need_root
  title "DNS 优化"
  warn "此项只优化 VPS 自身解析；客户端是否走代理 DNS 取决于你的客户端分流设置。"

  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved.service'; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat >/etc/systemd/resolved.conf.d/racknerd-dns.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8 9.9.9.9
FallbackDNS=1.0.0.1 8.8.4.4
DNSSEC=no
Cache=yes
EOF
    systemctl restart systemd-resolved || true
    resolvectl status 2>/dev/null | sed -n '1,80p' || true
    ok "systemd-resolved DNS 已设置。"
  else
    cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    ok "/etc/resolv.conf 已设置。"
  fi
}

backup_agent_configs() {
  clear
  need_root
  title "备份节点配置"
  mkdir -p "$BACKUP_DIR"
  local out="$BACKUP_DIR/v2ray-agent-backup-$(date +%F_%H%M%S).tar.gz"
  tar --ignore-failed-read -czf "$out" \
    /etc/v2ray-agent \
    /usr/local/etc/xray \
    /usr/local/etc/sing-box \
    /etc/nginx/conf.d \
    /etc/nginx/sites-enabled \
    /etc/systemd/system/xray.service \
    /etc/systemd/system/sing-box.service \
    2>/dev/null || true
  chmod 600 "$out" || true
  ok "已备份到：$out"
  warn "备份里可能含 UUID、私钥、证书等敏感信息，不要发给别人。"
}

list_backups() {
  clear
  title "备份列表"
  mkdir -p "$BACKUP_DIR"
  ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || warn "暂无备份。"
}

repair_core_services() {
  clear
  need_root
  title "修复/重启核心服务"
  for svc in xray sing-box nginx; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        ok "$svc 正在运行，尝试重启刷新配置..."
      else
        warn "$svc 未运行，尝试启动..."
      fi
      systemctl restart "$svc" || true
      systemctl --no-pager --lines=6 status "$svc" || true
      echo
    fi
  done
}

validate_core_configs() {
  clear
  title "核心配置语法检查"
  if has_cmd xray; then
    echo "--- xray ---"
    xray version || true
    [[ -f /usr/local/etc/xray/config.json ]] && xray -test -config /usr/local/etc/xray/config.json || true
    echo
  else
    warn "未找到 xray 命令。"
  fi

  if has_cmd sing-box; then
    echo "--- sing-box ---"
    sing-box version || true
    if [[ -f /usr/local/etc/sing-box/config.json ]]; then
      sing-box check -c /usr/local/etc/sing-box/config.json || true
    elif [[ -f /etc/sing-box/config.json ]]; then
      sing-box check -c /etc/sing-box/config.json || true
    fi
    echo
  else
    warn "未找到 sing-box 命令。"
  fi

  if has_cmd nginx; then
    echo "--- nginx ---"
    nginx -t || true
  else
    warn "未找到 nginx 命令。"
  fi
}

show_client_reality_template() {
  clear
  title "VLESS-Reality 客户端推荐模板"
  echo "适合你截图里的 VLESS + Reality + Vision 类型。"
  echo
  echo "别名 remarks:       自己命名，例如 RackNerd-Reality"
  echo "地址 address:       你的 VPS IP 或已解析到 VPS 的域名"
  echo "端口 port:          $CLIENT_PORT_DEFAULT，必须和服务端一致"
  echo "用户 ID id:         用 vasma 生成/查看，不要公开"
  echo "流控 flow:          $CLIENT_FLOW_DEFAULT"
  echo "加密 encryption:    none"
  echo "传输 network:       $CLIENT_NETWORK_DEFAULT"
  echo "伪装 type:          none"
  echo "TLS/security:       $CLIENT_SECURITY_DEFAULT"
  echo "SNI/serverName:     用 vasma 生成时给你的值，不要乱改"
  echo "Fingerprint:        $CLIENT_FINGERPRINT_DEFAULT"
  echo "PublicKey:          用 vasma 生成/查看"
  echo "ShortId:            用 vasma 生成/查看，不要公开"
  echo "SpiderX:            留空或按 vasma 输出"
  echo "Mux:                $CLIENT_MUX_DEFAULT"
  echo
  warn "如果之前截图/分享过节点参数，建议在 vasma 里删除/重置该用户或重新生成节点，再导入客户端。"
}

site_head_check() {
  local name="$1"
  local url="$2"
  local data code time_total final_url remote_ip
  data=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{http_code}|%{time_total}|%{remote_ip}|%{url_effective}' "$url" 2>/dev/null || echo "000|-1|-|-")
  IFS='|' read -r code time_total remote_ip final_url <<<"$data"
  printf "%-18s HTTP:%-4s 耗时:%-8s 远端:%-15s 最终:%s\n" "$name" "$code" "$time_total" "$remote_ip" "$final_url"
}

media_ai_check_light() {
  clear
  title "流媒体 / Grok / AI 服务可用性检测"
  warn "这只是 VPS 出口 IP 的连通性与地区可用性检测，不代表一定能长期解锁。"
  echo
  echo "[1] VPS 出口 IP 信息"
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)\n时区: \(.timezone)"' 2>/dev/null || true
  echo
  echo "[2] 站点连通性"
  for item in "${CHECK_SITES[@]}"; do
    IFS='|' read -r name url <<<"$item"
    site_head_check "$name" "$url"
  done
  echo
  echo "[3] 结果说明"
  echo "- HTTP 200/301/302 只代表能连上，不等于账号/内容库可用。"
  echo "- 如果 Netflix 提示代理/VPN，通常是 IP 被平台识别或地区不匹配，脚本无法从服务器端强制解决。"
  echo "- Grok/X 是否可用还取决于账号、地区、应用版本、风控和客户端 DNS/分流。"
  echo "- 手机/电脑客户端建议：VLESS-Reality 节点走代理，DNS 避免泄漏，Mux 关闭，Fingerprint 选 chrome。"
}

network_speed_light() {
  clear
  title "轻量网络测速"
  warn "只下载约 10MB 测速文件，用来粗略判断 VPS 出口速度，不代表真实晚高峰速度。"
  local url="https://speed.cloudflare.com/__down?bytes=10000000"
  local data speed time_total
  data=$(curl -4 -L -o /dev/null -sS --connect-timeout 8 --max-time 30 -w '%{speed_download}|%{time_total}' "$url" 2>/dev/null || echo "0|-1")
  IFS='|' read -r speed time_total <<<"$data"
  if [[ "$speed" != "0" ]]; then
    awk -v s="$speed" -v t="$time_total" 'BEGIN { printf "下载速度约：%.2f MB/s，耗时：%s 秒\n", s/1024/1024, t }'
  else
    warn "测速失败。"
  fi
}

security_audit() {
  clear
  title "安全体检"
  echo "[1] SSH 配置"
  if [[ -f /etc/ssh/sshd_config ]]; then
    grep -Ei '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port)\b' /etc/ssh/sshd_config || true
  fi
  echo
  echo "[2] 防火墙"
  if has_cmd ufw; then
    ufw status verbose || true
  else
    warn "未安装 ufw。"
  fi
  echo
  echo "[3] fail2ban"
  if has_cmd fail2ban-client; then
    fail2ban-client status || true
  else
    warn "未安装 fail2ban。"
  fi
  echo
  echo "[4] 敏感信息提醒"
  warn "不要把 /etc/v2ray-agent、/usr/local/etc/xray、/usr/local/etc/sing-box、备份压缩包、节点链接上传到公开仓库。"
  warn "如果截图露出 UUID / ShortId / PublicKey，建议在 vasma 里重置用户。"
}

show_account_hint() {
  clear
  title "查看节点/订阅提示"
  echo "如果已经安装 v2ray-agent："
  echo "  1) 输入 vasma"
  echo "  2) 选择：账号管理"
  echo "  3) 选择：查看账号 或 查看订阅"
  echo
  echo "快捷打开："
  echo "  vasma"
}

health_check() {
  clear
  title "健康检查"
  echo "[1] 系统资源"
  uptime || true
  free -h || true
  df -h / || true
  echo

  echo "[2] 网络连通"
  ping -c 3 1.1.1.1 || true
  echo

  echo "[3] 公网 IP"
  echo -n "IPv4: "; curl -4 -s --max-time 5 https://api.ipify.org || true; echo
  echo -n "IPv6: "; curl -6 -s --max-time 5 https://api64.ipify.org || true; echo
  echo

  echo "[4] 关键服务"
  for svc in xray sing-box nginx fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      systemctl is-active "$svc" >/dev/null 2>&1 && ok "$svc 运行中" || warn "$svc 未运行"
    fi
  done
  echo

  echo "[5] 常用端口监听"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
}

recommended_flow() {
  clear
  need_root
  title "推荐优化流程"
  warn "推荐顺序：先备份，再优化，再安全体检。"
  if confirm "是否先备份配置"; then backup_agent_configs; fi
  if confirm "是否应用安全速度优化"; then speed_tune_safe; fi
  if confirm "是否启用 fail2ban SSH 防爆破"; then install_fail2ban_safe; fi
  if confirm "是否配置 UFW 常用端口"; then configure_firewall; fi
  health_check
}

view_logs() {
  clear
  title "查看脚本日志"
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 120 "$LOG_FILE"
  else
    warn "暂无日志。"
  fi
}

uninstall_hint() {
  clear
  title "卸载提示"
  echo "建议用官方菜单卸载，避免残留配置："
  echo "  vasma"
  echo
  echo "然后在菜单里选择卸载相关功能。"
  echo
  echo "如只想删除本个性化管理脚本："
  echo "  rm -f $SELF_PATH $ALIAS_PATH"
}

main_menu() {
  need_root
  touch "$LOG_FILE" 2>/dev/null || true

  while true; do
    clear
    echo "=================================================="
    echo "  $SERVER_NAME 个性化 v2ray-agent 管理器 v$VERSION"
    echo "=================================================="
    echo "  1. 查看 VPS 系统信息"
    echo "  2. 检测是否为 mack-a v2ray-agent 安装"
    echo "  3. 安装/更新 v2ray-agent 官方脚本"
    echo "  4. 打开 v2ray-agent 菜单 vasma"
    echo "  5. 配置 UFW 常用防火墙端口"
    echo "  6. 自定义放行端口"
    echo "  7. 开启 BBR"
    echo "  8. 安全速度优化：BBR + TCP 参数"
    echo "  9. 回滚本脚本速度优化"
    echo " 10. 安全加固：fail2ban 防 SSH 爆破"
    echo " 11. DNS 优化：VPS 自身解析"
    echo " 12. 备份 v2ray-agent/Xray/sing-box/nginx 配置"
    echo " 13. 查看备份列表"
    echo " 14. 修复/重启 xray/sing-box/nginx"
    echo " 15. 核心配置语法检查"
    echo " 16. 流媒体 / Grok / AI 连通性检测"
    echo " 17. 轻量网络测速"
    echo " 18. 安全体检"
    echo " 19. 查看 VLESS-Reality 客户端推荐模板"
    echo " 20. 查看节点/订阅提示"
    echo " 21. 健康检查"
    echo " 22. 推荐优化流程：备份 + 优化 + 安全"
    echo " 23. 安装短命令 rn"
    echo " 24. 自更新本管理脚本"
    echo " 25. 查看脚本日志"
    echo " 26. 版本信息"
    echo " 27. 卸载提示"
    echo "  0. 退出"
    echo "=================================================="
    read -rp "请选择 [0-27]: " choice

    case "$choice" in
      1) show_server_info; pause ;;
      2) check_v2ray_agent; pause ;;
      3) install_or_update_agent; pause ;;
      4) open_agent_menu ;;
      5) configure_firewall; pause ;;
      6) custom_firewall_port; pause ;;
      7) enable_bbr; pause ;;
      8) speed_tune_safe; pause ;;
      9) rollback_speed_tune; pause ;;
      10) install_fail2ban_safe; pause ;;
      11) optimize_dns_safe; pause ;;
      12) backup_agent_configs; pause ;;
      13) list_backups; pause ;;
      14) repair_core_services; pause ;;
      15) validate_core_configs; pause ;;
      16) media_ai_check_light; pause ;;
      17) network_speed_light; pause ;;
      18) security_audit; pause ;;
      19) show_client_reality_template; pause ;;
      20) show_account_hint; pause ;;
      21) health_check; pause ;;
      22) recommended_flow; pause ;;
      23) install_self_alias; pause ;;
      24) self_update; pause ;;
      25) view_logs; pause ;;
      26) show_version; pause ;;
      27) uninstall_hint; pause ;;
      0) exit 0 ;;
      *) warn "无效选择"; sleep 1 ;;
    esac
  done
}

main_menu
