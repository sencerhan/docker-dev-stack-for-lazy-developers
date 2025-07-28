#!/bin/bash

# Renkli çıktı
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log fonksiyonları önce tanımlanmalı
log_info() {
    echo -e "${BLUE}[WATCHER]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# .env dosyasından ortam değişkenlerini yükle
ENV_FILE="$SCRIPT_DIR/../../.env"
if [ -f "$ENV_FILE" ]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        # Yorumları ve boş satırları atla
        [[ $key == \#* ]] && continue
        [[ -z "$key" ]] && continue
        
        # Değerin başındaki/sonundaki boşlukları ve tırnak işaretlerini kaldır
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
        
        # Değer boş değilse değişkeni ayarla
        if [ -n "$key" ] && [ -n "$value" ]; then
            export "$key=$value"
        fi
    done < "$ENV_FILE"
    
    # Log mesajını environment variable'lar set edildikten sonra yap
    if command -v log_info >/dev/null 2>&1; then
        log_info "Loaded environment variables from $ENV_FILE"
    fi
fi

# .env dosyasından PROJECTS_PATH kullan veya varsayılana dön
PROJECTS_PATH=${PROJECTS_PATH:-/var/www/html}
SITES_DIR="$PROJECTS_PATH"
WWW_DIR="$PROJECTS_PATH"
DOMAIN_SUFFIX=${DOMAIN_SUFFIX:-.localhost}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}

# Watcher kayıt dosyası
WATCHER_REGISTRY="/var/www/html/.watcher_registry.json"

# Debug
echo "PROJECTS_PATH: $PROJECTS_PATH"
echo "SITES_DIR: $SITES_DIR"
echo "WWW_DIR: $WWW_DIR"
echo "DOMAIN_SUFFIX: $DOMAIN_SUFFIX"
echo "MYSQL_ROOT_PASSWORD: [GİZLENDİ]"

# Projects dizini yoksa oluştur
mkdir -p "$SITES_DIR"

# Periyodik çalıştırma süresi (saniye)
AUTO_SCAN_INTERVAL=10

# Proje kopyalama işleminin tamamlanmasını bekle
wait_for_project_complete() {
    local project_name="$1"
    local project_path=$(get_project_path "$project_name")
    local max_wait=60
    local wait_count=0
    local last_size=0
    local stable_count=0
    
    if [ -z "$project_path" ]; then
        log_warning "Proje dizini bulunamadı, iptal ediliyor"
        return 1
    fi
    
    log_info "Proje dosyalarının hazır olması bekleniyor: $project_name"
    
    while [ $wait_count -lt $max_wait ]; do
        if [ ! -d "$project_path" ]; then
            log_warning "Proje dizini bulunamadı, iptal ediliyor"
            return 1
        fi
        
        # Dizin boyutunu kontrol et
        local current_size=$(du -s "$project_path" 2>/dev/null | cut -f1)
        
        if [ "$current_size" = "$last_size" ]; then
            ((stable_count++))
            if [ $stable_count -ge 5 ]; then  # More stable cycles required
                log_success "Proje dosyaları hazır: $project_name"
                return 0
            fi
        else
            stable_count=0
            last_size=$current_size
            log_info "Dosya aktarımı devam ediyor... (boyut: ${current_size}KB)"
        fi
        
        sleep 2
        ((wait_count++))
    done
    
    log_warning "Dosya aktarım kontrolü zaman aşımına uğradı, devam ediliyor"
    return 0
}

# Proje tipini algıla
detect_project_type() {
    local project_name="$1"
    local project_path=$(get_project_path "$project_name")
    
    if [ -z "$project_path" ]; then
        return 1
    fi
    
    # Önemli dosyaları kontrol et
    local has_composer=false
    local has_package_json=false
    local has_public=false
    local has_laravel=false
    local has_wordpress=false
    
    [ -f "$project_path/composer.json" ] && has_composer=true
    [ -f "$project_path/package.json" ] && has_package_json=true
    [ -d "$project_path/public" ] && has_public=true
    [ -f "$project_path/artisan" ] && has_laravel=true
    [ -f "$project_path/wp-config.php" ] && has_wordpress=true
    
    # Proje tipini belirle
    if [ "$has_laravel" = true ]; then
        echo "Laravel"
    elif [ "$has_wordpress" = true ]; then
        echo "WordPress"
    elif [ "$has_composer" = true ] && [ "$has_public" = true ]; then
        echo "PHP Framework (Symfony/CodeIgniter)"
    elif [ "$has_composer" = true ]; then
        echo "PHP Project"
    elif [ "$has_package_json" = true ]; then
        echo "Node.js Project"
    else
        echo "Standard PHP"
    fi
} 

# Watcher kayıt dosyası yönetimi
init_watcher_registry() {
    if [ ! -f "$WATCHER_REGISTRY" ]; then
        log_info "Watcher kayıt dosyası oluşturuluyor: $WATCHER_REGISTRY"
        cat > "$WATCHER_REGISTRY" << 'EOF'
{
  "_info": "Bu dosya watcher tarafından otomatik olarak yönetilir",
  "_version": "1.0",
  "_created": "",
  "processed_projects": {}
}
EOF
        # Oluşturma tarihini ekle
        local created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        sed -i "s/\"_created\": \"\"/\"_created\": \"$created_date\"/" "$WATCHER_REGISTRY"
        log_success "Watcher kayıt dosyası oluşturuldu"
    fi
}

# Proje kayıtlı mı kontrol et
is_project_processed() {
    local project_name="$1"
    
    if [ ! -f "$WATCHER_REGISTRY" ]; then
        return 1  # Kayıt dosyası yok, işlenmemiş
    fi
    
    # JSON'dan proje kaydını kontrol et (basit grep ile)
    if grep -q "\"$project_name\":" "$WATCHER_REGISTRY"; then
        return 0  # Kayıtlı
    else
        return 1  # Kayıtlı değil
    fi
}

# Projeyi kayıt dosyasına ekle
add_project_to_registry() {
    local project_name="$1"
    local project_type="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if [ ! -f "$WATCHER_REGISTRY" ]; then
        init_watcher_registry
    fi
    
    # Proje zaten kayıtlıysa güncelle, değilse ekle
    if is_project_processed "$project_name"; then
        log_info "Proje kaydı güncelleniyor: $project_name"
        # Mevcut kaydı güncelle (timestamp'i güncelle)
        sed -i "s/\"$project_name\": {[^}]*}/\"$project_name\": {\"type\": \"$project_type\", \"first_processed\": \"$(grep -o "\"$project_name\": {[^}]*}" "$WATCHER_REGISTRY" | grep -o '"first_processed": "[^"]*"' | cut -d'"' -f4)\", \"last_updated\": \"$timestamp\", \"database_created\": true, \"nginx_created\": true}/" "$WATCHER_REGISTRY"
    else
        log_info "Yeni proje kayıt dosyasına ekleniyor: $project_name"
        # Yeni kayıt ekle
        # processed_projects objesinin son satırından önce ekle
        sed -i "/\"processed_projects\": {/a\\    \"$project_name\": {\"type\": \"$project_type\", \"first_processed\": \"$timestamp\", \"last_updated\": \"$timestamp\", \"database_created\": true, \"nginx_created\": true}," "$WATCHER_REGISTRY"
    fi
}

# Projeyi kayıt dosyasından kaldır
remove_project_from_registry() {
    local project_name="$1"
    
    if [ ! -f "$WATCHER_REGISTRY" ]; then
        return
    fi
    
    log_info "Proje kayıt dosyasından kaldırılıyor: $project_name"
    # Proje satırını sil
    sed -i "/\"$project_name\": {[^}]*},*/d" "$WATCHER_REGISTRY"
}

# Kayıt dosyasını görüntüle
show_registry() {
    if [ -f "$WATCHER_REGISTRY" ]; then
        log_info "Watcher kayıt dosyası:"
        cat "$WATCHER_REGISTRY" | python3 -m json.tool 2>/dev/null || cat "$WATCHER_REGISTRY"
    else
        log_warning "Kayıt dosyası bulunamadı: $WATCHER_REGISTRY"
    fi
} 

# Nginx konfigürasyonu oluştur
create_nginx_config() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    local config_file="$sites_available/$domain"
    
    mkdir -p "$sites_available" "$sites_enabled"
    
    # Zaten varsa atla
    if [ -f "$config_file" ]; then
        log_info "Konfigürasyon zaten mevcut: $domain"
        return
    fi
    
    # Root path belirle
    local container_path=$(get_project_container_path "$project_name")
    if [ -z "$container_path" ]; then
        log_warning "Proje container path bulunamadı: $project_name"
        return 1
    fi
    
    local project_path=$(get_project_path "$project_name")
    local root_path="$container_path"
    
    # Laravel projesi mi kontrol et (public klasörü var mı?)
    if [ -d "$project_path/public" ]; then
        root_path="$container_path/public"
        log_info "Laravel projesi algılandı: $project_name (public klasörü kullanılacak)"
    else
        log_info "Standart proje algılandı: $project_name (kök dizin kullanılacak)"
    fi
     
    # Nginx konfigürasyonu oluştur
    cat > "$config_file" << EOF
server {
    listen 80;
    server_name $domain;
    
    root $root_path;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    client_max_body_size 1G;
}
EOF
    
    # Site'ı etkinleştir - relative path kullan
    ln -sf "../sites-available/$domain" "$sites_enabled/$domain"
    
    # Nginx reload
    docker exec nginx_proxy nginx -s reload 2>/dev/null || true
    log_success "Nginx konfigürasyonu oluşturuldu: $domain"
}

