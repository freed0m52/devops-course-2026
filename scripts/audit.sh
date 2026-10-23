#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo " [OK]  $desc"
    ((PASS++))
  else
    echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
    ((FAIL++))
  fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
PORT=$(sudo sshd -T | awk '/^port/{print $2}')
if [[ "$PORT" != "22" && -n "$PORT" ]]; then
  echo " [OK]  Порт SSH отличен от 22 (текущий: $PORT)"
  ((PASS++))
else
  echo " [FAIL] Порт SSH не должен быть 22 (текущий: '$PORT')"
  ((FAIL++))
fi
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
DEFAULT_IN=$(sudo ufw status verbose | awk '/^Default:/{print $2}')
check "Политика по умолчанию deny incoming" "deny" "$DEFAULT_IN"

echo "[3] Учётные записи"
awk -F: ' $3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
if sudo nginx -t > /dev/null 2>&1; then
  echo " [OK]  Конфигурация nginx синтаксически корректна"
  ((PASS++))
else
  echo " [FAIL] Конфигурация nginx содержит ошибки"
  ((FAIL++))
fi

if sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend 2592000 -noout > /dev/null 2>&1; then
  echo " [OK]  Сертификат действителен более 30 дней"
  ((PASS++))
else
  echo " [FAIL] Сертификат истекает менее чем через 30 дней"
  ((FAIL++))
fi

WORLD_WRITABLE=$(sudo find /var/www/devops-site -perm -o+w 2>/dev/null)
if [[ -z "$WORLD_WRITABLE" ]]; then
  echo " [OK]  Файлов с правом записи для всех не найдено"
  ((PASS++))
else
  echo " [FAIL] Найдены файлы с правом записи для всех: $WORLD_WRITABLE"
  ((FAIL++))
fi

check "Права ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"

echo "[5] Контейнеризация"

# Проверка а) служба docker активна
DOCKER_STATE=$(systemctl is-active docker 2>/dev/null || true)
check "Служба docker активна" "active" "$DOCKER_STATE"

# Проверка б) контейнер СУБД healthy
DB_HEALTH=$(sudo docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo "not_found")
check "Контейнер СУБД healthy" "healthy" "$DB_HEALTH"

# Проверка в) порты 5000 и 5432 не прослушиваются вне 127.0.0.1
PORTS_OUT=$(ss -tln 2>/dev/null | grep -E ':(5000|5432)\b' | grep -v '127.0.0.1' | wc -l)
if [[ "$PORTS_OUT" -eq 0 ]]; then
  echo " [OK]  Порты 5000 и 5432 не прослушиваются вне 127.0.0.1"
  ((PASS++))
else
  echo " [FAIL] Найдены порты 5000 или 5432 вне 127.0.0.1"
  ((FAIL++))
fi

# Проверка г) права .env = 600
ENV_PERMS=$(stat -c '%a' ~/app/.env 2>/dev/null || echo "missing")
check "Права .env равны 600" "600" "$ENV_PERMS"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1