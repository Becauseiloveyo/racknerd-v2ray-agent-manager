#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
REPO="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main"
UPSTREAM="https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh"
LOG="/var/log/my_vps_manager.log"
SELF="/root/my_vps_manager.sh"
BIN="/usr/local/bin/myvps"

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

header(){ clear; echo -e "${C}${W}╔══════════════════════════════════════╗${N}"; echo -e "${C}${W}║        我的 RackNerd VPS 管理        ║${N}"; echo -e "${C}${W}╚══════════════════════════════════════╝${N}"; echo -e "版本: $VERSION\n"; }

install_base(){
  need_root
  if has apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget ca-certificates jq ufw lsof iproute2 dnsutils cron tar unzip openssl fail2ban
    systemctl enable --now cron >/dev/null 2>&1 || true
  fi
  ok "基础工具完成"
}

fix_basic(){
  need_root
  if has timedatectl; then timedatectl set-ntp true || true; fi
  cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%F_%H%M%S)" 2>/dev/null || true
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n' >/etc/resolv.conf
  if has ufw; then
    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
    ufw allow 8443/tcp || true
    ufw allow 2053/tcp || true
    ufw allow 15593/tcp || true
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
  if has jq; then curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"地区: \(.country) \(.city)\nASN: \(.org)"' || true; else curl -4 -s --max-time 8 https://ipinfo.io/json || true; fi
}

ports_status(){
  echo "常用端口监听:"
  ss -tulpen 2>/dev/null | grep -E ':(22|80|443|8443|2053|15593)\b' || echo "未看到常用节点端口监听"
  echo
  systemctl --no-pager --full status xray 2>/dev/null | sed -n '1,12p' || true
  systemctl --no-pager --full status sing-box 2>/dev/null | sed -n '1,8p' || true
  systemctl --no-pager --full status nginx 2>/dev/null | sed -n '1,8p' || true
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

open_installer(){
  need_root
  if has vasma; then vasma; return; fi
  dl "$UPSTREAM" /root/install.sh
  chmod 700 /root/install.sh
  bash /root/install.sh
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
DNS：不要用运营商本地 DNS 解析关键网站，客户端里尽量让 DNS 跟随节点

v2rayN：
- 系统代理：自动配置系统代理
- 测速 -1 ms 不等于 VPS 一定坏，先看端口和日志

v2rayNG：
- 先全局模式测试
- 规则模式下，AI 相关域名要放在直连规则前面
EOF
}

platform_test(){ bash <(curl -Ls "$REPO/platform_check.sh"); }
ai_test(){ bash <(curl -Ls "$REPO/ai_access_fix.sh"); }
update_self(){ need_root; dl "$REPO/my_vps_manager.sh" "$SELF"; chmod 700 "$SELF"; ln -sf "$SELF" "$BIN"; ok "已更新，命令: myvps"; }
show_logs(){ tail -n 150 "$LOG" 2>/dev/null || true; journalctl -u xray -n 80 --no-pager 2>/dev/null || true; }

main_menu(){
  while true; do
    header
    echo -e "${G}1${N}. 首次准备       ${D}装工具、修 DNS/时间、防火墙、BBR${N}"
    echo -e "${G}2${N}. 安装/管理节点  ${D}打开 v2ray-agent，上游菜单只用来装节点${N}"
    echo -e "${G}3${N}. 服务和端口     ${D}看 443/8443/2053/15593 和核心服务${N}"
    echo -e "${G}4${N}. 备份配置       ${D}备份节点、Xray、sing-box、nginx${N}"
    echo -e "${G}5${N}. AI 检测        ${D}看 GPT/Grok 相关出口状态${N}"
    echo -e "${G}6${N}. 影视检测       ${D}看常见媒体平台出口状态${N}"
    echo -e "${G}7${N}. 客户端建议     ${D}v2rayN/v2rayNG 专用设置${N}"
    echo -e "${G}8${N}. 查看日志       ${D}出问题先看这里${N}"
    echo -e "${G}9${N}. 更新本脚本     ${D}以后只维护这个脚本${N}"
    echo -e "${G}0${N}. 退出"
    echo
    read -rp "请选择: " c || true
    case "$c" in
      1) header; install_base; fix_basic; vps_info; pause ;;
      2) open_installer ;;
      3) header; ports_status; pause ;;
      4) header; backup_conf; pause ;;
      5) header; ai_test; pause ;;
      6) header; platform_test; pause ;;
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
  tips) client_tips ;;
  *) main_menu ;;
esac
