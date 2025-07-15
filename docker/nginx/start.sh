#!/bin/bash

# Nginx başlat
echo "Nginx başlatılıyor..."

# Gerekli dizinleri oluştur
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Nginx'i başlat
exec nginx -g "daemon off;"
