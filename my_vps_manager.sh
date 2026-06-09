#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.2.0"
REPO="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
UPSTREAM="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
LOG="/var/log/my_vps_manager.log"
SELF="/root/my_vps_manager.sh"
BIN="/usr/local/bin/myvps"
PORTS="22 80 443 8443 2053 15593"
REPORT_DIR="/root/my-vps-reports"

if [[ -t 1 ]]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; D='\033[2m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; C=''; W=''; D=''; N=''
fi

log(){ mkdir -p "$(dirname "$LOG")" >/dev/null 2>&1 || true; echo -e "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
ok(){ log "${G}[OK]${N} $*"; }
warn(){ log "${Y}[注意]${N} $*"; }
err(){ log "${R}[错误]${N} $*"; }
has(){ command -v "$1" >/dev/null 2>&1; }
pause(){ read -rp "按回车返回..." _ || true; }
need_root(){ [[ ${EUID:-0} -eq 0 ]] || { err "请用 root 运行"; exit 1; }; }
dl(){ if has curl; then curl -fsSL --retry 3 --connect-timeout 10 --max-time 80 -o "$2" "$1"; else wget -q -O "$2" "$1"; fi; }

header(){
  clear
  echo -e "${C}${W}╔══════════════════════════════════════╗${N}"
  echo -e "${C}${W}║        我的 RackNerd VPS 管理        ║${N}"
  echo -e "${C}${W}╚══════════════════════════════════════╝${N}"
  echo -e "版本: $VERSION    主脚本: my_vps_manager.sh\n"
}

install_base(){
  need_root
  mkdir -p "$REPORT_DIR"
  if has apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates jq ufw lsof iproute2 dnsutils cron tar unzip openssl fail2ban
    systemctl enable --now cron >/dev/null 2>&1 || true
  else
    warn "当前系统不是 apt 系，脚本只做基础检查。推荐 Debian 12。"
  fi
  ok "基础工具完成"
}

fix_basic(){
  need_root
  if has timedatectl; then timedatectl set-ntp true || true; fi
  cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n' >/etc/resolv.conf
  if has ufw; then
    for p in $PORTS; do ufw allow "$p/tcp" || true; done
    ufw --force enable || true
  fi
  cat >/etc/sysctl.d/98-my-vps.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1
EOF
  sysctl --system >/dev/null || true
  ok "DNS、时间、防火墙、BBR 已处理"
}

vps_info(){
  echo "系统: $(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo unknown)"
  echo "内核: $(uname -r)"
  echo "CPU: $(nproc) 核"
  free -h || true
  df -h / || true
  echo
  echo "IPv4: $(curl -4 -s --max-time 6 https://api.ipify.org || true)"
  if has jq; then
    curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"地区: \(.country) \(.city)\nASN: \(.org)"' || true
  else
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
  fi
}

ports_status(){
  echo "常用端口监听:"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|8443|2053|15593)\b' || echo "未看到常用节点端口监听"
  echo
  for s in xray sing-box nginx fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^$s.service"; then
      systemctl --no-pager --full status "$s" 2>/dev/null | sed -n '1,8p' || true
      echo
    fi
  done
}

node_hint(){
  echo "节点安装建议："
  echo "- 主节点：VLESS Reality Vision"
  echo "- 主端口：443"
  echo "- 备用端口：8443 / 2053 / 15593"
  echo "- flow：xtls-rprx-vision"
  echo "- fingerprint：chrome"
  echo "- Mux：关闭"
  echo
  if [[ -d /etc/v2ray-agent ]]; then
    ok "检测到 /etc/v2ray-agent，说明系统里存在 v2ray-agent 配置目录。"
  else
    warn "未检测到 /etc/v2ray-agent。还没有安装，或不是 v2ray-agent 环境。"
  fi
  echo
  echo "安全说明：本脚本不会直接打印 UUID、PrivateKey、ShortId 或节点链接。"
  echo "需要查看/重置节点，请进：2. 安装/管理节点"
}

carrier_diag(){
  echo "运营商/热点诊断："
  echo
  ports_status
  echo "建议在 Windows v2rayN 电脑上分别连不同网络后测试："
  echo "  Test-NetConnection 你的VPS_IP -Port 443"
  echo "  Test-NetConnection 你的VPS_IP -Port 8443"
  echo "  Test-NetConnection 你的VPS_IP -Port 2053"
  echo "  Test-NetConnection 你的VPS_IP -Port 15593"
  echo
  echo "判断："
  echo "- 同一节点，移动能用、联通不行：多半是运营商线路/端口问题。"
  echo "- iPhone 热点不行、其他热点能用：多半是热点网络、IPv6、DNS 或运营商出口问题。"
  echo "- 443 能通，高位端口不通：优先保留 Reality 443。"
  echo "- 端口通但客户端不通：看 v2rayN/v2rayNG 的路由、DNS、Mux、IPv6。"
}

