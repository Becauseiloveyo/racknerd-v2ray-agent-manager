#!/usr/bin/env bash
# racknerd_v2ray_agent_manager.sh
# RackNerd VPS 管理脚本 - 个人版
#
# 这不是 v2ray-agent 官方项目。
# 这个脚本只做安装入口、检测、备份、加固和常用维护；
# v2ray-agent 本体仍从 mack-a 的官方 GitHub 源下载。

set -Eeuo pipefail

VERSION="1.1.1"
REPO_RAW_BASE="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
SELF_URL="$REPO_RAW_BASE/racknerd_v2ray_agent_manager.sh"
V2RAY_AGENT_URL="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"

SERVER_NAME="RackNerd-Debian12"
INSTALL_PATH="/root/install.sh"
SELF_PATH="/root/racknerd_v2ray_agent_manager.sh"
AGENT_DIR="/etc/v2ray-agent"
LOG_FILE="/var/log/racknerd_v2ray_agent_manager.log"
BACKUP_DIR="/root/vps-backups"
LOCK_FILE="/tmp/racknerd_v2ray_agent_manager.lock"
ALIAS_PATH="/usr/local/bin/rn"

CLIENT_PORT_DEFAULT="15593"
CLIENT_FLOW_DEFAULT="xtls-rprx-vision"
CLIENT_NETWORK_DEFAULT="tcp"
CLIENT_SECURITY_DEFAULT="reality"
CLIENT_FINGERPRINT_DEFAULT="chrome"
CLIENT_MUX_DEFAULT="off"

OPEN_PORTS=(22 80 443 15593)

CHECK_SITES=(
  "Netflix|https://www.netflix.com/"
  "Fast|https://fast.com/"
  "Disney+|https://www.disneyplus.com/"
  "PrimeVideo|https://www.primevideo.com/"
  "YouTube|https://www.youtube.com/"
  "Grok|https://grok.com/"
  "xAI|https://x.ai/"
  "X|https://x.com/"
  "OpenAI|https://chat.openai.com/"
)

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

ok() { log "${GREEN}[OK] $*${NC}"; }
warn() { log "${YELLOW}[注意] $*${NC}"; }
err() { log "${RED}[错误] $*${NC}"; }
info() { log "${BLUE}[信息] $*${NC}"; }
title() { echo -e "${CYAN}========== $* ==========${NC}"; }

on_error() {
  local line="$1"
  local cmd="$2"
  err "第 ${line} 行出错：${cmd}"
  err "日志：$LOG_FILE"
}
trap 'on_error ${LINENO} "$BASH_COMMAND"' ERR

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    err "脚本已经在另一个窗口运行。"
    exit 1
  fi
fi

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请用 root 执行：sudo bash $0"
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
    warn "没识别到 apt/dnf/yum，请手动安装：${pkgs[*]}"
  fi
}

install_base_tools() {
  info "检查基础工具"
  if has_cmd apt-get; then
    pkg_install curl wget ca-certificates unzip tar socat cron lsof ufw net-tools dnsutils jq iproute2 sudo util-linux fail2ban openssl
    systemctl enable --now cron >/dev/null 2>&1 || true
  elif has_cmd dnf || has_cmd yum; then
    pkg_install curl wget ca-certificates unzip tar socat cronie lsof net-tools bind-utils jq iproute sudo util-linux fail2ban openssl
    systemctl enable --now crond >/dev/null 2>&1 || true
  else
    warn "请手动安装 curl/wget/socat/cron/jq/fail2ban"
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
    err "缺少 curl 或 wget"
    return 1
  fi
}

show_version() {
  clear
  title "版本"
  echo "版本: $VERSION"
  echo "脚本: $SELF_PATH"
  echo "短命令: $ALIAS_PATH"
  echo "日志: $LOG_FILE"
  echo "项目: $REPO_RAW_BASE"
}

install_self_alias() {
  clear
  need_root
  title "安装 rn 短命令"
  cat >"$ALIAS_PATH" <<EOF
#!/usr/bin/env bash
bash "$SELF_PATH" "\$@"
EOF
  chmod +x "$ALIAS_PATH"
  ok "完成。以后输入 rn 就能打开菜单。"
}

