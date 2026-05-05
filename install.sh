#!/bin/bash
###############################################################################
#  Laravel Server Manager - INSTALL SCRIPT
#  Menu cài đặt hệ thống + LEMP Stack + Thư viện
#  Sau khi cài đặt, tải script quản lý qlvps từ CDN về
#
#  Usage:
#    curl -sL https://raw.githubusercontent.com/appnvtrong393-design/lemp-vps/main/install.sh | sudo bash
#
#  Auto mode: Khi pipe từ curl, tự động cài TẤT CẢ (không hỏi)
#  Interactive mode: Khi chạy trực tiếp, hiện menu chọn
###############################################################################

set -euo pipefail

# ========================== AUTO MODE DETECT ==========================
# Nếu không có TTY (pipe từ curl) hoặc có flag --auto thì tự động cài hết
AUTO_MODE=false
if [[ ! -t 0 ]] || [[ "${1:-}" == "--auto" ]]; then
    AUTO_MODE=true
fi

# ========================== CẤU HÌNH ==========================
SCRIPT_VERSION="3.0.0"
WEB_ROOT="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_LOG_DIR="/var/log/nginx"
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")
DEFAULT_PHP="8.3"

# Detect PHP versions khả dụng từ apt-cache
detect_php_available() {
    local available=()
    for ver in "${PHP_VERSIONS[@]}"; do
        if apt-cache show "php${ver}-fpm" &>/dev/null; then
            available+=("$ver")
        fi
    done

    if [[ ${#available[@]} -eq 0 ]]; then
        msg_warn "Khong tim thay PHP nao trong repo. Thu cai PPA..."
        add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
        apt-get update -y 2>/dev/null || true
        for ver in "${PHP_VERSIONS[@]}"; do
            if apt-cache show "php${ver}-fpm" &>/dev/null; then
                available+=("$ver")
            fi
        done
    fi

    echo "${available[@]}"
}
MYSQL_CONFIG="/root/.my.cnf"
BACKUP_DIR="/var/backups/server-manager"
LOG_FILE="/var/log/server-manager.log"
MANAGER_DIR="/opt/laravel-manager"

# ===== GITHUB CONFIG - Đổi lại username/repo của bạn =====
GITHUB_USER="appnvtrong393-design"
GITHUB_REPO="lemp-vps"
GITHUB_BRANCH="main"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"

# ========================== MÀU SẮC ==========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ========================== HÀM TIỆN ÍCH ==========================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

print_header() {
    clear 2>/dev/null || true
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}${BOLD}       Laravel Server Manager v$SCRIPT_VERSION                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${DIM}       INSTALL - Cai dat He thong & LEMP Stack            ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

msg_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok()    { echo -e "${GREEN}[  OK]${NC} $1"; }
msg_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
msg_error() { echo -e "${RED}[FAIL]${NC} $1"; }
msg_step()  { echo -e "${MAGENTA}[STEP]${NC} $1"; }

confirm() {
    if $AUTO_MODE; then
        return 0
    fi
    local prompt="${1:-Bạn có muốn tiếp tục?}"
    echo -ne "${YELLOW}$prompt (y/n): ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

press_enter() {
    if $AUTO_MODE; then
        echo ""
        return
    fi
    echo ""
    echo -ne "${DIM}Nhấn Enter để tiếp tục...${NC}"
    read -r
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Yeu cau quyen root. Dang tu dong sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME="$VERSION_CODENAME"
    else
        msg_error "Không thể xác định hệ điều hành."
        exit 1
    fi
    if [[ "$ID" != "ubuntu" ]]; then
        msg_error "Script chỉ hỗ trợ Ubuntu. Phát hiện: $OS_NAME"
        exit 1
    fi
    msg_ok "Hệ điều hành: $OS_NAME $OS_VERSION ($OS_CODENAME)"
}

get_server_ip() {
    curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

generate_password() {
    local length="${1:-16}"
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%' | head -c "$length"
}

show_services_status() {
    echo ""
    echo -e "${WHITE}${BOLD}  Trạng thái dịch vụ:${NC}"
    print_separator
    local services=("nginx" "mysql" "redis-server" "supervisor" "fail2ban" "ufw" "cron")
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} ${svc}: ${GREEN}active${NC}"
        elif systemctl list-unit-files | grep -q "^${svc}"; then
            echo -e "  ${RED}●${NC} ${svc}: ${RED}inactive${NC}"
        else
            echo -e "  ${DIM}○${NC} ${svc}: ${DIM}not installed${NC}"
        fi
    done
    for ver in "${PHP_VERSIONS[@]}"; do
        if systemctl is-active --quiet "php${ver}-fpm" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} php${ver}-fpm: ${GREEN}active${NC}"
        fi
    done
    print_separator
}

# ========================== HÀM DOWNLOAD TỪ GITHUB ==========================

download_file() {
    local url="$1"
    local dest="$2"
    curl -fsSL "$url" -o "$dest" 2>/dev/null
}

# Chạy lệnh với real-time log (hiện ra màn hình + ghi file)
run_log() {
    local label="$1"
    shift
    msg_step "$label..."
    if "$@" 2>&1 | tee -a "$LOG_FILE"; then
        msg_ok "$label"
    else
        local ret=${PIPESTATUS[0]}
        msg_error "$label (exit: $ret)"
        return $ret
    fi
}

# Chạy lệnh silent (chỉ ghi file, ko hiện màn hình)
run_silent() {
    "$@" >> "$LOG_FILE" 2>&1
}

# ========================== 1. SETUP & CẬP NHẬT HỆ THỐNG ==========================

setup_system() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ SETUP & CẬP NHẬT HỆ THỐNG${NC}"
    print_separator
    echo ""

    detect_os

    msg_step "Cập nhật danh sách gói..."
    apt-get update -y >> "$LOG_FILE" 2>&1
    msg_ok "Cập nhật danh sách gói hoàn tất"

    msg_step "Nâng cấp hệ thống..."
    apt-get upgrade -y >> "$LOG_FILE" 2>&1
    msg_ok "Nâng cấp hệ thống hoàn tất"

    msg_step "Cài đặt gói cơ bản..."
    apt-get install -y \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        unzip \
        zip \
        git \
        htop \
        nano \
        vim \
        net-tools \
        ufw \
        fail2ban \
        acl \
        cron \
        supervisor \
        certbot \
        python3-certbot-nginx \
        openssl \
        jq \
        tree \
        ncdu \
        iotop \
        sysstat \
        logrotate \
        rsync \
        2>&1 | tee -a "$LOG_FILE"
    msg_ok "Cài đặt gói cơ bản hoàn tất"

    msg_step "Cấu hình timezone Asia/Ho_Chi_Minh..."
    timedatectl set-timezone Asia/Ho_Chi_Minh 2>/dev/null || true
    msg_ok "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'Asia/Ho_Chi_Minh')"

    msg_step "Cấu hình UFW Firewall..."
    ufw default deny incoming >> "$LOG_FILE" 2>&1 || true
    ufw default allow outgoing >> "$LOG_FILE" 2>&1 || true
    ufw allow ssh >> "$LOG_FILE" 2>&1 || true
    ufw allow 'Nginx Full' >> "$LOG_FILE" 2>&1 || true
    ufw --force enable >> "$LOG_FILE" 2>&1 || true
    msg_ok "Firewall đã bật (SSH, HTTP, HTTPS)"

    msg_step "Cấu hình Fail2Ban..."
    systemctl enable fail2ban >> "$LOG_FILE" 2>&1 || true
    systemctl start fail2ban >> "$LOG_FILE" 2>&1 || true
    msg_ok "Fail2Ban đã kích hoạt"

    mkdir -p "$BACKUP_DIR" "$WEB_ROOT"

    msg_step "Dọn dẹp hệ thống..."
    apt-get autoremove -y >> "$LOG_FILE" 2>&1
    apt-get autoclean -y >> "$LOG_FILE" 2>&1
    msg_ok "Dọn dẹp hoàn tất"

    echo ""
    msg_ok "═══ SETUP HỆ THỐNG HOÀN TẤT ═══"
    log "System setup completed"
    press_enter
}

# ========================== 2. CÀI ĐẶT LEMP STACK ==========================

install_nginx() {
    msg_step "Cài đặt Nginx..."
    apt-get install -y nginx 2>&1 | tee -a "$LOG_FILE"
    systemctl enable nginx >> "$LOG_FILE" 2>&1
    systemctl start nginx >> "$LOG_FILE" 2>&1

    cat > /etc/nginx/conf.d/optimization.conf << 'NGINX_OPT'
# === Server Manager - Nginx Optimization ===
client_max_body_size 256M;
client_body_timeout 120s;
client_header_timeout 120s;
send_timeout 120s;

# Buffer sizes
fastcgi_buffer_size 128k;
fastcgi_buffers 256 16k;
fastcgi_busy_buffers_size 256k;
fastcgi_temp_file_write_size 256k;
NGINX_OPT

    if nginx -t 2>&1 | tee -a "$LOG_FILE"; then
        systemctl reload nginx
        msg_ok "Nginx da cai dat va toi uu"
    else
        msg_warn "Nginx config co loi, bo qua optimization.conf..."
        rm -f /etc/nginx/conf.d/optimization.conf
        systemctl reload nginx 2>/dev/null || true
    fi
}

install_php() {
    msg_step "Them PPA PHP (ondrej/php)..."
    add-apt-repository -y ppa:ondrej/php 2>&1 | tee -a "$LOG_FILE" || true

    if apt-get update -y 2>&1 | tee -a "$LOG_FILE"; then
        msg_ok "PPA ondrej/php OK"
    else
        # Fallback: dung PPA cua Ubuntu LTS truoc do (noble=24.04)
        msg_warn "PPA chua ho tro Ubuntu nay, thu fallback noble..."
        sed -i 's/Suites: .*/Suites: noble/' /etc/apt/sources.list.d/ondrej-*.sources 2>/dev/null || true
        sed -i 's/suites: .*/suites: noble/' /etc/apt/sources.list.d/ondrej-*.list 2>/dev/null || true
        if apt-get update -y 2>&1 | tee -a "$LOG_FILE"; then
            msg_ok "PPA ondrej/php OK (dung noble fallback)"
        else
            msg_warn "PPA khong ho tro, dung default repo"
            rm -f /etc/apt/sources.list.d/ondrej-*.list /etc/apt/sources.list.d/ondrej-*.sources 2>/dev/null || true
            apt-get update -y 2>&1 | tee -a "$LOG_FILE" || true
        fi
    fi

    # Detect PHP versions co san trong repo
    local php_available=($(detect_php_available))

    if [[ ${#php_available[@]} -eq 0 ]]; then
        msg_error "Khong tim thay PHP nao de cai dat!"
        return 1
    fi

    echo ""
    echo -e "${WHITE}Chon phien ban PHP can cai dat:${NC}"
    echo ""

    local selected_versions=()

    for i in "${!php_available[@]}"; do
        local ver="${php_available[$i]}"
        local status=""
        if command -v "php${ver}" &>/dev/null; then
            status="${GREEN}(da cai)${NC}"
        fi
        echo -e "  ${CYAN}$((i+1)))${NC} PHP ${ver} ${status}"
    done
    echo -e "  ${CYAN}A)${NC} Cai tat ca"
    echo ""

    if $AUTO_MODE; then
        # Auto: lay 3 phien ban moi nhat co san
        local count=${#php_available[@]}
        if [[ $count -ge 3 ]]; then
            selected_versions=("${php_available[$((count-3))]}" "${php_available[$((count-2))]}" "${php_available[$((count-1))]}")
        else
            selected_versions=("${php_available[@]}")
        fi
        msg_info "Auto mode: PHP = ${selected_versions[*]}"
    else
        echo -ne "${YELLOW}Nhap lua chon (vd: 1,3,5 hoac A): ${NC}"
        read -r php_choice

        case "$php_choice" in
            [Aa]) selected_versions=("${php_available[@]}") ;;
            *)
                IFS=',' read -ra choices <<< "$php_choice"
                for c in "${choices[@]}"; do
                    c=$(echo "$c" | tr -d ' ')
                    local idx=$((c - 1))
                    if [[ $idx -ge 0 && $idx -lt ${#php_available[@]} ]]; then
                        selected_versions+=("${php_available[$idx]}")
                    fi
                done
                ;;
        esac

        if [[ ${#selected_versions[@]} -eq 0 ]]; then
            msg_warn "Khong co phien ban nao duoc chon. Cai mac dinh PHP ${php_available[-1]}"
            selected_versions=("${php_available[-1]}")
        fi
    fi

    local PHP_EXTENSIONS=(
        "fpm" "cli" "common" "mysql" "pgsql" "sqlite3"
        "redis" "memcached" "curl" "gd" "imagick"
        "mbstring" "xml" "zip" "bcmath" "intl"
        "readline" "opcache" "soap" "imap"
        "tokenizer" "json" "fileinfo" "dom"
        "exif" "pcov" "xdebug"
    )

    for ver in "${selected_versions[@]}"; do
        msg_step "Cài đặt PHP ${ver} và extensions..."

        # Loc extension nao co san trong repo (bo qua virtual package), cai 1 lenh duy nhat
        local packages="php${ver}"
        local available_exts=()
        for ext in "${PHP_EXTENSIONS[@]}"; do
            local pkg="php${ver}-${ext}"
            # Chi lay package that (co Filename: trong apt-cache show, virtual package thi khong co)
            if apt-cache show "$pkg" 2>/dev/null | grep -q '^Filename:'; then
                packages+=" $pkg"
                available_exts+=("$ext")
            fi
        done
        local missing=$(( ${#PHP_EXTENSIONS[@]} - ${#available_exts[@]} ))
        if [[ $missing -gt 0 ]]; then
            msg_info "PHP ${ver}: ${#available_exts[@]}/${#PHP_EXTENSIONS[@]} extensions available, skip ${missing}"
        fi
        apt-get install -y $packages 2>&1 | tee -a "$LOG_FILE"

        local fpm_conf="/etc/php/${ver}/fpm/pool.d/www.conf"
        if [[ -f "$fpm_conf" ]]; then
            sed -i "s/^pm = .*/pm = dynamic/" "$fpm_conf"
            sed -i "s/^pm.max_children = .*/pm.max_children = 50/" "$fpm_conf"
            sed -i "s/^pm.start_servers = .*/pm.start_servers = 5/" "$fpm_conf"
            sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/" "$fpm_conf"
            sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = 35/" "$fpm_conf"
            sed -i "s/^;pm.max_requests = .*/pm.max_requests = 500/" "$fpm_conf"
        fi

        for ini_dir in "fpm" "cli"; do
            local ini_file="/etc/php/${ver}/${ini_dir}/php.ini"
            if [[ -f "$ini_file" ]]; then
                sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 256M/" "$ini_file"
                sed -i "s/^post_max_size = .*/post_max_size = 256M/" "$ini_file"
                sed -i "s/^memory_limit = .*/memory_limit = 512M/" "$ini_file"
                sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$ini_file"
                sed -i "s/^max_input_time = .*/max_input_time = 300/" "$ini_file"
                sed -i "s/^;date.timezone = .*/date.timezone = Asia\/Ho_Chi_Minh/" "$ini_file"
                sed -i "s/^;opcache.enable=.*/opcache.enable=1/" "$ini_file"
                sed -i "s/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/" "$ini_file"
                sed -i "s/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=20000/" "$ini_file"
                sed -i "s/^;opcache.validate_timestamps=.*/opcache.validate_timestamps=0/" "$ini_file"
            fi
        done

        systemctl enable "php${ver}-fpm" >> "$LOG_FILE" 2>&1 || true
        systemctl restart "php${ver}-fpm" >> "$LOG_FILE" 2>&1 || true
        msg_ok "PHP ${ver} đã cài đặt và tối ưu"
    done

    echo ""
    if $AUTO_MODE; then
        default_ver="${selected_versions[0]}"
        msg_info "Auto mode: PHP mặc định = ${default_ver}"
    else
        echo -ne "${YELLOW}Chọn PHP mặc định (vd: ${selected_versions[0]}): ${NC}"
        read -r default_ver
        default_ver="${default_ver:-${selected_versions[0]}}"
    fi
    update-alternatives --set php "/usr/bin/php${default_ver}" >> "$LOG_FILE" 2>&1 || true
    msg_ok "PHP mặc định: $(php -v 2>/dev/null | head -1)"
}

install_mysql() {
    msg_step "Cài đặt MySQL Server..."
    apt-get install -y mysql-server mysql-client 2>&1 | tee -a "$LOG_FILE"
    systemctl enable mysql >> "$LOG_FILE" 2>&1
    systemctl start mysql >> "$LOG_FILE" 2>&1

    local MYSQL_ROOT_PASS
    MYSQL_ROOT_PASS=$(generate_password 20)

    msg_step "Cấu hình MySQL root password..."
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASS}';" 2>/dev/null || \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';" 2>/dev/null || true

    cat > "$MYSQL_CONFIG" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASS}
EOF
    chmod 600 "$MYSQL_CONFIG"

    mysql --defaults-file="$MYSQL_CONFIG" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    mysql --defaults-file="$MYSQL_CONFIG" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    mysql --defaults-file="$MYSQL_CONFIG" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mysql --defaults-file="$MYSQL_CONFIG" -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    cat > /etc/mysql/conf.d/optimization.cnf << 'MYSQL_OPT'
[mysqld]
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
max_connections = 200
wait_timeout = 600
interactive_timeout = 600
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
MYSQL_OPT

    systemctl restart mysql >> "$LOG_FILE" 2>&1
    msg_ok "MySQL đã cài đặt và bảo mật"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  MYSQL ROOT CREDENTIALS - LƯU LẠI!          ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  User:     ${WHITE}root${NC}"
    echo -e "${GREEN}║${NC}  Password: ${WHITE}${MYSQL_ROOT_PASS}${NC}"
    echo -e "${GREEN}║${NC}  Config:   ${WHITE}${MYSQL_CONFIG}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

    echo "MySQL Root Password: ${MYSQL_ROOT_PASS}" >> "${BACKUP_DIR}/credentials.txt"
    chmod 600 "${BACKUP_DIR}/credentials.txt"
    log "MySQL installed"
}

install_composer() {
    msg_step "Cài đặt Composer..."
    curl -sS https://getcomposer.org/installer | php >> "$LOG_FILE" 2>&1
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    msg_ok "Composer: $(composer --version 2>/dev/null)"
}

install_nodejs() {
    msg_step "Cài đặt Node.js (LTS) & npm..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >> "$LOG_FILE" 2>&1
        apt-get install -y nodejs 2>&1 | tee -a "$LOG_FILE"
    fi
    msg_ok "Node.js: $(node --version 2>/dev/null) | npm: $(npm --version 2>/dev/null)"
}

install_redis() {
    msg_step "Cài đặt Redis Server..."
    apt-get install -y redis-server 2>&1 | tee -a "$LOG_FILE"
    systemctl enable redis-server >> "$LOG_FILE" 2>&1
    systemctl start redis-server >> "$LOG_FILE" 2>&1

    sed -i "s/^# maxmemory .*/maxmemory 256mb/" /etc/redis/redis.conf
    sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
    systemctl restart redis-server >> "$LOG_FILE" 2>&1

    msg_ok "Redis Server đã cài đặt"
}

install_phpmyadmin() {
    msg_step "Cài đặt phpMyAdmin..."

    local PMA_VERSION="5.2.1"
    local PMA_DIR="/var/www/phpmyadmin"

    if [[ -d "$PMA_DIR" ]]; then
        msg_warn "phpMyAdmin đã tồn tại tại $PMA_DIR"
        return
    fi

    cd /tmp
    wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.zip" -O phpmyadmin.zip 2>/dev/null || {
        msg_warn "Không thể tải phpMyAdmin. Bỏ qua."
        return
    }
    unzip -qo phpmyadmin.zip >> "$LOG_FILE" 2>&1
    mv "phpMyAdmin-${PMA_VERSION}-all-languages" "$PMA_DIR"
    rm -f phpmyadmin.zip

    local PMA_SECRET
    PMA_SECRET=$(generate_password 32)
    cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
    sed -i "s/\$cfg\['blowfish_secret'\] = .*/\$cfg['blowfish_secret'] = '${PMA_SECRET}';/" "$PMA_DIR/config.inc.php"

    chown -R www-data:www-data "$PMA_DIR"

    local PMA_PORT="8888"
    cat > "${NGINX_SITES_AVAILABLE}/phpmyadmin.conf" << PMACONF
server {
    listen ${PMA_PORT};
    server_name _;
    root ${PMA_DIR};
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${DEFAULT_PHP}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
PMACONF

    ln -sf "${NGINX_SITES_AVAILABLE}/phpmyadmin.conf" "${NGINX_SITES_ENABLED}/phpmyadmin.conf"
    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx

    ufw allow "$PMA_PORT" >> "$LOG_FILE" 2>&1 || true

    msg_ok "phpMyAdmin đã cài tại: http://$(get_server_ip):${PMA_PORT}"
    log "phpMyAdmin installed"
}

# ========================== MENU CÀI ĐẶT ==========================

install_menu() {
    while true; do
        print_header
        echo -e "  ${DIM}Server: $(get_server_ip 2>/dev/null) | $(hostname)${NC}"
        echo ""

        echo -e "  ${WHITE}${BOLD}── CÀI ĐẶT HỆ THỐNG ──${NC}"
        echo -e "  ${CYAN} 1)${NC}  Setup & Cập nhật hệ thống"
        echo ""
        echo -e "  ${WHITE}${BOLD}── CÀI ĐẶT LEMP STACK ──${NC}"
        echo -e "  ${CYAN} 2)${NC}  Cài TẤT CẢ (Nginx + PHP + MySQL + Composer + Node + Redis + phpMyAdmin)"
        echo -e "  ${CYAN} 3)${NC}  Cài Nginx"
        echo -e "  ${CYAN} 4)${NC}  Cài PHP (chọn phiên bản)"
        echo -e "  ${CYAN} 5)${NC}  Cài MySQL"
        echo ""
        echo -e "  ${WHITE}${BOLD}── CÔNG CỤ BỔ TRỢ ──${NC}"
        echo -e "  ${CYAN} 6)${NC}  Cài Composer"
        echo -e "  ${CYAN} 7)${NC}  Cài Node.js & npm"
        echo -e "  ${CYAN} 8)${NC}  Cài Redis"
        echo -e "  ${CYAN} 9)${NC}  Cài phpMyAdmin"
        echo ""
        echo -e "  ${WHITE}${BOLD}── QUẢN LÝ ──${NC}"
        echo -e "  ${CYAN}10)${NC}  Tải script quản lý qlvps từ GitHub"
        echo ""
        echo -e "  ${WHITE}${BOLD}── TRẠNG THÁI ──${NC}"
        echo -e "  ${CYAN}11)${NC}  Xem trạng thái dịch vụ"
        echo ""
        echo -e "  ${RED} 0)${NC}  Thoát"
        echo ""
        print_separator
        echo -ne "  ${YELLOW}Lựa chọn [0-11]: ${NC}"
        read -r choice

        case "$choice" in
            1)  setup_system ;;
            2)
                install_nginx
                install_php
                install_mysql
                install_composer
                install_nodejs
                install_redis
                install_phpmyadmin
                echo ""
                msg_ok "═══ CÀI ĐẶT LEMP STACK HOÀN TẤT ═══"
                show_services_status
                press_enter
                ;;
            3)  install_nginx; press_enter ;;
            4)  install_php; press_enter ;;
            5)  install_mysql; press_enter ;;
            6)  install_composer; press_enter ;;
            7)  install_nodejs; press_enter ;;
            8)  install_redis; press_enter ;;
            9)  install_phpmyadmin; press_enter ;;
            10) setup_manager_script ;;
            11) show_services_status; press_enter ;;
            0)
                echo ""
                msg_info "Cảm ơn bạn đã sử dụng Laravel Server Manager!"
                exit 0
                ;;
            *)
                msg_error "Lựa chọn không hợp lệ"
                sleep 1
                ;;
        esac
    done
}

