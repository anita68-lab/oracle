# OCI Instance Sniper

GitHub Actions кожні ~5 хв пробує створити Oracle A1-сервер з вашого boot volume.
Коли сервер створено — приходить повідомлення в Telegram, а workflow сам вимикається.

> Репозиторій має бути **публічним**: для публічних репо хвилини Actions безкоштовні.
> Секрети при цьому не видно нікому, а скрипт не пише IP чи помилки в лог (лише в Telegram).

## 1. Telegram-бот
1. У Telegram напишіть [@BotFather](https://t.me/BotFather) → `/newbot` → отримаєте **токен**.
2. Напишіть своєму боту будь-що (наприклад `/start`).
3. Відкрийте в браузері `https://api.telegram.org/bot<ТОКЕН>/getUpdates` і знайдіть `"chat":{"id": ...}` — це **chat id**.

## 2. API-ключ Oracle
Консоль Oracle → іконка профілю (справа вгорі) → **My profile** → **API keys** → **Add API key** →
**Generate API key pair** → **Download private key** → **Add**.
Oracle покаже блок конфігурації — з нього потрібні `user`, `fingerprint`, `tenancy`, `region`.

## 3. ID диска, subnet і AD
Вставте в Cloud Shell:
```bash
for AD in $(oci iam availability-domain list --compartment-id "$OCI_TENANCY" | jq -r '.data[].name'); do
  oci bv boot-volume list --compartment-id "$OCI_TENANCY" --availability-domain "$AD" --all 2>/dev/null \
    | jq -r '.data[]? | "BOOT_VOLUME: \(."display-name")\n  BOOT_VOLUME_ID=\(.id)\n  AVAILABILITY_DOMAIN=\(."availability-domain")"'
done
oci network subnet list --compartment-id "$OCI_TENANCY" --all \
  | jq -r '.data[] | "SUBNET: \(."display-name") (public: \(."prohibit-public-ip-on-vnic"|not))\n  SUBNET_ID=\(.id)"'
```
Візьміть значення для диска `instance-20260308-1912 (Boot Volume)` і для **публічного** subnet.

## 4. Секрети GitHub
Репозиторій → **Settings → Secrets and variables → Actions → New repository secret**:

| Секрет | Значення |
|---|---|
| `OCI_USER_OCID` | `user` з кроку 2 |
| `OCI_TENANCY_OCID` | `tenancy` з кроку 2 |
| `OCI_FINGERPRINT` | `fingerprint` з кроку 2 |
| `OCI_REGION` | `eu-frankfurt-1` |
| `OCI_PRIVATE_KEY` | увесь вміст завантаженого `.pem` (разом з рядками `-----BEGIN/END ...-----`) |
| `BOOT_VOLUME_ID` | з кроку 3 |
| `AVAILABILITY_DOMAIN` | з кроку 3 (напр. `sKLI:EU-FRANKFURT-1-AD-2`) |
| `SUBNET_ID` | з кроку 3 |
| `TELEGRAM_BOT_TOKEN` | з кроку 1 |
| `TELEGRAM_CHAT_ID` | з кроку 1 |

> `OCI_PRIVATE_KEY` — це **API-ключ** з кроку 2, а НЕ ваш SSH-ключ `ssh-key-2026-03-08.key`.

## 5. Запуск
**Actions** → **OCI Instance Sniper** → **Run workflow**. Далі він запускатиметься сам за розкладом.

## Налаштування
У `.github/workflows/oci-sniper.yml`: `INSTANCE_NAME`, `OCPUS`, `MEMORY_GB`.
Безкоштовно — до 2 OCPU / 12 GB сумарно на всі A1-сервери.

## Після створення
- Зупиніть скрипт у Cloud Shell (Ctrl+C), якщо він ще працює.
- Щоб запустити знову: **Actions → OCI Instance Sniper → Enable workflow**.