self_update() {
  clear
  need_root
  title "更新脚本"
  local tmp="/tmp/racknerd_v2ray_agent_manager.$$.sh"
  info "下载：$SELF_URL"
  download_file "$SELF_URL" "$tmp"
  if ! bash -n "$tmp"; then
    err "新脚本语法检查没过，已取消。"
    rm -f "$tmp"
    return 1
  fi
  cp -a "$SELF_PATH" "$SELF_PATH.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  install -m 700 "$tmp" "$SELF_PATH"
  rm -f "$tmp"
  ok "已更新。重新打开菜单即可。"
}

show_server_info() {
  clear
  title "$SERVER_NAME 信息"
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
  echo "IP 信息:"
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)\n时区: \(.timezone)"' 2>/dev/null || true
}

check_v2ray_agent() {
  clear
  title "v2ray-agent 检测"

  if has_cmd vasma; then
    ok "vasma: $(command -v vasma)"
  else
    warn "没找到 vasma"
  fi

  if has_cmd vasmad; then
    ok "vasmad: $(command -v vasmad)"
  else
    warn "没找到 vasmad"
  fi

  if [[ -d "$AGENT_DIR" ]]; then
    ok "目录存在：$AGENT_DIR"
    ls -la "$AGENT_DIR" | sed 's/^/  /'
  else
    warn "目录不存在：$AGENT_DIR"
  fi

  echo
  echo "服务状态:"
  for svc in xray sing-box nginx hysteria-server tuic fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      echo "--- $svc ---"
      systemctl --no-pager --lines=4 status "$svc" || true
    fi
  done

  echo
  echo "端口监听:"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
}

open_agent_menu() {
  if has_cmd vasma; then
    vasma
  elif [[ -x "$AGENT_DIR/install.sh" ]]; then
    bash "$AGENT_DIR/install.sh"
  else
    err "没找到 vasma，也没找到 $AGENT_DIR/install.sh"
    pause
  fi
}

download_agent() {
  info "下载 v2ray-agent 官方脚本"
  rm -f "$INSTALL_PATH"
  download_file "$V2RAY_AGENT_URL" "$INSTALL_PATH"
  chmod 700 "$INSTALL_PATH"
  ok "已保存：$INSTALL_PATH"
}

install_or_update_agent() {
  clear
  need_root
  install_base_tools
  download_agent
  info "接下来进入 v2ray-agent 官方菜单。"
  bash "$INSTALL_PATH"
}

configure_firewall() {
  clear
  need_root
  title "放行常用端口"
  if ! has_cmd ufw; then
    install_base_tools
  fi

  for port in "${OPEN_PORTS[@]}"; do
    ufw allow "${port}/tcp" || true
    ufw allow "${port}/udp" || true
  done

  ufw --force enable
  ufw status verbose
  ok "已放行：${OPEN_PORTS[*]}"
}

custom_firewall_port() {
  clear
  need_root
  title "自定义端口"
  if ! has_cmd ufw; then
    install_base_tools
  fi

  local port proto
  read -rp "端口，例如 443 或 15593: " port
  if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || (( port < 1 || port > 65535 )); then
    err "端口不对。"
    return 1
  fi

  read -rp "协议 tcp/udp/both [both]: " proto
  proto="${proto:-both}"
  case "$proto" in
    tcp) ufw allow "${port}/tcp" ;;
    udp) ufw allow "${port}/udp" ;;
    both) ufw allow "${port}/tcp"; ufw allow "${port}/udp" ;;
    *) err "协议不对。"; return 1 ;;
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
  ok "完成。"
}

speed_tune_safe() {
  clear
  need_root
  title "网络参数优化"
  warn "只改系统 TCP 参数，不改节点配置。"
  cp -a /etc/sysctl.conf "/etc/sysctl.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  cat >/etc/sysctl.d/98-racknerd-speed-safe.conf <<'EOF'
# RackNerd VPS network tuning
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
  ok "完成。"
  sysctl net.ipv4.tcp_congestion_control || true
}

rollback_speed_tune() {
  clear
  need_root
  title "回滚网络优化"
  rm -f /etc/sysctl.d/98-racknerd-speed-safe.conf /etc/sysctl.d/99-racknerd-bbr.conf
  sysctl --system || true
  ok "已移除本脚本写入的 sysctl 文件。"
}

