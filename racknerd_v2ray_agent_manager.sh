#!/usr/bin/env bash
# racknerd_v2ray_agent_manager.sh
# RackNerd VPS 管理脚本 - 个人版
#
# 这不是 v2ray-agent 官方项目。
# 这个脚本只做入口、检测、备份、加固和常用维护；
# v2ray-agent 本体仍从 mack-a 的官方 GitHub 源下载。

set -Eeuo pipefail

VERSION="1.3.0"
REPO_RAW_BASE="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
SELF_URL="$REPO_RAW_BASE/racknerd_v2ray_agent_manager.sh"
PLATFORM_CHECK_URL="$REPO_RAW_BASE/platform_check.sh"
V2RAY_AGENT_URL="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"

SERVER_NAME="RackNerd-Debian12"
SELF_PATH="/root/racknerd_v2ray_agent_manager.sh"
INSTALL_PATH="/root/install.sh"
AGENT_DIR="/etc/v2ray-agent"
BACKUP_DIR="/root/vps-backups"
REPORT_DIR="/root/vps-reports"
LOG_FILE="/var/log/racknerd_v2ray_agent_manager.log"
LOCK_FILE="/tmp/racknerd_v2ray_agent_manager.lock"
ALIAS_PATH="/usr/local/bin/rn"

CLIENT_PORT_DEFAULT="15593"
CLIENT_FLOW_DEFAULT="xtls-rprx-vision"
CLIENT_NETWORK_DEFAULT="tcp"
CLIENT_SECURITY_DEFAULT="reality"
CLIENT_FINGERPRINT_DEFAULT="chrome"
CLIENT_MUX_DEFAULT="off"
OPEN_PORTS=(22 80 443 15593)

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; PURPLE='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; PURPLE=''; BOLD=''; DIM=''; NC=''
fi

log() {
  mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true
  echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

ok() { log "${GREEN}[OK]${NC} $*"; }
warn() { log "${YELLOW}[注意]${NC} $*"; }
err() { log "${RED}[错误]${NC} $*"; }
info() { log "${BLUE}[信息]${NC} $*"; }

pause() { read -rp "按回车返回菜单..." _ || true; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请用 root 执行：sudo bash $0"
    exit 1
  fi
}

confirm() {
  local ans
  read -rp "$1 [y/N]: " ans || true
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

if has_cmd flock; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    err "脚本已经在另一个窗口运行。"
    exit 1
  fi
fi

on_error() {
  err "第 $1 行出错：$2"
  err "可以看日志：$LOG_FILE"
}
trap 'on_error ${LINENO} "$BASH_COMMAND"' ERR

line() { echo -e "${DIM}--------------------------------------------------${NC}"; }
section() { echo -e "\n${PURPLE}$1${NC}"; line; }

page_title() {
  clear
  echo -e "${CYAN}==================================================${NC}"
  echo -e "  ${BOLD}$1${NC}"
  echo -e "${CYAN}==================================================${NC}"
}

note_box() {
  echo
  echo -e "${CYAN}说明${NC}"
  line
  printf '%b\n' "$1"
}

result_box() {
  echo
  echo -e "${GREEN}结果${NC}"
  line
  printf '%b\n' "$1"
}

next_box() {
  echo
  echo -e "${YELLOW}下一步${NC}"
  line
  printf '%b\n' "$1"
}

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
  info "检查基础工具：curl、wget、jq、ufw、fail2ban 等"
  if has_cmd apt-get; then
    pkg_install curl wget ca-certificates unzip tar socat cron lsof ufw net-tools dnsutils jq iproute2 sudo util-linux fail2ban openssl
    systemctl enable --now cron >/dev/null 2>&1 || true
  elif has_cmd dnf || has_cmd yum; then
    pkg_install curl wget ca-certificates unzip tar socat cronie lsof net-tools bind-utils jq iproute sudo util-linux fail2ban openssl
    systemctl enable --now crond >/dev/null 2>&1 || true
  else
    warn "请手动安装 curl/wget/jq/ufw/fail2ban"
  fi
}

download_file() {
  local url="$1" out="$2"
  if has_cmd curl; then
    curl -fsSL --connect-timeout 10 --max-time 60 -o "$out" "$url"
  elif has_cmd wget; then
    wget -q --timeout=30 -O "$out" "$url"
  else
    err "缺少 curl 或 wget"
    return 1
  fi
}

service_state_text() {
  local svc="$1"
  if ! systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
    echo "未安装"
  elif systemctl is-active "$svc" >/dev/null 2>&1; then
    echo "运行中"
  else
    echo "未运行"
  fi
}

show_server_info() {
  page_title "VPS 信息"
  note_box "这个页面用来确认 VPS 的系统、资源、公网 IP 和机房信息。\n如果你要排查速度、平台连通性，先看这里。"

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
  if has_cmd jq; then
    curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)\n时区: \(.timezone)"' 2>/dev/null || true
  else
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
  fi

  result_box "看重点：\n- 内存和磁盘不要长期接近 100%。\n- IP 国家/地区会影响 Netflix、Grok、OpenAI 等平台显示。\n- ASN/Org 如果是普通机房，部分平台可能更容易风控。"
}

