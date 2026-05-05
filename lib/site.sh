#!/bin/bash
# ========================== QUẢN LÝ WEBSITE ==========================
# Functions: create_laravel_site, fix_permissions, install_ssl, manage_sites

create_laravel_site() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ TẠO WEBSITE LARAVEL${NC}"
    print_separator
    echo ""

    echo -ne "${YELLOW}Nhập domain (vd: example.com): ${NC}"
    read -r DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        msg_error "Domain không được để trống"
        press_enter
        return
    fi

    if [[ -f "${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf" ]]; then
        msg_error "Website ${DOMAIN} đã tồn tại!"
        press_enter
        return
    fi

    echo ""
    echo -e "${WHITE}Chọn phiên bản PHP:${NC}"
    local available_php=()
    for ver in "${PHP_VERSIONS[@]}"; do
        if command -v "php${ver}" &>/dev/null; then
            available_php+=("$ver")
        fi
    done

    if [[ ${#available_php[@]} -eq 0 ]]; then
        msg_error "Chưa cài đặt PHP nào. Vui lòng cài PHP trước."
        press_enter
        return
    fi

    for i in "${!available_php[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} PHP ${available_php[$i]}"
    done
    echo -ne "${YELLOW}Lựa chọn [1]: ${NC}"
    read -r php_idx
    php_idx="${php_idx:-1}"
    local PHP_VER="${available_php[$((php_idx-1))]}"

    echo ""
    echo -e "${WHITE}Loại project:${NC}"
    echo -e "  ${CYAN}1)${NC} Tạo project Laravel mới (composer create-project)"
    echo -e "  ${CYAN}2)${NC} Clone từ Git repository"
    echo -e "  ${CYAN}3)${NC} Chỉ tạo thư mục & Nginx config (deploy thủ công)"
    echo -ne "${YELLOW}Lựa chọn [1]: ${NC}"
    read -r project_type
    project_type="${project_type:-1}"

    local SITE_DIR="${WEB_ROOT}/${DOMAIN}"
    local GIT_URL=""

    if [[ "$project_type" == "2" ]]; then
        echo -ne "${YELLOW}Nhập Git URL: ${NC}"
        read -r GIT_URL
    fi

    local CREATE_DB="n"
    local DB_NAME=""
    local DB_USER=""
    local DB_PASS=""

    if confirm "Tạo database MySQL?"; then
        CREATE_DB="y"
        DB_NAME=$(echo "${DOMAIN}" | tr '.' '_' | tr '-' '_')
        echo -ne "${YELLOW}Tên database [${DB_NAME}]: ${NC}"
        read -r input_db
        DB_NAME="${input_db:-$DB_NAME}"

        DB_USER="${DB_NAME}_user"
        echo -ne "${YELLOW}Tên user DB [${DB_USER}]: ${NC}"
        read -r input_user
        DB_USER="${input_user:-$DB_USER}"

        DB_PASS=$(generate_password 16)
    fi

    echo ""
    print_separator
    echo -e "${WHITE}Xác nhận thông tin:${NC}"
    echo -e "  Domain:     ${CYAN}${DOMAIN}${NC}"
    echo -e "  Thư mục:    ${CYAN}${SITE_DIR}${NC}"
    echo -e "  PHP:        ${CYAN}${PHP_VER}${NC}"
    if [[ "$CREATE_DB" == "y" ]]; then
        echo -e "  Database:   ${CYAN}${DB_NAME}${NC}"
        echo -e "  DB User:    ${CYAN}${DB_USER}${NC}"
    fi
    print_separator
    echo ""

    if ! confirm "Bắt đầu tạo website?"; then
        return
    fi

    echo ""

    msg_step "Tạo thư mục website..."
    mkdir -p "$SITE_DIR"

    case "$project_type" in
        1)
            msg_step "Tạo Laravel project mới..."
            cd "$WEB_ROOT"
            composer create-project --prefer-dist laravel/laravel "$DOMAIN" 2>> "$LOG_FILE" || {
                msg_error "Không thể tạo Laravel project. Kiểm tra Composer."
                press_enter
                return
            }
            ;;
        2)
            msg_step "Clone repository..."
            git clone "$GIT_URL" "$SITE_DIR" 2>> "$LOG_FILE" || {
                msg_error "Không thể clone repository."
                press_enter
                return
            }
            cd "$SITE_DIR"
            composer install --no-dev --optimize-autoloader 2>> "$LOG_FILE" || true
            if [[ -f ".env.example" ]] && [[ ! -f ".env" ]]; then
                cp .env.example .env
                php artisan key:generate 2>/dev/null || true
            fi
            ;;
        3)
            msg_step "Tạo thư mục cơ bản..."
            mkdir -p "${SITE_DIR}/public"
            echo "<?php phpinfo();" > "${SITE_DIR}/public/index.php"
            ;;
    esac

    msg_step "Phân quyền thư mục..."
    chown -R www-data:www-data "$SITE_DIR"
    find "$SITE_DIR" -type f -exec chmod 644 {} \;
    find "$SITE_DIR" -type d -exec chmod 755 {} \;
    if [[ -d "${SITE_DIR}/storage" ]]; then
        chmod -R 775 "${SITE_DIR}/storage"
        chmod -R 775 "${SITE_DIR}/bootstrap/cache"
    fi
    msg_ok "Phân quyền hoàn tất"

    msg_step "Tạo Nginx configuration..."
    cat > "${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf" << NGINXCONF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${SITE_DIR}/public;

    index index.php index.html index.htm;
    charset utf-8;

    access_log ${NGINX_LOG_DIR}/${DOMAIN}-access.log;
    error_log  ${NGINX_LOG_DIR}/${DOMAIN}-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.ht { deny all; }
    location ~ /\.env { deny all; }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