install_fail2ban_safe() {
  clear
  need_root
  title "SSH 防爆破"
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
  ok "fail2ban 已开启。"
}

optimize_dns_safe() {
  clear
  need_root
  title "DNS"
  warn "这里只改 VPS 自己的解析。客户端分流和 DNS 还要看你的客户端设置。"

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
    ok "已设置 systemd-resolved。"
  else
    cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    ok "已写入 /etc/resolv.conf。"
  fi
}

backup_agent_configs() {
  clear
  need_root
  title "备份"
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
  ok "备份文件：$out"
  warn "备份里可能有 UUID、私钥、证书，不要发给别人。"
}

list_backups() {
  clear
  title "备份列表"
  mkdir -p "$BACKUP_DIR"
  ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || warn "还没有备份。"
}

repair_core_services() {
  clear
  need_root
  title "重启核心服务"
  for svc in xray sing-box nginx; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        ok "$svc 正在运行，准备重启。"
      else
        warn "$svc 没在运行，准备启动。"
      fi
      systemctl restart "$svc" || true
      systemctl --no-pager --lines=6 status "$svc" || true
      echo
    fi
  done
}

validate_core_configs() {
  clear
  title "配置检查"

  if has_cmd xray; then
    echo "--- xray ---"
    xray version || true
    [[ -f /usr/local/etc/xray/config.json ]] && xray -test -config /usr/local/etc/xray/config.json || true
    echo
  else
    warn "没找到 xray。"
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
    warn "没找到 sing-box。"
  fi

  if has_cmd nginx; then
    echo "--- nginx ---"
    nginx -t || true
  else
    warn "没找到 nginx。"
  fi
}

show_client_reality_template() {
  clear
  title "VLESS-Reality 参数参考"
  echo "别名 remarks:       自己命名，例如 RackNerd-Reality"
  echo "地址 address:       VPS IP 或解析到 VPS 的域名"
  echo "端口 port:          $CLIENT_PORT_DEFAULT，必须和服务端一致"
  echo "用户 ID id:         在 vasma 里查看，不要公开"
  echo "流控 flow:          $CLIENT_FLOW_DEFAULT"
  echo "加密 encryption:    none"
  echo "传输 network:       $CLIENT_NETWORK_DEFAULT"
  echo "伪装 type:          none"
  echo "TLS/security:       $CLIENT_SECURITY_DEFAULT"
  echo "SNI/serverName:     按 vasma 输出填写"
  echo "Fingerprint:        $CLIENT_FINGERPRINT_DEFAULT"
  echo "PublicKey:          按 vasma 输出填写"
  echo "ShortId:            按 vasma 输出填写，不要公开"
  echo "SpiderX:            留空或按 vasma 输出"
  echo "Mux:                $CLIENT_MUX_DEFAULT"
  echo
  warn "如果截图发过节点参数，建议在 vasma 里重置用户。"
}

site_head_check() {
  local name="$1"
  local url="$2"
  local data code time_total final_url remote_ip
  data=$(curl -4 -L -sS -o /dev/null --connect-timeout 5 --max-time 15 -w '%{http_code}|%{time_total}|%{remote_ip}|%{url_effective}' "$url" 2>/dev/null || echo "000|-1|-|-")
  IFS='|' read -r code time_total remote_ip final_url <<<"$data"
  printf "%-14s HTTP:%-4s 耗时:%-8s 远端:%-15s %s\n" "$name" "$code" "$time_total" "$remote_ip" "$final_url"
}

service_check_light() {
  clear
  title "流媒体 / Grok / OpenAI 连通性"
  warn "这里只看 VPS 出口能不能连上。能连上不等于账号或片库一定可用。"
  echo
  echo "[1] 出口 IP"
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)\n时区: \(.timezone)"' 2>/dev/null || true
  echo
  echo "[2] 连通性"
  for item in "${CHECK_SITES[@]}"; do
    IFS='|' read -r name url <<<"$item"
    site_head_check "$name" "$url"
  done
  echo
  echo "说明："
  echo "- HTTP 200/301/302 只说明能访问。"
  echo "- Netflix、Grok、OpenAI 还会看 IP、账号、地区和客户端 DNS。"
  echo "- 客户端建议关闭 Mux，Reality fingerprint 用 chrome。"
}