# ========================== TẢI SCRIPT QUẢN LÝ TỪ CDN ==========================

setup_manager_script() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ TẢI SCRIPT QUẢN LÝ (qlvps) TỪ GITHUB${NC}"
    print_separator
    echo ""

    echo -e "  ${WHITE}GitHub:${NC} ${CYAN}github.com/${GITHUB_USER}/${GITHUB_REPO}${NC}"
    echo -e "  ${WHITE}Branch:${NC} ${CYAN}${GITHUB_BRANCH}${NC}"
    echo ""

    msg_step "Tạo thư mục ${MANAGER_DIR}..."
    mkdir -p "${MANAGER_DIR}/lib"

    msg_step "Tải script quản lý từ GitHub..."

    local FILES=(
        "lib/common.sh"
        "lib/site.sh"
        "lib/services.sh"
        "lib/tools.sh"
        "lib/info.sh"
        "qlvps"
    )

    local all_ok=true
    for file in "${FILES[@]}"; do
        local file_url="${GITHUB_RAW}/${file}"
        local file_path="${MANAGER_DIR}/${file}"

        msg_info "Tải ${file}..."
        if download_file "$file_url" "$file_path"; then
            msg_ok "  ${file}"
        else
            msg_error "  ${file} - THẤT BẠI"
            all_ok=false
        fi
    done

    if ! $all_ok; then
        echo ""
        msg_error "Một số file không tải được. Kiểm tra:"
        echo -e "  - Repo đúng? Hiện tại: github.com/${GITHUB_USER}/${GITHUB_REPO}"
        echo -e "  - Branch đúng? Hiện tại: ${GITHUB_BRANCH}"
        echo -e "  - File đã push lên GitHub chưa?"
        echo -e "  - Thử: curl -I ${GITHUB_RAW}/qlvps"
        press_enter
        return
    fi

    # Set permissions
    chmod +x "${MANAGER_DIR}/qlvps"
    chmod -R +x "${MANAGER_DIR}/lib/"

    # Symlink /usr/local/bin/qlvps
    ln -sf "${MANAGER_DIR}/qlvps" /usr/local/bin/qlvps

    # Alias cho root
    if ! grep -q "alias qlvps=" /root/.bashrc 2>/dev/null; then
        echo "alias qlvps='sudo bash /opt/laravel-manager/qlvps'" >> /root/.bashrc
    fi

    # Alias cho user thường
    local user_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    if [[ -n "$user_home" && "$user_home" != "/root" ]]; then
        if ! grep -q "alias qlvps=" "${user_home}/.bashrc" 2>/dev/null; then
            echo "alias qlvps='sudo bash /opt/laravel-manager/qlvps'" >> "${user_home}/.bashrc"
        fi
    fi

    echo ""
    msg_ok "═══ SCRIPT QUẢN LÝ ĐÃ CÀI ĐẶT ═══"
    echo ""
    echo -e "  ${WHITE}Thư mục:${NC}    ${MANAGER_DIR}/"
    echo -e "  ${WHITE}Lệnh:${NC}       ${GREEN}qlvps${NC}"
    echo -e "  ${WHITE}Alias:${NC}      qlvps -> bash ${MANAGER_DIR}/qlvps"
    echo ""
    echo -e "  ${YELLOW}Gõ 'qlvps' để vào menu quản lý. Tự động sudo nếu cần.${NC}"
    echo ""
    log "qlvps manager script installed from github.com/${GITHUB_USER}/${GITHUB_REPO}"

    press_enter
}