check_v2ray_agent() {
  page_title "检测 v2ray-agent"
  note_box "这个功能只负责检查当前 VPS 上有没有 v2ray-agent 常见目录、vasma 命令、核心服务和端口。"

  local has_vasma="否" has_dir="否"
  if has_cmd vasma; then
    has_vasma="是"
    ok "找到 vasma：$(command -v vasma)"
  else
    warn "没有找到 vasma"
  fi

  if has_cmd vasmad; then
    ok "找到 vasmad：$(command -v vasmad)"
  else
    warn "没有找到 vasmad"
  fi

  if [[ -d "$AGENT_DIR" ]]; then
    has_dir="是"
    ok "找到目录：$AGENT_DIR"
  else
    warn "没有找到目录：$AGENT_DIR"
  fi

  echo
  echo "服务状态："
  for svc in xray sing-box nginx hysteria-server tuic fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        echo -e "  ${GREEN}$svc：运行中${NC}"
      else
        echo -e "  ${YELLOW}$svc：未运行${NC}"
      fi
    fi
  done

  echo
  echo "常见端口监听："
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || echo "没有看到常见端口监听，可能端口不是这些。"

  result_box "vasma 命令：$has_vasma\n配置目录：$has_dir"
  next_box "如果 vasma 和目录都存在，基本就是已经装过。\n想进原脚本菜单，回主菜单选 4。\n如果都没有，回主菜单选 3 安装。"
}

open_agent_menu() {
  page_title "打开 vasma"
  note_box "这里会进入 mack-a/v2ray-agent 的上游菜单。\n里面的作者信息、版本信息和推广区来自上游脚本，不是本脚本加的。"

  if has_cmd vasma; then
    vasma
  elif [[ -x "$AGENT_DIR/install.sh" ]]; then
    bash "$AGENT_DIR/install.sh"
  else
    err "没找到 vasma，也没找到 $AGENT_DIR/install.sh"
    next_box "先回主菜单选 3 安装/更新 v2ray-agent。"
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
  page_title "安装/更新 v2ray-agent"
  note_box "这个功能会下载 mack-a/v2ray-agent 的官方 install.sh，然后进入它自己的菜单。\n第一次搭建、重装、升级都可以从这里进。"
  install_base_tools
  download_agent
  next_box "接下来会进入上游菜单。\n第一次使用可以选“一键无域名Reality”或按你自己的需要安装。"
  pause
  bash "$INSTALL_PATH"
}

