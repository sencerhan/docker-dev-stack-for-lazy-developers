FROM php:8.3-fpm

# Tüm gerekli paketleri kur
RUN apt-get update && apt-get install -y \
    nginx \
    default-mysql-server \
    redis-server \
    supervisor \
    inotify-tools \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    && rm -rf /var/lib/apt/lists/*

# GD extensionunu FreeType ve JPEG desteği ile kur
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

# Composer kur
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# PHP konfigürasyonunu kopyala
COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-custom.ini

# Nginx konfigürasyonunu kopyala
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/sites-available /etc/nginx/sites-available
COPY docker/nginx/sites-enabled /etc/nginx/sites-enabled

# MySQL konfigürasyonunu kopyala
COPY docker/mysql/my.cnf /etc/mysql/conf.d/my.cnf

# MySQL data dizinini oluştur
RUN mkdir -p /var/lib/mysql

# Supervisor konfigürasyonunu oluştur
RUN mkdir -p /var/log/supervisor
COPY docker/all-in-one/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# MySQL başlatma scripti
COPY docker/all-in-one/init-mysql.sh /usr/local/bin/init-mysql.sh
RUN chmod +x /usr/local/bin/init-mysql.sh

# Nginx başlatma scripti
COPY docker/all-in-one/init-nginx.sh /usr/local/bin/init-nginx.sh
RUN chmod +x /usr/local/bin/init-nginx.sh

# Ana başlatma scripti
COPY docker/all-in-one/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# File watcher scripti (tek container için optimize edilmiş)
COPY docker/all-in-one/watcher.sh /usr/local/bin/watcher.sh
RUN chmod +x /usr/local/bin/watcher.sh

# Çalışma dizini
WORKDIR /var/www/html

# www-data kullanıcısını user ID 1000 yap
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

# MySQL data dizini için volume
VOLUME ["/var/lib/mysql"]

# Port'ları aç
EXPOSE 80 3306 6379 9000

# Supervisor ile tüm servisleri başlat
CMD ["/usr/local/bin/start.sh"]
