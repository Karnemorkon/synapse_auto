#!/bin/bash
# ===================================================================================
#
# Інтерактивний скрипт для встановлення Matrix Synapse
# ===================================================================================

# Зупинити виконання скрипту, якщо виникне помилка
set -e

# --- Перевірка прав доступу ---
if [[ $EUID -ne 0 ]]; then
   echo "Помилка: Цей скрипт потрібно запускати з правами root або через sudo."
   exit 1
fi

clear
echo "================================================="
echo " Ласкаво просимо до майстра встановлення Matrix! "
echo "================================================="
echo

# --- Крок 1: Інтерактивне збирання інформації ---
BASE_DIR=(pwd)"/matrix" # Базова директорія для всіх файлів Matrix
MAUTRIX_DOCKER_REGISTRY="dock.mau.dev" # Правильний домен для Docker образів Mautrix Bridges

# Перевіряємо, чи існує базова директорія
if [ -d "$BASE_DIR" ]; then
    echo "Виявлено існуючу директорію Matrix ($BASE_DIR)."
    while true; do
        read -p "Ви хочете оновити існуюче встановлення (лише Docker образи) чи створити нове? (update/new) [new]: " INSTALL_MODE
        INSTALL_MODE=${INSTALL_MODE:-new}
        case $INSTALL_MODE in
            update|new) break;;
            *) echo "Некоректний вибір. Будь ласка, введіть 'update' або 'new'.";;
        esac
    done
    if [ "$INSTALL_MODE" = "update" ]; then
        echo "✅ Ви обрали оновлення існуючого встановлення. Будуть оновлені Docker образи."
        # Переходимо до кроку оновлення
        echo "-------------------------------------------------"
        echo "Крок: Оновлення Docker образів"
        echo "-------------------------------------------------"
        # Просто запускаємо docker compose pull
        docker compose -f "$BASE_DIR/docker-compose.yml" pull || true # Дозволяємо помилку, якщо стек не повністю готовий
        echo "✅ Docker образи оновлено та стек перезапущено."
        exit 0 # Виходимо після оновлення образів
    fi
    # Якщо обрано "new", але директорія існує, запитаємо про видалення
    echo "Ви обрали створити нове встановлення, але директорія $BASE_DIR вже існує."
    read -p "Видалити існуючу директорію Matrix ($BASE_DIR) та створити нове встановлення? (yes/no) [no]: " DELETE_EXISTING
    DELETE_EXISTING=${DELETE_EXISTING:-no}
    if [ "$DELETE_EXISTING" = "yes" ]; then
        echo "⏳ Видаляю існуючу директорію Matrix..."
        sudo rm -rf "$BASE_DIR"
        echo "✅ Існуючу директорію Matrix видалено."
    else
        echo "❌ Скасовано встановлення. Будь ласка, видаліть директорію вручну або виберіть 'update'."
        exit 1
    fi
fi

# Запитуємо домен
DEFAULT_DOMAIN="example.ua"
read -p "Введіть ваш домен для Matrix [$DEFAULT_DOMAIN]: " DOMAIN
DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

# Запитуємо пароль для бази даних
while true; do
    read -sp "Створіть надійний пароль для бази даних PostgreSQL: " POSTGRES_PASSWORD
    echo
    read -sp "Повторіть пароль: " POSTGRES_PASSWORD_CONFIRM
    echo
    [ "$POSTGRES_PASSWORD" = "$POSTGRES_PASSWORD_CONFIRM" ] && break
    echo "Паролі не співпадають. Спробуйте ще раз."
done

# Запитуємо про публічну реєстрацію
while true; do
    read -p "Дозволити публічну реєстрацію нових користувачів? (yes/no) [no]: " ALLOW_PUBLIC_REGISTRATION
    ALLOW_PUBLIC_REGISTRATION=${ALLOW_PUBLIC_REGISTRATION:-no}
    case "$ALLOW_PUBLIC_REGISTRATION" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done

# Запитуємо про федерацію
while true; do
    read -p "Увімкнути федерацію (спілкування з іншими Matrix-серверами)? (yes/no) [no]: " ENABLE_FEDERATION
    ENABLE_FEDERATION=${ENABLE_FEDERATION:-no}
    case "$ENABLE_FEDERATION" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done

# Запитуємо про встановлення Element Web
while true; do
    read -p "Встановити Element Web (офіційний клієнт Matrix)? (yes/no) [yes]: " INSTALL_ELEMENT
    INSTALL_ELEMENT=${INSTALL_ELEMENT:-yes}
    case "$INSTALL_ELEMENT" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done

