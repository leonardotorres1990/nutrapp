   #!/bin/bash
    sudo apt update
    sudo apt upgrade -y
    sudo apt install apache2 mysql-server php libapache2-mod-php php-mysql -y
    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar -xf latest.tar.gz
    sudo mv wordpress /var/www/html/
    sudo chown -R www-data:www-data /var/www/html/wordpress
    sudo chmod -R 755 /var/www/html/wordpress
    sudo vi /etc/apache2/sites-available/wordpress.conf
    # Añade lo siguiente al archivo wordpress.conf
      <VirtualHost *:80>
     ServerName ip de la instancia ec2
     DocumentRoot /var/www/html/wordpress
     <Directory /var/www/html/wordpress/>
         Options FollowSymlinks
         AllowOverride All
         Require all granted
     </Directory>
     ErrorLog ${APACHE_LOG_DIR}/error.log
     CustomLog ${APACHE_LOG_DIR}/access.log combined
 </VirtualHost>
    sudo a2ensite wordpress.conf
    sudo a2enmod rewrite
    sudo systemctl restart apache2
    sudo systemctl reload apache2
    # crear base de datos wordpress
    mysql -h terraform-20230608215329726100000002.cxopvhonpnhj.us-east-1.rds.amazonaws.com -uadmin -p
    CREATE DATABASE wordpress;
    SHOW DATABASES;

 