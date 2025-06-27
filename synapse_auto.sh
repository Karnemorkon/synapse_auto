#!/bin/bash
# ===================================================================================
#
# Інтерактивний скрипт для встановлення Matrix Synapse
# ===================================================================================

# Зупинити виконання скрипту, якщо виникне помилка
set -e

# --- Налаштування логування ---
LOG_DIR_PATH_FOR_SCRIPT=$(pwd)
LOG_FILENAME_FOR_SCRIPT="matrix_install_$(date +%Y-%m-%d_%H-%M-%S).log"
FULL_LOG_PATH_FOR_SCRIPT="$LOG_DIR_PATH_FOR_SCRIPT/$LOG_FILENAME_FOR_SCRIPT"

# Функція для виводу повідомлення на екран та в лог
log_echo() {
    echo "$@" # Вивід на екран
    if [ -n "$FULL_LOG_PATH_FOR_SCRIPT" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $@" >> "$FULL_LOG_PATH_FOR_SCRIPT"
    fi
}

# --- Перевірка прав доступу ---
if [[ $EUID -ne 0 ]]; then
   # Ініціалізуємо файл логу тут, якщо він ще не створений, для запису першої помилки
   if [ ! -f "$FULL_LOG_PATH_FOR_SCRIPT" ] && [ -n "$FULL_LOG_PATH_FOR_SCRIPT" ]; then
       echo "=== Початок сесії встановлення Matrix $(date) ===" > "$FULL_LOG_PATH_FOR_SCRIPT"
   fi
   log_echo "Помилка: Цей скрипт потрібно запускати з правами root або через sudo."
   exit 1
fi

# Ініціалізація файлу логу (якщо ще не створено)
if [ -n "$FULL_LOG_PATH_FOR_SCRIPT" ] && [ ! -f "$FULL_LOG_PATH_FOR_SCRIPT" ]; then
    echo "=== Початок сесії встановлення Matrix $(date) ===" > "$FULL_LOG_PATH_FOR_SCRIPT"
fi
log_echo "Файл логу сесії: $FULL_LOG_PATH_FOR_SCRIPT"
log_echo "Увага: Не всі інтерактивні запити будуть детально залоговані, але основні кроки, помилки та вивід команд - так."
echo # Порожній рядок для відокремлення

clear
log_echo "================================================="
log_echo " Ласкаво просимо до майстра встановлення Matrix! "
log_echo "================================================="
log_echo "" # Еквівалент echo

# --- Крок 1: Інтерактивне збирання інформації ---
log_echo "--- Крок 1: Інтерактивне збирання інформації ---"
BASE_DIR=$(pwd)"/matrix" # Базова директорія для всіх файлів Matrix
MAUTRIX_DOCKER_REGISTRY="dock.mau.dev" # Правильний домен для Docker образів Mautrix Bridges
ELEMENT_WEB_VERSION="v1.11.104" # Версія Element Web для завантаження. Перевірте актуальну на https://github.com/element-hq/element-web/releases

# Перевіряємо, чи існує базова директорія
if [ -d "$BASE_DIR" ]; then
    log_echo "Виявлено існуючу директорію Matrix ($BASE_DIR)."
    while true; do
        read -p "Ви хочете оновити існуюче встановлення (лише Docker образи) чи створити нове? (update/new) [new]: " INSTALL_MODE
        INSTALL_MODE=${INSTALL_MODE:-new}
        case $INSTALL_MODE in
            update|new) break;;
            *) echo "Некоректний вибір. Будь ласка, введіть 'update' або 'new'.";;
        esac
    done
    if [ "$INSTALL_MODE" = "update" ]; then
        log_echo "✅ Ви обрали оновлення існуючого встановлення. Будуть оновлені Docker образи."
        log_echo "-------------------------------------------------"
        log_echo "Крок: Оновлення Docker образів"
        log_echo "-------------------------------------------------"
        log_echo "⚠️ Важливо: Цей режим оновить лише Docker образи. Якщо в нових версіях програмного забезпечення змінився формат конфігураційних файлів,"
        log_echo "вам може знадобитися оновити їх вручну. Завжди робіть резервні копії перед оновленням!"
        log_echo "⏳ Завантажую нові образи (docker compose pull)..."
        if docker compose -f "$BASE_DIR/docker-compose.yml" pull >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1; then
            log_echo "✅ Нові образи успішно завантажено."
        else
            log_echo "⚠️ Помилка під час docker compose pull. Спроба продовжити..."
        fi

        log_echo "⏳ Перезапускаю Docker стек з новими образами (docker compose up -d --remove-orphans)..."
        if docker compose -f "$BASE_DIR/docker-compose.yml" up -d --remove-orphans >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1; then
            log_echo "✅ Docker стек успішно перезапущено з новими образами."
        else
            log_echo "❌ Помилка під час перезапуску Docker стеку. Перевірте логи: $FULL_LOG_PATH_FOR_SCRIPT"
            exit 1
        fi
        log_echo "✅ Оновлення завершено."
        exit 0
    fi
    log_echo "Ви обрали створити нове встановлення, але директорія $BASE_DIR вже існує."
    read -p "Видалити існуючу директорію Matrix ($BASE_DIR) та створити нове встановлення? (yes/no) [no]: " DELETE_EXISTING
    DELETE_EXISTING=${DELETE_EXISTING:-no}
    if [ "$DELETE_EXISTING" = "yes" ]; then
        log_echo "⏳ Видаляю існуючу директорію Matrix: $BASE_DIR..."
        sudo rm -rf "$BASE_DIR"
        log_echo "✅ Існуючу директорію Matrix видалено."
    else
        log_echo "❌ Скасовано встановлення. Будь ласка, видаліть директорію вручну або виберіть 'update'."
        exit 1
    fi
