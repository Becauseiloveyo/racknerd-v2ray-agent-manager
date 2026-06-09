#!/usr/bin/env bash
# fresh_setup.sh
# 全新安装辅助脚本：适合重装系统后第一次跑，或者准备重新整理 VPS 时使用。
# 不会删除 v2ray-agent 配置；真正卸载旧环境请先用 vasma 上游菜单处理，或直接重装系统。

set -Eeuo pipefail

V2RAY_AGENT_URL="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
MANAGER_URL="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/racknerd_v2ray_agent_manager.sh"
MANAGER_PATH="/root/racknerd_v2ray_agent_manager.sh"
AGENT_INSTALL_PATH="/root/install.sh"
ALIAS_PATH="/usr/local/bin/rn"
LOG_FILE="/var/log/racknerd_fresh_setup.log"

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

log(){ mkdir -p "$(dirname "$LOG_FILE")" >/dev/null 2>&1 || true; echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
ok(){ log "${GREEN}[OK]${NC} $*"; }
warn(){ log "${YELLOW}[注意]${NC} $*"; }
err(){ log "${RED}[错误]${NC} $*"; }
info(){ log "${BLUE}[信息]${NC} $*"; }
title(){ echo -e "\n${CYAN}==================================================${NC}\n  ${BOLD}$*${NC}\n${CYAN}==================================================${NC}"; }
pause(){ read -rp "按回车继续..." _ || true; }
confirm(){ local ans; read -rp "$1 [y/N]: " ans || true; [[ "${ans:-}" =~ ^[Yy]$ ]]; }
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

need_root(){
  if [[ "${EUID}" -ne 0 ]]; then
    err "请用 root 执行：sudo bash fresh_setup.sh"
    exit 1
  fi
}

download_file(){
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

install_tools(){
  title "1. 安装基础工具"
  if has_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl wget ca-certificates jq ufw lsof iproute2 dnsutils socat cron tar unzip openssl fail2ban
    systemctl enable --now cron >/dev/null 2>&1 || true
  elif has_cmd dnf; then
    dnf install -y curl wget ca-certificates jq ufw lsof iproute bind-utils socat cronie tar unzip openssl fail2ban
    systemctl enable --now crond >/dev/null 2>&1 || true
  elif has_cmd yum; then
    yum install -y curl wget ca-certificates jq lsof iproute bind-utils socat cronie tar unzip openssl fail2ban
    systemctl enable --now crond >/dev/null 2>&1 || true
  else
    warn "没识别到 apt/dnf/yum，请手动安装 curl/wget/jq/ufw。"
  fi
  ok "基础工具检查完成。"
}

show_server(){
  title "2. VPS 基本信息"
  echo "主机名: $(hostname)"
  echo "系统: $(grep -PRE '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo unknown)"
  echo "内核: $(uname -r)"
  echo "CPU: $(nproc) 核"
  echo
  free -h || true
  df -h / || true
  echo
  echo "公网 IP:"
  echo -n "IPv4: "; curl -4 -s --max-time 5 https://api.ipify.org || true; echo
  echo -n "IPv6: "; curl -6 -s --max-time 5 https://api64.ipify.org || true; echo
  echo
  if has_cmd jq; then
    curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家/地区: \(.country)\n城市: \(.city)\nASN/Org: \(.org)"' 2>/dev/null || true
  else
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
  fi
}

fix_time_dns(){
  title "3. 修复时间和 DNS"
  if has_cmd timedatectl; then
    timedatectl set-ntp true || true
    timedatectl | sed -n '1,8p' || true
  else
    warn "没有 timedatectl，跳过时间同步。"
  fi

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
  else
    cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
    cat >/etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
  fi
  ok "时间和 DNS 已处理。"
}

network_tune(){
  title "4. 开启 BBR 和基础网络参数"
  cat >/etc/sysctl.d/98-racknerd-fresh-network.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_mtu_probing=1
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
EOF
  sysctl --system >/dev/null || true
  sysctl net.ipv4.tcp_congestion_control || true
  ok "网络参数已应用。"
}

check_ports(){
  title "5. 检查 80 / 443 / 15593 端口"
  echo "当前监听："
  ss -tulpen 2>/dev/null | grep -E ':(80|443|15593)\b' || echo "没有看到 80/443/15593 被占用。"
  echo
  if ss -tulpen 2>/dev/null | grep -q ':443\b'; then
    warn "443 已被占用。安装 Reality 443 前要确认是谁占用，避免冲突。"
  else
    ok "443 当前未占用，适合优先安装 Reality 443。"
  fi
}

setup_firewall(){
  title "6. 设置防火墙"
  if ! has_cmd ufw; then
    warn "没有 ufw，跳过防火墙。"
    return 0
  fi
  ufw allow 22/tcp || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 443/udp || true
  ufw allow 15593/tcp || true
  ufw allow 15593/udp || true
  ufw --force enable
  ufw status verbose || true
  ok "已放行 22/80/443/15593。"
}

install_manager(){
  title "7. 安装你的管理脚本"
  download_file "$MANAGER_URL" "$MANAGER_PATH"
  chmod 700 "$MANAGER_PATH"
  cat >"$ALIAS_PATH" <<EOF
#!/usr/bin/env bash
bash "$MANAGER_PATH" "\$@"
EOF
  chmod +x "$ALIAS_PATH"
  ok "已安装管理脚本：$MANAGER_PATH"
  ok "以后输入 rn 可以打开菜单。"
}

download_agent(){
  title "8. 下载 v2ray-agent 官方脚本"
  download_file "$V2RAY_AGENT_URL" "$AGENT_INSTALL_PATH"
  chmod 700 "$AGENT_INSTALL_PATH"
  ok "已下载：$AGENT_INSTALL_PATH"
}

print_install_plan(){
  title "推荐安装方案"
  cat <<'EOF'
这次建议不要一次装很多协议，先装一个稳定方案：

推荐：VLESS + Reality + Vision
端口：优先 443
flow：xtls-rprx-vision
fingerprint：chrome
Mux：关闭
IPv6：客户端先关闭或优先 IPv4
DNS：客户端 DNS 走代理

为什么优先 443：
- 联通/移动/热点/公司网对 443 兼容性通常更好
- 你之前 15593 在不同运营商下不稳定

保留建议：
- 如果你还想保留备用，可以后面再加 15593
- 不要一开始把 WS、Trojan、VMess、Reality、XHTTP 全装满，排查会变复杂

进入 v2ray-agent 上游菜单后，大概这样选：
- 第一次新系统：选“一键无域名 Reality”或 REALITY 管理
- 端口能选就选 443
- 如果 443 被占用，不要硬抢，先查占用或换 8443/2053/15593
- 生成账号后马上导入手机/电脑测试

客户端建议：
- 先用全局模式测试
- Mux 关闭
- IPv6 关闭或优先 IPv4
- OpenAI/Grok 相关域名走代理
EOF
}

launch_agent(){
  title "进入 v2ray-agent 安装菜单"
  if confirm "现在打开 v2ray-agent 官方菜单吗"; then
    bash "$AGENT_INSTALL_PATH"
  else
    echo "稍后手动打开："
    echo "bash $AGENT_INSTALL_PATH"
    echo "或者安装完成后用：vasma"
  fi
}

main(){
  need_root
  title "RackNerd VPS 全新安装辅助"
  echo "适合重装 Debian 12 后第一次运行。"
  echo "不会删除旧 v2ray-agent 配置；要彻底干净，建议先在 VPS 面板重装系统。"

  install_tools
  show_server
  fix_time_dns
  network_tune
  check_ports
  setup_firewall
  install_manager
  download_agent
  print_install_plan
  launch_agent

  title "完成"
  echo "你的管理脚本：bash $MANAGER_PATH"
  echo "短命令：rn"
  echo "v2ray-agent 官方菜单：vasma"
  echo "日志：$LOG_FILE"
}

main "$@"
