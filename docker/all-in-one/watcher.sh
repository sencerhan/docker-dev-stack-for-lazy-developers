#!/bin/bash

# Renkli çıktı
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log fonksiyonları
log_info() {
    echo -e "${BLUE}[WATCHER]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Tek container için ayarlar
PROJECTS_PATH=${PROJECTS_PATH:-/var/www/html}
SITES_DIR="$PROJECTS_PATH"
DOMAIN_SUFFIX=${DOMAIN_SUFFIX:-.localhost}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}

# Watcher kayıt dosyası
WATCHER_REGISTRY="/var/www/html/.watcher_registry.json"

# Process lock dosyası (race condition önleme)
LOCK_DIR="/tmp/watcher_locks"
mkdir -p "$LOCK_DIR"

# Bellek ve işlem limitleri
MAX_FIND_DEPTH=3
MAX_FILE_COUNT=10000

# Debug
log_info "PROJECTS_PATH: $PROJECTS_PATH"
log_info "DOMAIN_SUFFIX: $DOMAIN_SUFFIX"

# Lock fonksiyonları
acquire_lock() {
    local project_name="$1"
    local lock_file="$LOCK_DIR/${project_name}.lock"
    
    if [ -f "$lock_file" ]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_warning "Proje zaten işleniyor: $project_name (PID: $lock_pid)"
            return 1
        else
            # Eski lock dosyasını temizle
            rm -f "$lock_file"
        fi
    fi
    
    echo $ > "$lock_file"
    return 0
}

release_lock() {
    local project_name="$1"
    local lock_file="$LOCK_DIR/${project_name}.lock"
    rm -f "$lock_file"
}

# Proje kaldır
remove_project_auto() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    
    log_info "Proje kaldırılıyor: $project_name"
    
    # Subdomain'leri temizle
    remove_project_subdomains "$project_name"
    
    # Nginx konfigürasyonunu kaldır
    remove_nginx_config "$project_name"
    
    # MySQL veritabanını kaldır
    remove_mysql_database "$project_name"
    
    log_success "Proje kaldırıldı: $project_name"
}

# Projects dizini yoksa oluştur
mkdir -p "$SITES_DIR"

# Periyodik çalıştırma süresi (saniye)
AUTO_SCAN_INTERVAL=10

# Proje kopyalama işleminin tamamlanmasını bekle
wait_for_project_complete() {
    local project_name="$1"
    local project_path="$SITES_DIR/$project_name"
    local max_wait=120  # 2 dakika bekle
    local wait_count=0
    local last_size=0
    local stable_count=0
    
    if [ ! -d "$project_path" ]; then
        log_warning "Proje dizini bulunamadı: $project_path"
        return 1
    fi
    
    log_info "Proje dosyalarının hazır olması bekleniyor: $project_name"
    
    while [ $wait_count -lt $max_wait ]; do
        if [ ! -d "$project_path" ]; then
            log_warning "Proje dizini bulunamadı, iptal ediliyor"
            return 1
        fi
        
        # Dizin boyutunu ve dosya sayısını kontrol et (bellek optimizasyonu)
        local current_size=$(du -s "$project_path" 2>/dev/null | cut -f1)
        local file_count=$(find "$project_path" -maxdepth $MAX_FIND_DEPTH -type f 2>/dev/null | head -n $MAX_FILE_COUNT | wc -l)
        
        # Çok büyük projeler için uyarı
        if [ "$file_count" -ge "$MAX_FILE_COUNT" ]; then
            log_warning "Büyük proje algılandı ($file_count+ dosya), performans etkilenebilir"
        fi
        
        if [ "$current_size" = "$last_size" ]; then
            ((stable_count++))
            if [ $stable_count -ge 8 ]; then  # Daha fazla stable cycle bekle
                log_success "Proje dosyaları hazır: $project_name (${current_size}KB, ${file_count} dosya)"
                
                # Laravel projesi için özel kontrol
                if [ -f "$project_path/composer.json" ]; then
                    log_info "Laravel projesi algılandı, public klasörü kontrol ediliyor..."
                    local public_wait=0
                    while [ $public_wait -lt 30 ]; do
                        if [ -d "$project_path/public" ] && [ -f "$project_path/public/index.php" ]; then
                            log_success "Public klasörü hazır!"
                            break
                        fi
                        log_info "Public klasörü bekleniyor... ($public_wait/30)"
                        sleep 1
                        ((public_wait++))
                    done
                fi
                
                return 0
            fi
        else
            stable_count=0
            last_size=$current_size
            log_info "Dosya aktarımı devam ediyor... (boyut: ${current_size}KB, dosya: ${file_count})"
        fi
        
        sleep 3  # Daha uzun bekleme
        ((wait_count++))
    done
    
    log_warning "Dosya aktarım kontrolü zaman aşımına uğradı, devam ediliyor"
    return 0
}