fi

# Запитуємо домен
DEFAULT_DOMAIN="example.ua"
DOMAIN_VALID=false
while [ "$DOMAIN_VALID" = false ]; do
    read -p "Введіть ваш домен для Matrix [$DEFAULT_DOMAIN]: " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ && ! "$DOMAIN" =~ \.\. ]]; then
        if [[ ! "$DOMAIN" =~ ^[-.] && ! "$DOMAIN" =~ [-.]$ && ! "$DOMAIN" =~ \.- && ! "$DOMAIN" =~ -\. ]]; then
            DOMAIN_VALID=true
        else
            echo "Некоректний формат домену: не може починатися/закінчуватися дефісом або крапкою, або містити '.-' або '-.'."
        fi
    else
        echo "Некоректний формат домену. Будь ласка, введіть домен у форматі 'example.com' або 'sub.example.com'."
        echo "Домен повинен містити принаймні одну крапку, складатися з літер, цифр, дефісів та крапок."
    fi
done
log_echo "Обраний домен: $DOMAIN"

# Запитуємо пароль для бази даних
while true; do
    read -sp "Створіть надійний пароль для бази даних PostgreSQL: " POSTGRES_PASSWORD
    echo
    read -sp "Повторіть пароль: " POSTGRES_PASSWORD_CONFIRM
    echo
    [ "$POSTGRES_PASSWORD" = "$POSTGRES_PASSWORD_CONFIRM" ] && break
    echo "Паролі не співпадають. Спробуйте ще раз."
done
log_echo "Пароль для PostgreSQL встановлено."

# Запитуємо про публічну реєстрацію
while true; do
    read -p "Дозволити публічну реєстрацію нових користувачів? (yes/no) [no]: " ALLOW_PUBLIC_REGISTRATION
    ALLOW_PUBLIC_REGISTRATION=${ALLOW_PUBLIC_REGISTRATION:-no}
    case "$ALLOW_PUBLIC_REGISTRATION" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done
log_echo "Публічна реєстрація: $ALLOW_PUBLIC_REGISTRATION"

# Запитуємо про федерацію
while true; do
    read -p "Увімкнути федерацію (спілкування з іншими Matrix-серверами)? (yes/no) [no]: " ENABLE_FEDERATION
    ENABLE_FEDERATION=${ENABLE_FEDERATION:-no}
    case "$ENABLE_FEDERATION" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done
log_echo "Федерація: $ENABLE_FEDERATION"

# Запитуємо про встановлення Element Web
while true; do
    read -p "Встановити Element Web (офіційний клієнт Matrix)? (yes/no) [yes]: " INSTALL_ELEMENT
    INSTALL_ELEMENT=${INSTALL_ELEMENT:-yes}
    case "$INSTALL_ELEMENT" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done
log_echo "Встановлення Element Web: $INSTALL_ELEMENT"

echo
log_echo "--- Налаштування доступу до вашого Matrix-сервера ---"
echo "Ви можете використовувати Cloudflare Tunnel або Let's Encrypt через Nginx Proxy Manager (NPM)."
echo "Cloudflare Tunnel: Приховує IP вашого сервера, зручно, якщо ваш сервер за NAT."
echo "Let's Encrypt (NPM): Стандартний SSL-сертифікат для прямого доступу, вимагає відкритих портів 80/443."
echo "Одночасно використовувати їх не рекомендовано для одного домену."

USE_CLOUDFLARE_TUNNEL="no"
USE_NPM="no"
read -p "Використовувати Cloudflare Tunnel для доступу? (yes/no) [yes]: " USE_CLOUDFLARE_TUNNEL
USE_CLOUDFLARE_TUNNEL=${USE_CLOUDFLARE_TUNNEL:-yes}

CLOUDFLARE_TUNNEL_TOKEN=""
if [ "$USE_CLOUDFLARE_TUNNEL" = "yes" ]; then
    log_echo "Обрано Cloudflare Tunnel."
    echo "Для Cloudflare Tunnel вам потрібен токен тунелю."
    echo "Його можна отримати на панелі керування Cloudflare Zero Trust (Access -> Tunnels)."
    read -p "Введіть токен Cloudflare Tunnel: " CLOUDFLARE_TUNNEL_TOKEN
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        log_echo "❌ Токен Cloudflare Tunnel не може бути порожнім, якщо ви обрали Cloudflare Tunnel. Скасовано."
        exit 1
    fi
    log_echo "Токен Cloudflare Tunnel надано."
    USE_NPM="no"
