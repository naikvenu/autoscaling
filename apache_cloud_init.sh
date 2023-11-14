#!/bin/bash

:<<'COMMENT'
Cloud init script for Compute Instance custom metric based Autoscaling.
Author: Venugopal Naik
COMMENT

BUCKET=artifacts
artifact_path=/home/opc/artifacts
tmp_path=/tmp/artifacts
log_file=/var/log/bootstrap_init.log
echo "APACHE_AUTOSCALING_CLOUD_INIT::  BEGIN" > "$log_file"

export INSTANCE_OCID=`curl http://169.254.169.254/opc/v1/instance/id`

log() {
  local message="$1"
  local return_code="$2"
  local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  local log_message="$timestamp - $message"

  if [ -n "$return_code" ]; then
    log_message="DONE: $log_message (Exit Code: $return_code)"
    if [ "$return_code" -ne 0 ]; then
      log_message="$log_message (Error)"
    fi
  fi

  echo "$log_message"
  echo "$log_message" >> "$log_file"
}

sudo dnf -y install oraclelinux-developer-release-el8
log "Adding OL8 repo..."

log "Checking and installing Java .."
# Check if Java is installed
if type -p java &>/dev/null; then
    log "Java is installed."

    # Check the Java version
    java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f 2)

    if [[ "$java_version" < "1.8.0_281" ]]; then
        log "Java version $java_version is below the required minimum version (JDK 8u281 -b02)."
        log "Updating Java..."
        sudo dnf install -y java-1.8.0-openjdk
    else
        log "Java version is compatible."
    fi
else
    log "Java is not installed. Installing Java..."
    sudo dnf install -y java-1.8.0-openjdk
fi

sudo dnf -y install python36-oci-cli
log "Installing OCI CLI..."
sudo dnf -y install jq
log "Installing jq .."

json_output=$(oci os ns get --auth instance_principal)
NAMESPACE=$(echo "$json_output" | jq -r '.data')
log "Found the OCI object storage namespace as $NAMESPACE .."

# Download objects from the source directory to the temporary directory
if oci os object bulk-download -ns "$NAMESPACE" -bn "$BUCKET" --dest-dir "$artifact_path" --auth instance_principal --overwrite >> "$log_file" 2>&1; then
  log "Successfully downloaded objects from Object Storage Bucket: $BUCKET"
else
  log "Failed to download objects from Object Storage Bucket $BUCKET"
  exit 1
fi

log "Noted instance OCID: ${INSTANCE_OCID}"

