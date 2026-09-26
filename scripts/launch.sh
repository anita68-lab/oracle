#!/usr/bin/env bash
# Пробує створити Oracle A1-інстанс з існуючого boot volume.
# Шле повідомлення в Telegram, коли сервер створено або сталася невідома помилка.
# Увага: репозиторій публічний, тому в лог НЕ виводимо IP та помилки — лише в Telegram.

set -uo pipefail

: "${OCI_TENANCY_OCID:?потрібен секрет OCI_TENANCY_OCID}"
: "${BOOT_VOLUME_ID:?потрібен секрет BOOT_VOLUME_ID}"
: "${SUBNET_ID:?потрібен секрет SUBNET_ID}"
: "${AVAILABILITY_DOMAIN:?потрібен секрет AVAILABILITY_DOMAIN}"

COMPARTMENT_ID="${COMPARTMENT_ID:-$OCI_TENANCY_OCID}"
INSTANCE_NAME="${INSTANCE_NAME:-my-server}"
# Розміри по черзі "OCPU:GB": спершу великий, якщо немає місця — менший.
SHAPES="${SHAPES:-2:12 1:6}"
ATTEMPTS="${ATTEMPTS:-8}"   # спроб за один запуск workflow
WAIT="${WAIT:-60}"          # секунд між спробами

OUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

tg() {
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="${TELEGRAM_CHAT_ID}" \
      --data-urlencode text="$1" >/dev/null || true
  fi
}

stop_workflow() { echo "stop=true" >> "$OUT_FILE"; }

# 1. Якщо сервер уже існує — нічого не робимо і вимикаємо workflow.
EXISTING=$(oci compute instance list --compartment-id "$COMPARTMENT_ID" \
    --display-name "$INSTANCE_NAME" --all 2>/dev/null \
  | jq -r '[.data[]? | select(."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING")] | length')
if [ "${EXISTING:-0}" -gt 0 ]; then
  echo "Сервер '$INSTANCE_NAME' вже існує — зупиняюсь."
  stop_workflow
  exit 0
fi

# 2. Спроби створення.
try_launch() {  # $1=OCPU $2=GB; 0 = створено, 1 = немає місця, 2 = стоп
  local OCPUS="$1" MEMORY_GB="$2" OUT ERR INSTANCE_ID IP
  OUT=$(oci --no-retry compute instance launch \
    --compartment-id "$COMPARTMENT_ID" \
    --availability-domain "$AVAILABILITY_DOMAIN" \
    --shape VM.Standard.A1.Flex \
    --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
    --source-details "{\"sourceType\":\"bootVolume\",\"bootVolumeId\":\"$BOOT_VOLUME_ID\"}" \
    --subnet-id "$SUBNET_ID" \
    --assign-public-ip true \
    --display-name "$INSTANCE_NAME" 2>/tmp/launch_err)

  if [ $? -eq 0 ]; then
    echo "  ${OCPUS}/${MEMORY_GB}: сервер створено!"
    INSTANCE_ID=$(echo "$OUT" | jq -r '.data.id')
    oci compute instance get --instance-id "$INSTANCE_ID" \
      --wait-for-state RUNNING --max-wait-seconds 600 >/dev/null 2>&1
    IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" 2>/dev/null \
      | jq -r '.data[0]."public-ip" // "невідомо"')
    tg "🎉 Oracle сервер '$INSTANCE_NAME' створено!
Shape: A1.Flex ${OCPUS} OCPU / ${MEMORY_GB} GB
Public IP: $IP
Підключення: ssh -i ssh-key-2026-03-08.key ubuntu@$IP

Workflow автоматично вимкнено."
    stop_workflow
    return 0
  fi

  ERR=$(cat /tmp/launch_err)
  case "$ERR" in
    *"Out of host capacity"*|*"Out of capacity"*|*"InternalError"*)
      echo "  ${OCPUS}/${MEMORY_GB}: немає місця."
      return 1 ;;
    *"TooManyRequests"*)
      echo "  Забагато запитів — завершую цей запуск."
      exit 0 ;;
    *)
      echo "  ${OCPUS}/${MEMORY_GB}: невідома помилка (деталі надіслано в Telegram)."
      tg "❌ Oracle sniper: невідома помилка, workflow вимкнено.
${ERR:0:800}"
      stop_workflow
      exit 1 ;;
  esac
}

for i in $(seq 1 "$ATTEMPTS"); do
  echo "[$(date -u '+%H:%M:%S')] Спроба $i/$ATTEMPTS..."
  for S in $SHAPES; do
    try_launch "${S%%:*}" "${S##*:}" && exit 0
  done
  [ "$i" -lt "$ATTEMPTS" ] && sleep "$WAIT"
done

echo "Місця поки немає, наступний запуск за розкладом."
