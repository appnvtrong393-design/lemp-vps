#!/bin/bash
# ========================== CRONJOB & QUEUE ==========================

manage_cron_queue() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ QUẢN LÝ CRONJOB & QUEUE LARAVEL${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Cấu hình Laravel Scheduler (Cronjob)"
    echo -e "  ${CYAN}2)${NC} Cấu hình Laravel Queue Worker (Supervisor)"
    echo -e "  ${CYAN}3)${NC} Xem danh sách Cronjob hiện tại"
    echo -e "  ${CYAN}4)${NC} Xem trạng thái Supervisor/Queue"
    echo -e "  ${CYAN}5)${NC} Restart tất cả Queue Workers"
    echo -e "  ${CYAN}6)${NC} Cấu hình Laravel Horizon"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r cq_choice

    case "$cq_choice" in
        1) setup_cron ;;
        2) setup_queue ;;
        3)
            echo ""
            echo -e "${WHITE}Cronjob hiện tại (www-data):${NC}"
            crontab -u www-data -l 2>/dev/null || echo "  (không có cronjob nào)"
            echo ""
            echo -e "${WHITE}Cronjob hiện tại (root):${NC}"
            crontab -l 2>/dev/null || echo "  (không có cronjob nào)"
            press_enter
            ;;
        4)
            echo ""
            supervisorctl status 2>/dev/null || msg_warn "Supervisor chưa cài đặt"
            press_enter
            ;;
        5)
            supervisorctl restart all 2>/dev/null || msg_warn "Supervisor chưa cài đặt"
            msg_ok "Đã restart tất cả queue workers"
            press_enter
            ;;
        6) setup_horizon ;;
        0) return ;;
    esac
}

setup_cron() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        if [[ -f "${WEB_ROOT}/${name}/artisan" ]]; then
            sites+=("$name")
        fi
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        msg_warn "Không tìm thấy Laravel project nào."
        press_enter
        return
    fi

    echo -e "${WHITE}Chọn website để cấu hình Scheduler:${NC}"
    for i in "${!sites[@]}"; do
        local cron_status=""
        if crontab -u www-data -l 2>/dev/null | grep -q "${sites[$i]}"; then
            cron_status="${GREEN}(đã cấu hình)${NC}"
        fi
        echo -e "  ${CYAN}$((i+1)))${NC} ${sites[$i]} ${cron_status}"
    done
    echo -e "  ${CYAN}A)${NC} Tất cả"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r cron_choice

    local target=()
    if [[ "$cron_choice" =~ ^[Aa]$ ]]; then
        target=("${sites[@]}")
    else
        local idx=$((cron_choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#sites[@]} ]]; then
            target=("${sites[$idx]}")
        fi
    fi

    for site in "${target[@]}"; do
        local php_ver="$DEFAULT_PHP"
        local nginx_conf="${NGINX_SITES_AVAILABLE}/${site}.conf"
        if [[ -f "$nginx_conf" ]]; then
            local detected
            detected=$(grep -oP 'php\K[0-9]+\.[0-9]+' "$nginx_conf" | head -1)
            [[ -n "$detected" ]] && php_ver="$detected"
        fi

        local cron_line="* * * * * cd ${WEB_ROOT}/${site} && /usr/bin/php${php_ver} artisan schedule:run >> /dev/null 2>&1"

        local existing
        existing=$(crontab -u www-data -l 2>/dev/null || true)
        if echo "$existing" | grep -q "${site}.*schedule:run"; then
            msg_warn "${site} - Scheduler đã được cấu hình"
        else
            (echo "$existing"; echo "$cron_line") | crontab -u www-data -
            msg_ok "${site} - Scheduler đã thêm"
        fi
    done

    echo ""
    echo -e "${WHITE}Cronjob hiện tại:${NC}"
    crontab -u www-data -l 2>/dev/null || true

    log "Cron configured for: ${target[*]}"
    press_enter
}

setup_queue() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        if [[ -f "${WEB_ROOT}/${name}/artisan" ]]; then
            sites+=("$name")
        fi
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        msg_warn "Không tìm thấy Laravel project nào."
        press_enter
        return
    fi

    echo -e "${WHITE}Chọn website để cấu hình Queue Worker:${NC}"
    for i in "${!sites[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${sites[$i]}"
    done
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r q_choice
    local idx=$((q_choice - 1))
    local site="${sites[$idx]}"
    local site_dir="${WEB_ROOT}/${site}"

    local php_ver="$DEFAULT_PHP"
    local nginx_conf="${NGINX_SITES_AVAILABLE}/${site}.conf"
    if [[ -f "$nginx_conf" ]]; then
        local detected
        detected=$(grep -oP 'php\K[0-9]+\.[0-9]+' "$nginx_conf" | head -1)
        [[ -n "$detected" ]] && php_ver="$detected"
    fi

    echo -ne "${YELLOW}Số worker processes [3]: ${NC}"
    read -r num_workers
    num_workers="${num_workers:-3}"

    echo -ne "${YELLOW}Queue name [default]: ${NC}"
    read -r queue_name
    queue_name="${queue_name:-default}"

    echo -ne "${YELLOW}Số lần retry khi lỗi [3]: ${NC}"
    read -r max_tries
    max_tries="${max_tries:-3}"

    local worker_name
    worker_name=$(echo "${site}" | tr '.' '-' | tr -dc 'a-zA-Z0-9-')

    cat > "/etc/supervisor/conf.d/${worker_name}-worker.conf" << SUPCONF
[program:${worker_name}-worker]
process_name=%(program_name)s_%(process_num)02d
command=/usr/bin/php${php_ver} ${site_dir}/artisan queue:work redis --sleep=3 --tries=${max_tries} --max-time=3600 --queue=${queue_name}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=${num_workers}
redirect_stderr=true
stdout_logfile=${site_dir}/storage/logs/worker.log
stopwaitsecs=3600
SUPCONF

    supervisorctl reread >> "$LOG_FILE" 2>&1
    supervisorctl update >> "$LOG_FILE" 2>&1
    supervisorctl start "${worker_name}-worker:*" >> "$LOG_FILE" 2>&1 || true

    msg_ok "Queue Worker đã cấu hình cho ${site}"
    echo ""
    supervisorctl status "${worker_name}-worker:*" 2>/dev/null || true

    log "Queue worker configured for: ${site}"
    press_enter
}

