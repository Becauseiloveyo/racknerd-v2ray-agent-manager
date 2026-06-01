#!/usr/bin/env bash
# racknerd_v2ray_agent_manager.sh
# Clean Edition：个性化 VPS 管理脚本。
# 功能：检测/安装/启动 mack-a v2ray-agent，优化速度/安全，并做流媒体与 AI 服务可用性检测。
# 适用：Debian 12 / Ubuntu，建议 root 执行。
# 说明：
# 1) 本脚本本身不加入广告、推广链接或无关输出。
# 2) 本脚本不会“保证解锁”任何平台；流媒体/AI 可用性主要取决于 IP 地区、IP 信誉、平台风控和客户端设置。
# 3) 本脚本通过官方 GitHub 源下载 v2ray-agent，不魔改官方项目版权/许可信息。

set -Eeuo pipefail

# ===== 可按需修改的个性化配置 =====
SERVER_NAME="RackNerd-Debian12"
V2RAY_AGENT_URL="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
INSTALL_PATH="/root/install.sh"
AGENT_DIR="/etc/v2ray-agent"
LOG_FILE="/var/log/racknerd_v2ray_agent_manager.log"
BACKUP_DIR="/root/vps-backups"

# 你的常用 VLESS-Reality 客户端模板；不要把 UUID/ShortId/PrivateKey 写进公开脚本。
CLIENT_PORT_DEFAULT="15593"
CLIENT_FLOW_DEFAULT="xtls-rprx-vision"
CLIENT_NETWORK_DEFAULT="tcp"
CLIENT_SECURITY_DEFAULT="reality"
CLIENT_FINGERPRINT_DEFAULT="chrome"
CLIENT_MUX_DEFAULT="off"

# 常用放行端口；按你的实际方案修改。
# Reality 通常只需要 22 + 节点端口；如果走 443，也放行 443。
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
NC='\033[0m'

log() {
  mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true
  echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

ok() { log "${GREEN}✅ $*${NC}"; }
warn() { log "${YELLOW}⚠️  $*${NC}"; }
err() { log "${RED}❌ $*${NC}"; }
info() { log "${BLUE}ℹ️  $*${NC}"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 执行：sudo bash $0"
    exit 1
  fi
}

pause() {
  read -rp "按回车继续..." _ || true
}

install_base_tools() {
  info "安装/检查基础工具..."
  if command -v apt >/dev/null 2>&1; then
    apt update
    apt install -y curl wget ca-certificates unzip tar socat cron lsof ufw net-tools dnsutils jq iproute2 sudo util-linux fail2ban
    systemctl enable --now cron >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget ca-certificates unzip tar socat cronie lsof net-tools bind-utils jq iproute sudo util-linux fail2ban
    systemctl enable --now crond >/dev/null 2>&1 || true
  else
    warn "未识别 apt/yum，请手动安装 curl/wget/socat/cron/jq/fail2ban。"
  fi
}

show_server_info() {
  clear
  echo "========== $SERVER_NAME 系统信息 =========="
  echo "主机名: $(hostname)"
  echo "系统: $(grep -PRE '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"' || true)"
  echo "内核: $(uname -r)"
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
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)"' 2>/dev/null || true
  echo "=========================================="
}

check_v2ray_agent() {
  clear
  echo "========== v2ray-agent 检测 =========="

  if command -v vasma >/dev/null 2>&1; then
    ok "发现脚本快捷命令：$(command -v vasma)"
  else
    warn "未发现 vasma 命令"
  fi

  if command -v vasmad >/dev/null 2>&1; then
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
  for svc in xray sing-box nginx hysteria-server tuic; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      echo "--- $svc ---"
      systemctl --no-pager --lines=4 status "$svc" || true
    fi
  done

  echo
  echo "端口监听："
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
  echo "======================================"
}

