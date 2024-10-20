#!/bin/bash

# Function to display message
display_message() {
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Function to set the server timezone
set_timezone() {
    offset=$1
    if [[ $offset -ge 0 ]]; then
        timezone="Etc/GMT-$offset"
    else
        timezone="Etc/GMT$((-offset))"
    fi
    display_message "Setting server time to $timezone..."
    sudo timedatectl set-timezone $timezone
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run this script as root."
    exit
fi

# Step 1: Create a new user 'dev' and add to sudo group (if not already exists)
if id "dev" &>/dev/null; then
    display_message "User 'dev' already exists."
else
    display_message "Creating a new user 'dev' and adding to sudo group..."
    sudo adduser dev
    sudo usermod -aG sudo dev
    display_message "User 'dev' created and added to sudo group."
fi

# Prompt for the timezone offset
read -p "Enter the offset from GMT (e.g., 7 for UTC+7, -7 for UTC-7): " gmt_offset
set_timezone $gmt_offset

# Fix locale issue for add-apt-repository
display_message "Fixing locale issue for add-apt-repository..."
export LC_ALL=C.UTF-8

# Step 2: Update and upgrade the system
display_message "Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

# Step 3: Install essential libraries (software-properties-common)
display_message "Installing essential libraries and common development tools (curl, git, zip, unzip, software-properties-common)..."
sudo apt-get install curl git zip unzip software-properties-common -y

# Step 4: Add the PPA for Nginx
display_message "Adding Nginx PPA repository..."
sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/nginx
sudo apt update -y

# Step 5: Install Nginx
display_message "Installing Nginx..."
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
display_message "Nginx installed and running."

# Protect Nginx Version Disclosure
display_message "Protecting Nginx version disclosure..."
sudo sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf

# Step 6: Install MariaDB
display_message "Installing MariaDB..."
sudo apt install mariadb-server mariadb-client -y
sudo systemctl start mariadb
sudo systemctl enable mariadb
display_message "MariaDB installed and running."

# Step 7: Check if MariaDB is secured
display_message "Checking if MariaDB is secured..."
SECURED=1
# Check for anonymous users
if sudo mysql -e "SELECT User, Host FROM mysql.user WHERE User='';" | grep -q ''; then
    SECURED=0
fi

# Check if root can log in remotely
if sudo mysql -e "SELECT User, Host FROM mysql.user WHERE User='root' AND Host='%';" | grep -q 'root'; then
    SECURED=0
fi

# Check if test database exists
if sudo mysql -e "SHOW DATABASES LIKE 'test';" | grep -q 'test'; then
    SECURED=0
fi

if [ "$SECURED" -eq 0 ]; then
    display_message "MariaDB is not secured. Running mysql_secure_installation..."
    sudo mysql_secure_installation
else
    display_message "MariaDB is already secured."
fi

# Step 8: Add PHP 7.4 Repository
display_message "Adding PHP 7.4 repository..."
sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
sudo apt update -y

# Step 9: Install PHP 7.4 and necessary PHP extensions
display_message "Installing PHP 7.4 and common PHP extensions..."
sudo apt install php7.4 php7.4-fpm php7.4-mysql php7.4-cli php7.4-curl php7.4-zip php7.4-xml php7.4-mbstring php7.4-gd php7.4-soap php7.4-intl php7.4-bcmath php7.4-xmlrpc php7.4-json -y

# Configure PHP limits
display_message "Configuring PHP settings..."
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 64M/" /etc/php/7.4/fpm/php.ini
sudo sed -i "s/post_max_size = .*/post_max_size = 64M/" /etc/php/7.4/fpm/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = 256M/" /etc/php/7.4/fpm/php.ini
sudo sed -i "s/max_execution_time = .*/max_execution_time = 300/" /etc/php/7.4/fpm/php.ini

# Restart PHP-FPM service
sudo systemctl restart php7.4-fpm
display_message "PHP 7.4 installed and configured."

# Step 10: Create /srv/wp directory and set permissions
display_message "Creating /srv/wp directory and setting permissions..."
sudo mkdir -p /srv/wp
sudo chown -R www-data:www-data /srv/wp
sudo chmod -R 755 /srv/wp

# Step 11: Add simple "Page Not Found" in /srv/wp/index.html
display_message "Creating a 'Page Not Found' page at /srv/wp/index.html..."
sudo tee /srv/wp/index.html > /dev/null << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 Page Not Found</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            margin-top: 100px;
        }
        h1 {
            font-size: 48px;
            color: #ff6347;
        }
        p {
            font-size: 18px;
            color: #555;
        }
    </style>
</head>
<body>
    <h1>404</h1>
    <p>Oops! The page you are looking for does not exist.</p>
</body>
</html>
EOL
sudo chown www-data:www-data /srv/wp/index.html
sudo chmod 644 /srv/wp/index.html
display_message "'Page Not Found' page created at /srv/wp/index.html."

# Step 12: Configure Nginx to use PHP and serve from /srv/wp
display_message "Configuring Nginx to serve from /srv/wp and use PHP..."
sudo tee /etc/nginx/sites-available/default > /dev/null << EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /srv/wp;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

# Test and reload Nginx configuration
sudo nginx -t
sudo systemctl reload nginx
display_message "Nginx configured to use /srv/wp as the root directory."

# Step 13: Set up UFW Firewall
display_message "Configuring UFW firewall to allow Nginx traffic..."
sudo ufw allow 'OpenSSH'
sudo ufw allow 'Nginx Full'
sudo ufw enable
display_message "UFW firewall configured to allow Nginx traffic."

# Step 14: Generate Self-Signed SSL Certificate for the public IP or hostname

# Get the server's public IP address
server_ip=$(hostname -I | awk '{print $1}')
read -p "Do you want to use a hostname instead of the public IP ($server_ip)? Enter hostname or press ENTER to use IP: " server_hostname

if [ -z "$server_hostname" ]; then
    server_hostname=$server_ip
fi

display_message "Generating self-signed SSL certificate for $server_hostname..."

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/CN=$server_hostname"

# Generate Diffie-Hellman group
sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048

# Step 15: Configure Nginx for SSL
display_message "Configuring Nginx for SSL..."

# Create a snippet for SSL settings
sudo tee /etc/nginx/snippets/self-signed.conf > /dev/null << EOL
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOL

# Create a snippet for SSL parameters
sudo tee /etc/nginx/snippets/ssl-params.conf > /dev/null << EOL
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_dhparam /etc/nginx/dhparam.pem;
ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
EOL

# Update Nginx default server block to use SSL
sudo tee /etc/nginx/sites-available/default > /dev/null << EOL
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    
    include snippets/self-signed.conf;
    include snippets/ssl-params.conf;

    root /srv/wp;
    index index.php index.html index.htm;

    server_name $server_hostname;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name $server_hostname;

    return 301 https://\$host\$request_uri;
}
EOL

# Test and reload Nginx configuration
sudo nginx -t
sudo systemctl reload nginx

display_message "Nginx configured to use self-signed SSL for $server_hostname."

# Step 16: Switching to 'dev' user for further configurations
display_message "Switching to 'dev' user to execute user-level tasks..."
sudo -u dev -H bash << 'EOF'

# User-level configuration here (e.g., any user-specific settings, installing user-level tools, etc.)
display_message "Performing user-specific configurations for 'dev'..."

# Example: create a .bashrc alias (just an example)
echo "alias ll='ls -alF'" >> ~/.bashrc

EOF

# Final message
display_message "LEMP stack installation completed successfully!"
echo "User 'dev' has been created, a 'Page Not Found' page is available at /srv/wp/index.html, and Nginx is serving from /srv/wp with a self-signed SSL certificate for $server_hostname."