# Konfigürasyonu kaldır
remove_nginx_config() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    
    # Konfigürasyon dosyalarını sil
    rm -f "$sites_available/$domain" "$sites_enabled/$domain"
    
    # Nginx reload
    docker exec nginx_proxy nginx -s reload 2>/dev/null || true
    log_success "Nginx konfigürasyonu kaldırıldı: $domain"
}
# Otomatik subdomains.json oluştur
create_default_subdomains_json() {
    local project_name="$1"
    local project_path="$2"
    local json_file="$project_path/subdomains.json"
    
    # Zaten varsa oluşturma
    if [ -f "$json_file" ]; then
        return 0
    fi
    
    log_info "Örnek subdomains.json oluşturuluyor: $project_name"
    
    # Boş template ile açıklama
    cat > "$json_file" << 'EOF'
{
  "_info": "Bu dosyayı düzenleyerek subdomain'ler ekleyebilirsiniz",
  "_examples": {
    "api_folder": "{ \"subdomain\": \"api\", \"folder\": \"api\" }",
    "main_project": "{ \"subdomain\": \"www\", \"folder\": null }",
    "admin_panel": "{ \"subdomain\": \"admin\", \"folder\": \"admin-panel\" }"
  },
  "_usage": [
    "1. Aşağıdaki _templates'i silin ve subdomains'e taşıyın",
    "2. 'folder': null ise ana proje dizini kullanılır", 
    "3. 'folder': 'klasor-adi' ise o klasör kullanılır",
    "4. Dosyayı kaydettiğinizde otomatik oluşur"
  ],
  "_templates": [
    {
      "subdomain": "api",
      "folder": "api"
    },
    {
      "subdomain": "admin",
      "folder": "admin"
    },
    {
      "subdomain": "www",
      "folder": null
    }
  ],
  "subdomains": [
    
  ]
}
EOF
    
    log_success "subdomains.json template oluşturuldu"
    log_info "Subdomain eklemek için: nano $json_file"
    log_info "Örnek kullanım dosyada mevcuttur"
}