network_speed_light() {
  clear
  title "轻量测速"
  warn "下载约 10MB，只做粗略参考。"
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
  title "安全检查"
  echo "[1] SSH"
  if [[ -f /etc/ssh/sshd_config ]]; then
    grep -Ei '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port)\b' /etc/ssh/sshd_config || true
  fi
  echo

  echo "[2] 防火墙"
  if has_cmd ufw; then
    ufw status verbose || true
  else
    warn "没安装 ufw。"
  fi
  echo

  echo "[3] fail2ban"
  if has_cmd fail2ban-client; then
    fail2ban-client status || true
  else
    warn "没安装 fail2ban。"
  fi
  echo

  echo "[4] 提醒"
  warn "不要公开 /etc/v2ray-agent、节点链接、订阅链接和备份压缩包。"
  warn "截图露出 UUID / ShortId / PublicKey 后，最好重置用户。"
}

show_account_hint() {
  clear
  title "查看节点"
  echo "已安装 v2ray-agent 的情况下："
  echo "  1) 输入 vasma"
  echo "  2) 进账号管理"
  echo "  3) 查看账号或订阅"
}

health_check() {
  clear
  title "健康检查"
  echo "[1] 资源"
  uptime || true
  free -h || true
  df -h / || true
  echo

  echo "[2] 网络"
  ping -c 3 1.1.1.1 || true
  echo

  echo "[3] 公网 IP"
  echo -n "IPv4: "; curl -4 -s --max-time 5 https://api.ipify.org || true; echo
  echo -n "IPv6: "; curl -6 -s --max-time 5 https://api64.ipify.org || true; echo
  echo

  echo "[4] 服务"
  for svc in xray sing-box nginx fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      systemctl is-active "$svc" >/dev/null 2>&1 && ok "$svc 运行中" || warn "$svc 未运行"
    fi
  done
  echo

  echo "[5] 端口"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
}

recommended_flow() {
  clear
  need_root
  title "建议流程"
  warn "先备份，再改参数。"
  if confirm "先备份配置"; then backup_agent_configs; fi
  if confirm "应用网络参数优化"; then speed_tune_safe; fi
  if confirm "开启 fail2ban"; then install_fail2ban_safe; fi
  if confirm "放行常用端口"; then configure_firewall; fi
  health_check
}

view_logs() {
  clear
  title "日志"
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 120 "$LOG_FILE"
  else
    warn "还没有日志。"
  fi
}

uninstall_hint() {
  clear
  title "卸载"
  echo "卸载 v2ray-agent："
  echo "  vasma"
  echo
  echo "只删除本脚本："
  echo "  rm -f $SELF_PATH $ALIAS_PATH"
}

main_menu() {
  need_root
  touch "$LOG_FILE" 2>/dev/null || true

  while true; do
    clear
    echo "=================================================="
    echo "  RackNerd VPS 管理脚本 v$VERSION"
    echo "=================================================="
    echo "  1. VPS 信息"
    echo "  2. 检测 v2ray-agent"
    echo "  3. 安装/更新 v2ray-agent"
    echo "  4. 打开 vasma"
    echo "  5. 放行常用端口"
    echo "  6. 自定义放行端口"
    echo "  7. 开启 BBR"
    echo "  8. 网络参数优化"
    echo "  9. 回滚网络优化"
    echo " 10. SSH 防爆破"
    echo " 11. DNS 设置"
    echo " 12. 备份配置"
    echo " 13. 查看备份"
    echo " 14. 重启核心服务"
    echo " 15. 配置检查"
    echo " 16. 流媒体/Grok/OpenAI 连通性"
    echo " 17. 轻量测速"
    echo " 18. 安全检查"
    echo " 19. VLESS-Reality 参数参考"
    echo " 20. 查看节点提示"
    echo " 21. 健康检查"
    echo " 22. 建议流程"
    echo " 23. 安装 rn 短命令"
    echo " 24. 更新本脚本"
    echo " 25. 查看日志"
    echo " 26. 版本"
    echo " 27. 卸载提示"
    echo "  0. 退出"
    echo "=================================================="
    read -rp "选择 [0-27]: " choice

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
      16) service_check_light; pause ;;
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