# Proje tipini algıla
detect_project_type() {
    local project_name="$1"
    local project_path="$SITES_DIR/$project_name"
    
    if [ ! -d "$project_path" ]; then
        return 1
    fi
    
    # Önemli dosyaları kontrol et
    local has_composer=false
    local has_laravel=false
    local has_wordpress=false
    
    [ -f "$project_path/composer.json" ] && has_composer=true
    [ -f "$project_path/artisan" ] && has_laravel=true
    [ -f "$project_path/wp-config.php" ] && has_wordpress=true
    
    # Proje tipini belirle
    if [ "$has_laravel" = true ]; then
        echo "Laravel"
    elif [ "$has_wordpress" = true ]; then
        echo "WordPress"
    elif [ "$has_composer" = true ]; then
        echo "PHP Project"
    else
        echo "Standard PHP"
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
    local container_path="/var/www/html/$project_name"
    local project_path="$SITES_DIR/$project_name"
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
        fastcgi_pass localhost:9000;
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
    nginx -s reload 2>/dev/null || true
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
    nginx -s reload 2>/dev/null || true
    log_success "Nginx konfigürasyonu kaldırıldı: $domain"
}

# MySQL veritabanı oluştur
create_mysql_database() {
    local project_name="$1"
    local db_name="${project_name}"
    local db_user="root"
    local db_pass="${MYSQL_ROOT_PASSWORD:-root}"
    
    log_info "MySQL veritabanı oluşturuluyor: $db_name"
    
    # MySQL veritabanını oluştur
    if mysql -u"$db_user" -p"$db_pass" -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
        log_success "MySQL veritabanı oluşturuldu: $db_name"
        
        # Veritabanı bilgilerini .env dosyasına yazma (Laravel projesi ise)
        local project_path="$SITES_DIR/$project_name"
        if [ -f "$project_path/.env.example" ] && [ ! -f "$project_path/.env" ]; then
            log_info "Laravel .env dosyası oluşturuluyor..."
            cp "$project_path/.env.example" "$project_path/.env"
            
            # .env dosyasındaki veritabanı bilgilerini güncelle
            sed -i "s/DB_HOST=.*/DB_HOST=localhost/" "$project_path/.env"
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
    if mysql -u"$db_user" -p"$db_pass" -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null; then
        log_success "MySQL veritabanı kaldırıldı: $db_name"
    else
        log_warning "MySQL veritabanı kaldırılamadı: $db_name"
    fi
}

# Otomatik subdomains.json oluştur
create_default_subdomains_json() {
    local project_name="$1"
    local project_path="$SITES_DIR/$project_name"
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
}