# Proje ekle (JSON subdomain destekli)
add_project_auto() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    
    log_info "Proje kontrol ediliyor: $project_name"
    
    # Proje zaten işlenmiş mi kontrol et
    if is_project_processed "$project_name"; then
        log_info "Proje zaten işlenmiş, atlanıyor: $project_name"
        return 0
    fi
    
    log_info "Yeni proje algılandı: $project_name"
    
    # Kopyalama işleminin tamamlanmasını bekle
    if ! wait_for_project_complete "$project_name"; then
        return 1
    fi
    
    # Proje tipini algıla
    local project_type=$(detect_project_type "$project_name")
    log_info "Proje tipi: $project_type"
    
    # Ana domain için Nginx konfigürasyonu oluştur
    create_nginx_config "$project_name"
    
    # MySQL veritabanı oluştur
    create_mysql_database "$project_name"
    
    # Projeyi kayıt dosyasına ekle
    add_project_to_registry "$project_name" "$project_type"
    
    # Otomatik subdomains.json oluştur
    local project_path=$(get_project_path "$project_name")
    create_default_subdomains_json "$project_name" "$project_path"
    
    # Subdomains.json dosyasını kontrol et ve işle
    if [ -f "$project_path/subdomains.json" ]; then
        log_info "subdomains.json dosyası işleniyor..."
        parse_subdomains_json "$project_name"
    fi
    
    log_success "Proje hazır: http://$domain ($project_type)"
}