else
    log_echo "Cloudflare Tunnel не обрано."
    read -p "Використовувати Nginx Proxy Manager (NPM) з Let's Encrypt для доступу? (yes/no) [no]: " USE_NPM
    USE_NPM=${USE_NPM:-no}
    if [ "$USE_NPM" = "yes" ]; then
        log_echo "✅ Ви обрали Nginx Proxy Manager. Переконайтеся, що порти 80 та 443 доступні."
    else
        log_echo "Nginx Proxy Manager не обрано."
    fi
fi

echo
log_echo "--- Налаштування мостів (ботів) ---"
echo "Мости дозволяють інтегрувати Matrix з іншими месенджерами."

INSTALL_SIGNAL_BRIDGE="no"
INSTALL_WHATSAPP_BRIDGE="no"
INSTALL_TELEGRAM_BRIDGE="no"
INSTALL_DISCORD_BRIDGE="no"

read -p "Встановити Signal Bridge (для спілкування з користувачами Signal)? (yes/no) [no]: " INSTALL_SIGNAL_BRIDGE
INSTALL_SIGNAL_BRIDGE=${INSTALL_SIGNAL_BRIDGE:-no}
log_echo "Встановлення Signal Bridge: $INSTALL_SIGNAL_BRIDGE"

read -p "Встановити WhatsApp Bridge (для спілкування з користувачами WhatsApp)? (yes/no) [no]: " INSTALL_WHATSAPP_BRIDGE
INSTALL_WHATSAPP_BRIDGE=${INSTALL_WHATSAPP_BRIDGE:-no}
log_echo "Встановлення WhatsApp Bridge: $INSTALL_WHATSAPP_BRIDGE"

read -p "Встановити Telegram Bridge (для спілкування з користувачами Telegram)? (yes/no) [no]: " INSTALL_TELEGRAM_BRIDGE
INSTALL_TELEGRAM_BRIDGE=${INSTALL_TELEGRAM_BRIDGE:-no}
log_echo "Встановлення Telegram Bridge: $INSTALL_TELEGRAM_BRIDGE"

read -p "Встановити Discord Bridge (для спілкування з користувачами Discord)? (yes/no) [no]: " INSTALL_DISCORD_BRIDGE
INSTALL_DISCORD_BRIDGE=${INSTALL_DISCORD_BRIDGE:-no}
log_echo "Встановлення Discord Bridge: $INSTALL_DISCORD_BRIDGE"

# Запитуємо про встановлення Portainer
while true; do
    read -p "Встановити Portainer (веб-інтерфейс для керування Docker)? (yes/no) [yes]: " INSTALL_PORTAINER
    INSTALL_PORTAINER=${INSTALL_PORTAINER:-yes}
    case "$INSTALL_PORTAINER" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done
log_echo "Встановлення Portainer: $INSTALL_PORTAINER"

log_echo "-------------------------------------------------"
log_echo "Перевірка налаштувань:"
log_echo "Домен: $DOMAIN"
log_echo "Базова директорія: $BASE_DIR"
log_echo "Публічна реєстрація: $ALLOW_PUBLIC_REGISTRATION"
log_echo "Федерація: $ENABLE_FEDERATION"
log_echo "Встановлення Element Web: $INSTALL_ELEMENT"
log_echo "Використання Cloudflare Tunnel: $USE_CLOUDFLARE_TUNNEL"
log_echo "Використання Let's Encrypt (NPM): $USE_NPM"
log_echo "Встановлення Portainer: $INSTALL_PORTAINER"
log_echo "Встановлення Signal Bridge: $INSTALL_SIGNAL_BRIDGE"
log_echo "Встановлення WhatsApp Bridge: $INSTALL_WHATSAPP_BRIDGE"
log_echo "Встановлення Telegram Bridge: $INSTALL_TELEGRAM_BRIDGE"
log_echo "Встановлення Discord Bridge: $INSTALL_DISCORD_BRIDGE"
log_echo "-------------------------------------------------"
read -p "Натисніть Enter для продовження або Ctrl+C для скасування..."

# --- Функції ---
install_docker_dependencies() {
    log_echo "--- Функція: install_docker_dependencies ---"
    log_echo "⏳ Оновлюю списки пакетів..."
    apt update -y >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
    log_echo "✅ Списки пакетів оновлено."

    log_echo "⏳ Встановлюю базові пакети (curl, apt-transport-https, ca-certificates, gnupg)..."
    apt install -y curl apt-transport-https ca-certificates gnupg >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
    log_echo "✅ Базові пакети встановлено."

    log_echo "⏳ Встановлюю Docker Engine..."
    if ! systemctl is-active --quiet docker; then
        install -m 0755 -d /etc/apt/keyrings >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        fi
        if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
                $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        fi
        apt update -y >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        log_echo "✅ Docker Engine встановлено."
    else
        log_echo "✅ Docker вже встановлено."
    fi

    log_echo "⏳ Встановлюю Docker Compose..."
    # Перевіряємо спочатку плагін, потім окрему команду
    if docker compose version >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1; then
        log_echo "✅ Docker Compose (plugin) вже встановлено або встановлюється з Docker Engine."
    elif command -v docker-compose &> /dev/null; then
        log_echo "✅ Docker Compose (standalone) вже встановлено."
    else
        log_echo "❌ Docker Compose не знайдено. Docker Engine було встановлено з плагіном, але команда 'docker compose' недоступна, або Docker Engine не встановлено коректно."
        log_echo "Будь ласка, перевірте встановлення Docker та Docker Compose."
        # Спроба встановити docker-compose-plugin ще раз, якщо він не підтягнувся
        log_echo "Спроба доставити docker-compose-plugin..."
        apt install -y docker-compose-plugin >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        if docker compose version >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1; then
            log_echo "✅ Docker Compose (plugin) успішно доставлено."
        else
            log_echo "❌ Не вдалося встановити Docker Compose. Будь ласка, встановіть його вручну."
            exit 1
        fi
    fi
    log_echo "--- Кінець функції: install_docker_dependencies ---"
}