configure_firewall() {
  page_title "放行常用端口"
  note_box "放行 SSH、Web 和你当前常用的 Reality 端口。\n当前默认端口：${OPEN_PORTS[*]}"
  if ! has_cmd ufw; then install_base_tools; fi
  for port in "${OPEN_PORTS[@]}"; do
    ufw allow "${port}/tcp" || true
    ufw allow "${port}/udp" || true
  done
  ufw --force enable
  ufw status verbose
  result_box "常用端口已放行。"
  next_box "客户端端口必须和服务端一致。\n如果你的节点不是 15593，回菜单选 6 自定义放行端口。"
}

custom_firewall_port() {
  page_title "自定义放行端口"
  note_box "节点换端口以后，防火墙也要放行同一个端口。"
  if ! has_cmd ufw; then install_base_tools; fi
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
  result_box "端口 $port 已放行。"
}

enable_bbr() {
  page_title "开启 BBR"
  note_box "BBR 是 Linux 的 TCP 拥塞控制算法。\n一般可以改善跨境线路的速度和稳定性。"
  cat >/etc/sysctl.d/99-racknerd-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system
  echo
  sysctl net.ipv4.tcp_congestion_control || true
  result_box "如果上面显示 net.ipv4.tcp_congestion_control = bbr，说明已经开启。"
}

speed_tune_safe() {
  page_title "网络参数优化"
  note_box "这个功能只改系统 TCP 参数，不改节点配置。\n会先备份 /etc/sysctl.conf。"
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
  result_box "网络参数已写入 /etc/sysctl.d/98-racknerd-speed-safe.conf。"
  next_box "如果优化后感觉异常，回菜单选 9 回滚网络优化。"
}

rollback_speed_tune() {
  page_title "回滚网络优化"
  note_box "只删除本脚本写入的 sysctl 优化文件，不会卸载 v2ray-agent。"
  rm -f /etc/sysctl.d/98-racknerd-speed-safe.conf /etc/sysctl.d/99-racknerd-bbr.conf
  sysctl --system || true
  result_box "已移除本脚本写入的网络优化文件。"
}

install_fail2ban_safe() {
  page_title "SSH 防爆破"
  note_box "fail2ban 会自动封禁短时间内多次尝试 SSH 登录失败的 IP。\n适合直接暴露 22 端口的 VPS。"
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
  result_box "fail2ban 已开启。看到 Jail list 或 sshd 状态就正常。"
}

optimize_dns_safe() {
  page_title "DNS 设置"
  note_box "这里改的是 VPS 自己的 DNS。\n手机/电脑客户端有没有 DNS 泄漏，还要看客户端设置。"
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
  else
    cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
  fi
  result_box "VPS DNS 已设置。"
}

backup_agent_configs() {
  page_title "备份配置"
  note_box "会备份 v2ray-agent、Xray、sing-box、nginx 相关配置。\n备份文件可能包含 UUID、私钥、证书，不要发给别人。"
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
  result_box "备份文件：$out"
}

list_backups() {
  page_title "查看备份"
  note_box "这里只列出本脚本放在 $BACKUP_DIR 里的备份。"
  mkdir -p "$BACKUP_DIR"
  ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || warn "还没有备份。"
}

repair_core_services() {
  page_title "重启核心服务"
  note_box "节点异常、改完配置、证书更新后，可以重启 xray / sing-box / nginx。"
  for svc in xray sing-box nginx; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      echo
      echo "--- $svc ---"
      systemctl restart "$svc" || true
      if systemctl is-active "$svc" >/dev/null 2>&1; then
        ok "$svc 运行中"
      else
        warn "$svc 没运行，下面是状态信息"
      fi
      systemctl --no-pager --lines=6 status "$svc" || true
    fi
  done
  next_box "如果重启后仍不正常，回菜单选 15 做配置检查。"
}

validate_core_configs() {
  page_title "配置检查"
  note_box "这个功能检查 xray / sing-box / nginx 配置有没有明显语法错误。"
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
  result_box "如果输出里有 successful / test is successful / syntax is ok，通常说明配置没明显语法错误。\n如果出现 error、failed、invalid，就按提示里的文件和行号处理。"
}