echo
echo "--- Налаштування доступу до вашого Matrix-сервера ---"
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
    echo "Для Cloudflare Tunnel вам потрібен токен тунелю."
    echo "Його можна отримати на панелі керування Cloudflare Zero Trust (Access -> Tunnels)."
    read -p "Введіть токен Cloudflare Tunnel: " CLOUDFLARE_TUNNEL_TOKEN
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        echo "❌ Токен Cloudflare Tunnel не може бути порожнім, якщо ви обрали Cloudflare Tunnel. Скасовано."
        exit 1
    fi
else
    # Якщо Cloudflare Tunnel не використовується, пропонуємо NPM
    read -p "Використовувати Nginx Proxy Manager (NPM) з Let's Encrypt для доступу? (yes/no) [no]: " USE_NPM
    USE_NPM=${USE_NPM:-no}
    if [ "$USE_NPM" = "yes" ]; then
        echo "✅ Ви обрали Nginx Proxy Manager. Переконайтеся, що порти 80 та 443 доступні."
    fi
fi

echo
echo "--- Налаштування мостів (ботів) ---"
echo "Мости дозволяють інтегрувати Matrix з іншими месенджерами."

INSTALL_SIGNAL_BRIDGE="no"
INSTALL_WHATSAPP_BRIDGE="no"
INSTALL_TELEGRAM_BRIDGE="no"
INSTALL_DISCORD_BRIDGE="no"

read -p "Встановити Signal Bridge (для спілкування з користувачами Signal)? (yes/no) [no]: " INSTALL_SIGNAL_BRIDGE
INSTALL_SIGNAL_BRIDGE=${INSTALL_SIGNAL_BRIDGE:-no}

read -p "Встановити WhatsApp Bridge (для спілкування з користувачами WhatsApp)? (yes/no) [no]: " INSTALL_WHATSAPP_BRIDGE
INSTALL_WHATSAPP_BRIDGE=${INSTALL_WHATSAPP_BRIDGE:-no}

read -p "Встановити Telegram Bridge (для спілкування з користувачами Telegram)? (yes/no) [no]: " INSTALL_TELEGRAM_BRIDGE
INSTALL_TELEGRAM_BRIDGE=${INSTALL_TELEGRAM_BRIDGE:-no}

read -p "Встановити Discord Bridge (для спілкування з користувачами Discord)? (yes/no) [no]: " INSTALL_DISCORD_BRIDGE
INSTALL_DISCORD_BRIDGE=${INSTALL_DISCORD_BRIDGE:-no}


# Запитуємо про встановлення Portainer
while true; do
    read -p "Встановити Portainer (веб-інтерфейс для керування Docker)? (yes/no) [yes]: " INSTALL_PORTAINER
    INSTALL_PORTAINER=${INSTALL_PORTAINER:-yes}
    case "$INSTALL_PORTAINER" in
        yes|no) break;;
        *) echo "Некоректний вибір. Будь ласка, введіть 'yes' або 'no'.";;
    esac
done

echo "-------------------------------------------------"
echo "Перевірка налаштувань:"
echo "Домен: $DOMAIN"
echo "Базова директорія: $BASE_DIR"
echo "Публічна реєстрація: $ALLOW_PUBLIC_REGISTRATION"
echo "Федерація: $ENABLE_FEDERATION"
echo "Встановлення Element Web: $INSTALL_ELEMENT"
echo "Використання Cloudflare Tunnel: $USE_CLOUDFLARE_TUNNEL"
echo "Використання Let's Encrypt (NPM): $USE_NPM"
echo "Встановлення Portainer: $INSTALL_PORTAINER"
echo "Встановлення Signal Bridge: $INSTALL_SIGNAL_BRIDGE"
echo "Встановлення WhatsApp Bridge: $INSTALL_WHATSAPP_BRIDGE"
echo "Встановлення Telegram Bridge: $INSTALL_TELEGRAM_BRIDGE"
echo "Встановлення Discord Bridge: $INSTALL_DISCORD_BRIDGE"
echo "-------------------------------------------------"
read -p "Натисніть Enter для продовження або Ctrl+C для скасування..."

# --- Крок 2: Встановлення необхідних залежностей ---
echo "-------------------------------------------------"
echo "Крок: Встановлення необхідних залежностей"
echo "-------------------------------------------------"

echo "⏳ Оновлюю списки пакетів..."
apt update -y
echo "✅ Списки пакетів оновлено."

