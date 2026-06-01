#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/Becauseiloveyo/racknerd-v2ray-agent-manager/main/racknerd_v2ray_agent_manager.sh"
DST="/root/racknerd_v2ray_agent_manager.sh"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$DST" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$DST" "$URL"
else
  echo "请先安装 curl 或 wget"
  exit 1
fi

chmod +x "$DST"
bash "$DST"