NGINXCONF

    ln -sf "${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf" "${NGINX_SITES_ENABLED}/${DOMAIN}.conf"

    if nginx -t >> "$LOG_FILE" 2>&1; then
        systemctl reload nginx
        msg_ok "Nginx config tạo thành công"
    else
        msg_error "Nginx config có lỗi! Kiểm tra: nginx -t"
    fi

    if [[ "$CREATE_DB" == "y" ]]; then
        msg_step "Tạo database MySQL..."
        if [[ -f "$MYSQL_CONFIG" ]]; then
            mysql --defaults-file="$MYSQL_CONFIG" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
            mysql --defaults-file="$MYSQL_CONFIG" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null
            mysql --defaults-file="$MYSQL_CONFIG" -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';" 2>/dev/null
            mysql --defaults-file="$MYSQL_CONFIG" -e "FLUSH PRIVILEGES;" 2>/dev/null
            msg_ok "Database tạo thành công"

            if [[ -f "${SITE_DIR}/.env" ]]; then
                sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" "${SITE_DIR}/.env"
                sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" "${SITE_DIR}/.env"
                sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" "${SITE_DIR}/.env"
                msg_ok "File .env đã được cập nhật"
            fi
        else
            msg_error "Không tìm thấy MySQL credentials. Tạo DB thủ công."
        fi
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}${BOLD}  WEBSITE ĐÃ TẠO THÀNH CÔNG!                                ${NC}${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Domain:      ${CYAN}${DOMAIN}${NC}"
    echo -e "${GREEN}║${NC}  URL:         ${CYAN}http://${DOMAIN}${NC}"
    echo -e "${GREEN}║${NC}  Thư mục:     ${CYAN}${SITE_DIR}${NC}"
    echo -e "${GREEN}║${NC}  PHP:         ${CYAN}${PHP_VER}${NC}"
    if [[ "$CREATE_DB" == "y" ]]; then
        echo -e "${GREEN}║${NC}  DB Name:     ${CYAN}${DB_NAME}${NC}"
        echo -e "${GREEN}║${NC}  DB User:     ${CYAN}${DB_USER}${NC}"
        echo -e "${GREEN}║${NC}  DB Password: ${CYAN}${DB_PASS}${NC}"
    fi
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

    local info_file="${BACKUP_DIR}/site-${DOMAIN}.info"
    cat > "$info_file" << EOF
=== Website: ${DOMAIN} ===
Created: $(date)
Directory: ${SITE_DIR}
PHP Version: ${PHP_VER}
Nginx Config: ${NGINX_SITES_AVAILABLE}/${DOMAIN}.conf
EOF
    if [[ "$CREATE_DB" == "y" ]]; then
        cat >> "$info_file" << EOF
Database: ${DB_NAME}
DB User: ${DB_USER}
DB Password: ${DB_PASS}
EOF
    fi
    chmod 600 "$info_file"
    msg_ok "Thông tin đã lưu tại: ${info_file}"

    log "Created Laravel site: ${DOMAIN}"
    press_enter
}

# ========================== PHÂN QUYỀN LARAVEL ==========================

