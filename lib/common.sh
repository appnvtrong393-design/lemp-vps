#!/bin/bash
###############################################################################
#  Common - Shared utilities, config, colors
#  Dùng chung cho install.sh và qlvps
###############################################################################

set -euo pipefail

# ========================== CẤU HÌNH ==========================
SCRIPT_VERSION="3.0.0"
WEB_ROOT="/var/www"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_LOG_DIR="/var/log/nginx"
PHP_VERSIONS=("5.6" "7.0" "7.1" "7.2" "7.3" "7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")
DEFAULT_PHP="8.3"
MYSQL_CONFIG="/root/.my.cnf"
BACKUP_DIR="/var/backups/server-manager"
LOG_FILE="/var/log/server-manager.log"
MANAGER_DIR="/opt/laravel-manager"

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
    echo -e "${CYAN}║${DIM}       Ubuntu LEMP Stack + Laravel Management              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[  OK]${NC} $1"
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

msg_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

msg_step() {
    echo -e "${MAGENTA}[STEP]${NC} $1"
}

confirm() {
    local prompt="${1:-Bạn có muốn tiếp tục?}"
    echo -ne "${YELLOW}$prompt (y/n): ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

press_enter() {
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

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while ps -p "$pid" > /dev/null 2>&1; do
        for i in $(seq 0 $((${#spinstr} - 1))); do
            echo -ne "\r${CYAN}${spinstr:$i:1}${NC} $2"
            sleep $delay
        done
    done
    echo -ne "\r"
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
