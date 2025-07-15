FROM alpine:latest

# Gerekli paketleri yükle
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    inotify-tools \
    openssl 
 
# Çalışma dizini
WORKDIR /app

# Watcher script'ini kopyala
COPY watcher.sh /app/watcher.sh
RUN chmod +x /app/watcher.sh

# Projects dizini oluştur
RUN mkdir -p /app/projects

# Environment variables (will be overridden by docker-compose.yml from .env)
ENV PROJECTS_PATH=/var/www/html
ENV DOMAIN_SUFFIX=.test
ENV SITES_DIR=/var/www/html
ENV WWW_DIR=/var/www/html
 
CMD ["/app/watcher.sh"]