echo "⏳ Встановлюю базові пакети (curl, apt-transport-https, ca-certificates, gnupg)..."
apt install -y curl apt-transport-https ca-certificates gnupg
echo "✅ Базові пакети встановлено."

echo "⏳ Встановлюю Docker Engine..."
if ! systemctl is-active --quiet docker; then
    install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "✅ Docker Engine встановлено."
else
    echo "✅ Docker вже встановлено."
fi

echo "⏳ Встановлюю Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    # Docker Compose V2 встановлюється як плагін docker-compose-plugin
    if ! docker compose version &> /dev/null; then
        echo "❌ Docker Compose не знайдено. Будь ласка, встановіть його вручну або переконайтеся, що docker-compose-plugin встановлено."
        exit 1
    fi
    echo "✅ Docker Compose встановлено."
else
    echo "✅ Docker Compose вже встановлено."
fi

if [ "$INSTALL_PORTAINER" = "yes" ]; then
    echo "⏳ Запускаю Portainer..."
    if ! docker ps -a --format '{{.Names}}' | grep -q "portainer"; then
        docker volume create portainer_data
        docker run -d -p 8000:8000 -p 9443:9443 --name portainer \
            --restart always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:latest
        echo "✅ Portainer запущено. Доступно за адресою https://<IP_вашого_сервера>:9443"
    else
        echo "✅ Portainer вже запущено."
    fi
fi

# --- Крок 3: Підготовка структури папок та генерація конфігурацій ---
echo "-------------------------------------------------"
echo "Крок: Підготовка структури папок та генерація конфігурацій"
echo "-------------------------------------------------"

echo "⏳ Створюю структуру папок у $BASE_DIR..."
mkdir -p "$BASE_DIR/synapse/config"
mkdir -p "$BASE_DIR/synapse/data"
mkdir -p "$BASE_DIR/element"
mkdir -p "$BASE_DIR/certs" # Для Let's Encrypt або інших сертифікатів

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
echo "✅ Структуру папок створено."

# Генеруємо конфігураційний файл для Synapse
echo "⏳ Генерую конфігураційний файл для Synapse (homeserver.yaml)..."
sudo docker run --rm \
    -v "$BASE_DIR/synapse/config:/data" \
    -e SYNAPSE_SERVER_NAME="$DOMAIN" \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate

# Створюємо символічне посилання для ключів підпису, якщо його немає
# Це потрібно для того, щоб ключ був доступний на рівні $BASE_DIR/synapse/data
# де Synapse очікує його, коли /data - це /synapse/data
if [ ! -f "$BASE_DIR/synapse/data/$DOMAIN.signing.key" ]; then
    cp "$BASE_DIR/synapse/config/$DOMAIN.signing.key" "$BASE_DIR/synapse/data/$DOMAIN.signing.key"
    chown -R 991:991 "$BASE_DIR/synapse/data" # Переконаємося, що права правильні
fi
echo "✅ homeserver.yaml згенеровано."


# Генеруємо конфігураційні файли для мостів (тільки якщо вибрано)
if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    echo "⏳ Генерую конфігураційний файл для Signal Bridge..."
    sudo docker run --rm \
        -v "$BASE_DIR/signal-bridge/config:/data" \
        -e CONFIG_PATH=/data/config.yaml \
        "$MAUTRIX_DOCKER_REGISTRY/mautrix-signal:latest" -g > "$BASE_DIR/signal-bridge/config/config.yaml"
    echo "✅ Конфігураційний файл для Signal Bridge згенеровано."
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    echo "⏳ Генерую конфігураційний файл для WhatsApp Bridge..."
    sudo docker run --rm \
        -v "$BASE_DIR/whatsapp-bridge/config:/data" \
        -e CONFIG_PATH=/data/config.yaml \
        "$MAUTRIX_DOCKER_REGISTRY/mautrix-whatsapp:latest" -g > "$BASE_DIR/whatsapp-bridge/config/config.yaml"
    echo "✅ Конфігураційний файл для WhatsApp Bridge згенеровано."
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    echo "⏳ Генерую конфігураційний файл для Telegram Bridge..."
    sudo docker run --rm \
        -v "$BASE_DIR/telegram-bridge/config:/data" \
        -e CONFIG_PATH=/data/config.yaml \
        "$MAUTRIX_DOCKER_REGISTRY/mautrix-telegram:latest" -g > "$BASE_DIR/telegram-bridge/config/config.yaml"
    echo "✅ Конфігураційний файл для Telegram Bridge згенеровано."
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    echo "⏳ Генерую конфігураційний файл для Discord Bridge..."
    sudo docker run --rm \
        -v "$BASE_DIR/discord-bridge/config:/data" \
        -e CONFIG_PATH=/data/config.yaml \
        "$MAUTRIX_DOCKER_REGISTRY/mautrix-discord:latest" -g > "$BASE_DIR/discord-bridge/config/config.yaml"
    echo "✅ Конфігураційний файл для Discord Bridge згенеровано."
