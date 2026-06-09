#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[注意]${NC} $*"; }
err(){ echo -e "${RED}[错误]${NC} $*"; }
title(){ echo -e "\n${CYAN}========== $* ==========${NC}"; }

URLS=(
  "ChatGPT|https://chatgpt.com/"
  "OpenAI|https://openai.com/"
  "OpenAI API|https://api.openai.com/v1/models"
  "OpenAI CDN|https://cdn.oaistatic.com/"
  "OpenAI Files|https://files.oaiusercontent.com/"
  "Grok|https://grok.com/"
  "xAI|https://x.ai/"
  "X|https://x.com/"
)

status_text(){
  case "$1" in
    000) echo "连接失败" ;;
    2*|3*) echo "可连接" ;;
    401|403) echo "有响应/可能需要登录或受限" ;;
    451) echo "地区受限" ;;
    *) echo "有响应" ;;
  esac
}

probe(){
  local name="$1" url="$2" data code t ip final status
  data=$(curl -4 -L -sS -o /dev/null --connect-timeout 6 --max-time 18 -w '%{http_code}|%{time_total}|%{remote_ip}|%{url_effective}' "$url" 2>/dev/null || echo "000|-1|-|-")
  IFS='|' read -r code t ip final <<<"$data"
  status=$(status_text "$code")
  printf "%-13s HTTP:%-4s %-24s 耗时:%-7s 远端:%s\n" "$name" "$code" "$status" "$t" "$ip"
}

fix_vps_dns_time(){
  title "修复 VPS DNS 和时间"
  if [[ "${EUID}" -ne 0 ]]; then
    err "需要 root。请用 root 运行。"
    return 1
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-ntp true || true
    timedatectl || true
  else
    warn "没有 timedatectl，跳过时间修复。"
  fi

  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-resolved.service'; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat >/etc/systemd/resolved.conf.d/ai-access-dns.conf <<'EOF'
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
  ok "已尝试修复 VPS DNS 和时间。"
}

print_client_rules(){
  title "客户端规则参考"
  cat <<'EOF'
如果手机/电脑是规则模式，把下面这些域名强制走 proxy，放在直连中国规则前面：

DOMAIN-SUFFIX,openai.com,proxy
DOMAIN-SUFFIX,chatgpt.com,proxy
DOMAIN-SUFFIX,oaistatic.com,proxy
DOMAIN-SUFFIX,oaiusercontent.com,proxy
DOMAIN-SUFFIX,auth0.com,proxy
DOMAIN-SUFFIX,grok.com,proxy
DOMAIN-SUFFIX,x.ai,proxy
DOMAIN-SUFFIX,x.com,proxy
DOMAIN-SUFFIX,twimg.com,proxy

v2rayNG / v2rayN 建议：
- 先用全局模式测试
- 关闭 Mux
- 关闭 IPv6 或优先 IPv4
- DNS 走代理，不要让运营商 DNS 解析 ChatGPT/Grok
- Reality fingerprint 用 chrome
- 如果运营商不稳定，新增 443 端口节点测试
EOF
}

main(){
  title "GPT / Grok 访问诊断"
  echo "这个脚本只做检测和基础修复，不能保证账号、地区或平台风控一定放行。"

  title "出口 IP"
  if command -v jq >/dev/null 2>&1; then
    curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\nCountry: \(.country)\nCity: \(.city)\nOrg: \(.org)\nTimezone: \(.timezone)"' 2>/dev/null || true
  else
    curl -4 -s --max-time 8 https://ipinfo.io/json || true
  fi

  title "系统时间"
  date || true
  timedatectl 2>/dev/null | sed -n '1,8p' || true

  title "DNS"
  cat /etc/resolv.conf 2>/dev/null || true

  title "站点连接"
  for item in "${URLS[@]}"; do
    IFS='|' read -r name url <<<"$item"
    probe "$name" "$url"
  done

  title "判断"
  cat <<'EOF'
- VPS 上这些站点都可连接，但手机/电脑不行：多半是客户端分流、DNS、IPv6、系统代理或运营商网络问题。
- VPS 上也连接失败：多半是 VPS 出口 IP、DNS、系统时间或线路问题。
- 只有某一个平台不让访问：多半是账号地区、IP 信誉或平台风控，脚本无法保证修复。
EOF

  print_client_rules

  if [[ "${1:-}" == "--fix" ]]; then
    fix_vps_dns_time
  else
    echo
    echo "需要尝试修复 VPS DNS/时间时运行："
    echo "bash <(curl -Ls https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/ai_access_fix.sh) --fix"
  fi
}

main "$@"
