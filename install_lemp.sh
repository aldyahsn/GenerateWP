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

# Step 11: Set up UFW Firewall
display_message "Configuring UFW firewall to allow Nginx traffic..."
sudo ufw allow 'OpenSSH'
sudo ufw allow 'Nginx Full'
sudo ufw enable
display_message "UFW firewall configured to allow Nginx traffic."

display_message "DONE"