fi


# --- Крок 4: Налаштування конфігураційних файлів ---
echo "-------------------------------------------------"
echo "Крок: Налаштування конфігураційних файлів"
echo "-------------------------------------------------"

# Налаштовуємо homeserver.yaml
HOMESERVER_CONFIG="$BASE_DIR/synapse/config/homeserver.yaml"

echo "⏳ Налаштовую базу даних PostgreSQL в homeserver.yaml..."
sed -i "s|#url: postgres://user:password@host:port/database|url: postgres://matrix_user:$POSTGRES_PASSWORD@postgres:5432/matrix_db|" "$HOMESERVER_CONFIG"
sed -i "/database:/a \ \   # Explicitly set the database type to pg (PostgreSQL)\n    name: pg" "$HOMESERVER_CONFIG"
echo "✅ Базу даних PostgreSQL налаштовано."

if [ "$ALLOW_PUBLIC_REGISTRATION" = "yes" ]; then
    echo "⏳ Вмикаю публічну реєстрацію..."
    sed -i "s|enable_registration: false|enable_registration: true|" "$HOMESERVER_CONFIG"
    echo "✅ Публічну реєстрацію увімкнено."
else
    echo "✅ Публічна реєстрація вимкнена (за замовчуванням)."
fi

if [ "$ENABLE_FEDERATION" = "no" ]; then
    echo "⏳ Вимикаю федерацію (налаштуйте фаєрвол для порту 8448, якщо необхідно)..."
    sed -i "/#federation_client_minimum_tls_version:/a \ \   federation_enabled: false" "$HOMESERVER_CONFIG"
    echo "✅ Федерацію вимкнено."
else
    echo "✅ Федерація увімкнена (за замовчуванням)."
fi

# Додаємо налаштування мостів до homeserver.yaml
echo "⏳ Додаю налаштування мостів до homeserver.yaml..."
cat <<EOF >> "$HOMESERVER_CONFIG"

# Mautrix Bridges Configuration
app_service_config_files:
EOF

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    echo "  - /data/signal-registration.yaml" >> "$HOMESERVER_CONFIG"
fi
if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    echo "  - /data/whatsapp-registration.yaml" >> "$HOMESERVER_CONFIG"
fi
if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    echo "  - /data/telegram-registration.yaml" >> "$HOMESERVER_CONFIG"
fi
if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    echo "  - /data/discord-registration.yaml" >> "$HOMESERVER_CONFIG"
fi
echo "✅ Конфігурацію Synapse оновлено."

# Завантажуємо та налаштовуємо Element Web
if [ "$INSTALL_ELEMENT" = "yes" ]; then
    echo "⏳ Завантажую та налаштовую Element Web..."
    ELEMENT_VERSION="v1.11.104" # Можна оновити, якщо потрібно
    ELEMENT_TAR="element-$ELEMENT_VERSION.tar.gz"
    ELEMENT_URL="https://github.com/element-hq/element-web/releases/download/$ELEMENT_VERSION/$ELEMENT_TAR"

    echo "Завантажую Element Web версії: $ELEMENT_VERSION"
    curl -L "$ELEMENT_URL" -o "$BASE_DIR/$ELEMENT_TAR"
    tar -xzf "$BASE_DIR/$ELEMENT_TAR" -C "$BASE_DIR/element" --strip-components=1
    rm "$BASE_DIR/$ELEMENT_TAR"

    # Створюємо config.json для Element
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
    echo "✅ Element Web завантажено та налаштовано."
else
    echo "✅ Встановлення Element Web пропущено."
fi


# --- Крок 5: Створення файлу docker-compose.yml ---
echo "-------------------------------------------------"
echo "Крок: Створення файлу docker-compose.yml"
echo "-------------------------------------------------"

# Обчислення портів Synapse залежно від Cloudflare Tunnel або NPM
SYNAPSE_PORTS=""
if [ "$USE_CLOUDFLARE_TUNNEL" = "yes" ]; then
    # Cloudflare Tunnel буде проксіювати на internal:8008 та internal:8448
    SYNAPSE_PORTS="" # Порти не потрібно прокидати на хост, бо тунель йде до контейнера