# Install the management agent first
cp -r ${artifact_path} /tmp/
chmod +x ${tmp_path}/*
sudo rpm -ivh ${tmp_path}/oracle.mgmt_agent.rpm
log "Management Agent RPM Install .." $?
sleep 5
sudo /opt/oracle/mgmt_agent/agent_inst/bin/setup.sh opts=${tmp_path}/input.rsp
log "Management Agent Setup .." $?

# Install Apache
sudo dnf install -y httpd
log "Installing Apache httpd server" $?

sudo dnf -y install php
log "Installing PHP .."

# Start Apache and enable it to start on boot
sudo systemctl start httpd
sudo systemctl enable httpd
log "Enabling Apache httpd server" $?

# Configuring Apache

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

if curl -I "http://localhost" | grep -q "HTTP/1.1 200 OK"; then
    log "Apache has been installed, the index.php file has been added, and Apache is accessible."
else
    log "Apache installation or accessibility check failed."
fi

log "Enabling mod_status..."
# Add mod_status configuration at the end of httpd.conf
echo -e "\n# Enable mod_status\nLoadModule status_module modules/mod_status.so\nExtendedStatus On\n<Location \"/server-status\">\n    SetHandler server-status\n    Order deny,allow\n    Deny from all\n    Allow from localhost\n</Location>" | sudo tee -a /etc/httpd/conf/httpd.conf
# Restart Apache
sudo systemctl restart httpd

log "Checking mod_status..."
status_page=$(curl -s http://localhost/server-status?auto)
if [ $? -eq 0 ]; then
    log "Mod_status is enabled. Status page content:"
    log "$status_page"
else
    log "Failed to access mod_status. Please check your Apache configuration."
fi

# Configuring Agent

# Define the URL
URL="http://169.254.169.254/opc/v1/instance"

# Use curl to fetch the hostname
node_name=$(curl -s $URL/hostname)
compartment_id=$(curl -s $URL/compartmentId)
node_ocid=$(curl -s $URL/id)

# Check if curl was successful
if [ $? -eq 0 ]; then
  # Update the apache.properties file
  sudo cat <<EOL |sudo tee /opt/oracle/mgmt_agent/agent_inst/discovery/PrometheusEmitter/apache.properties > /dev/null
url=http://localhost:9117/metrics
namespace=apache_mod_stats
nodeName=$node_name
nodeOcid=$node_ocid
scheduleMins=1
metricDimensions=nodeName,nodeOcid
allowMetrics=*
compartmentId=$compartment_id
EOL

  log "Successfully updated apache.properties with node_name: ${node_name}"
else
  log "Failed to retrieve node_name from ${URL}"
fi

sudo cat <<EOL |sudo tee /opt/oracle/mgmt_agent/agent_inst/discovery/PrometheusEmitter/node.properties > /dev/null
url=http://localhost:9100/metrics
namespace=apache_node_stats
nodeOcid=$node_ocid
scheduleMins=1
metricDimensions=nodeName,nodeOcid
allowMetrics=*
compartmentId=$compartment_id
EOL

log "Successfully updated node.properties with node_name: ${node_name}"

sudo cp ${tmp_path}/apache_exporter /usr/sbin/apache_exporter
sudo cp ${tmp_path}/node_exporter /usr/sbin/node_exporter

apache_exporter_file="/etc/systemd/system/apache_exporter.service"
node_exporter_file="/etc/systemd/system/node_exporter.service"

# Create or overwrite the service unit file
sudo cat <<EOF | sudo tee ${apache_exporter_file} > /dev/null
[Unit]
Description=Apache Prometheus mod_stats exporter
[Service]
ExecStart=/usr/sbin/apache_exporter
WorkingDirectory=${artifact_path}
User=opc
Type=simple

[Install]
WantedBy=multi-user.target
EOF


log "Creating Apache Exporter Service File .."

sudo cat <<EOF | sudo tee ${node_exporter_file} > /dev/null
[Unit]
Description=Prometheus Node Exporter

[Service]
ExecStart=/usr/sbin/node_exporter
WorkingDirectory=${artifact_path}
User=opc
Type=simple

[Install]
WantedBy=multi-user.target
EOF

log "Creating Node Exporter Service File .."


sudo systemctl daemon-reload

sudo systemctl enable apache_exporter
sudo systemctl enable node_exporter
sudo systemctl start apache_exporter
sudo systemctl start node_exporter

log "Enabling Apache and Node Services .."

if sudo systemctl is-active --quiet apache_exporter; then
  log "Apache Exporter service is active."
else
  log "Error: Apache Exporter service is not active."
fi

if sudo systemctl is-active --quiet node_exporter; then
  log "Apache Node Exporter service is active."
else
  log "Error: Apache Node Exporter service is not active."
fi

if sudo systemctl is-active --quiet mgmt_agent; then
  log "Management Agent service is active."
else
  log "Error: Management Agent service is not active."
fi

urls=("http://localhost:9117/metrics" "http://localhost:9100/metrics")

for url in "${urls[@]}"; do
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$url")

  if [[ $http_status -ge 200 && $http_status -lt 300 ]]; then
    log "$url - HTTP status code $http_status: OK"
      else
    log "$url - HTTP status code $http_status: Not OK"
     fi
done


sudo firewall-offline-cmd --zone=public --add-service=http
sudo systemctl reload firewalld
log "Adding firewall rules for http service .."

log " Apache init Completed, Please check the logs for any errors .."