fix_permissions() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ PHÂN QUYỀN FILE LARAVEL${NC}"
    print_separator
    echo ""

    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        sites+=("$name")
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        msg_warn "Không tìm thấy website nào."
        press_enter
        return
    fi

    echo -e "${WHITE}Danh sách website:${NC}"
    for i in "${!sites[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${sites[$i]}"
    done
    echo -e "  ${CYAN}A)${NC} Tất cả website"
    echo ""
    echo -ne "${YELLOW}Chọn website: ${NC}"
    read -r site_choice

    local target_sites=()
    if [[ "$site_choice" =~ ^[Aa]$ ]]; then
        target_sites=("${sites[@]}")
    else
        local idx=$((site_choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#sites[@]} ]]; then
            target_sites=("${sites[$idx]}")
        else
            msg_error "Lựa chọn không hợp lệ"
            press_enter
            return
        fi
    fi

    echo ""
    echo -e "${WHITE}Chế độ phân quyền:${NC}"
    echo -e "  ${CYAN}1)${NC} Standard (owner: www-data, 644/755)"
    echo -e "  ${CYAN}2)${NC} Development (owner: www-data, group: current user)"
    echo -e "  ${CYAN}3)${NC} Strict Security (640/750)"
    echo -ne "${YELLOW}Lựa chọn [1]: ${NC}"
    read -r perm_mode
    perm_mode="${perm_mode:-1}"

    for site in "${target_sites[@]}"; do
        local site_dir="${WEB_ROOT}/${site}"
        if [[ ! -d "$site_dir" ]]; then
            msg_warn "Thư mục ${site_dir} không tồn tại, bỏ qua."
            continue
        fi

        msg_step "Phân quyền: ${site}..."

        case "$perm_mode" in
            1)
                chown -R www-data:www-data "$site_dir"
                find "$site_dir" -type f -exec chmod 644 {} \;
                find "$site_dir" -type d -exec chmod 755 {} \;
                ;;
            2)
                local current_user
                current_user=$(logname 2>/dev/null || echo "$SUDO_USER")
                chown -R "${current_user}:www-data" "$site_dir"
                find "$site_dir" -type f -exec chmod 664 {} \;
                find "$site_dir" -type d -exec chmod 775 {} \;
                ;;
            3)
                chown -R www-data:www-data "$site_dir"
                find "$site_dir" -type f -exec chmod 640 {} \;
                find "$site_dir" -type d -exec chmod 750 {} \;
                ;;
        esac

        if [[ -d "${site_dir}/storage" ]]; then
            chmod -R 775 "${site_dir}/storage"
            chmod -R 775 "${site_dir}/bootstrap/cache"
            mkdir -p "${site_dir}/storage/logs"
            touch "${site_dir}/storage/logs/laravel.log"
            chown www-data:www-data "${site_dir}/storage/logs/laravel.log"
        fi

        if [[ -f "${site_dir}/.env" ]]; then
            chmod 640 "${site_dir}/.env"
            chown www-data:www-data "${site_dir}/.env"
        fi

        if [[ -f "${site_dir}/artisan" ]]; then
            chmod 755 "${site_dir}/artisan"
        fi

        if command -v setfacl &>/dev/null; then
            setfacl -Rm u:www-data:rwX "${site_dir}/storage" 2>/dev/null || true
            setfacl -Rm u:www-data:rwX "${site_dir}/bootstrap/cache" 2>/dev/null || true
            setfacl -dRm u:www-data:rwX "${site_dir}/storage" 2>/dev/null || true
            setfacl -dRm u:www-data:rwX "${site_dir}/bootstrap/cache" 2>/dev/null || true
        fi

        msg_ok "${site} - Phân quyền hoàn tất"
    done

    echo ""
    msg_ok "═══ PHÂN QUYỀN HOÀN TẤT ═══"
    log "Permissions fixed for: ${target_sites[*]}"
    press_enter
}

# ========================== HTTPS / SSL ==========================