open_agent_menu() {
  if command -v vasma >/dev/null 2>&1; then
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

  if ! wget -O "$INSTALL_PATH" --no-check-certificate "$V2RAY_AGENT_URL"; then
    err "下载失败。请检查 VPS 网络或稍后重试。"
    exit 1
  fi

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
  echo "========== 配置 UFW 防火墙 =========="
  if ! command -v ufw >/dev/null 2>&1; then
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

enable_bbr() {
  clear
  need_root
  echo "========== 开启 BBR =========="
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
  echo "========== 安全速度优化 =========="
  warn "这是通用 TCP/队列优化，不会修改 v2ray-agent 节点配置。"
  cat >/etc/sysctl.d/98-racknerd-speed-safe.conf <<'EOF'
# RackNerd 1G RAM VPS safe network tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=1024 65535
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
  sysctl --system
  ok "速度优化已应用。"
  echo
  echo "当前拥塞控制："
  sysctl net.ipv4.tcp_congestion_control || true
}

install_fail2ban_safe() {
  clear
  need_root
  echo "========== SSH 防爆破保护 =========="
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
  echo "========== DNS 优化 =========="
  warn "此项只优化 VPS 自身解析；客户端是否走代理 DNS 取决于你的客户端分流设置。"

  if systemctl list-unit-files | grep -q '^systemd-resolved.service'; then
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
  echo "========== 备份节点配置 =========="
  mkdir -p "$BACKUP_DIR"
  local out="$BACKUP_DIR/v2ray-agent-backup-$(date +%F_%H%M%S).tar.gz"
  tar --ignore-failed-read -czf "$out" \
    /etc/v2ray-agent \
    /usr/local/etc/xray \
    /usr/local/etc/sing-box \
    /etc/nginx/conf.d \
    /etc/nginx/sites-enabled \
    2>/dev/null || true
  chmod 600 "$out" || true
  ok "已备份到：$out"
  warn "备份里可能含 UUID、私钥、证书等敏感信息，不要发给别人。"
}

repair_core_services() {
  clear
  need_root
  echo "========== 修复/重启核心服务 =========="
  for svc in xray sing-box nginx; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        ok "$svc 正在运行"
      else
        warn "$svc 未运行，尝试启动..."
        systemctl restart "$svc" || true
      fi
      systemctl --no-pager --lines=4 status "$svc" || true
      echo
    fi
  done
}

show_client_reality_template() {
  clear
  echo "========== VLESS-Reality 客户端推荐模板 =========="
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
  echo "==============================================="
}

site_head_check() {
  local name="$1"
  local url="$2"
  local code time_total final_url remote_ip

  code=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  time_total=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{time_total}' "$url" 2>/dev/null || echo "-1")
  final_url=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{url_effective}' "$url" 2>/dev/null || echo "-")
  remote_ip=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{remote_ip}' "$url" 2>/dev/null || echo "-")

  printf "%-18s HTTP:%-4s 耗时:%-8s 远端:%-15s 最终:%s\n" "$name" "$code" "$time_total" "$remote_ip" "$final_url"
}

media_ai_check_light() {
  clear
  echo "========== 流媒体 / Grok / AI 服务可用性检测 =========="
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
  echo "===================================================="
}

show_account_hint() {
  clear
  echo "========== 查看节点/订阅提示 =========="
  echo "如果已经安装 v2ray-agent："
  echo "  1) 输入 vasma"
  echo "  2) 选择：账号管理"
  echo "  3) 选择：查看账号 或 查看订阅"
  echo
  echo "快捷打开："
  echo "  vasma"
  echo "======================================"
}

health_check() {
  clear
  echo "========== 健康检查 =========="
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
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
      systemctl is-active "$svc" >/dev/null 2>&1 && ok "$svc 运行中" || warn "$svc 未运行"
    fi
  done
  echo

  echo "[5] 常用端口监听"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
  echo "======================================"
}

uninstall_hint() {
  clear
  echo "========== 卸载提示 =========="
  echo "建议用官方菜单卸载，避免残留配置："
  echo "  vasma"
  echo
  echo "然后在菜单里选择卸载相关功能。"
  echo
  echo "如只想删除本个性化管理脚本："
  echo "  rm -f /root/racknerd_v2ray_agent_manager.sh"
  echo "================================"
}

main_menu() {
  need_root
  touch "$LOG_FILE" 2>/dev/null || true

  while true; do
    clear
    echo "=================================================="
    echo "  $SERVER_NAME 个性化 v2ray-agent 管理器 Clean Edition"
    echo "=================================================="
    echo "  1. 查看 VPS 系统信息"
    echo "  2. 检测是否为 mack-a v2ray-agent 安装"
    echo "  3. 安装/更新 v2ray-agent 官方脚本"
    echo "  4. 打开 v2ray-agent 菜单 vasma"
    echo "  5. 配置 UFW 防火墙"
    echo "  6. 开启 BBR"
    echo "  7. 安全速度优化：BBR + TCP 参数"
    echo "  8. 安全加固：fail2ban 防 SSH 爆破"
    echo "  9. DNS 优化：VPS 自身解析"
    echo " 10. 备份 v2ray-agent/Xray/sing-box/nginx 配置"
    echo " 11. 修复/重启 xray/sing-box/nginx"
    echo " 12. 流媒体 / Grok / AI 连通性检测"
    echo " 13. 查看你的 VLESS-Reality 客户端推荐模板"
    echo " 14. 查看节点/订阅提示"
    echo " 15. 健康检查"
    echo " 16. 卸载提示"
    echo "  0. 退出"
    echo "=================================================="
    read -rp "请选择 [0-16]: " choice

    case "$choice" in
      1) show_server_info; pause ;;
      2) check_v2ray_agent; pause ;;
      3) install_or_update_agent; pause ;;
      4) open_agent_menu ;;
      5) configure_firewall; pause ;;
      6) enable_bbr; pause ;;
      7) speed_tune_safe; pause ;;
      8) install_fail2ban_safe; pause ;;
      9) optimize_dns_safe; pause ;;
      10) backup_agent_configs; pause ;;
      11) repair_core_services; pause ;;
      12) media_ai_check_light; pause ;;
      13) show_client_reality_template; pause ;;
      14) show_account_hint; pause ;;
      15) health_check; pause ;;
      16) uninstall_hint; pause ;;
      0) exit 0 ;;
      *) warn "无效选择"; sleep 1 ;;
    esac
  done
}

main_menu
