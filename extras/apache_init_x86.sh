## Copyright (c) 2022 Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

# Author: Venugopal Naik (venugopal.naik@oracle.com)

artifact_path=/home/opc/artifacts
tmp_path=/tmp/artifacts
log_file=${artifact_path}/apache_init.log

log() {
  local message="$1"
  local return_code="$2"
  local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  local log_message="$timestamp - $message"

  if [ -n "$return_code" ]; then
    log_message="$log_message (Exit Code: $return_code)"
    if [ "$return_code" -ne 0 ]; then
      log_message="$log_message (Error)"
    fi
  fi

  echo "apache_int: $log_message"
  echo "apache_init: $log_message" >> "$log_file"
}

log "Apache init Started .."

log "Checking and installing Java .."
# Check if Java is installed
if type -p java &>/dev/null; then
    log "Java is installed."

    # Check the Java version
    java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f 2)

    if [[ "$java_version" < "1.8.0_281" ]]; then
        log "Java version $java_version is below the required minimum version (JDK 8u281 -b02)."
        log "Updating Java..."
        sudo yum install -y java-1.8.0-openjdk
    else
        log "Java version is compatible."
    fi
else
    log "Java is not installed. Installing Java..."
    sudo yum install -y java-1.8.0-openjdk
fi

# Install the management agent first
cp -r ${artifact_path} /tmp/
chmod +x ${tmp_path}/*
sudo rpm -ivh ${tmp_path}/oracle.mgmt_agent.rpm

log "Management Agent RPM Install .." $?

sleep 5

sudo /opt/oracle/mgmt_agent/agent_inst/bin/setup.sh opts=${tmp_path}/input.rsp

log "Management Agent Setup .." $?

sleep 10

# Setting the Apache Properties

# Define the URL
URL="http://169.254.169.254/opc/v1/instance"

# Use curl to fetch the hostname
node_name=$(curl -s $URL/hostname)
compartment_id=$(curl -s $URL/compartmentId)

# Check if curl was successful
if [ $? -eq 0 ]; then
  # Update the apache.properties file
  sudo cat <<EOL |sudo tee /opt/oracle/mgmt_agent/agent_inst/discovery/PrometheusEmitter/apache.properties > /dev/null
url=http://localhost:9117/metrics
namespace=apache_mod_stats
nodeName=$node_name
scheduleMins=1
metricDimensions=nodeName
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
nodeName=$node_name
scheduleMins=1
metricDimensions=nodeName
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


log "Running a load generator script in the end"
sudo ${tmp_path}/apache_test.sh &

# Start the test 
log " Apache init Completed, Please check the logs for any errors .."