run_platform_check() {
  page_title "平台可用性检测"
  note_box "这个检测只看 VPS 出口能不能连上平台入口。\n它不保证账号、片库、地区功能一定可用。"
  local tmp="/tmp/platform_check.$$.sh"
  download_file "$PLATFORM_CHECK_URL" "$tmp"
  chmod 700 "$tmp"
  bash "$tmp"
  rm -f "$tmp"
  next_box "如果某个平台显示 failed 或 region，多数是 IP、地区、账号或客户端 DNS 问题。\n脚本不能保证所有平台都可用。"
}

network_speed_light() {
  page_title "轻量测速"
  note_box "下载约 10MB，只做粗略参考，不等于真实晚高峰速度。"
  local url="https://speed.cloudflare.com/__down?bytes=10000000"
  local data speed time_total
  data=$(curl -4 -L -o /dev/null -sS --connect-timeout 8 --max-time 30 -w '%{speed_download}|%{time_total}' "$url" 2>/dev/null || echo "0|-1")
  IFS='|' read -r speed time_total <<<"$data"
  if [[ "$speed" != "0" ]]; then
    awk -v s="$speed" -v t="$time_total" 'BEGIN { printf "下载速度约：%.2f MB/s，耗时：%s 秒\n", s/1024/1024, t }'
    result_box "速度正常与否要结合你本地网络、VPS 地区和晚高峰情况看。"
  else
    warn "测速失败。"
  fi
}

security_audit() {
  page_title "安全检查"
  note_box "这个页面只做基础检查，不等于完整安全审计。"
  echo "[1] SSH 配置"
  if [[ -f /etc/ssh/sshd_config ]]; then
    grep -Ei '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port)\b' /etc/ssh/sshd_config || true
  fi
  echo
  echo "[2] 防火墙"
  if has_cmd ufw; then ufw status verbose || true; else warn "没安装 ufw。"; fi
  echo
  echo "[3] fail2ban"
  if has_cmd fail2ban-client; then fail2ban-client status || true; else warn "没安装 fail2ban。"; fi
  result_box "重点看：\n- 防火墙是否开启。\n- SSH 是否只放必要端口。\n- fail2ban 是否运行。\n- 节点参数和备份不要公开。"
}

show_client_reality_template() {
  page_title "VLESS-Reality 参数参考"
  note_box "按你之前截图的 VLESS + Reality + Vision 类型整理。"
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
  next_box "如果截图发过 UUID、ShortId、PublicKey，建议进 vasma 重置用户。"
}

show_account_hint() {
  page_title "查看节点提示"
  note_box "节点信息属于敏感内容，不建议截图发给别人。"
  echo "已安装 v2ray-agent 的情况下："
  echo "  1) 输入 vasma"
  echo "  2) 进账号管理"
  echo "  3) 查看账号或订阅"
}

health_check() {
  page_title "健康检查"
  note_box "快速看系统资源、网络、服务和端口。出问题时先跑这个。"
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
  result_box "如果资源正常、核心服务运行中、节点端口在监听，服务端大概率没大问题。"
}

troubleshooting_guide() {
  page_title "故障排查建议"
  note_box "这里不是直接改配置，而是按常见现象告诉你先看哪里。\n看不懂命令输出时，先选这个。"

  echo -e "${BOLD}常见问题怎么判断${NC}"
  line
  cat <<'EOF'
1) 客户端连不上节点
   先看：
   - 2. 检测 v2ray-agent：xray/sing-box 是否运行
   - 5/6. 防火墙端口：服务端端口是否放行
   - 15. 配置检查：配置有没有语法错误
   - 客户端端口、UUID、PublicKey、ShortId、SNI 是否和 vasma 输出一致

   常见原因：
   - VPS 防火墙没放行节点端口
   - 服务端重启失败
   - 客户端参数填错
   - 截图泄漏参数后被别人占用或滥用