setup_horizon() {
    echo ""
    msg_warn "Laravel Horizon cần được cài đặt trong project Laravel."
    echo ""
    echo -e "${WHITE}Hướng dẫn:${NC}"
    echo "  1. cd /var/www/your-site"
    echo '  2. composer require laravel/horizon'
    echo '  3. php artisan horizon:install'
    echo '  4. php artisan horizon:publish'
    echo ""
    echo -e "${WHITE}Sau đó quay lại để cấu hình Supervisor cho Horizon.${NC}"
    echo ""

    if confirm "Cấu hình Supervisor cho Horizon?"; then
        local sites=()
        for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
            [[ -f "$conf" ]] || continue
            local name
            name=$(basename "$conf" .conf)
            [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
            if [[ -f "${WEB_ROOT}/${name}/artisan" ]]; then
                sites+=("$name")
            fi
        done

        echo -e "${WHITE}Chọn website:${NC}"
        for i in "${!sites[@]}"; do
            echo -e "  ${CYAN}$((i+1)))${NC} ${sites[$i]}"
        done
        echo -ne "${YELLOW}Lựa chọn: ${NC}"
        read -r h_choice
        local idx=$((h_choice - 1))
        local site="${sites[$idx]}"
        local site_dir="${WEB_ROOT}/${site}"

        local php_ver="$DEFAULT_PHP"
        local worker_name
        worker_name=$(echo "${site}" | tr '.' '-' | tr -dc 'a-zA-Z0-9-')

        cat > "/etc/supervisor/conf.d/${worker_name}-horizon.conf" << HCONF
[program:${worker_name}-horizon]
process_name=%(program_name)s
command=/usr/bin/php${php_ver} ${site_dir}/artisan horizon
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=${site_dir}/storage/logs/horizon.log
stopwaitsecs=3600
HCONF

        supervisorctl reread >> "$LOG_FILE" 2>&1
        supervisorctl update >> "$LOG_FILE" 2>&1
        msg_ok "Horizon Supervisor đã cấu hình cho ${site}"
    fi

    press_enter
}

# ========================== DATABASE ==========================

manage_database() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ QUẢN LÝ DATABASE${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Danh sách databases"
    echo -e "  ${CYAN}2)${NC} Tạo database + user mới"
    echo -e "  ${CYAN}3)${NC} Xóa database"
    echo -e "  ${CYAN}4)${NC} Backup database"
    echo -e "  ${CYAN}5)${NC} Restore database"
    echo -e "  ${CYAN}6)${NC} Đổi mật khẩu MySQL root"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r db_choice

    case "$db_choice" in
        1) list_databases ;;
        2) create_database ;;
        3) drop_database ;;
        4) backup_database ;;
        5) restore_database ;;
        6) change_mysql_root_pass ;;
        0) return ;;
    esac
}

