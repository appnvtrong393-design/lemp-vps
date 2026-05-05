#!/bin/bash
# ========================== THÔNG TIN SERVER ==========================

show_server_info() {
    print_header
    echo -e "${WHITE}${BOLD}  ▸ THÔNG TIN SERVER${NC}"
    print_separator
    echo ""

    echo -e "  ${WHITE}Hostname:${NC}    $(hostname)"
    echo -e "  ${WHITE}IP:${NC}          $(get_server_ip)"
    echo -e "  ${WHITE}OS:${NC}          $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"
    echo -e "  ${WHITE}Kernel:${NC}      $(uname -r)"
    echo -e "  ${WHITE}Uptime:${NC}      $(uptime -p)"
    echo -e "  ${WHITE}CPU:${NC}         $(nproc) cores"
    echo -e "  ${WHITE}RAM:${NC}         $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
    echo -e "  ${WHITE}Disk:${NC}        $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')"
    echo -e "  ${WHITE}Timezone:${NC}    $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'N/A')"
    echo ""

    echo -e "  ${WHITE}Nginx:${NC}       $(nginx -v 2>&1 | cut -d'/' -f2 || echo 'N/A')"
    echo -e "  ${WHITE}MySQL:${NC}       $(mysql --version 2>/dev/null | awk '{print $3}' || echo 'N/A')"
    echo -e "  ${WHITE}Composer:${NC}    $(composer --version 2>/dev/null | awk '{print $3}' || echo 'N/A')"
    echo -e "  ${WHITE}Node.js:${NC}     $(node --version 2>/dev/null || echo 'N/A')"
    echo -e "  ${WHITE}Redis:${NC}       $(redis-server --version 2>/dev/null | awk '{print $3}' | tr -d 'v=' || echo 'N/A')"
    echo ""

    echo -e "  ${WHITE}PHP versions:${NC}"
    for ver in "${PHP_VERSIONS[@]}"; do
        if command -v "php${ver}" &>/dev/null; then
            local is_default=""
            local current=$(php -v 2>/dev/null | head -1 | awk '{print $2}')
            [[ "$current" == "${ver}"* ]] && is_default="${GREEN}(default)${NC}"
            echo -e "    ${CYAN}●${NC} PHP ${ver} ${is_default}"
        fi
    done

    echo ""
    show_services_status

    press_enter
}