2) 能连上但速度慢
   先看：
   - 18. 轻量测速：VPS 出口速度
   - 1. VPS 信息：IP 地区和机房
   - 8. 网络参数优化：只做系统 TCP 优化
   - 晚高峰可能是线路问题，不一定是脚本问题

   建议：
   - Reality 客户端关闭 Mux
   - Fingerprint 用 chrome
   - 不要同时开太多设备测速
   - 换机房/换 IP 往往比反复改参数有效

3) Netflix / Grok / OpenAI 不可用
   先看：
   - 17. 平台可用性检测
   - 1. VPS 信息里的国家、地区、ASN
   - 客户端 DNS 是否走代理

   说明：
   - HTTP 能连接不等于账号和内容库一定可用
   - 平台限制主要看 IP 信誉、账号地区和风控
   - 脚本不能保证所有平台都能用

4) vasma 菜单有推广区
   说明：
   - 那是 mack-a/v2ray-agent 上游菜单自带显示
   - 不是这个个人管理脚本加的
   - 本脚本只负责调用它，不修改上游作者信息

5) 证书或域名相关问题
   先看：
   - 域名 A 记录是否指向 VPS IPv4
   - 80/443 是否放行
   - nginx 是否运行
   - 系统时间是否准确

6) 更新后出问题
   先看：
   - 25. 查看日志
   - 16. 配置检查
   - 15. 重启核心服务

   建议：
   - 更新或改配置前先选 12 备份
   - 本脚本更新前会备份旧脚本
EOF

  next_box "想自动收集一份不含节点密钥的排查报告，回菜单选 29。\n如果时间不准，回菜单选 30 修复系统时间。"
}

generate_diagnostic_report() {
  page_title "生成诊断报告"
  note_box "生成一份基础报告，方便你自己排查。\n不会打包 /etc/v2ray-agent 或节点配置，不主动输出 UUID、私钥、订阅链接。"

  mkdir -p "$REPORT_DIR"
  local report="$REPORT_DIR/diagnostic-$(date +%F_%H%M%S).txt"

  {
    echo "RackNerd VPS diagnostic report"
    echo "Generated at: $(date '+%F %T %Z')"
    echo "Script version: $VERSION"
    echo
    echo "== OS =="
    echo "Hostname: $(hostname)"
    echo "System: $(os_pretty)"
    echo "Kernel: $(uname -r)"
    echo "Arch: $(uname -m)"
    echo
    echo "== Resources =="
    uptime || true
    free -h || true
    df -h / || true
    echo
    echo "== Public IP =="
    echo -n "IPv4: "; curl -4 -s --max-time 5 https://api.ipify.org || true; echo
    echo -n "IPv6: "; curl -6 -s --max-time 5 https://api64.ipify.org || true; echo
    echo
    echo "== IP info =="
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
    echo
    echo "== DNS =="
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "== Services =="
    for svc in xray sing-box nginx fail2ban; do
      echo "$svc: $(service_state_text "$svc")"
    done
    echo
    echo "== Ports =="
    ss -tulpen 2>/dev/null | grep -E ':(22|80|443|15593|8443|2053|2083|2087|2096)\b' || true
    echo
    echo "== Firewall =="
    if has_cmd ufw; then ufw status verbose || true; else echo "ufw not installed"; fi
    echo
    echo "== Time =="
    date
    timedatectl 2>/dev/null || true
    echo
    echo "== Recent script log =="
    tail -n 80 "$LOG_FILE" 2>/dev/null || true
  } > "$report"

  chmod 600 "$report" || true
  result_box "诊断报告已生成：$report"
  next_box "这份报告不包含节点配置文件，但仍可能包含你的公网 IP。\n发给别人前自己先看一遍。"
}

