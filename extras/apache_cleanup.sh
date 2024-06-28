
## Copyright (c) 2022 Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

#Disclaimer:
#This script is provided for experimental purposes only and should not be used in production. 

sudo /opt/oracle/mgmt_agent/agent_inst/bin/uninstaller.sh

sleep 2
sudo rpm -evh oracle.mgmt_agent

apache_exporter_file="/etc/systemd/system/apache_exporter.service"
node_exporter_file="/etc/systemd/system/node_exporter.service"

sudo systemctl stop apache_exporter
sudo systemctl stop node_exporter

sudo systemctl disable apache_exporter
sudo systemctl disable node_exporter

sudo rm $apache_exporter_file $node_exporter_file
sudo rm /usr/sbin/apache_exporter /usr/sbin/node_exporter

sudo yum remove -y java-1.8.0-openjdk

sudo systemctl stop apache_init