# ========================== AUTO INSTALL ==========================

auto_install() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ AUTO INSTALL - CÀI ĐẶT TỰ ĐỘNG TOÀN BỘ${NC}"
    print_separator
    echo ""
    echo -e "  ${GREEN}Tự động cài:${NC}"
    echo -e "    1. Setup & cập nhật hệ thống"
    echo -e "    2. Nginx"
    echo -e "    3. PHP (8.2, 8.3, 8.4)"
    echo -e "    4. MySQL"
    echo -e "    5. Composer"
    echo -e "    6. Node.js & npm"
    echo -e "    7. Redis"
    echo -e "    8. phpMyAdmin"
    echo -e "    9. Tải script quản lý qlvps"
    echo ""
    echo -e "  ${YELLOW}Bắt đầu sau 3 giây... (Ctrl+C để hủy)${NC}"
    sleep 3

    detect_os
    echo ""

    # 1. Setup system
    run_log "[1/9] Update package list"          apt-get update -y
    run_log "[1/9] Upgrade system"               apt-get upgrade -y
    run_log "[1/9] Install base packages"        apt-get install -y software-properties-common apt-transport-https ca-certificates curl wget gnupg lsb-release unzip zip git htop nano vim net-tools ufw fail2ban acl cron supervisor certbot python3-certbot-nginx openssl jq tree ncdu iotop sysstat logrotate rsync

    run_silent timedatectl set-timezone Asia/Ho_Chi_Minh 2>/dev/null || true
    run_silent ufw default deny incoming 2>/dev/null || true
    run_silent ufw default allow outgoing 2>/dev/null || true
    run_silent ufw allow ssh 2>/dev/null || true
    run_silent ufw allow 'Nginx Full' 2>/dev/null || true
    run_silent ufw --force enable 2>/dev/null || true
    run_silent systemctl enable fail2ban 2>/dev/null || true
    run_silent systemctl start fail2ban 2>/dev/null || true
    run_silent apt-get autoremove -y
    run_silent apt-get autoclean -y
    msg_ok "[1/9] Setup he thong hoan tat"

    # 2-4: LEMP core
    echo ""
    msg_step "[2/9] Cai dat Nginx..."
    install_nginx

    echo ""
    msg_step "[3/9] Cai dat PHP (8.2, 8.3, 8.4)..."
    install_php

    echo ""
    msg_step "[4/9] Cai dat MySQL..."
    install_mysql

    # 5-7: Tools
    echo ""
    msg_step "[5/9] Cai dat Composer..."
    install_composer

    echo ""
    msg_step "[6/9] Cai dat Node.js & npm..."
    install_nodejs

    echo ""
    msg_step "[7/9] Cai dat Redis..."
    install_redis

    # 8. phpMyAdmin
    echo ""
    msg_step "[8/9] Cai dat phpMyAdmin..."
    install_phpmyadmin

    # 9. Download qlvps
    echo ""
    msg_step "[9/9] Tai script quan ly qlvps..."
    setup_manager_script

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}${BOLD}  AUTO INSTALL HOÀN TẤT!                                   ${NC}${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Gõ lệnh sau để vào menu quản lý:                           ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${WHITE}qlvps${NC}                                                       ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  MySQL root password lưu tại:                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${WHITE}${MYSQL_CONFIG}${NC}                               ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    show_services_status
    log "Auto install completed"
}

# ========================== KHỞI CHẠY ==========================

check_root
mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
touch "$LOG_FILE"

if $AUTO_MODE; then
    auto_install
else
    install_menu
fi