list_databases() {
    echo ""
    if [[ -f "$MYSQL_CONFIG" ]]; then
        echo -e "${WHITE}Databases trên server:${NC}"
        mysql --defaults-file="$MYSQL_CONFIG" -e "SHOW DATABASES;" 2>/dev/null
        echo ""
        echo -e "${WHITE}Users:${NC}"
        mysql --defaults-file="$MYSQL_CONFIG" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null
    else
        msg_error "Không tìm thấy MySQL credentials"
    fi
    press_enter
}

create_database() {
    echo ""
    echo -ne "${YELLOW}Tên database: ${NC}"
    read -r db_name
    echo -ne "${YELLOW}Tên user [${db_name}_user]: ${NC}"
    read -r db_user
    db_user="${db_user:-${db_name}_user}"
    local db_pass
    db_pass=$(generate_password 16)

    if [[ -f "$MYSQL_CONFIG" ]]; then
        mysql --defaults-file="$MYSQL_CONFIG" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
        mysql --defaults-file="$MYSQL_CONFIG" -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" 2>/dev/null
        mysql --defaults-file="$MYSQL_CONFIG" -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';" 2>/dev/null
        mysql --defaults-file="$MYSQL_CONFIG" -e "FLUSH PRIVILEGES;" 2>/dev/null

        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  DATABASE ĐÃ TẠO                     ║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  Database: ${CYAN}${db_name}${NC}"
        echo -e "${GREEN}║${NC}  User:     ${CYAN}${db_user}${NC}"
        echo -e "${GREEN}║${NC}  Password: ${CYAN}${db_pass}${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"

        echo "DB: ${db_name} | User: ${db_user} | Pass: ${db_pass}" >> "${BACKUP_DIR}/credentials.txt"
    else
        msg_error "Không tìm thấy MySQL credentials"
    fi
    press_enter
}

drop_database() {
    echo ""
    echo -ne "${YELLOW}Tên database cần xóa: ${NC}"
    read -r db_name

    if confirm "XÁC NHẬN XÓA DATABASE ${db_name}?"; then
        if [[ -f "$MYSQL_CONFIG" ]]; then
            mysql --defaults-file="$MYSQL_CONFIG" -e "DROP DATABASE IF EXISTS \`${db_name}\`;" 2>/dev/null
            msg_ok "Database ${db_name} đã xóa"
        fi
    fi
    press_enter
}

backup_database() {
    echo ""
    echo -ne "${YELLOW}Tên database cần backup (hoặc 'all'): ${NC}"
    read -r db_name

    local backup_file
    mkdir -p "${BACKUP_DIR}/db"

    if [[ "$db_name" == "all" ]]; then
        backup_file="${BACKUP_DIR}/db/all-databases-$(date +%Y%m%d%H%M%S).sql.gz"
        mysqldump --defaults-file="$MYSQL_CONFIG" --all-databases 2>/dev/null | gzip > "$backup_file"
    else
        backup_file="${BACKUP_DIR}/db/${db_name}-$(date +%Y%m%d%H%M%S).sql.gz"
        mysqldump --defaults-file="$MYSQL_CONFIG" "$db_name" 2>/dev/null | gzip > "$backup_file"
    fi

    msg_ok "Backup lưu tại: ${backup_file}"
    msg_info "Size: $(du -h "$backup_file" | cut -f1)"
    press_enter
}

restore_database() {
    echo ""
    echo -e "${WHITE}Backup files:${NC}"
    ls -la "${BACKUP_DIR}/db/" 2>/dev/null || msg_warn "Không có backup nào"
    echo ""
    echo -ne "${YELLOW}Đường dẫn file backup (.sql.gz): ${NC}"
    read -r backup_path
    echo -ne "${YELLOW}Tên database đích: ${NC}"
    read -r db_name

    if [[ -f "$backup_path" ]]; then
        gunzip < "$backup_path" | mysql --defaults-file="$MYSQL_CONFIG" "$db_name" 2>/dev/null
        msg_ok "Restore hoàn tất"
    else
        msg_error "File không tồn tại"
    fi
    press_enter
}