# --- Крок 2: Встановлення необхідних залежностей ---
log_echo "-------------------------------------------------"
log_echo "Крок: Встановлення необхідних залежностей"
log_echo "-------------------------------------------------"
install_docker_dependencies

if [ "$INSTALL_PORTAINER" = "yes" ]; then
    log_echo "⏳ Запускаю Portainer..."
    if ! docker ps -a --format '{{.Names}}' | grep -q "portainer"; then
        docker volume create portainer_data >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        docker run -d -p 8000:8000 -p 9443:9443 --name portainer \
            --restart always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
        log_echo "✅ Portainer запущено. Доступно за адресою https://<IP_вашого_сервера>:9443"
    else
        log_echo "✅ Portainer вже запущено."
    fi
fi

# --- Крок 3: Підготовка структури папок та генерація конфігурацій ---
log_echo "-------------------------------------------------"
log_echo "Крок: Підготовка структури папок та генерація конфігурацій"
log_echo "-------------------------------------------------"

log_echo "⏳ Створюю структуру папок у $BASE_DIR..."
mkdir -p "$BASE_DIR/synapse/config"
mkdir -p "$BASE_DIR/synapse/data"
mkdir -p "$BASE_DIR/element"
mkdir -p "$BASE_DIR/certs"

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    mkdir -p "$BASE_DIR/signal-bridge/config"
    mkdir -p "$BASE_DIR/signal-bridge/data"
fi
if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    mkdir -p "$BASE_DIR/whatsapp-bridge/config"
    mkdir -p "$BASE_DIR/whatsapp-bridge/data"
fi
if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    mkdir -p "$BASE_DIR/telegram-bridge/config"
    mkdir -p "$BASE_DIR/telegram-bridge/data"
fi
if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    mkdir -p "$BASE_DIR/discord-bridge/config"
    mkdir -p "$BASE_DIR/discord-bridge/data"
fi
log_echo "✅ Структуру папок створено."

log_echo "⏳ Генерую конфігураційний файл для Synapse (homeserver.yaml)..."
sudo docker run --rm \
    -v "$BASE_DIR/synapse/config:/data" \
    -e SYNAPSE_SERVER_NAME="$DOMAIN" \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1

log_echo "⏳ Встановлюю права доступу для homeserver.yaml та ключа підпису..."
if [ -f "$BASE_DIR/synapse/config/homeserver.yaml" ]; then
    sudo chown 991:991 "$BASE_DIR/synapse/config/homeserver.yaml"
    sudo chmod 600 "$BASE_DIR/synapse/config/homeserver.yaml"
else
    log_echo "⚠️ Попередження: Файл homeserver.yaml не знайдено для встановлення прав."
fi

if [ -f "$BASE_DIR/synapse/config/$DOMAIN.signing.key" ]; then
    sudo chown 991:991 "$BASE_DIR/synapse/config/$DOMAIN.signing.key"
    sudo chmod 600 "$BASE_DIR/synapse/config/$DOMAIN.signing.key"
else
    log_echo "⚠️ Попередження: Файл ключа підпису $DOMAIN.signing.key не знайдено у конфігураційній директорії для встановлення прав."
fi

SIGNING_KEY_IN_DATA_DIR="$BASE_DIR/synapse/data/$DOMAIN.signing.key"
SIGNING_KEY_IN_CONFIG_DIR="$BASE_DIR/synapse/config/$DOMAIN.signing.key"

if [ ! -f "$SIGNING_KEY_IN_DATA_DIR" ] && [ -f "$SIGNING_KEY_IN_CONFIG_DIR" ]; then
    log_echo "⏳ Копіюю ключ підпису до директорії даних Synapse..."
    cp "$SIGNING_KEY_IN_CONFIG_DIR" "$SIGNING_KEY_IN_DATA_DIR"
fi

log_echo "⏳ Встановлюю власника для директорії даних Synapse ($BASE_DIR/synapse/data)..."
sudo chown -R 991:991 "$BASE_DIR/synapse/data"
if [ -f "$SIGNING_KEY_IN_DATA_DIR" ]; then
    sudo chmod 600 "$SIGNING_KEY_IN_DATA_DIR"
fi
log_echo "✅ homeserver.yaml згенеровано та права доступу оновлено."