fix_time_sync() {
  page_title "修复系统时间"
  note_box "系统时间不准可能导致证书、TLS、Reality 连接异常。\n这个功能会开启系统 NTP 对时。"

  if has_cmd timedatectl; then
    timedatectl set-ntp true || true
    sleep 2
    timedatectl || true
    result_box "已尝试开启系统自动对时。"
  else
    warn "没有 timedatectl，尝试安装 chrony。"
    if has_cmd apt-get; then
      pkg_install chrony
      systemctl enable --now chrony || true
    elif has_cmd dnf || has_cmd yum; then
      pkg_install chrony
      systemctl enable --now chronyd || true
    fi
    date
    result_box "已尝试安装并启动 chrony。"
  fi

  next_box "如果时间仍不准，可能是 VPS 系统环境限制，重启 VPS 后再看。"
}

recommended_flow() {
  page_title "建议流程"
  note_box "适合第一次整理 VPS：先备份，再优化，再做安全检查。"
  if confirm "先备份配置"; then backup_agent_configs; fi
  if confirm "应用网络参数优化"; then speed_tune_safe; fi
  if confirm "开启 fail2ban"; then install_fail2ban_safe; fi
  if confirm "放行常用端口"; then configure_firewall; fi
  health_check
}

install_self_alias() {
  page_title "安装 rn 短命令"
  cat >"$ALIAS_PATH" <<EOF
#!/usr/bin/env bash
bash "$SELF_PATH" "\$@"
EOF
  chmod +x "$ALIAS_PATH"
  result_box "以后输入 rn 就能打开这个菜单。"
}

self_update() {
  page_title "更新本脚本"
  note_box "从你的 GitHub 仓库拉取最新版主脚本。更新前会备份旧脚本。"
  local tmp="/tmp/racknerd_v2ray_agent_manager.$$.sh"
  download_file "$SELF_URL" "$tmp"
  if ! bash -n "$tmp"; then
    err "新脚本语法检查没过，已取消。"
    rm -f "$tmp"
    return 1
  fi
  cp -a "$SELF_PATH" "$SELF_PATH.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  install -m 700 "$tmp" "$SELF_PATH"
  rm -f "$tmp"
  result_box "已更新。重新打开菜单即可。"
}

view_logs() {
  page_title "查看日志"
  note_box "这里显示最近 120 行脚本日志。"
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 120 "$LOG_FILE"
  else
    warn "还没有日志。"
  fi
}

show_version() {
  page_title "版本"
  echo "版本: $VERSION"
  echo "脚本路径: $SELF_PATH"
  echo "短命令: $ALIAS_PATH"
  echo "日志: $LOG_FILE"
  echo "报告目录: $REPORT_DIR"
  echo "仓库: $REPO_RAW_BASE"
}

uninstall_hint() {
  page_title "卸载提示"
  note_box "本脚本和 v2ray-agent 是两回事。"
  echo "卸载 v2ray-agent："
  echo "  vasma"
  echo
  echo "只删除本脚本："
  echo "  rm -f $SELF_PATH $ALIAS_PATH"
}

menu_item() {
  printf "  ${GREEN}%2s${NC}. %-28s ${DIM}%s${NC}\n" "$1" "$2" "$3"
}