# JSON dosyasını okuma fonksiyonu
parse_subdomains_json() {
    local project_name="$1"
    local project_path="$SITES_DIR/$project_name"
    local json_file="$project_path/subdomains.json"
    
    if [ ! -f "$json_file" ]; then
        log_warning "subdomains.json dosyası bulunamadı: $json_file"
        return 1
    fi
    
    log_info "subdomains.json işleniyor: $project_name"
    
    # JSON'ı satır satır işle (basit parser)
    local in_array=false
    local subdomain=""
    local folder=""
    
    while IFS= read -r line; do
        # Boş satırları ve yorumları atla
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [[ -z "$line" || "$line" == \#* ]] && continue
        
        # Debug: Satırı göster
        log_info "DEBUG: Satır işleniyor: '$line'"
        
        # Array başlangıcı
        if [[ "$line" == *"\"subdomains\""* && "$line" == *"["* ]]; then
            in_array=true
            log_info "DEBUG: subdomains array başladı"
            continue
        fi
        
        # Array bitişi
        if [[ "$line" == *"]"* ]]; then
            in_array=false
            log_info "DEBUG: subdomains array bitti"
            continue
        fi
        
        # Array içindeyken objeleri işle
        if [ "$in_array" = true ]; then
            # Subdomain field
            if [[ "$line" == *"\"subdomain\":"* ]]; then
                subdomain=$(echo "$line" | sed 's/.*"subdomain":[[:space:]]*"//' | sed 's/".*//')
                log_info "DEBUG: Subdomain bulundu: '$subdomain'"
            fi
            
            # Folder field (null değeri de destekle)
            if [[ "$line" == *"\"folder\":"* ]]; then
                if [[ "$line" == *"null"* ]]; then
                    folder="null"
                    log_info "DEBUG: Folder null olarak ayarlandı"
                else
                    folder=$(echo "$line" | sed 's/.*"folder":[[:space:]]*"//' | sed 's/".*//')
                    log_info "DEBUG: Folder bulundu: '$folder'"
                fi
            fi
            
            # Obje bittiğinde subdomain oluştur
            if [[ "$line" == *"}"* ]] && [ -n "$subdomain" ]; then
                log_info "DEBUG: Subdomain oluşturuluyor: '$subdomain' -> '$folder'"
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
    local project_path="$SITES_DIR/$project_name"
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
    local container_path="/var/www/html/$project_name"
    local project_path="$SITES_DIR/$project_name"
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
        fastcgi_pass localhost:9000;
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
    nginx -s reload 2>/dev/null || true
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
    nginx -s reload 2>/dev/null || true
    log_success "Tüm subdomain'ler kaldırıldı"
}

# Proje ekle
add_project_auto() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    local project_path="$SITES_DIR/$project_name"
    
    # Lock kontrolü (race condition önleme)
    if ! acquire_lock "$project_name"; then
        return 1
    fi
    
    # Trap ile lock temizleme garantisi
    trap "release_lock '$project_name'" EXIT
    
    log_info "Proje kontrol ediliyor: $project_name"
    
    log_info "Yeni proje algılandı: $project_name"
    
    # Kopyalama işleminin tamamlanmasını bekle
    if ! wait_for_project_complete "$project_name"; then
        release_lock "$project_name"
        return 1
    fi
    
    # Proje tipini algıla
    local project_type=$(detect_project_type "$project_name")
    log_info "Proje tipi: $project_type"
    
    # Nginx konfigürasyonu oluştur
    create_nginx_config "$project_name"
    
    # MySQL veritabanı oluştur
    create_mysql_database "$project_name"
    
    # Composer'ı kur (composer.json varsa)
    if [ -f "$project_path/composer.json" ]; then
        log_info "Composer bağımlılıkları kuruluyor..."
        cd "$project_path"
        composer install --no-interaction 2>/dev/null || {
            log_warning "Composer install başarısız oldu"
        }
        cd /
    fi
    
    # npm dependencies (package.json varsa)
    if [ -f "$project_path/package.json" ]; then
        log_info "npm bağımlılıkları kuruluyor..."
        cd "$project_path"
        npm install 2>/dev/null || {
            log_warning "npm install başarısız oldu"
        }
        cd /
    fi
    
    # Laravel .env kur (.env.example varsa)
    if [ -f "$project_path/.env.example" ] && [ ! -f "$project_path/.env" ]; then
        log_info "Laravel .env dosyası oluşturuluyor..."
        cp "$project_path/.env.example" "$project_path/.env"
        
        # Database ayarlarını güncelle
        sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" "$project_path/.env"
        sed -i "s/^DB_HOST=.*/DB_HOST=localhost/" "$project_path/.env"
        sed -i "s/^DB_PORT=.*/DB_PORT=3306/" "$project_path/.env"
        sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$project_name/" "$project_path/.env"
        sed -i "s/^DB_USERNAME=.*/DB_USERNAME=root/" "$project_path/.env"
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}/" "$project_path/.env"
        
        # Laravel key generate
        cd "$project_path"
        php artisan key:generate 2>/dev/null || true
        cd /
    fi
    
    # İzinleri düzelt
    chown -R www-data:www-data "$project_path" 2>/dev/null || true
    chmod -R 755 "$project_path" 2>/dev/null || true
    
    # Laravel storage ve bootstrap/cache izinleri
    if [ -d "$project_path/storage" ]; then
        chmod -R 775 "$project_path/storage" 2>/dev/null || true
    fi
    if [ -d "$project_path/bootstrap/cache" ]; then
        chmod -R 775 "$project_path/bootstrap/cache" 2>/dev/null || true
    fi
    
    # subdomains.json varsa işle, yoksa template oluştur
    if [ -f "$project_path/subdomains.json" ]; then
        log_info "Mevcut subdomains.json işleniyor..."
        parse_subdomains_json "$project_name"
    else
        log_info "subdomains.json template oluşturuluyor..."
        create_default_subdomains_json "$project_name"
    fi
    
    log_success "Proje hazır: http://$domain ($project_type)"
    
    if [ -f "$project_path/subdomains.json" ]; then
        log_info "subdomains.json düzenlemek için: nano $project_path/subdomains.json"
        log_info "Düzenleme sonrası dosyayı kaydedin, otomatik oluşacak"
    fi
}

