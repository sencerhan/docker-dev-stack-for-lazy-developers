#!/bin/bash

# İzinleri ayarla
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/lib/mysql

# Redis kullanıcısı oluştur
if ! id redis &>/dev/null; then
    useradd -r -s /bin/false redis
fi

# Log dizinlerini oluştur
mkdir -p /var/log/supervisor
mkdir -p /var/log/nginx

# Supervisor'ü başlat
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