main_menu() {
  need_root
  touch "$LOG_FILE" 2>/dev/null || true

  while true; do
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "  ${BOLD}RackNerd VPS 管理脚本 v$VERSION${NC}"
    echo -e "  ${DIM}不是 v2ray-agent 官方脚本，只是个人维护菜单${NC}"
    echo -e "${CYAN}==================================================${NC}"

    section "安装管理"
    menu_item 1  "VPS 信息"                 "看系统、资源、IP 和机房信息"
    menu_item 2  "检测 v2ray-agent"          "看 vasma、目录、服务、端口是否正常"
    menu_item 3  "安装/更新 v2ray-agent"     "下载并进入 mack-a 官方安装菜单"
    menu_item 4  "打开 vasma"                "进入上游 v2ray-agent 菜单"

    section "端口和网络"
    menu_item 5  "放行常用端口"              "放行 22/80/443/15593"
    menu_item 6  "自定义放行端口"            "节点换端口后用这个"
    menu_item 7  "开启 BBR"                  "常见 TCP 加速设置"
    menu_item 8  "网络参数优化"              "写入一组常用 sysctl 参数"
    menu_item 9  "回滚网络优化"              "撤回本脚本写入的网络参数"
    menu_item 10 "DNS 设置"                  "设置 VPS 自身 DNS"

    section "安全和备份"
    menu_item 11 "SSH 防爆破"                "安装并启用 fail2ban"
    menu_item 12 "备份配置"                  "备份 v2ray-agent/Xray/sing-box/nginx"
    menu_item 13 "查看备份"                  "列出已经生成的备份文件"
    menu_item 14 "安全检查"                  "看 SSH、防火墙、fail2ban 状态"

    section "维护和排查"
    menu_item 15 "重启核心服务"              "重启 xray/sing-box/nginx"
    menu_item 16 "配置检查"                  "检查核心配置有没有语法错误"
    menu_item 17 "平台可用性检测"            "检测流媒体/AI/社交平台连接情况"
    menu_item 18 "轻量测速"                  "下载 10MB 粗略测速"
    menu_item 19 "健康检查"                  "资源、网络、服务、端口总览"
    menu_item 28 "故障排查建议"              "按常见问题给处理建议"
    menu_item 29 "生成诊断报告"              "生成不含节点密钥的排查报告"
    menu_item 30 "修复系统时间"              "开启 NTP，处理时间不准问题"

    section "节点和脚本"
    menu_item 20 "VLESS-Reality 参数参考"    "给客户端填参数时对照"
    menu_item 21 "查看节点提示"              "告诉你去 vasma 哪里看节点"
    menu_item 22 "建议流程"                  "备份 + 优化 + 安全检查"
    menu_item 23 "安装 rn 短命令"            "以后输入 rn 打开菜单"
    menu_item 24 "更新本脚本"                "从 GitHub 拉取最新版"
    menu_item 25 "查看日志"                  "查看最近脚本运行日志"
    menu_item 26 "版本"                      "查看脚本版本和路径"
    menu_item 27 "卸载提示"                  "说明怎么删脚本或卸载上游"

    echo
    echo -e "  ${RED} 0${NC}. 退出"
    echo -e "${CYAN}==================================================${NC}"
    read -rp "选择 [0-30]: " choice

    case "$choice" in
      1) show_server_info; pause ;;
      2) check_v2ray_agent; pause ;;
      3) install_or_update_agent; pause ;;
      4) open_agent_menu; pause ;;
      5) configure_firewall; pause ;;
      6) custom_firewall_port; pause ;;
      7) enable_bbr; pause ;;
      8) speed_tune_safe; pause ;;
      9) rollback_speed_tune; pause ;;
      10) optimize_dns_safe; pause ;;
      11) install_fail2ban_safe; pause ;;
      12) backup_agent_configs; pause ;;
      13) list_backups; pause ;;
      14) security_audit; pause ;;
      15) repair_core_services; pause ;;
      16) validate_core_configs; pause ;;
      17) run_platform_check; pause ;;
      18) network_speed_light; pause ;;
      19) health_check; pause ;;
      20) show_client_reality_template; pause ;;
      21) show_account_hint; pause ;;
      22) recommended_flow; pause ;;
      23) install_self_alias; pause ;;
      24) self_update; pause ;;
      25) view_logs; pause ;;
      26) show_version; pause ;;
      27) uninstall_hint; pause ;;
      28) troubleshooting_guide; pause ;;
      29) generate_diagnostic_report; pause ;;
      30) fix_time_sync; pause ;;
      0) exit 0 ;;
      *) warn "无效选择"; sleep 1 ;;
    esac
  done
}

main_menu