change_mysql_root_pass() {
    echo ""
    local new_pass
    new_pass=$(generate_password 20)
    echo -ne "${YELLOW}Mật khẩu mới (Enter để auto-generate): ${NC}"
    read -r input_pass
    new_pass="${input_pass:-$new_pass}"

    if [[ -f "$MYSQL_CONFIG" ]]; then
        mysql --defaults-file="$MYSQL_CONFIG" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${new_pass}';" 2>/dev/null

        cat > "$MYSQL_CONFIG" << EOF
[client]
user=root
password=${new_pass}
EOF
        chmod 600 "$MYSQL_CONFIG"

        msg_ok "Mật khẩu root MySQL đã đổi"
        echo -e "  New password: ${CYAN}${new_pass}${NC}"
    else
        msg_error "Không tìm thấy MySQL credentials"
    fi
    press_enter
}

# ========================== PHP MANAGEMENT ==========================

manage_php() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ QUẢN LÝ PHP${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Đổi PHP mặc định (CLI)"
    echo -e "  ${CYAN}2)${NC} Cài thêm phiên bản PHP"
    echo -e "  ${CYAN}3)${NC} Cài thêm PHP extension"
    echo -e "  ${CYAN}4)${NC} Restart PHP-FPM"
    echo -e "  ${CYAN}5)${NC} Xem php.ini paths"
    echo -e "  ${CYAN}6)${NC} Sửa php.ini"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r php_mgmt

    case "$php_mgmt" in
        1)
            echo ""
            echo -e "${WHITE}Phiên bản PHP đang cài:${NC}"
            local avail=()
            for ver in "${PHP_VERSIONS[@]}"; do
                if command -v "php${ver}" &>/dev/null; then
                    avail+=("$ver")
                    echo -e "  ${CYAN}${#avail[@]})${NC} PHP ${ver}"
                fi
            done
            echo -ne "${YELLOW}Chọn: ${NC}"
            read -r def_choice
            local new_default="${avail[$((def_choice - 1))]}"
            update-alternatives --set php "/usr/bin/php${new_default}" 2>/dev/null
            msg_ok "PHP mặc định: $(php -v | head -1)"
            ;;
        2)
            msg_warn "Tính năng này cần chạy từ install.sh"
            ;;
        3)
            echo -ne "${YELLOW}PHP version (vd: 8.3): ${NC}"
            read -r pv
            echo -ne "${YELLOW}Extension name (vd: imagick): ${NC}"
            read -r ext
            apt-get install -y "php${pv}-${ext}" >> "$LOG_FILE" 2>&1
            systemctl restart "php${pv}-fpm" 2>/dev/null
            msg_ok "php${pv}-${ext} đã cài"
            ;;
        4)
            for ver in "${PHP_VERSIONS[@]}"; do
                if systemctl is-active --quiet "php${ver}-fpm" 2>/dev/null; then
                    systemctl restart "php${ver}-fpm"
                    msg_ok "php${ver}-fpm restarted"
                fi
            done
            ;;
        5)
            for ver in "${PHP_VERSIONS[@]}"; do
                if command -v "php${ver}" &>/dev/null; then
                    echo -e "  PHP ${ver}: $(php${ver} --ini 2>/dev/null | grep 'Loaded Configuration' | awk -F: '{print $2}')"
                fi
            done
            ;;
        6)
            echo -ne "${YELLOW}PHP version (vd: 8.3): ${NC}"
            read -r pv
            echo -e "  ${CYAN}1)${NC} FPM php.ini"
            echo -e "  ${CYAN}2)${NC} CLI php.ini"
            echo -ne "${YELLOW}Lựa chọn: ${NC}"
            read -r ini_type
            local ini_path="/etc/php/${pv}/fpm/php.ini"
            [[ "$ini_type" == "2" ]] && ini_path="/etc/php/${pv}/cli/php.ini"
            ${EDITOR:-nano} "$ini_path"
            systemctl restart "php${pv}-fpm" 2>/dev/null
            ;;
        0) return ;;
    esac
    press_enter
}
