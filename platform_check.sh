#!/usr/bin/env bash
set -Eeuo pipefail

SITES=(
  "media|Netflix|https://www.netflix.com/"
  "media|Fast|https://fast.com/"
  "media|Disney+|https://www.disneyplus.com/"
  "media|PrimeVideo|https://www.primevideo.com/"
  "media|YouTube|https://www.youtube.com/"
  "media|Hulu|https://www.hulu.com/"
  "media|Max|https://www.max.com/"
  "media|AppleTV|https://tv.apple.com/"
  "media|Paramount+|https://www.paramountplus.com/"
  "media|Peacock|https://www.peacocktv.com/"
  "media|Crunchyroll|https://www.crunchyroll.com/"
  "media|Spotify|https://open.spotify.com/"
  "media|Twitch|https://www.twitch.tv/"
  "media|TikTok|https://www.tiktok.com/"
  "ai|OpenAI Web|https://chat.openai.com/"
  "ai|Claude|https://claude.ai/"
  "ai|Gemini|https://gemini.google.com/"
  "ai|Copilot|https://copilot.microsoft.com/"
  "ai|Perplexity|https://www.perplexity.ai/"
  "ai|Poe|https://poe.com/"
  "ai|Grok|https://grok.com/"
  "social|X|https://x.com/"
  "social|Telegram|https://web.telegram.org/"
  "social|Discord|https://discord.com/"
  "social|Reddit|https://www.reddit.com/"
  "game|Steam|https://store.steampowered.com/"
  "game|Epic|https://store.epicgames.com/"
)

status_text() {
  case "$1" in
    000) echo "failed" ;;
    2*|3*) echo "ok" ;;
    401|403) echo "responded" ;;
    451) echo "region" ;;
    *) echo "responded" ;;
  esac
}

probe() {
  local cat="$1" name="$2" url="$3" data code t ip final status
  data=$(curl -4 -L -sS -o /dev/null --connect-timeout 6 --max-time 18 -w '%{http_code}|%{time_total}|%{remote_ip}|%{url_effective}' "$url" 2>/dev/null || echo "000|-1|-|-")
  IFS='|' read -r code t ip final <<<"$data"
  status=$(status_text "$code")
  printf "%-7s %-14s HTTP:%-4s %-10s time:%-7s remote:%s\n" "$cat" "$name" "$code" "$status" "$t" "$ip"
}

echo "== IP =="
if command -v jq >/dev/null 2>&1; then
  curl -4 -s --max-time 8 https://ipinfo.io/json | jq -r '"IP: \(.ip)\nCountry: \(.country)\nCity: \(.city)\nOrg: \(.org)"' 2>/dev/null || true
else
  curl -4 -s --max-time 8 https://ipinfo.io/json || true
fi

echo
echo "== DNS =="
cat /etc/resolv.conf 2>/dev/null || true

echo
echo "== Sites =="
for item in "${SITES[@]}"; do
  IFS='|' read -r cat name url <<<"$item"
  probe "$cat" "$name" "$url"
done

echo
echo "说明：ok/responded 只代表服务器有响应，不代表账号、内容库或客户端一定可用。"
echo "如果某个平台一直 failed/region，通常要看 IP 地区、IP 信誉、账号地区和客户端 DNS。"