install_ssl() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ CÀI ĐẶT HTTPS / SSL (Let's Encrypt)${NC}"
    print_separator
    echo ""

    if ! command -v certbot &>/dev/null; then
        msg_step "Cài đặt Certbot..."
        apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
    fi

    echo -e "${WHITE}Danh sách domain trên server:${NC}"
    echo ""

    local domains=()
    local idx=0
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue

        local ssl_status="${RED}✗ HTTP${NC}"
        if grep -q "ssl_certificate" "$conf" 2>/dev/null; then
            ssl_status="${GREEN}✓ HTTPS${NC}"
        fi

        domains+=("$name")
        idx=$((idx + 1))
        echo -e "  ${CYAN}${idx})${NC} ${name}  ${ssl_status}"
    done

    if [[ ${#domains[@]} -eq 0 ]]; then
        msg_warn "Không tìm thấy domain nào."
        press_enter
        return
    fi

    echo -e "  ${CYAN}A)${NC} Cài SSL cho tất cả domain"
    echo ""
    echo -ne "${YELLOW}Chọn domain (số hoặc A): ${NC}"
    read -r ssl_choice

    local target_domains=()
    if [[ "$ssl_choice" =~ ^[Aa]$ ]]; then
        target_domains=("${domains[@]}")
    else
        local idx=$((ssl_choice - 1))
        if [[ $idx -ge 0 && $idx -lt ${#domains[@]} ]]; then
            target_domains=("${domains[$idx]}")
        else
            msg_error "Lựa chọn không hợp lệ"
            press_enter
            return
        fi
    fi

    echo -ne "${YELLOW}Nhập email cho Let's Encrypt: ${NC}"
    read -r LE_EMAIL
    if [[ -z "$LE_EMAIL" ]]; then
        msg_error "Email không được để trống"
        press_enter
        return
    fi

    for domain in "${target_domains[@]}"; do
        msg_step "Cài SSL cho ${domain}..."
        certbot --nginx -d "$domain" -d "www.${domain}" \
            --email "$LE_EMAIL" \
            --agree-tos \
            --non-interactive \
            --redirect \
            >> "$LOG_FILE" 2>&1 && \
        msg_ok "SSL đã cài cho ${domain}" || \
        msg_error "Lỗi cài SSL cho ${domain}. Kiểm tra DNS trỏ đúng IP server."
    done

    msg_step "Cấu hình tự động gia hạn SSL..."
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    fi
    msg_ok "Auto-renew SSL đã cấu hình (3AM hàng ngày)"

    echo ""
    msg_ok "═══ CÀI ĐẶT SSL HOÀN TẤT ═══"
    log "SSL installed for: ${target_domains[*]}"
    press_enter
}

# ========================== QUẢN LÝ WEBSITE MENU ==========================

manage_sites() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ QUẢN LÝ WEBSITE${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Danh sách website"
    echo -e "  ${CYAN}2)${NC} Bật/Tắt website"
    echo -e "  ${CYAN}3)${NC} Xóa website"
    echo -e "  ${CYAN}4)${NC} Đổi PHP version cho website"
    echo -e "  ${CYAN}5)${NC} Xem Nginx config"
    echo -e "  ${CYAN}6)${NC} Sửa Nginx config"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r site_mgmt

    case "$site_mgmt" in
        1) list_sites ;;
        2) toggle_site ;;
        3) delete_site ;;
        4) change_php_version ;;
        5) view_nginx_config ;;
        6) edit_nginx_config ;;
        0) return ;;
    esac
}

list_sites() {
    echo ""
    print_separator
    printf "${WHITE}%-30s %-10s %-8s %-10s${NC}\n" "DOMAIN" "PHP" "SSL" "STATUS"
    print_separator

    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue

        local php_ver="-"
        local detected
        detected=$(grep -oP 'php\K[0-9]+\.[0-9]+' "$conf" | head -1)
        [[ -n "$detected" ]] && php_ver="$detected"

        local ssl_status="${RED}No${NC}"
        grep -q "ssl_certificate" "$conf" 2>/dev/null && ssl_status="${GREEN}Yes${NC}"

        local enabled="${RED}Off${NC}"
        [[ -L "${NGINX_SITES_ENABLED}/${name}.conf" ]] && enabled="${GREEN}On${NC}"

        printf "  %-30s %-10s %-18b %-20b\n" "$name" "$php_ver" "$ssl_status" "$enabled"
    done

    echo ""
    press_enter
}

toggle_site() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        local status="ON"
        [[ ! -L "${NGINX_SITES_ENABLED}/${name}.conf" ]] && status="OFF"
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name} [${status}]"
    done

    echo -ne "${YELLOW}Chọn website để bật/tắt: ${NC}"
    read -r t_choice
    local idx=$((t_choice - 1))
    local site="${sites[$idx]}"

    if [[ -L "${NGINX_SITES_ENABLED}/${site}.conf" ]]; then
        rm -f "${NGINX_SITES_ENABLED}/${site}.conf"
        msg_ok "${site} đã TẮT"
    else
        ln -sf "${NGINX_SITES_AVAILABLE}/${site}.conf" "${NGINX_SITES_ENABLED}/${site}.conf"
        msg_ok "${site} đã BẬT"
    fi

    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx
    press_enter
}

