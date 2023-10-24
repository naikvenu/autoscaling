# Install Apache, this is only required for demo purpose.
# Check if the script is running with superuser privileges


# Install Apache using yum
sudo yum -y install httpd

log "Installing Apache httpd server" $?
# Start Apache and enable it to start on boot
sudo systemctl start httpd
sudo systemctl enable httpd

log "Enabling Apache httpd server" $?

# Create the index.php file
cat <<EOF > /var/www/html/index.php
<!DOCTYPE html>
<html>
  <h1>This is Apache Instance Scaling Demo</h1>
  <body>
    <p><?php echo "The hostname of this machine is: " . gethostname(); ?></p>
  </body>
</html>
EOF

# Adjust permissions to make the index.php file accessible
chmod 644 /var/www/html/index.php

# Restart Apache to apply changes
systemctl restart httpd

sudo firewall-cmd --zone=public --add-service=http --permanent
sudo firewall-cmd --reload

if curl -I "http://localhost" | grep -q "HTTP/1.1 200 OK"; then
    log "Apache has been installed, the index.php file has been added, and Apache is accessible."
else
    log "Apache installation or accessibility check failed."
fi
