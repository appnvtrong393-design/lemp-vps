#!/bin/bash
# ========================== BACKUP & RESTORE ==========================

manage_backup() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ BACKUP & RESTORE${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Backup toàn bộ website + database"
    echo -e "  ${CYAN}2)${NC} Backup chỉ website (files)"
    echo -e "  ${CYAN}3)${NC} Backup chỉ database"
    echo -e "  ${CYAN}4)${NC} Xem danh sách backup"
    echo -e "  ${CYAN}5)${NC} Cấu hình auto backup (cron)"
    echo -e "  ${CYAN}6)${NC} Xóa backup cũ"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r bk_choice

    case "$bk_choice" in
        1)
            echo ""
            local sites=()
            for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
                [[ -f "$conf" ]] || continue
                local name=$(basename "$conf" .conf)
                [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
                sites+=("$name")
            done

            for site in "${sites[@]}"; do
                msg_step "Backup ${site}..."
                local ts=$(date +%Y%m%d%H%M%S)
                if [[ -d "${WEB_ROOT}/${site}" ]]; then
                    tar -czf "${BACKUP_DIR}/${site}-files-${ts}.tar.gz" -C "${WEB_ROOT}" "${site}" 2>/dev/null
                fi
                local db_name=$(echo "${site}" | tr '.' '_' | tr '-' '_')
                if [[ -f "$MYSQL_CONFIG" ]]; then
                    mysqldump --defaults-file="$MYSQL_CONFIG" "$db_name" 2>/dev/null | gzip > "${BACKUP_DIR}/${site}-db-${ts}.sql.gz" || true
                fi
                msg_ok "${site} backup hoàn tất"
            done
            ;;
        2) backup_files_only ;;
        3) backup_database ;;
        4)
            echo ""
            echo -e "${WHITE}Danh sách backup:${NC}"
            ls -lhS "${BACKUP_DIR}/" 2>/dev/null || echo "  (trống)"
            ;;
        5) setup_auto_backup ;;
        6)
            echo -ne "${YELLOW}Xóa backup cũ hơn bao nhiêu ngày? [30]: ${NC}"
            read -r days
            days="${days:-30}"
            find "${BACKUP_DIR}" -name "*.tar.gz" -mtime "+${days}" -delete 2>/dev/null
            find "${BACKUP_DIR}" -name "*.sql.gz" -mtime "+${days}" -delete 2>/dev/null
            msg_ok "Đã xóa backup cũ hơn ${days} ngày"
            ;;
        0) return ;;
    esac
    press_enter
}

backup_files_only() {
    echo ""
    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        sites+=("$name")
        echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
    done

    echo -ne "${YELLOW}Chọn website: ${NC}"
    read -r b_choice
    local idx=$((b_choice - 1))
    local site="${sites[$idx]}"

    local ts=$(date +%Y%m%d%H%M%S)
    tar -czf "${BACKUP_DIR}/${site}-files-${ts}.tar.gz" -C "${WEB_ROOT}" "${site}" 2>/dev/null
    msg_ok "Backup: ${BACKUP_DIR}/${site}-files-${ts}.tar.gz"
}

