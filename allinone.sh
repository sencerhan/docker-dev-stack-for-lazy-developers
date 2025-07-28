#!/bin/bash

# Tek container modunda çalış
start() {
    echo "🚀 Laravel stack başlatılıyor (tek container)..."
    docker-compose -f docker-compose-allinone.yml up -d
    echo "✅ Laravel stack başlatıldı!"
    echo "📌 Web: http://localhost"
    echo "📌 MySQL: localhost:3306 (root/root)"
    echo "📌 Redis: localhost:6379"
}

stop() {
    echo "⏹️  Laravel stack durduruluyor..."
    docker-compose -f docker-compose-allinone.yml down
    echo "✅ Laravel stack durduruldu!"
}

restart() {
    echo "🔄 Laravel stack yeniden başlatılıyor..."
    docker-compose -f docker-compose-allinone.yml down
    docker-compose -f docker-compose-allinone.yml up -d
    echo "✅ Laravel stack yeniden başlatıldı!"
}

rebuild() {
    echo "🔨 Laravel stack rebuild ediliyor..."
    docker-compose -f docker-compose-allinone.yml down
    docker-compose -f docker-compose-allinone.yml up --build -d
    echo "✅ Laravel stack rebuild edildi!"
}

status() {
    echo "📊 Stack durumu:"
    docker-compose -f docker-compose-allinone.yml ps
}

logs() {
    docker-compose -f docker-compose-allinone.yml logs -f
}

shell() {
    echo "🐚 Container'a bağlanılıyor..."
    docker-compose -f docker-compose-allinone.yml exec all-in-one bash
}

artisan() {
    if [ -z "$1" ]; then
        echo "❌ Artisan komutu belirtmelisiniz!"
        echo "Örnek: $0 artisan migrate"
        return 1
    fi
    
    echo "🎨 Artisan komutu çalıştırılıyor: php artisan $*"
    docker-compose -f docker-compose-allinone.yml exec all-in-one php artisan "$@"
}

composer() {
    if [ -z "$1" ]; then
        echo "❌ Composer komutu belirtmelisiniz!"
        echo "Örnek: $0 composer install"
        return 1
    fi
    
    echo "📦 Composer komutu çalıştırılıyor: composer $*"
    docker-compose -f docker-compose-allinone.yml exec all-in-one composer "$@"
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
    rebuild)
        rebuild
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    shell)
        shell
        ;;
    artisan)
        shift
        artisan "$@"
        ;;
    composer)
        shift
        composer "$@"
        ;;
    *)
        echo "Kullanım: $0 {start|stop|restart|rebuild|status|logs|shell|artisan [komut]|composer [komut]}"
        echo ""
        echo "🚀 TEK CONTAINER MOD"
        echo "Örnekler:"
        echo "  $0 start              # Stack'i başlat"
        echo "  $0 stop               # Stack'i durdur"
        echo "  $0 restart            # Stack'i yeniden başlat"
        echo "  $0 rebuild            # Stack'i rebuild et"
        echo "  $0 status             # Durum kontrolü"
        echo "  $0 logs               # Logları göster"
        echo "  $0 shell              # Container'a bağlan"
        echo "  $0 artisan migrate    # Artisan migrate"
        echo "  $0 composer install   # Composer install"
        exit 1
esac