delete_site() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
    done

    echo -ne "${YELLOW}Chọn website để xóa: ${NC}"
    read -r d_choice
    local idx=$((d_choice - 1))
    local site="${sites[$idx]}"

    echo ""
    msg_warn "BẠN SẮP XÓA WEBSITE: ${site}"
    echo -e "  Thư mục: ${WEB_ROOT}/${site}"
    echo ""

    local del_files="n"
    local del_db="n"

    if confirm "Xóa thư mục website?"; then del_files="y"; fi
    if confirm "Xóa database (nếu có)?"; then
        del_db="y"
        local db_name
        db_name=$(echo "${site}" | tr '.' '_' | tr '-' '_')
        echo -ne "${YELLOW}Tên database [${db_name}]: ${NC}"
        read -r input_db
        db_name="${input_db:-$db_name}"
    fi

    if ! confirm "XÁC NHẬN XÓA ${site}? KHÔNG THỂ HOÀN TÁC!"; then
        return
    fi

    if [[ -d "${WEB_ROOT}/${site}" && "$del_files" == "y" ]]; then
        msg_step "Backup trước khi xóa..."
        tar -czf "${BACKUP_DIR}/${site}-$(date +%Y%m%d%H%M%S).tar.gz" -C "${WEB_ROOT}" "${site}" 2>/dev/null || true
    fi

    rm -f "${NGINX_SITES_ENABLED}/${site}.conf"
    rm -f "${NGINX_SITES_AVAILABLE}/${site}.conf"
    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx

    rm -f "/etc/supervisor/conf.d/$(echo "${site}" | tr '.' '-')-*.conf"
    supervisorctl reread >> "$LOG_FILE" 2>&1 || true
    supervisorctl update >> "$LOG_FILE" 2>&1 || true

    local crontab_content
    crontab_content=$(crontab -u www-data -l 2>/dev/null | grep -v "${site}" || true)
    echo "$crontab_content" | crontab -u www-data - 2>/dev/null || true

    if [[ "$del_files" == "y" ]]; then
        rm -rf "${WEB_ROOT:?}/${site}"
        msg_ok "Thư mục đã xóa"
    fi

    if [[ "$del_db" == "y" && -f "$MYSQL_CONFIG" ]]; then
        mysql --defaults-file="$MYSQL_CONFIG" -e "DROP DATABASE IF EXISTS \`${db_name}\`;" 2>/dev/null || true
        mysql --defaults-file="$MYSQL_CONFIG" -e "DROP USER IF EXISTS '${db_name}_user'@'localhost';" 2>/dev/null || true
        msg_ok "Database đã xóa"
    fi

    msg_ok "Website ${site} đã xóa hoàn toàn"
    log "Deleted site: ${site}"
    press_enter
}

change_php_version() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        local current_php
        current_php=$(grep -oP 'php\K[0-9]+\.[0-9]+' "$conf" | head -1)
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name} (PHP ${current_php:-unknown})"
    done

    echo -ne "${YELLOW}Chọn website: ${NC}"
    read -r p_choice
    local idx=$((p_choice - 1))
    local site="${sites[$idx]}"
    local conf="${NGINX_SITES_AVAILABLE}/${site}.conf"

    echo ""
    echo -e "${WHITE}Chọn phiên bản PHP mới:${NC}"
    local available_php=()
    for ver in "${PHP_VERSIONS[@]}"; do
        if command -v "php${ver}" &>/dev/null; then
            available_php+=("$ver")
            echo -e "  ${CYAN}${#available_php[@]})${NC} PHP ${ver}"
        fi
    done

    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r new_php_choice
    local new_ver="${available_php[$((new_php_choice - 1))]}"

    sed -i "s|php[0-9]\+\.[0-9]\+-fpm\.sock|php${new_ver}-fpm.sock|g" "$conf"

    if nginx -t >> "$LOG_FILE" 2>&1; then
        systemctl reload nginx
        msg_ok "${site} đã chuyển sang PHP ${new_ver}"
    else
        msg_error "Lỗi Nginx config! Kiểm tra: nginx -t"
    fi

    press_enter
}

view_nginx_config() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
    done

    echo -ne "${YELLOW}Chọn website: ${NC}"
    read -r v_choice
    local idx=$((v_choice - 1))
    local site="${sites[$idx]}"
    echo ""
    print_separator
    cat "${NGINX_SITES_AVAILABLE}/${site}.conf"
    print_separator
    press_enter
}

edit_nginx_config() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name
        name=$(basename "$conf" .conf)
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
    done

    echo -ne "${YELLOW}Chọn website: ${NC}"
    read -r e_choice
    local idx=$((e_choice - 1))
    local site="${sites[$idx]}"

    ${EDITOR:-nano} "${NGINX_SITES_AVAILABLE}/${site}.conf"

    if nginx -t >> "$LOG_FILE" 2>&1; then
        systemctl reload nginx
        msg_ok "Nginx config đã reload"
    else
        msg_error "Nginx config có lỗi!"
    fi

    press_enter
}