generate_bridge_config() {
    local bridge_name_human="$1"
    local bridge_dir_name="$2"
    local bridge_image_name="$3"
    local bridge_config_file_path="$BASE_DIR/$bridge_dir_name/config/config.yaml"

    log_echo "⏳ Генерую конфігураційний файл для $bridge_name_human ($bridge_config_file_path)..."
    # Переконуємося, що директорія існує
    mkdir -p "$BASE_DIR/$bridge_dir_name/config"

    # Використовуємо sudo для docker run, оскільки команда може потребувати створення файлів у системних директоріях (хоча тут це /data всередині контейнера)
    # Перенаправляємо stdout (>), а stderr додаємо до основного логу (2>&1)
    if sudo docker run --rm \
        -v "$BASE_DIR/$bridge_dir_name/config:/data" \
        -e CONFIG_PATH=/data/config.yaml \
        "$bridge_image_name" -g > "$bridge_config_file_path" 2>> "$FULL_LOG_PATH_FOR_SCRIPT"; then
        sudo chmod 600 "$bridge_config_file_path"
        log_echo "✅ Конфігураційний файл для $bridge_name_human згенеровано та встановлено права."
    else
        log_echo "❌ Помилка генерації конфігураційного файлу для $bridge_name_human. Див. деталі вище або в $FULL_LOG_PATH_FOR_SCRIPT."
        # Можна додати exit 1, якщо це критично
    fi
}

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    generate_bridge_config "Signal Bridge" "signal-bridge" "$MAUTRIX_DOCKER_REGISTRY/mautrix-signal:latest"
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    generate_bridge_config "WhatsApp Bridge" "whatsapp-bridge" "$MAUTRIX_DOCKER_REGISTRY/mautrix-whatsapp:latest"
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    generate_bridge_config "Telegram Bridge" "telegram-bridge" "$MAUTRIX_DOCKER_REGISTRY/mautrix-telegram:latest"
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    generate_bridge_config "Discord Bridge" "discord-bridge" "$MAUTRIX_DOCKER_REGISTRY/mautrix-discord:latest"
fi

# --- Крок 4: Налаштування конфігураційних файлів ---
log_echo "-------------------------------------------------"
log_echo "Крок: Налаштування конфігураційних файлів"
log_echo "-------------------------------------------------"

HOMESERVER_CONFIG="$BASE_DIR/synapse/config/homeserver.yaml"

log_echo "⏳ Налаштовую базу даних PostgreSQL в homeserver.yaml..."
sed -i "s|#url: postgres://user:password@host:port/database|url: postgres://matrix_user:$POSTGRES_PASSWORD@postgres:5432/matrix_db|" "$HOMESERVER_CONFIG"
sed -i "/database:/a \ \   # Explicitly set the database type to pg (PostgreSQL)\n    name: pg" "$HOMESERVER_CONFIG"
log_echo "✅ Базу даних PostgreSQL налаштовано."

if [ "$ALLOW_PUBLIC_REGISTRATION" = "yes" ]; then
    log_echo "⏳ Вмикаю публічну реєстрацію в $HOMESERVER_CONFIG..."
    sed -i "s|enable_registration: false|enable_registration: true|" "$HOMESERVER_CONFIG"
    log_echo "✅ Публічну реєстрацію увімкнено."
else
    log_echo "✅ Публічна реєстрація вимкнена (за замовчуванням)."
fi

if [ "$ENABLE_FEDERATION" = "no" ]; then
    log_echo "⏳ Вимикаю федерацію в $HOMESERVER_CONFIG..."
    if ! grep -q "federation_enabled: false" "$HOMESERVER_CONFIG"; then # Запобігання дублюванню
        sed -i "/#federation_client_minimum_tls_version:/a \ \ federation_enabled: false" "$HOMESERVER_CONFIG"
    fi
    log_echo "✅ Федерацію вимкнено."
else
    log_echo "✅ Федерація увімкнена (за замовчуванням)."
fi

log_echo "⏳ Додаю налаштування мостів до $HOMESERVER_CONFIG..."
if ! grep -q "app_service_config_files:" "$HOMESERVER_CONFIG"; then # Запобігання дублюванню
cat <<EOF >> "$HOMESERVER_CONFIG"

# Mautrix Bridges Configuration
app_service_config_files:
EOF
fi

ensure_app_service_registered() {
    local service_file_path="$1"
    # Перевіряємо, чи шлях вже існує в файлі, ігноруючи пробіли на початку рядка
    if ! grep -q "^\s*-\s*$service_file_path" "$HOMESERVER_CONFIG"; then
        log_echo "Додаю $service_file_path до app_service_config_files"
        echo "  - $service_file_path" >> "$HOMESERVER_CONFIG"
    else
        log_echo "$service_file_path вже зареєстровано в app_service_config_files"
    fi
}

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    ensure_app_service_registered "/data/signal-registration.yaml"
fi
if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    ensure_app_service_registered "/data/whatsapp-registration.yaml"
fi
if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    ensure_app_service_registered "/data/telegram-registration.yaml"
fi
if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    ensure_app_service_registered "/data/discord-registration.yaml"
fi
log_echo "✅ Конфігурацію Synapse оновлено для мостів."

