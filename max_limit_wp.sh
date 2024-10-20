#!/bin/bash

# Define the desired max size for uploads (50M in this case)
MAX_SIZE="50M"

# Function to update nginx configuration
update_nginx_config() {
  # Path to nginx configuration file (adjust if different)
  NGINX_CONF="/etc/nginx/nginx.conf"

  # Check if client_max_body_size is already set
  if grep -q "client_max_body_size" $NGINX_CONF; then
    # Update the client_max_body_size value
    sudo sed -i "s/client_max_body_size.*/client_max_body_size $MAX_SIZE;/g" $NGINX_CONF
  else
    # Add the client_max_body_size directive under the http block
    sudo sed -i "/http {/a \\    client_max_body_size $MAX_SIZE;" $NGINX_CONF
  fi

  echo "Updated Nginx configuration: client_max_body_size set to $MAX_SIZE."

  # Test and reload Nginx to apply changes
  sudo nginx -t && sudo systemctl reload nginx

  if [ $? -eq 0 ]; then
    echo "Nginx reloaded successfully."
  else
    echo "Nginx reload failed. Check the configuration."
  fi
}

# Function to update all PHP configurations
update_php_config() {
  # Find all php.ini files in /etc/php/ directory for all installed PHP versions
  PHP_INI_FILES=$(find /etc/php/ -type f -name "php.ini")

  for PHP_INI in $PHP_INI_FILES; do
    # Update both upload_max_filesize and post_max_size
    sudo sed -i "s/upload_max_filesize =.*/upload_max_filesize = $MAX_SIZE/g" $PHP_INI
    sudo sed -i "s/post_max_size =.*/post_max_size = $MAX_SIZE/g" $PHP_INI

    echo "Updated PHP configuration: upload_max_filesize and post_max_size set to $MAX_SIZE in $PHP_INI."

    # Extract PHP version from the path (e.g., /etc/php/7.4/cli/php.ini -> 7.4)
    PHP_VERSION=$(echo $PHP_INI | grep -oP '(?<=/etc/php/)\d\.\d')

    # Restart PHP-FPM for each version if applicable
    if [ -n "$PHP_VERSION" ]; then
      echo "Restarting PHP-FPM for PHP $PHP_VERSION..."
      sudo systemctl restart php${PHP_VERSION}-fpm
      if [ $? -eq 0 ]; then
        echo "PHP-FPM for PHP $PHP_VERSION restarted successfully."
      else
        echo "PHP-FPM restart failed for PHP $PHP_VERSION. Check the configuration."
      fi
    fi
  done
}

# Run the update functions
update_nginx_config
update_php_config

echo "All Nginx and PHP limits updated and services restarted successfully!"