else
    # Для прямого доступу або NPM, прокидаємо порти на хост
    SYNAPSE_PORTS="- \"8008:8008\"\n      - \"8448:8448\""
fi

cat <<EOF > "$BASE_DIR/docker-compose.yml"
version: '3.8'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    volumes:
      - ./synapse/data/postgres:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: matrix_db
      POSTGRES_USER: matrix_user
      POSTGRES_PASSWORD: $POSTGRES_PASSWORD

  # Matrix Synapse Homeserver
  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    depends_on:
      - postgres
    volumes:
      - ./synapse/config:/data
      - ./synapse/data:/synapse/data # Для ключів підпису та медіа
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

  # Synapse Admin Panel
  synapse-admin:
    image: awesometechs/synapse-admin:latest
    restart: unless-stopped
    depends_on:
      - synapse
    environment:
      SYNAPSE_URL: http://synapse:8008
      SYNAPSE_SERVER_NAME: $DOMAIN
    ports:
      - "8080:80" # Порт для адмін-панелі

EOF

if [ "$INSTALL_ELEMENT" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Element Web Client
  element:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./element:/usr/share/nginx/html:ro
    ports:
      - "80:80" # Стандартний порт для веб-клієнта
EOF
fi

# Додаємо мости, якщо вибрано
if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Mautrix Signal Bridge
  signal-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-signal:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./signal-bridge/config:/data:z
      - ./signal-bridge/data:/data_bridge:z # Для збереження даних Signal
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=signal" # Мітка для ідентифікації Portainer
EOF
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Mautrix WhatsApp Bridge
  whatsapp-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-whatsapp:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./whatsapp-bridge/config:/data:z
      - ./whatsapp-bridge/data:/data_bridge:z # Для збереження даних WhatsApp
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=whatsapp" # Мітка для ідентифікації Portainer
EOF
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Mautrix Telegram Bridge
  telegram-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-telegram:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./telegram-bridge/config:/data:z
      - ./telegram-bridge/data:/data_bridge:z # Для збереження даних Telegram
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=telegram" # Мітка для ідентифікації Portainer
EOF
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Mautrix Discord Bridge
  discord-bridge:
    image: $MAUTRIX_DOCKER_REGISTRY/mautrix-discord:latest
    restart: unless-stopped
    depends_on:
      - synapse
    volumes:
      - ./discord-bridge/config:/data:z
      - ./discord-bridge/data:/data_bridge:z # Для збереження даних Discord
    environment:
      - MAUTRIX_CONFIG_PATH=/data/config.yaml
      - MAUTRIX_REGISTRATION_PATH=/data/registration.yaml
    labels:
      - "mautrix_bridge=discord" # Мітка для ідентифікації Portainer
EOF
fi

if [ "$USE_CLOUDFLARE_TUNNEL" = "yes" ]; then
cat <<EOF >> "$BASE_DIR/docker-compose.yml"
  # Cloudflare Tunnel
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel run --token $CLOUDFLARE_TUNNEL_TOKEN
    environment:
      TUNNEL_TOKEN: $CLOUDFLARE_TUNNEL_TOKEN
EOF
fi

echo "✅ Файл docker-compose.yml створено у $BASE_DIR."

# --- Крок 6: Запуск Docker стеку та фінальне налаштування ---
echo "-------------------------------------------------"
echo "Крок: Запуск Docker стеку та фінальне налаштування"
echo "-------------------------------------------------"

echo "⏳ Завантажую та запускаю Docker образи. Це може зайняти деякий час..."
cd "$BASE_DIR"
docker compose pull # Завантажуємо всі образи
docker compose up -d # Запускаємо всі сервіси в фоновому режимі
echo "✅ Docker стек запущено успішно."

# Чекаємо, поки Synapse завантажиться
echo "⏳ Чекаю, поки Matrix Synapse завантажиться (максимум 180 секунд)..."
for i in $(seq 1 18); do # 18 * 10 секунд = 180 секунд
    echo "⏳ Чекаю, поки Matrix Synapse завантажиться (пройшло $((i*10-10)) секунд)..."
    if curl -s http://localhost:8008/_matrix/client/versions > /dev/null; then
        echo "✅ Matrix Synapse запущено!"
        break
    fi
    sleep 10
done

if ! curl -s http://localhost:8008/_matrix/client/versions > /dev/null; then
    echo "❌ Помилка: Matrix Synapse не запустився. Будь ласка, вручну перевірте логи контейнера 'matrix_synapse' за допомогою 'sudo docker logs matrix_synapse'."
    echo "Можливо, вам знадобиться збільшити ліміти пам'яті для контейнера Synapse, якщо у вас недостатньо RAM."
    exit 1
fi

# Генерація реєстраційних файлів для мостів
echo "⏳ Генерую файли реєстрації для мостів..."

if [ "$INSTALL_SIGNAL_BRIDGE" = "yes" ]; then
    sudo docker compose exec synapse generate_registration \
        --force \
        -u "http://signal-bridge:8000" \
        -c "/data/signal-registration.yaml" \
        "io.mau.bridge.signal"
    echo "✅ Реєстраційний файл для Signal Bridge згенеровано."
fi

if [ "$INSTALL_WHATSAPP_BRIDGE" = "yes" ]; then
    sudo docker compose exec synapse generate_registration \
        --force \
        -u "http://whatsapp-bridge:8000" \
        -c "/data/whatsapp-registration.yaml" \
        "io.mau.bridge.whatsapp"
    echo "✅ Реєстраційний файл для WhatsApp Bridge згенеровано."
fi

if [ "$INSTALL_TELEGRAM_BRIDGE" = "yes" ]; then
    sudo docker compose exec synapse generate_registration \
        --force \
        -u "http://telegram-bridge:8000" \
        -c "/data/telegram-registration.yaml" \
        "io.mau.bridge.telegram"
    echo "✅ Реєстраційний файл для Telegram Bridge згенеровано."
fi

if [ "$INSTALL_DISCORD_BRIDGE" = "yes" ]; then
    sudo docker compose exec synapse generate_registration \
        --force \
        -u "http://discord-bridge:8000" \
        -c "/data/discord-registration.yaml" \
        "io.mau.bridge.discord"
    echo "✅ Реєстраційний файл для Discord Bridge згенеровано."
fi

echo "-------------------------------------------------"
echo "           ВСТАНОВЛЕННЯ ЗАВЕРШЕНО!             "
echo "-------------------------------------------------"
echo
echo "ВАШІ НАСТУПНІ КРОКИ:"
echo "1. Зайдіть в Portainer: https://<IP_вашого_сервера>:9443"
echo "   (Вам потрібно буде створити обліковий запис адміністратора при першому вході). Зазвичай це Admin / admin"
echo
echo "2. Якщо ви використовували Cloudflare Tunnel, переконайтеся, що ви налаштували DNS-записи та правила тунелю в Cloudflare Zero Trust:"
echo "   - Для Matrix (Synapse): ${DOMAIN}:8008 або ${DOMAIN}:8448"
echo "   - Для Element Web (якщо встановлено): ${DOMAIN}:80"
echo "   - Для Synapse Admin: ${DOMAIN}/synapse-admin"
echo "   - Для Portainer: ${DOMAIN}/portainer"
echo "   Використовуйте 'HTTP' для протоколу, якщо Cloudflare Tunnel звертається до портів контейнерів безпосередньо."
echo "   Якщо у вас декілька сервісів на одному домені (наприклад, $DOMAIN/synapse-admin), використовуйте правила 'Path' у Cloudflare Tunnel."
echo
echo "3. Для управління мостами (Signal, WhatsApp тощо):"
echo "   a. Зайдіть у Portainer -> Stacks -> matrix."
echo "   b. Перейдіть до відповідного контейнера моста (наприклад, 'matrix_signal-bridge_1')."
echo "   c. Перегляньте 'Logs' для інструкцій з реєстрації моста. Зазвичай це команда `!signal login` в Matrix."
echo
echo "4. Ваш Matrix Home Server (Synapse) доступний за адресою: http://<IP_вашого_сервера>:8008 (якщо без Cloudflare/NPM)"
if [ "$INSTALL_ELEMENT" = "yes" ]; then
    echo "5. Element Web буде доступний за адресою: http://<IP_вашого_сервера>:80 (якщо без Cloudflare/NPM)"
fi
echo "6. Synapse Admin Panel доступна за адресою: http://<IP_вашого_сервера>:8080"
echo
echo "Для створення першого адміністративного користувача Matrix (якщо публічна реєстрація вимкнена або ви хочете створити його вручну):"
echo "sudo docker compose exec synapse register_new_matrix_user -admin -u <username> -p <password>"
echo
echo "Успіхів!"
