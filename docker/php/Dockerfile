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
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    && rm -rf /var/lib/apt/lists/*

# GD extensionunu FreeType ve JPEG desteği ile kur
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

# Composer kur
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# PHP konfigürasyonunu kopyala
COPY php.ini /usr/local/etc/php/conf.d/99-custom.ini

# Çalışma dizini
WORKDIR /var/www/html

# www-data kullanıcısını user ID 1000 yap
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

# İzinleri ayarla
RUN chown -R www-data:www-data /var/www/html

USER www-data

EXPOSE 9000

CMD ["php-fpm"]