backup_conf(){
  need_root
  local dir="/root/my-vps-backup-$(date +%F_%H%M%S)"
  mkdir -p "$dir"
  [[ -d /etc/v2ray-agent ]] && tar -czf "$dir/v2ray-agent.tar.gz" /etc/v2ray-agent 2>/dev/null || true
  [[ -d /usr/local/etc/xray ]] && tar -czf "$dir/xray.tar.gz" /usr/local/etc/xray 2>/dev/null || true
  [[ -d /usr/local/etc/sing-box ]] && tar -czf "$dir/sing-box.tar.gz" /usr/local/etc/sing-box 2>/dev/null || true
  [[ -d /etc/nginx ]] && tar -czf "$dir/nginx.tar.gz" /etc/nginx 2>/dev/null || true
  ok "备份完成: $dir"
}

redact(){
  sed -E \
    -e 's#vless://[^[:space:]]+#vless://***REDACTED***#g' \
    -e 's#trojan://[^[:space:]]+#trojan://***REDACTED***#g' \
    -e 's#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}#***UUID***#g' \
    -e 's#(privateKey|PrivateKey|shortId|ShortId|password|passwd|uuid|id)[":= ]+[^, }]+#\1: ***REDACTED***#g'
}

safe_report(){
  need_root
  mkdir -p "$REPORT_DIR"
  local f="$REPORT_DIR/report-$(date +%F_%H%M%S).txt"
  {
    echo "My VPS Safe Diagnostic Report"
    echo "Time: $(date '+%F %T %Z')"
    echo
    echo "== System =="
    grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null || true
    uname -a
    free -h || true
    df -h / || true
    echo
    echo "== IP / ASN =="
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
    echo
    echo "== DNS =="
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "== Time =="
    date
    timedatectl 2>/dev/null | sed -n '1,12p' || true
    echo
    echo "== Ports =="
    ss -tulpen 2>/dev/null | grep -E ':(22|80|443|8443|2053|15593)\b' || true
    echo
    echo "== Services =="
    for s in xray sing-box nginx fail2ban; do
      systemctl --no-pager --full status "$s" 2>/dev/null | sed -n '1,10p' || true
      echo
    done
    echo "== Recent Manager Log =="
    tail -n 120 "$LOG" 2>/dev/null | redact || true
    echo
    echo "== Recent Xray Log =="
    journalctl -u xray -n 80 --no-pager 2>/dev/null | redact || true
  } > "$f"
  chmod 600 "$f" || true
  ok "安全诊断报告已生成：$f"
  warn "报告不主动读取配置文件，但仍会包含公网 IP。发给别人前自己先看一遍。"
}

open_installer(){
  need_root
  if has vasma; then vasma; return; fi
  dl "$UPSTREAM" /root/install.sh
  chmod 700 /root/install.sh
  bash /root/install.sh
}

leak_tip(){
  echo "泄露处理提醒："
  echo "如果你曾经截图、发聊天、发仓库时暴露过以下内容："
  echo "- UUID"
  echo "- PrivateKey"
  echo "- PublicKey"
  echo "- ShortId"
  echo "- 节点链接 / 订阅链接"
  echo
  echo "建议进入：2. 安装/管理节点"
  echo "然后在 v2ray-agent 里重置用户或重新生成节点，再重新导入 v2rayN/v2rayNG。"
}

client_tips(){
  cat <<'EOF'
专门给你的 v2rayN / v2rayNG 建议：

推荐节点：VLESS Reality Vision
端口：优先 443，备用 8443 / 2053 / 15593
flow：xtls-rprx-vision
fingerprint：chrome
Mux：关闭
IPv6：关闭或优先 IPv4
路由：先用全局测试，确认稳定后再改规则
DNS：尽量让 DNS 跟随节点，避免运营商 DNS 影响

v2rayN：
- 系统代理：自动配置系统代理
- 测速 -1 ms 不等于 VPS 一定坏，先看服务、端口和日志
- Windows 可用：Test-NetConnection VPS_IP -Port 443

v2rayNG：
- 先全局模式测试
- 规则模式下，AI 相关域名要放在直连规则前面
- 手机热点网络不稳时，先关 IPv6 或优先 IPv4
EOF
  echo
  leak_tip
}