# Proje kaldır
remove_project_auto() {
    local project_name="$1"
    local domain="${project_name}${DOMAIN_SUFFIX}"
    
    log_info "Proje kaldırıldı: $project_name"
    
    # Nginx konfigürasyonunu kaldır
    remove_nginx_config "$project_name"
    
    # MySQL veritabanını kaldır
    remove_mysql_database "$project_name"
    
    log_success "Konfigürasyon temizlendi: $domain"
}

# Ana watcher
start_watcher() {
    log_info "🔍 Otomatik klasör izleyici başlatılıyor..."
    log_info "İzlenen dizin: $SITES_DIR"
    log_info "DOMAIN_SUFFIX: $DOMAIN_SUFFIX"
    log_info "Otomatik tarama süresi: $AUTO_SCAN_INTERVAL saniye"
    
    # Dizinleri oluştur
    mkdir -p "$SITES_DIR"
    
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
    
    # Projects dizinini izle
    log_info "inotifywait başlatılıyor: $SITES_DIR"
    inotifywait -m -r -e create,delete,moved_to,moved_from,modify --format '%w%f %e' "$SITES_DIR" | \
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
        
        # subdomains.json değişikliklerini kontrol et
        if [[ "$relative_path" == "$project_name/subdomains.json" ]]; then
            case "$event" in
                *MODIFY*)
                    log_info "subdomains.json güncellendi: $project_name"
                    sleep 1  # Dosya yazımının tamamlanmasını bekle
                    # Önce mevcut subdomain'leri temizle
                    remove_project_subdomains "$project_name"
                    # Sonra yeniden oluştur
                    parse_subdomains_json "$project_name"
                    ;;
                *CREATE*)
                    log_info "subdomains.json oluşturuldu: $project_name"
                    sleep 1
                    parse_subdomains_json "$project_name"
                    ;;
            esac
        fi
        
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
        fi
    done
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
    case "${1:-start}" in
        "start")
            check_dependencies
            start_watcher
            ;;
        "stop")
            pkill -f "inotifywait.*$SITES_DIR" 2>/dev/null
            pkill -f "watcher.sh" 2>/dev/null
            ;;
        *)
            log_info "Kullanım: $0 {start|stop}"
            ;;
    esac
}

main "$@"