if [ "$INSTALL_ELEMENT" = "yes" ]; then
    log_echo "⏳ Завантажую та налаштовую Element Web..."
    ELEMENT_TAR="element-$ELEMENT_WEB_VERSION.tar.gz"
    ELEMENT_URL="https://github.com/element-hq/element-web/releases/download/$ELEMENT_WEB_VERSION/$ELEMENT_TAR"

    log_echo "Завантажую Element Web версії: $ELEMENT_WEB_VERSION з $ELEMENT_URL"
    curl -L "$ELEMENT_URL" -o "$BASE_DIR/$ELEMENT_TAR" >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
    log_echo "Розпаковую $ELEMENT_TAR до $BASE_DIR/element..."
    tar -xzf "$BASE_DIR/$ELEMENT_TAR" -C "$BASE_DIR/element" --strip-components=1
    rm "$BASE_DIR/$ELEMENT_TAR"

    log_echo "Створюю конфігураційний файл для Element: $BASE_DIR/element/config.json"
    cat <<EOF > "$BASE_DIR/element/config.json"
{
    "default_server_name": "$DOMAIN",
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$DOMAIN",
            "server_name": "$DOMAIN"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "default_identity_server": "https://vector.im",
    "disable_custom_homeserver": false,
    "show_labs_settings": true,
    "brand": "Matrix ($DOMAIN)"
}
EOF
    log_echo "✅ Element Web завантажено та налаштовано."
else
    log_echo "✅ Встановлення Element Web пропущено."
fi

# --- Крок 4.5: Перевірка доступності портів ---
log_echo "-------------------------------------------------"
log_echo "Крок: Перевірка доступності портів"
log_echo "-------------------------------------------------"

check_port_available() {
    local port_to_check=$1
    local service_name=$2
    log_echo "⏳ Перевіряю доступність порту $port_to_check для $service_name..."
    if command -v ss &> /dev/null && ss -tuln | grep -q ":$port_to_check\s" ; then
        log_echo "❌ Помилка: Порт $port_to_check вже використовується іншим процесом (перевірено за допомогою ss)."
        echo "Будь ласка, зупиніть сервіс, що використовує цей порт."
        echo "Ви можете використати 'sudo ss -tulnp | grep :$port_to_check' для ідентифікації процесу."
        return 1
    elif command -v netstat &> /dev/null && netstat -tuln | grep -q ":$port_to_check\s" ; then
        log_echo "❌ Помилка: Порт $port_to_check вже використовується іншим процесом (перевірено за допомогою netstat)."
        echo "Будь ласка, зупиніть сервіс, що використовує цей порт."
        echo "Ви можете використати 'sudo netstat -tulnp | grep :$port_to_check' для ідентифікації процесу."
        return 1
    elif ! command -v ss &> /dev/null && ! command -v netstat &> /dev/null; then
        log_echo "⚠️ Попередження: Команди 'ss' та 'netstat' не знайдено. Не можу перевірити доступність порту $port_to_check."
        return 0
    else
        log_echo "✅ Порт $port_to_check вільний для $service_name."
        return 0
    fi
}

PORTS_OK=true
if [ "$INSTALL_PORTAINER" = "yes" ]; then
    check_port_available 9443 "Portainer HTTPS" || PORTS_OK=false
    check_port_available 8000 "Portainer Edge Agent" || PORTS_OK=false
fi
check_port_available 8080 "Synapse Admin Panel" || PORTS_OK=false

if [ "$INSTALL_ELEMENT" = "yes" ]; then
    if [ "$USE_CLOUDFLARE_TUNNEL" = "no" ] && [ "$USE_NPM" = "no" ]; then
        check_port_available 80 "Element Web (HTTP)" || PORTS_OK=false
    fi
fi
if [ "$USE_CLOUDFLARE_TUNNEL" = "no" ]; then
    check_port_available 8008 "Synapse Client-Server API" || PORTS_OK=false
    check_port_available 8448 "Synapse Federation API" || PORTS_OK=false
fi

if [ "$PORTS_OK" = false ]; then
    log_echo "❌ Виявлено конфлікти портів. Будь ласка, вирішіть їх перед продовженням або переналаштуйте сервіси, що їх займають."
    exit 1
fi
log_echo "✅ Усі необхідні порти виглядають вільними."
echo

# --- Крок 5: Створення файлу docker-compose.yml ---
log_echo "-------------------------------------------------"
log_echo "Крок: Створення файлу docker-compose.yml у $BASE_DIR/docker-compose.yml"
log_echo "-------------------------------------------------"

SYNAPSE_PORTS=""
if [ "$USE_CLOUDFLARE_TUNNEL" = "yes" ]; then
    SYNAPSE_PORTS=""
else
    SYNAPSE_PORTS="- \"8008:8008\"\n      - \"8448:8448\""
fi