status_text(){
  case "$1" in
    000) echo "失败" ;;
    2*|3*) echo "可连" ;;
    401|403) echo "有响应/可能受限" ;;
    451) echo "地区限制" ;;
    *) echo "有响应" ;;
  esac
}

probe(){
  local name="$1" url="$2" data code time ip st
  data=$(curl -4 -L -sS -o /dev/null --connect-timeout 6 --max-time 18 -w '%{http_code}|%{time_total}|%{remote_ip}' "$url" 2>/dev/null || echo "000|-1|-")
  IFS='|' read -r code time ip <<<"$data"
  st=$(status_text "$code")
  printf "%-12s HTTP:%-4s %-18s 耗时:%-7s 远端:%s\n" "$name" "$code" "$st" "$time" "$ip"
}

show_exit_ip(){
  echo "出口 IP:"
  if has jq; then
    curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\n国家: \(.country)\n城市: \(.city)\nASN: \(.org)"' || true
  else
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
  fi
  echo
}

ai_test(){
  show_exit_ip
  probe ChatGPT https://chatgpt.com/
  probe OpenAI https://openai.com/
  probe OpenAI_API https://api.openai.com/v1/models
  probe OpenAI_CDN https://cdn.oaistatic.com/
  probe OpenAI_File https://files.oaiusercontent.com/
  probe Grok https://grok.com/
  probe xAI https://x.ai/
  probe X https://x.com/
  echo
  warn "检测是 VPS 出口连通性，不等于账号或平台一定放行。"
}

media_test(){
  show_exit_ip
  probe YouTube https://www.youtube.com/
  probe Netflix https://www.netflix.com/
  probe Disney https://www.disneyplus.com/
  probe PrimeVideo https://www.primevideo.com/
  probe TikTok https://www.tiktok.com/
  probe Spotify https://www.spotify.com/
  echo
  warn "检测可连不等于片库解锁；片库和账号地区、IP 信誉有关。"
}

update_self(){
  need_root
  dl "$REPO/my_vps_manager.sh" "$SELF"
  chmod 700 "$SELF"
  ln -sf "$SELF" "$BIN"
  ok "已更新。以后输入：myvps"
}

show_logs(){
  tail -n 150 "$LOG" 2>/dev/null || true
  journalctl -u xray -n 80 --no-pager 2>/dev/null || true
}

main_menu(){
  while true; do
    header
    echo -e "${G}1${N}. 首次准备       ${D}装工具、修 DNS/时间、防火墙、BBR${N}"
    echo -e "${G}2${N}. 安装/管理节点  ${D}打开 v2ray-agent，上游菜单只用来装节点${N}"
    echo -e "${G}3${N}. 状态/运营商诊断 ${D}端口、服务、联通/移动/热点排查${N}"
    echo -e "${G}4${N}. 备份/诊断报告   ${D}备份配置，生成安全排查报告${N}"
    echo -e "${G}5${N}. AI 检测        ${D}GPT/Grok/OpenAI/X 出口状态${N}"
    echo -e "${G}6${N}. 影视检测       ${D}YouTube/Netflix/Disney 等出口状态${N}"
    echo -e "${G}7${N}. 客户端/安全建议 ${D}v2rayN/v2rayNG 和泄露重置提醒${N}"
    echo -e "${G}8${N}. 查看日志       ${D}出问题先看这里${N}"
    echo -e "${G}9${N}. 更新本脚本     ${D}以后只维护这个脚本${N}"
    echo -e "${G}0${N}. 退出"
    echo
    read -rp "请选择: " c || true
    case "$c" in
      1) header; update_self; install_base; fix_basic; vps_info; pause ;;
      2) open_installer ;;
      3) header; node_hint; echo; carrier_diag; pause ;;
      4) header; backup_conf; safe_report; pause ;;
      5) header; ai_test; pause ;;
      6) header; media_test; pause ;;
      7) header; client_tips; pause ;;
      8) header; show_logs; pause ;;
      9) header; update_self; pause ;;
      0) exit 0 ;;
    esac
  done
}

case "${1:-}" in
  update) update_self ;;
  fix) install_base; fix_basic ;;
  status) ports_status ;;
  diag) node_hint; echo; carrier_diag ;;
  report) safe_report ;;
  ai) ai_test ;;
  media) media_test ;;
  tips) client_tips ;;
  *) main_menu ;;
esac
