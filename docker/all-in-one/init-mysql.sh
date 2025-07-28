#!/bin/bash

# MySQL data dizinini kontrol et
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "MySQL veritabanı ilk kez başlatılıyor..."
    
    # MySQL'i başlat
    mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
    
    # MySQL'i geçici olarak başlat
    mysqld --user=mysql --datadir=/var/lib/mysql --skip-networking &
    
    # MySQL'in başlamasını bekle
    sleep 10
    
    # Root şifresini ayarla
    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';"
    mysql -u root -proot -e "CREATE USER 'root'@'%' IDENTIFIED BY 'root';"
    mysql -u root -proot -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
    mysql -u root -proot -e "FLUSH PRIVILEGES;"
    
    # Geçici MySQL'i durdur
    mysqladmin -u root -proot shutdown
    
    echo "MySQL veritabanı hazırlandı!"
fi

# MySQL'i başlat
exec mysqld --user=mysql --datadir=/var/lib/mysql
