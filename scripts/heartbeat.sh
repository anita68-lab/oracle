#!/usr/bin/env bash
# Щогодинний звіт у Telegram: sniper працює, сервер ще не створено.
set -uo pipefail

touch .heartbeat   # маркер для actions/cache (1 звіт на годину)

[ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ] && exit 0

SINCE=$(date -u -d '-60 min' '+%Y-%m-%dT%H:%M:%SZ')
RUNS=$(gh api "repos/${GITHUB_REPOSITORY}/actions/workflows/oci-sniper.yml/runs?created=>=${SINCE}&per_page=1" \
  --jq '.total_count' 2>/dev/null || echo "?")
NOW=$(TZ=Europe/Kyiv date '+%H:%M')

TEXT="⏳ Oracle sniper працює (${NOW} за Києвом)
Сервер ще не створено: в AD-2 немає вільного місця.
За останню годину: запусків ${RUNS}, кожен запуск = 8 спроб (2/12, потім 1/6).
Логи: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" --data-urlencode text="$TEXT" >/dev/null || true
echo "Щогодинний звіт надіслано."