setup_auto_backup() {
    echo ""
    echo -ne "${YELLOW}Backup lúc mấy giờ hàng ngày? [2]: ${NC}"
    read -r backup_hour
    backup_hour="${backup_hour:-2}"

    local backup_script="/usr/local/bin/server-auto-backup.sh"
    cat > "$backup_script" << 'BACKUP_SCRIPT'
#!/bin/bash
BACKUP_DIR="/var/backups/server-manager"
WEB_ROOT="/var/www"
MYSQL_CONFIG="/root/.my.cnf"
KEEP_DAYS=30
TS=$(date +%Y%m%d%H%M%S)

mkdir -p "${BACKUP_DIR}/auto"

for dir in ${WEB_ROOT}/*/; do
    site=$(basename "$dir")
    [[ "$site" == "html" || "$site" == "phpmyadmin" ]] && continue

    tar -czf "${BACKUP_DIR}/auto/${site}-files-${TS}.tar.gz" -C "${WEB_ROOT}" "${site}" 2>/dev/null

    db_name=$(echo "${site}" | tr '.' '_' | tr '-' '_')
    if [[ -f "$MYSQL_CONFIG" ]]; then
        mysqldump --defaults-file="$MYSQL_CONFIG" "$db_name" 2>/dev/null | gzip > "${BACKUP_DIR}/auto/${site}-db-${TS}.sql.gz" || true
    fi
done

find "${BACKUP_DIR}/auto" -name "*.tar.gz" -mtime "+${KEEP_DAYS}" -delete 2>/dev/null
find "${BACKUP_DIR}/auto" -name "*.sql.gz" -mtime "+${KEEP_DAYS}" -delete 2>/dev/null
BACKUP_SCRIPT

    chmod +x "$backup_script"

    local existing=$(crontab -l 2>/dev/null | grep -v "server-auto-backup" || true)
    (echo "$existing"; echo "0 ${backup_hour} * * * ${backup_script} >> /var/log/auto-backup.log 2>&1") | crontab -

    msg_ok "Auto backup hàng ngày lúc ${backup_hour}:00 đã cấu hình"
}

# ========================== DEPLOY HELPER ==========================

deploy_helper() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ DEPLOY HELPER${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Chạy Laravel deployment commands"
    echo -e "  ${CYAN}2)${NC} Tạo deploy script cho website"
    echo -e "  ${CYAN}3)${NC} Clear all Laravel caches"
    echo -e "  ${CYAN}4)${NC} Optimize Laravel (cache config/route/view)"
    echo -e "  ${CYAN}5)${NC} Run migrations"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r deploy_choice

    local sites=()
    for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
        [[ -f "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
        if [[ -f "${WEB_ROOT}/${name}/artisan" ]]; then
            sites+=("$name")
        fi
    done

    if [[ ${#sites[@]} -eq 0 && "$deploy_choice" != "0" ]]; then
        msg_warn "Không tìm thấy Laravel project nào."
        press_enter
        return
    fi

    if [[ "$deploy_choice" == "0" ]]; then return; fi

    echo ""
    echo -e "${WHITE}Chọn website:${NC}"
    for i in "${!sites[@]}"; do
        echo -e "  ${CYAN}$((i+1)))${NC} ${sites[$i]}"
    done
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r site_idx
    local site="${sites[$((site_idx-1))]}"
    local site_dir="${WEB_ROOT}/${site}"

    cd "$site_dir"

    case "$deploy_choice" in
        1)
            msg_step "Full deployment..."
            sudo -u www-data git pull 2>/dev/null || true
            sudo -u www-data composer install --no-dev --optimize-autoloader 2>> "$LOG_FILE"
            sudo -u www-data php artisan migrate --force 2>> "$LOG_FILE"
            sudo -u www-data php artisan config:cache 2>> "$LOG_FILE"
            sudo -u www-data php artisan route:cache 2>> "$LOG_FILE"
            sudo -u www-data php artisan view:cache 2>> "$LOG_FILE"
            sudo -u www-data php artisan event:cache 2>> "$LOG_FILE" || true
            sudo -u www-data php artisan storage:link 2>> "$LOG_FILE" || true
            sudo -u www-data npm install 2>> "$LOG_FILE" || true
            sudo -u www-data npm run build 2>> "$LOG_FILE" || true
            sudo -u www-data php artisan queue:restart 2>/dev/null || true
            msg_ok "Deploy hoàn tất cho ${site}"
            ;;
        2)
            local deploy_script="${site_dir}/deploy.sh"
            cat > "$deploy_script" << DEPLOY
#!/bin/bash
set -e
cd ${site_dir}

echo "Pulling latest changes..."
git pull origin main

echo "Installing dependencies..."
composer install --no-dev --optimize-autoloader

echo "Running migrations..."
php artisan migrate --force

echo "Caching..."
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

echo "Building assets..."
npm install
npm run build

echo "Restarting queue..."
php artisan queue:restart

echo "Setting permissions..."
chown -R www-data:www-data ${site_dir}
chmod -R 775 ${site_dir}/storage
chmod -R 775 ${site_dir}/bootstrap/cache

echo "Deploy complete!"
DEPLOY
            chmod +x "$deploy_script"
            chown www-data:www-data "$deploy_script"
            msg_ok "Deploy script tạo tại: ${deploy_script}"
            ;;
        3)
            sudo -u www-data php artisan cache:clear
            sudo -u www-data php artisan config:clear
            sudo -u www-data php artisan route:clear
            sudo -u www-data php artisan view:clear
            sudo -u www-data php artisan event:clear 2>/dev/null || true
            msg_ok "All Laravel caches cleared"
            ;;
        4)
            sudo -u www-data php artisan config:cache
            sudo -u www-data php artisan route:cache
            sudo -u www-data php artisan view:cache
            sudo -u www-data php artisan event:cache 2>/dev/null || true
            msg_ok "Laravel optimized"
            ;;
        5)
            echo -ne "${YELLOW}Chế độ (1=migrate, 2=migrate:fresh, 3=migrate:rollback): ${NC}"
            read -r mig_mode
            case "$mig_mode" in
                1) sudo -u www-data php artisan migrate --force ;;
                2)
                    if confirm "CẢNH BÁO: migrate:fresh sẽ XÓA TẤT CẢ TABLES. Tiếp tục?"; then
                        sudo -u www-data php artisan migrate:fresh --force
                    fi
                    ;;
                3) sudo -u www-data php artisan migrate:rollback ;;
            esac
            ;;
    esac

    press_enter
}

# ========================== SECURITY ==========================

manage_security() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ BẢO MẬT SERVER${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Kiểm tra bảo mật (Security Audit)"
    echo -e "  ${CYAN}2)${NC} Cấu hình UFW Firewall"
    echo -e "  ${CYAN}3)${NC} Xem Fail2Ban status & logs"
    echo -e "  ${CYAN}4)${NC} Đổi SSH Port"
    echo -e "  ${CYAN}5)${NC} Tắt SSH password (chỉ dùng key)"
    echo -e "  ${CYAN}6)${NC} Cấu hình tự động cập nhật bảo mật"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r sec_choice

    case "$sec_choice" in
        1)
            echo ""
            echo -e "${WHITE}${BOLD}Security Audit:${NC}"
            print_separator

            if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
                echo -e "  ${RED}✗${NC} Root login via SSH: ${RED}ENABLED${NC} (nên tắt)"
            else
                echo -e "  ${GREEN}✓${NC} Root login via SSH: ${GREEN}DISABLED${NC}"
            fi

            if ufw status | grep -q "active"; then
                echo -e "  ${GREEN}✓${NC} UFW Firewall: ${GREEN}ACTIVE${NC}"
            else
                echo -e "  ${RED}✗${NC} UFW Firewall: ${RED}INACTIVE${NC}"
            fi

            if systemctl is-active --quiet fail2ban; then
                echo -e "  ${GREEN}✓${NC} Fail2Ban: ${GREEN}ACTIVE${NC}"
            else
                echo -e "  ${RED}✗${NC} Fail2Ban: ${RED}INACTIVE${NC}"
            fi

            if dpkg -l | grep -q unattended-upgrades; then
                echo -e "  ${GREEN}✓${NC} Auto security updates: ${GREEN}ENABLED${NC}"
            else
                echo -e "  ${YELLOW}!${NC} Auto security updates: ${YELLOW}NOT CONFIGURED${NC}"
            fi

            echo ""
            echo -e "  ${WHITE}Open ports:${NC}"
            ss -tlnp 2>/dev/null | grep LISTEN | awk '{print "    " $4 " -> " $6}' | head -20

            echo ""
            echo -e "  ${WHITE}Recent failed SSH logins:${NC}"
            grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 | while read -r line; do
                echo "    ${line}"
            done
            ;;
        2)
            echo ""
            echo -e "${WHITE}UFW Status:${NC}"
            ufw status verbose
            echo ""
            echo -ne "${YELLOW}Thêm rule (vd: allow 3306, deny 8080, hoặc Enter để bỏ qua): ${NC}"
            read -r ufw_rule
            if [[ -n "$ufw_rule" ]]; then
                ufw $ufw_rule >> "$LOG_FILE" 2>&1
                msg_ok "Rule đã thêm"
            fi
            ;;
        3)
            echo ""
            fail2ban-client status 2>/dev/null
            echo ""
            fail2ban-client status sshd 2>/dev/null
            ;;
        4)
            echo -ne "${YELLOW}Nhập SSH port mới [22]: ${NC}"
            read -r new_port
            new_port="${new_port:-22}"
            sed -i "s/^#\?Port .*/Port ${new_port}/" /etc/ssh/sshd_config
            ufw allow "$new_port" >> "$LOG_FILE" 2>&1
            systemctl restart sshd
            msg_ok "SSH port đã đổi thành ${new_port}"
            msg_warn "Nhớ cập nhật firewall và kết nối lại SSH!"
            ;;
        5)
            sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
            systemctl restart sshd
            msg_ok "SSH password authentication đã tắt"
            msg_warn "Đảm bảo bạn đã thêm SSH key trước!"
            ;;
        6)
            apt-get install -y unattended-upgrades >> "$LOG_FILE" 2>&1
            dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
            msg_ok "Auto security updates đã cấu hình"
            ;;
        0) return ;;
    esac
    press_enter
}