# Proje kaldır (subdomain'lerle birlikte)
remove_project_auto() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    
    log_info "Proje kaldırıldı: $project_name"
    
    # Ana domain konfigürasyonunu kaldır
    remove_nginx_config "$project_name"
    
    # Tüm subdomain'leri kaldır
    remove_project_subdomains "$project_name"
    
    # MySQL veritabanını kaldır
    remove_mysql_database "$project_name"
    
    # Projeyi kayıt dosyasından kaldır
    remove_project_from_registry "$project_name"
    
    log_success "Konfigürasyon temizlendi: $domain ve tüm subdomain'ler"
}

# JSON dosyasını okuma fonksiyonu
parse_subdomains_json() {
    local project_name="$1"
    local project_path=$(get_project_path "$project_name")
    local json_file="$project_path/subdomains.json"
    
    if [ ! -f "$json_file" ]; then
        return 1
    fi
    
    # JSON'ı satır satır işle (basit parser)
    local in_array=false
    local subdomain=""
    local folder=""
    
    while IFS= read -r line; do
        # Boş satırları ve yorumları atla
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [[ -z "$line" || "$line" == \#* ]] && continue
        
        # Array başlangıcı
        if [[ "$line" == *"\"subdomains\""* && "$line" == *"["* ]]; then
            in_array=true
            continue
        fi
        
        # Array bitişi
        if [[ "$line" == *"]"* ]]; then
            in_array=false
            continue
        fi
        
        # Array içindeyken objeleri işle
        if [ "$in_array" = true ]; then
            # Subdomain field
            if [[ "$line" == *"\"subdomain\":"* ]]; then
                subdomain=$(echo "$line" | sed 's/.*"subdomain":[[:space:]]*"//' | sed 's/".*//')
            fi
            
            # Folder field (null değeri de destekle)
            if [[ "$line" == *"\"folder\":"* ]]; then
                if [[ "$line" == *"null"* ]]; then
                    folder="null"
                else
                    folder=$(echo "$line" | sed 's/.*"folder":[[:space:]]*"//' | sed 's/".*//')
                fi
            fi
            
            # Obje bittiğinde subdomain oluştur
            if [[ "$line" == *"}"* ]] && [ -n "$subdomain" ]; then
                create_subdomain "$project_name" "$subdomain" "$folder"
                subdomain=""
                folder=""
            fi
        fi
    done < "$json_file"
}

# Subdomain oluşturma fonksiyonu
create_subdomain() {
    local project_name="$1"
    local subdomain="$2"
    local folder="$3"
    local domain="${subdomain}.${project_name}${DOMAIN_SUFFIX}"
    
    # Klasör kontrolü (null ise ana dizin kullan)
    local project_path=$(get_project_path "$project_name")
    if [ -n "$folder" ] && [ "$folder" != "null" ]; then
        if [ ! -d "$project_path/$folder" ]; then
            log_warning "Subdomain klasörü bulunamadı: $folder (proje: $project_name)"
            return 1
        fi
        log_info "Subdomain oluşturuluyor: $domain → $folder klasörü"
    else
        log_info "Subdomain oluşturuluyor: $domain → ana proje dizini"
    fi
    
    # Nginx konfigürasyonu oluştur
    create_subdomain_config "$project_name" "$subdomain" "$folder"
}

# Subdomain için Nginx konfigürasyonu
create_subdomain_config() {
    local project_name="$1"
    local subdomain="$2"
    local folder="$3"
    local domain="${subdomain}.${project_name}${DOMAIN_SUFFIX}"
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    local config_file="$sites_available/$domain"
    
    mkdir -p "$sites_available" "$sites_enabled"
    
    # Zaten varsa atla
    if [ -f "$config_file" ]; then
        log_info "Subdomain konfigürasyonu zaten mevcut: $domain"
        return
    fi
    
    # Root path belirle
    local container_path=$(get_project_container_path "$project_name")
    local project_path=$(get_project_path "$project_name")
    local root_path
    
    if [ -n "$folder" ] && [ "$folder" != "null" ]; then
        # Belirli klasör kullan
        root_path="$container_path/$folder"
        if [ -d "$project_path/$folder/public" ]; then
            root_path="$container_path/$folder/public"
            log_info "Subdomain public klasörü bulundu: $domain ($folder/public)"
        else
            log_info "Subdomain klasör path: $domain ($folder)"
        fi
    else
        # Ana proje dizini kullan
        root_path="$container_path"
        if [ -d "$project_path/public" ]; then
            root_path="$container_path/public"
            log_info "Subdomain ana proje public klasörü: $domain (public)"
        else
            log_info "Subdomain ana proje dizini: $domain (root)"
        fi
    fi 
    
    # Nginx konfigürasyonu oluştur
    cat > "$config_file" << EOF
server {
    listen 80;
    server_name $domain;
    
    root $root_path;
    index index.php index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_read_timeout 300;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    client_max_body_size 1G;
}
EOF
    
    # Site'ı etkinleştir - relative path kullan
    ln -sf "../sites-available/$domain" "$sites_enabled/$domain"
    
    # Nginx reload
    docker exec nginx_proxy nginx -s reload 2>/dev/null || true
    log_success "Subdomain hazır: http://$domain"
}

# Proje subdomain'lerini temizle
remove_project_subdomains() {
    local project_name="$1"
    
    # Tüm subdomain konfigürasyonlarını bul ve sil
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    
    for config in "$sites_available"/*."$project_name"*; do
        if [ -f "$config" ]; then
            local domain=$(basename "$config")
            log_info "Subdomain kaldırılıyor: $domain"
            
            # Konfigürasyonları sil
            rm -f "$sites_available/$domain" "$sites_enabled/$domain"
        fi
    done
    
    # Nginx reload
    docker exec nginx_proxy nginx -s reload 2>/dev/null || true
    log_success "Tüm subdomain'ler kaldırıldı"
}

# MySQL veritabanı oluştur
create_mysql_database() {
    local project_name="$1"
    local db_name="${project_name}"
    local db_user="root"
    local db_pass="${MYSQL_ROOT_PASSWORD:-root}"
    
    log_info "MySQL veritabanı oluşturuluyor: $db_name"
    
    # MySQL veritabanını oluştur
    if docker exec mysql_db mysql -u"$db_user" -p"$db_pass" -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
        log_success "MySQL veritabanı oluşturuldu: $db_name"
        
        # Veritabanı bilgilerini .env dosyasına yazma (Laravel projesi ise)
        local project_path=$(get_project_path "$project_name")
        if [ -f "$project_path/.env.example" ] && [ ! -f "$project_path/.env" ]; then
            log_info "Laravel .env dosyası oluşturuluyor..."
            cp "$project_path/.env.example" "$project_path/.env"
            
            # .env dosyasındaki veritabanı bilgilerini güncelle
            sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" "$project_path/.env"
            sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" "$project_path/.env"
            sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_pass/" "$project_path/.env"
            
            log_success "Laravel .env dosyası güncellendi"
        fi
    else
        log_warning "MySQL veritabanı oluşturulamadı: $db_name"
    fi
}

# MySQL veritabanını kaldır
remove_mysql_database() {
    local project_name="$1"
    local db_name="${project_name}"
    local db_user="root"
    local db_pass="${MYSQL_ROOT_PASSWORD:-root}"
    
    log_info "MySQL veritabanı kaldırılıyor: $db_name"
    
    # MySQL veritabanını kaldır
    if docker exec mysql_db mysql -u"$db_user" -p"$db_pass" -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
        log_success "MySQL veritabanı kaldırıldı: $db_name"
    else
        log_warning "MySQL veritabanı kaldırılamadı: $db_name"
    fi
}

# Ana watcher
start_watcher() {
    log_info "🔍 Otomatik klasör izleyici başlatılıyor..."
    log_info "İzlenen dizin: $SITES_DIR"
    log_info "PROJECTS_PATH: $PROJECTS_PATH"
    log_info "DOMAIN_SUFFIX: $DOMAIN_SUFFIX"
    log_info "Otomatik tarama süresi: $AUTO_SCAN_INTERVAL saniye"
    log_info "Kayıt dosyası: $WATCHER_REGISTRY"
    log_info "Çıkmak için Ctrl+C"
    
    # Dizinleri oluştur
    mkdir -p "$SITES_DIR"
    
    # Watcher kayıt dosyasını başlat
    init_watcher_registry
    
    # İlk başlangıçta temizlik yap
    cleanup_orphaned_configs
    
    # İlk başlangıçta mevcut projeleri tara
    log_info "Mevcut projeler taranıyor..."
    for project_dir in "$SITES_DIR"/*; do
        if [ -d "$project_dir" ]; then
            project_name=$(basename "$project_dir")
            if [[ ! "$project_name" =~ ^\..*$ ]]; then
                log_info "Mevcut proje bulundu: $project_name"
                add_project_auto "$project_name"
            fi
        fi
    done
    
    # Periyodik tarama işlemini başlat (arka planda)
    auto_scan_function &
    AUTO_SCAN_PID=$!
    
    # Düzgün kapanma için temizlik fonksiyonu
    cleanup() {
        log_info "Watcher durduruluyor..."
        kill $AUTO_SCAN_PID 2>/dev/null
        pkill -P $$ inotifywait 2>/dev/null
        exit 0
    }
    
    # Sinyalleri yakala
    trap cleanup SIGTERM SIGINT
    
    # Projects dizinini izle
    (
        # -m: sürekli izleme modu
        # -r: alt klasörleri de izle
        # -e: izlenecek olaylar
        log_info "inotifywait başlatılıyor: $SITES_DIR"
        inotifywait -m -r -e create,delete,moved_to,moved_from,modify --format '%w%f %e' "$SITES_DIR" &
        SITES_PID=$!
        
        # Store PID for cleanup
        echo $SITES_PID > /tmp/watcher_sites.pid
        
        wait
    ) | \
    while read line; do
        # Debug çıktısı
        log_info "DEBUG: Olay algılandı: $line"
        
        file=$(echo "$line" | cut -d' ' -f1)
        event=$(echo "$line" | cut -d' ' -f2-)
        
        # Proje adını çıkar
        relative_path="${file#$SITES_DIR/}"
        project_name=$(echo "$relative_path" | cut -d'/' -f1)
        
        # Geçersiz proje isimlerini filtrele
        if [[ -z "$project_name" || "$project_name" =~ ^\..*$ ]]; then
            continue
        fi
        
        log_info "Olay: $event, Proje: $project_name (Yol: $relative_path)"
        
        # Ana proje dizinindeki değişiklikleri kontrol et
        if [[ "$relative_path" == "$project_name" || "$relative_path" == "$project_name/" ]]; then
            case "$event" in
                *CREATE*|*MOVED_TO*)
                    if [[ -d "$file" ]]; then
                        log_info "Yeni proje klasörü oluşturuldu: $project_name"
                        # Daha uzun bekleme süresi
                        sleep 3
                        add_project_auto "$project_name"
                    fi
                    ;;
                *DELETE*|*MOVED_FROM*)
                    log_info "Proje klasörü silindi: $project_name"
                    remove_project_auto "$project_name"
                    ;;
            esac
        elif [[ "$file" == *"subdomains.json" ]]; then
            # subdomains.json değişikliği
            case "$event" in
                *MODIFY*|*CREATE*|*MOVED_TO*)
                    log_info "subdomains.json güncellendi: $project_name"
                    sleep 1  # Dosya yazma işleminin bitmesini bekle
                    
                    # Mevcut subdomain'leri temizle
                    remove_project_subdomains "$project_name"
                    
                    # Yeni subdomain'leri oluştur
                    if [ -f "$file" ]; then
                        parse_subdomains_json "$project_name"
                        log_success "Subdomain'ler güncellendi: $project_name"
                    fi
                    ;;
            esac
        fi
    done
}

# Proje dizinini belirle
get_project_path() {
    local project_name="$1"
    
    # PROJECTS_PATH altında proje dizinini kontrol et
    local project_path="$PROJECTS_PATH/$project_name"
    
    if [ -d "$project_path" ]; then
        echo "$project_path"
        return 0
    else
        return 1
    fi
}

# Proje container path'ini belirle
get_project_container_path() {
    local project_name="$1"
    
    # Container içinde projects dizini /var/www/html olarak mount ediliyor
    echo "/var/www/html/$project_name"
    return 0
}

# Otomatik temizlik fonksiyonu - mevcut olmayan projeler için konfigürasyonları temizle
cleanup_orphaned_configs() {
    log_info "🧹 Yetim kalan konfigürasyonlar temizleniyor..."
    
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    local cleanup_count=0
    
    # sites-available'daki tüm dosyaları kontrol et
    for config_file in "$sites_available"/*; do
        if [ -f "$config_file" ]; then
            local domain=$(basename "$config_file")
            local project_name=""
            
            # Domain'den proje adını çıkar
            if [[ "$domain" == *.*.* ]]; then
                # Subdomain durumu: api.myproject.localhost -> myproject
                project_name=$(echo "$domain" | sed -E 's/^[^.]*\.([^.]+)\..*$/\1/')
            else
                # Ana domain durumu: myproject.localhost -> myproject
                project_name=$(echo "$domain" | sed -E 's/^([^.]+)\..*$/\1/')
            fi
            
            # Proje dizininin var olup olmadığını kontrol et
            if [ -n "$project_name" ]; then
                if [ ! -d "$PROJECTS_PATH/$project_name" ]; then
                    log_info "Yetim konfigürasyon bulundu: $domain (proje: $project_name)"
                    
                    # Konfigürasyon dosyalarını sil
                    rm -f "$sites_available/$domain" "$sites_enabled/$domain"
                    
                    ((cleanup_count++))
                    log_success "Temizlendi: $domain"
                fi
            fi
        fi
    done
    
    # Nginx reload
    if [ $cleanup_count -gt 0 ]; then
        docker exec nginx_proxy nginx -s reload 2>/dev/null || true
        log_success "$cleanup_count yetim konfigürasyon temizlendi"
    else
        log_info "Temizlenecek yetim konfigürasyon bulunamadı"
    fi
}

# Gerekli paketleri kontrol et
check_dependencies() {
    if ! command -v inotifywait &> /dev/null; then
        echo "inotify-tools yüklenmemiş. Yükleniyor..."
        apt-get update && apt-get install -y inotify-tools
    fi
}

# Ana fonksiyon
main() {
    cd "$SCRIPT_DIR"
    
    case "${1:-start}" in
        "start")
            check_dependencies
            start_watcher
            ;;
        "stop")
            # Kill using PID files if they exist
            if [ -f /tmp/watcher_sites.pid ]; then
                kill $(cat /tmp/watcher_sites.pid) 2>/dev/null
                rm -f /tmp/watcher_sites.pid
            fi
            
            # Fallback: kill by pattern
            pkill -f "inotifywait.*$SITES_DIR" 2>/dev/null
            pkill -f "auto_scan_function" 2>/dev/null
            pkill -f "watcher.sh" 2>/dev/null
            
            log_success "Watcher durduruldu"
            ;;
        "status")
            if pgrep -f "inotifywait.*$SITES_DIR" > /dev/null || pgrep -f "auto_scan_function" > /dev/null; then
                log_success "Watcher çalışıyor ✓"
            else
                log_warning "Watcher çalışmıyor ✗"
            fi
            ;;
        "cleanup")
            cleanup_orphaned_configs
            ;;
        "scan")
            # Tüm projeleri tara ve yeniden yapılandır
            log_info "Tüm projeler taranıyor..."
            for project_dir in "$SITES_DIR"/*; do
                if [ -d "$project_dir" ]; then
                    project_name=$(basename "$project_dir")
                    if [[ ! "$project_name" =~ ^\..*$ ]]; then
                        log_info "Proje taranıyor: $project_name"
                        add_project_auto "$project_name"
                    fi
                fi
            done
            log_success "Tüm projeler tarandı ve yapılandırıldı"
            ;;
        "registry")
            show_registry
            ;;
        "reset")
            log_warning "Watcher kayıt dosyası sıfırlanıyor..."
            rm -f "$WATCHER_REGISTRY"
            init_watcher_registry
            log_success "Kayıt dosyası sıfırlandı"
            ;;
        *)
            echo "Kullanım: $0 {start|stop|status|cleanup|scan|registry|reset}"
            echo "  start    - Watcher'ı başlat"
            echo "  stop     - Watcher'ı durdur"
            echo "  status   - Watcher durumunu kontrol et"
            echo "  cleanup  - Yetim konfigürasyonları temizle"
            echo "  scan     - Tüm projeleri yeniden tara"
            echo "  registry - Kayıt dosyasını görüntüle"
            echo "  reset    - Kayıt dosyasını sıfırla"
            exit 1
            ;;
    esac
}

# Periyodik tarama fonksiyonu
auto_scan_function() {
    log_info "🔄 Otomatik tarama başlatılıyor (her $AUTO_SCAN_INTERVAL saniyede bir)"
    
    while true; do
        # Yetim konfigürasyonları temizle
        cleanup_orphaned_configs > /dev/null 2>&1
        
        # Mevcut projeleri tara
        log_info "📂 Periyodik tarama yapılıyor..."
        
        # Tüm proje klasörlerini listele
        all_project_dirs=$(find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
        
        # Her bir proje klasörü için işlem yap
        for project_dir in $all_project_dirs; do
            project_name=$(basename "$project_dir")
            
            # Gizli klasörleri atla
            if [[ "$project_name" =~ ^\..*$ ]]; then
                continue
            fi
            
            # Nginx konfigürasyonunu kontrol et
            domain="${project_name}${DOMAIN_SUFFIX}"
            config_file="$SCRIPT_DIR/../../docker/nginx/sites-available/$domain"
            
            if [ ! -f "$config_file" ]; then
                log_info "🆕 Eksik konfigürasyon bulundu: $project_name"
                add_project_auto "$project_name"
            fi
        done
        
        # Belirtilen süre kadar bekle
        sleep $AUTO_SCAN_INTERVAL
    done
}

main "$@"
