#!/bin/bash

# Tüm servisleri başlat
start() {
    echo "🚀 Tüm servisleri başlatılıyor..."
    docker-compose up -d
    echo "✅ Tüm servisler başlatıldı!"
}

# Tüm servisleri durdur (veriler korunur)
stop() {
    echo "⏹️  Tüm servisler durduruluyor..."
    docker-compose down
    echo "✅ Tüm servisler durduruldu!"
}

# Tüm servisleri yeniden başlat
restart() {
    echo "🔄 Tüm servisler yeniden başlatılıyor..."
    docker-compose down
    docker-compose up -d
    echo "✅ Tüm servisler yeniden başlatıldı!"
}

# PHP'yi rebuild et
rebuild-php() {
    echo "🔨 PHP rebuild ediliyor..."
    docker-compose up --build -d php
    echo "✅ PHP rebuild edildi!"
}

# Tüm servisleri rebuild et
rebuild-all() {
    echo "🔨 Tüm servisler rebuild ediliyor..."
    docker-compose down
    docker-compose up --build -d
    echo "✅ Tüm servisler rebuild edildi!"
}

# Status kontrol et
status() {
    echo "📊 Servis durumu:"
    docker-compose ps
}

# Logları göster
logs() {
    if [ -z "$1" ]; then
        docker-compose logs -f
    else
        docker-compose logs -f "$1"
    fi
}

# MySQL volume'unu backup al
backup-mysql() {
    timestamp=$(date +%Y%m%d_%H%M%S)
    echo "💾 MySQL backup alınıyor: mysql_backup_$timestamp.sql"
    docker-compose exec mysql mysqldump -u root -proot --all-databases > "mysql_backup_$timestamp.sql"
    echo "✅ Backup alındı!"
}

# Artisan komutlarını docker container içinde çalıştır
artisan() {
    if [ -z "$1" ]; then
        echo "❌ Artisan komutu belirtmelisiniz!"
        echo "Örnek: $0 artisan migrate"
        return 1
    fi
    
    echo "🎨 Artisan komutu çalıştırılıyor: php artisan $*"
    docker-compose exec php php artisan "$@"
}

# Composer komutlarını docker container içinde çalıştır
composer() {
    if [ -z "$1" ]; then
        echo "❌ Composer komutu belirtmelisiniz!"
        echo "Örnek: $0 composer install"
        return 1
    fi
    
    echo "📦 Composer komutu çalıştırılıyor: composer $*"
    docker-compose exec php composer "$@"
}

# PHP container'a bash ile bağlan
shell() {
    echo "🐚 PHP container'a bağlanılıyor..."
    docker-compose exec php bash
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    rebuild-php)
        rebuild-php
        ;;
    rebuild-all)
        rebuild-all
        ;;
    status)
        status
        ;;
    logs)
        logs "$2"
        ;;
    backup)
        backup-mysql
        ;;
    artisan)
        shift
        artisan "$@"
        ;;
    composer)
        shift
        composer "$@"
        ;;
    shell)
        shell
        ;;
    *)
        echo "Kullanım: $0 {start|stop|restart|rebuild-php|rebuild-all|status|logs [servis]|backup|artisan [komut]|composer [komut]|shell}"
        echo ""
        echo "Örnekler:"
        echo "  $0 start              # Tüm servisleri başlat"
        echo "  $0 stop               # Tüm servisleri durdur"
        echo "  $0 restart            # Tüm servisleri yeniden başlat"
        echo "  $0 rebuild-php        # Sadece PHP'yi rebuild et"
        echo "  $0 rebuild-all        # Tüm servisleri rebuild et"
        echo "  $0 status             # Servis durumunu göster"
        echo "  $0 logs               # Tüm logları göster"
        echo "  $0 logs nginx         # Sadece nginx loglarını göster"
        echo "  $0 backup             # MySQL backup al"
        echo "  $0 artisan migrate    # Artisan migrate çalıştır"
        echo "  $0 artisan make:model User  # Model oluştur"
        echo "  $0 composer install   # Composer install"
        echo "  $0 shell              # PHP container'a bash ile bağlan"
        exit 1
esac