# ========================== LOG VIEWER ==========================

view_logs() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ XEM LOG${NC}"
    print_separator
    echo ""

    echo -e "  ${CYAN}1)${NC} Nginx access log (global)"
    echo -e "  ${CYAN}2)${NC} Nginx error log (global)"
    echo -e "  ${CYAN}3)${NC} Nginx log theo website"
    echo -e "  ${CYAN}4)${NC} Laravel log"
    echo -e "  ${CYAN}5)${NC} MySQL slow query log"
    echo -e "  ${CYAN}6)${NC} PHP-FPM log"
    echo -e "  ${CYAN}7)${NC} System log (syslog)"
    echo -e "  ${CYAN}8)${NC} Script log"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r log_choice

    local log_file=""

    case "$log_choice" in
        1) log_file="/var/log/nginx/access.log" ;;
        2) log_file="/var/log/nginx/error.log" ;;
        3)
            local sites=()
            for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
                [[ -f "$conf" ]] || continue
                local name=$(basename "$conf" .conf)
                [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
                sites+=("$name")
                echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
            done
            echo -ne "${YELLOW}Chọn website: ${NC}"
            read -r s
            local site="${sites[$((s-1))]}"
            echo -e "  ${CYAN}1)${NC} Access log"
            echo -e "  ${CYAN}2)${NC} Error log"
            echo -ne "${YELLOW}Chọn: ${NC}"
            read -r lt
            if [[ "$lt" == "1" ]]; then
                log_file="${NGINX_LOG_DIR}/${site}-access.log"
            else
                log_file="${NGINX_LOG_DIR}/${site}-error.log"
            fi
            ;;
        4)
            local sites=()
            for conf in "${NGINX_SITES_AVAILABLE}"/*.conf; do
                [[ -f "$conf" ]] || continue
                local name=$(basename "$conf" .conf)
                [[ "$name" == "default" || "$name" == "phpmyadmin" ]] && continue
                if [[ -f "${WEB_ROOT}/${name}/storage/logs/laravel.log" ]]; then
                    sites+=("$name")
                    echo -e "  ${CYAN}${#sites[@]})${NC} ${name}"
                fi
            done
            echo -ne "${YELLOW}Chọn website: ${NC}"
            read -r s
            log_file="${WEB_ROOT}/${sites[$((s-1))]}/storage/logs/laravel.log"
            ;;
        5) log_file="/var/log/mysql/slow.log" ;;
        6)
            local php_ver
            echo -ne "${YELLOW}PHP version (vd: 8.3): ${NC}"
            read -r php_ver
            log_file="/var/log/php${php_ver}-fpm.log"
            ;;
        7) log_file="/var/log/syslog" ;;
        8) log_file="$LOG_FILE" ;;
        0) return ;;
    esac

    if [[ -n "$log_file" && -f "$log_file" ]]; then
        echo ""
        echo -e "${WHITE}Log: ${log_file}${NC}"
        echo -e "${DIM}(Ctrl+C để thoát)${NC}"
        print_separator
        tail -f "$log_file" 2>/dev/null || tail -50 "$log_file"
    elif [[ -n "$log_file" ]]; then
        msg_warn "File log không tồn tại: ${log_file}"
    fi
    press_enter
}

# ========================== SWAP MEMORY ==========================

manage_swap() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ QUẢN LÝ SWAP MEMORY${NC}"
    print_separator
    echo ""

    echo -e "  ${WHITE}Swap hiện tại:${NC}"
    free -h | grep -i swap
    swapon --show 2>/dev/null
    echo ""

    echo -e "  ${CYAN}1)${NC} Tạo Swap file"
    echo -e "  ${CYAN}2)${NC} Xóa Swap"
    echo -e "  ${CYAN}3)${NC} Tối ưu swappiness"
    echo -e "  ${CYAN}0)${NC} Quay lại"
    echo ""
    echo -ne "${YELLOW}Lựa chọn: ${NC}"
    read -r swap_choice

    case "$swap_choice" in
        1)
            echo -ne "${YELLOW}Kích thước Swap (vd: 2G, 4G) [2G]: ${NC}"
            read -r swap_size
            swap_size="${swap_size:-2G}"

            if [[ -f /swapfile ]]; then
                msg_warn "Swapfile đã tồn tại. Xóa trước nếu muốn tạo mới."
            else
                fallocate -l "$swap_size" /swapfile
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile

                if ! grep -q "/swapfile" /etc/fstab; then
                    echo "/swapfile none swap sw 0 0" >> /etc/fstab
                fi

                msg_ok "Swap ${swap_size} đã tạo"
            fi
            ;;
        2)
            swapoff /swapfile 2>/dev/null || true
            rm -f /swapfile
            sed -i '/swapfile/d' /etc/fstab
            msg_ok "Swap đã xóa"
            ;;
        3)
            echo -ne "${YELLOW}Swappiness value (0-100, recommend 10) [10]: ${NC}"
            read -r swappiness
            swappiness="${swappiness:-10}"
            sysctl vm.swappiness="$swappiness"
            echo "vm.swappiness=$swappiness" > /etc/sysctl.d/99-swappiness.conf
            msg_ok "Swappiness = ${swappiness}"
            ;;
        0) return ;;
    esac
    press_enter
}
