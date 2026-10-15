#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
# CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# ---- 1. Разбор аргумента --dry-run ----
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ -n "${1:-}" ]]; then
    echo "Неизвестный аргумент: $1" >&2
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi

# ---- 2. Проверки по требованиям 4 и 5 ----
# Требование 4: файл site/index.html должен существовать
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: ${LOCAL_DIR}index.html не найден. Деплой отменён." >&2
    exit 1
fi

# Требование 5: незафиксированных изменений быть не должно
if ! git diff-index --quiet HEAD --; then
    echo "Ошибка: в репозитории есть незафиксированные изменения. Деплой отменён." >&2
    exit 1
fi

# ---- 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR} ----
RSYNC_OPTS=(-avz --delete --chmod=D755,F644)
RSYNC_SSH="ssh -o BatchMode=yes -o ConnectTimeout=5"

if $DRY_RUN; then
    echo "=== Пробный запуск (--dry-run) ==="
    rsync "${RSYNC_OPTS[@]}" --dry-run -e "${RSYNC_SSH}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    # ---- 4. При --dry-run — завершение с кодом 0 без проверки доступности ----
    echo "Пробный запуск завершён, изменения не внесены."
    exit 0
fi

echo "=== Доставка содержимого ==="
rsync "${RSYNC_OPTS[@]}" -e "${RSYNC_SSH}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# ---- 5. Проверка доступности ${SITE_URL} ----
echo "=== Проверка доступности ${SITE_URL} ==="
if ! curl -fsSk -o /dev/null "${SITE_URL}"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен." >&2
    exit 1
fi

# ---- 7. Успешное завершение — код 0 с коротким хешем ----
SHORT_HASH="$(git rev-parse --short HEAD)"
echo "Деплой успешен. Коммит: ${SHORT_HASH}"
exit 0