cat <<EOF > "$BASE_DIR/docker-compose.yml"
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    volumes:
      - ./synapse/data/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: matrix_db
      POSTGRES_USER: matrix_user
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD

  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    depends_on:
      - postgres
    volumes:
      - ./synapse/config:/data
      - ./synapse/data:/synapse/data
      - ./signal-bridge/config/registration.yaml:/data/signal-registration.yaml:ro
      - ./whatsapp-bridge/config/registration.yaml:/data/whatsapp-registration.yaml:ro
      - ./telegram-bridge/config/registration.yaml:/data/telegram-registration.yaml:ro
      - ./discord-bridge/config/registration.yaml:/data/discord-registration.yaml:ro
    environment:
      SYNAPSE_SERVER_NAME: $DOMAIN
      SYNAPSE_REPORT_STATS: "no"
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
    ports:
$SYNAPSE_PORTS
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8008/_matrix/client/versions || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  synapse-admin:
    image: awesometechs/synapse-admin:latest
    restart: unless-stopped
    depends_on:
      - synapse
    environment:
      SYNAPSE_URL: http://synapse:8008
      SYNAPSE_SERVER_NAME: $DOMAIN
    ports:
      - "8080:80"

EOF

if [ "$INSTALL_ELEMENT" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  element:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./element:/usr/share/nginx/html:ro
    ports:
      - "80:80"
EOF
fi

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  signal-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-signal:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./signal-bridge/config:/data:z
      - ./signal-bridge/data:/data_bridge:z
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=signal"
EOF
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  whatsapp-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-whatsapp:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./whatsapp-bridge/config:/data:z
      - ./whatsapp-bridge/data:/data_bridge:z
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=whatsapp"
EOF
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  telegram-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-telegram:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./telegram-bridge/config:/data:z
      - ./telegram-bridge/data:/data_bridge:z
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=telegram"
EOF
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  discord-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-discord:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./discord-bridge/config:/data:z
      - ./discord-bridge/data:/data_bridge:z
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=discord"
EOF
fi

if [ "$USE_CLOUDFLARE_TUNNEL" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel run --token $CLOUDFLARE_TUNNEL_TOKEN
    environment:
      TUNNEL_TOKEN: $CLOUDFLARE_TUNNEL_TOKEN
EOF
fi
log_echo "✅ Файл docker-compose.yml створено."

# --- Крок 6: Запуск Docker стеку та фінальне налаштування ---
log_echo "-------------------------------------------------"
log_echo "Крок: Запуск Docker стеку та фінальне налаштування"
log_echo "-------------------------------------------------"

log_echo "⏳ Завантажую Docker образи (docker compose pull)..."
cd "$BASE_DIR"
docker compose pull >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
log_echo "✅ Образи завантажено."
log_echo "⏳ Запускаю Docker стек (docker compose up -d)..."
docker compose up -d >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1
log_echo "✅ Docker стек запущено успішно."

log_echo "⏳ Чекаю, поки Matrix Synapse завантажиться (максимум 180 секунд)..."
for i in $(seq 1 18); do
    log_echo "Перевірка Synapse... (спроба $i, пройшло $(( (i-1)*10 )) секунд)..."
    if curl -sf http://localhost:8008/_matrix/client/versions > /dev/null; then
        log_echo "✅ Matrix Synapse запущено!"
        break
    fi
    if [ $i -eq 18 ]; then
        log_echo "❌ Помилка: Matrix Synapse не запустився після 180 секунд."
        log_echo "Будь ласка, вручну перевірте логи контейнера 'synapse' (зазвичай '$BASE_DIR' або 'matrix_synapse_1') за допомогою 'docker logs <container_name>'."
        log_echo "Також перевірте лог Synapse всередині контейнера: docker exec <container_name> cat /data/homeserver.log"
        log_echo "Можливо, вам знадобиться збільшити ліміти пам'яті для контейнера Synapse, якщо у вас недостатньо RAM."
        exit 1
    fi
    sleep 10
done

log_echo "⏳ Генерую файли реєстрації для мостів..."

generate_bridge_registration() {
    local bridge_name_human="$1"
    local bridge_service_name_in_compose="$2" # Наприклад, "signal-bridge"
    local bridge_registration_file_path_in_synapse_container="$3" # Наприклад, "/data/signal-registration.yaml"
    local bridge_appservice_id="$4" # Наприклад, "io.mau.bridge.signal"
    # Порт моста зазвичай 8000 для Mautrix мостів
    local bridge_internal_url="http://${bridge_service_name_in_compose}:8000"

    log_echo "Генерую реєстраційний файл для $bridge_name_human..."
    # Переконуємося, що ми в директорії $BASE_DIR для docker compose exec
    # cd "$BASE_DIR" # Це вже робиться перед викликом цієї функції
    if sudo docker compose exec synapse generate_registration \
        --force \
        -u "$bridge_internal_url" \
        -c "$bridge_registration_file_path_in_synapse_container" \
        "$bridge_appservice_id" >> "$FULL_LOG_PATH_FOR_SCRIPT" 2>&1; then
        log_echo "✅ Реєстраційний файл для $bridge_name_human згенеровано."
    else
        log_echo "❌ Помилка генерації реєстраційного файлу для $bridge_name_human. Див. $FULL_LOG_PATH_FOR_SCRIPT."
    fi
}

# Перебуваємо в $BASE_DIR перед генерацією реєстрацій
cd "$BASE_DIR"

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    generate_bridge_registration "Signal Bridge" "signal-bridge" "/data/signal-registration.yaml" "io.mau.bridge.signal"
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    generate_bridge_registration "WhatsApp Bridge" "whatsapp-bridge" "/data/whatsapp-registration.yaml" "io.mau.bridge.whatsapp"
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    generate_bridge_registration "Telegram Bridge" "telegram-bridge" "/data/telegram-registration.yaml" "io.mau.bridge.telegram"
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    generate_bridge_registration "Discord Bridge" "discord-bridge" "/data/discord-registration.yaml" "io.mau.bridge.discord"
fi
# Повертаємося до попередньої директорії, якщо це потрібно (хоча скрипт майже завершено)
# cd - > /dev/null

log_echo "-------------------------------------------------"
log_echo "           ВСТАНОВЛЕННЯ ЗАВЕРШЕНО!             "
log_echo "-------------------------------------------------"
log_echo ""
log_echo "ВАШІ НАСТУПНІ КРОКИ:"
log_echo "1. Зайдіть в Portainer: https://<IP_вашого_сервера>:9443 (якщо встановлено)"
log_echo "   (Вам потрібно буде створити обліковий запис адміністратора при першому вході)."
log_echo ""
log_echo "2. Якщо ви використовували Cloudflare Tunnel, переконайтеся, що ви налаштували DNS-записи та правила тунелю в Cloudflare Zero Trust."
log_echo "   Доступ до сервісів буде через ваш домен $DOMAIN, наприклад:"
log_echo "   - Matrix (Synapse): https://$DOMAIN (клієнти будуть використовувати цей домен)"
log_echo "   - Element Web: https://$DOMAIN (якщо встановлено та налаштовано в тунелі)"
log_echo "   - Synapse Admin: https://$DOMAIN/synapse-admin (якщо налаштовано в тунелі)"
log_echo "   - Portainer: https://$DOMAIN/portainer (якщо налаштовано в тунелі)"
log_echo ""
log_echo "3. Якщо ви НЕ використовували Cloudflare Tunnel:"
log_echo "   - Ваш Matrix Home Server (Synapse) доступний за адресою: http://<IP_вашого_сервера>:8008 та https://<IP_вашого_сервера>:8448"
if [ "$INSTALL_ELEMENT" = "yes" ]; then
    log_echo "   - Element Web буде доступний за адресою: http://<IP_вашого_сервера>:80 (якщо не використовується NPM для SSL)"
fi
log_echo "   - Synapse Admin Panel доступна за адресою: http://<IP_вашого_сервера>:8080"
log_echo ""
log_echo "4. Для управління мостами (Signal, WhatsApp тощо):"
log_echo "   a. Зайдіть у Portainer (якщо встановлено) -> Stacks -> matrix."
log_echo "   b. Перейдіть до відповідного контейнера моста (наприклад, 'matrix-signal-bridge-1')." # Назви можуть трохи відрізнятися
log_echo "   c. Перегляньте 'Logs' для інструкцій з реєстрації моста. Зазвичай це команди типу \`!signal login\` в Matrix."
log_echo ""
log_echo "5. Для створення першого адміністративного користувача Matrix (якщо публічна реєстрація вимкнена або ви хочете створити його вручну):"
log_echo "   cd $BASE_DIR"
log_echo "   sudo docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml -a -u <username> -p <password> http://localhost:8008"
log_echo "   (замініть <username> та <password> на бажані)"
log_echo ""
log_echo "--- РЕКОМЕНДАЦІЇ ЩОДО РЕЗЕРВНОГО КОПІЮВАННЯ ---"
log_echo "Дуже важливо регулярно робити резервні копії вашого Matrix сервера!"
log_echo "Ключові директорії для резервного копіювання:"
log_echo "  - Postgres база даних: $BASE_DIR/synapse/data/postgres"
log_echo "  - Synapse медіа та ключі: $BASE_DIR/synapse/data (за виключенням postgres)"
log_echo "  - Конфігурація Synapse: $BASE_DIR/synapse/config"
log_echo "  - Конфігурації мостів (якщо встановлені):"
if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then log_echo "    - Signal: $BASE_DIR/signal-bridge/config та $BASE_DIR/signal-bridge/data"; fi
if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then log_echo "    - WhatsApp: $BASE_DIR/whatsapp-bridge/config та $BASE_DIR/whatsapp-bridge/data"; fi
if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then log_echo "    - Telegram: $BASE_DIR/telegram-bridge/config та $BASE_DIR/telegram-bridge/data"; fi
if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then log_echo "    - Discord: $BASE_DIR/discord-bridge/config та $BASE_DIR/discord-bridge/data"; fi
log_echo "  - Файл docker-compose.yml: $BASE_DIR/docker-compose.yml"
log_echo "Розгляньте використання інструментів типу pg_dump для консистентного бекапу PostgreSQL."
log_echo "-------------------------------------------------"
log_echo ""
log_echo "Успіхів! Перевірте файл логу: $FULL_LOG_PATH_FOR_SCRIPT для деталей встановлення."
log_echo "=== Завершення сесії встановлення Matrix $(date) ==="
