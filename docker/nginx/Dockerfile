FROM nginx:alpine

# Gerekli paketleri yükle
RUN apk add --no-cache curl

# Nginx konfigürasyon dosyalarını kopyala
COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf

# SSL dizinini oluştur

# Sites dizinlerini oluştur
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Başlangıç scripti
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
