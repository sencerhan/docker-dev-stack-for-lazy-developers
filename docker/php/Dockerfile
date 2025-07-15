FROM php:8.3-fpm

# Sistem paketlerini kur
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    zip \
    unzip \
    libzip-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensionları kur
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

# Çalışma dizini
WORKDIR /var/www/html

# www-data kullanıcısını user ID 1000 yap
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

# İzinleri ayarla
RUN chown -R www-data:www-data /var/www/html

USER www-data

EXPOSE 9000

CMD ["php-fpm"]
