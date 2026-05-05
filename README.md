# LEMP VPS Manager

Script tự động cài đặt và quản lý LEMP Stack + Laravel trên Ubuntu.

## Cài đặt

```bash
curl -sL https://cdn.jsdelivr.net/gh/appnvtrong393-design/lemp-vps@main/install.sh | sudo bash
```

Sau khi chạy, script tự động:
- Setup hệ thống (firewall, fail2ban, timezone...)
- Cài Nginx, PHP, MySQL, Composer, Node.js, Redis, phpMyAdmin
- Tải script quản lý `qlvps` về `/opt/laravel-manager/`
- Tạo alias `qlvps`

## Quản lý

```bash
qlvps
```

| Menu | Chức năng |
|------|-----------|
| **Website** | Tạo site Laravel, quản lý (bật/tắt/xóa), phân quyền, cài SSL |
| **Services** | Cronjob & Queue Worker, Database, PHP |
| **Tools** | Backup/Restore, Deploy, Bảo mật, Log, Swap |

## Hỗ trợ

- Ubuntu 20.04 / 22.04 / 24.04 / 26.04
- PHP 5.6 → 8.5

## Cấu trúc

```
install.sh          # Script cài đặt (curl 1 lệnh)
qlvps               # Script quản lý chính
lib/
├── common.sh       # Cấu hình, màu sắc, hàm dùng chung
├── site.sh         # Quản lý website
├── services.sh     # Cron/Queue, Database, PHP
├── tools.sh        # Backup, Deploy, Security, Logs, Swap
└── info.sh         # Thông tin server
```
