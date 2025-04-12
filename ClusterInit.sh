#!/bin/bash

# Nutanix initial standup script
# No API until Prism Central installed, so we're doing this the old fashioned way!

CVM_IP="172.25.1.11"
CVM_USER="admin"
CVM_PASSWORD="nutanix/4u"
CLUSTER_NAME="xntnx1"
CLUSTER_IP="172.25.1.100"
DATA_IP="172.25.1.101"
DNS_SERVERS="172.18.11.250"
NTP_SERVERS="time.xrs444.net"
CVM_NODES="172.25.1.11,172.25.1.21,172.25.1.31"
NETWORK_NAME="VMs"
POOL_START="172.25.2.1" 
POOL_END="172.25.2.200"
VLAN="2002"
DOMAINS="l.xrs444.net,x.xrs444.net"
VLAN_SUBNET="172.25.2.250/24"
VLAN_COMMENT="General VM Network"
UPLINKS="10g"

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is not installed. Install it to use password authentication."
    exit 1
fi

echo "===== Nutanix Cluster Configuration Script ====="
echo "Connecting to CVM at $CVM_IP"

# Create a temporary file to store the commands
SSH_COMMANDS=$(mktemp)
trap 'rm -f $SSH_COMMANDS' EXIT

# Add commands to execute within the single SSH session
cat > "$SSH_COMMANDS" <<EOF
# Test connection
echo "Connection to CVM successful"

# Check cluster status
echo "Checking cluster status"
CLUSTER_STATUS=\$(cluster status)
echo "\$CLUSTER_STATUS"

if [[ "\$CLUSTER_STATUS" == *"Cluster services are degraded"* ]] || [[ "\$CLUSTER_STATUS" == *"Cluster services are stopped"* ]]; then
    echo "Cluster needs attention."
else
    echo "Cluster is up, proceeding with configuration as requested."
fi

# Create/configure cluster
echo "Creating/configuring cluster '$CLUSTER_NAME'"
cluster -s $CVM_NODES --cluster_name=$CLUSTER_NAME --redundancy_factor=2 create

# Configure cluster DNS
echo "Configuring cluster DNS"
ncli cluster add-to-name-servers servers=$DNS_SERVERS

# Configure cluster NTP
echo "Configuring cluster NTP"
ncli cluster add-to-ntp-servers servers=$NTP_SERVERS

# Configure cluster virtual IP
echo "Configuring cluster virtual IP"
ncli cluster set-external-ip-address external-ip-address=$CLUSTER_IP

# Configure data services IP
echo "Configuring cluster data services IP"
ncli cluster edit-params external-data-services-ip-addresses=$DATA_IP

# Configure intial VM Subnet/VLAN
echo "Creating $NETWORK_NAME"
acli net.create $NETWORK_NAME vlan=$VLAN ip_config=$VLAN_SUBNET annotation=$VLAN_COMMENT
acli net.add_dhcp_pool $NETWORK_NAME start=$POOL_START end=$POOL_END
acli net.update_dhcp_dns $NETWORK_NAME servers=$DNS_SERVERS domains=$DOMAINS

# Configure LACP
echo "Configuring LACP, using quick mode so expect the connection to drop."
acli net.update_virtual_switch vs0 bond_type=kBalanceTcp lacp_fallback=true lacp_timeout=kFast host_uplink_config select all $UPLINKS quick_mode=true

EOF

# Execute command block
sshpass -p "$CVM_PASSWORD" ssh -o StrictHostKeyChecking=no "$CVM_USER@$CVM_IP" < "$SSH_COMMANDS"
SSH_RESULT=$?

if [ $SSH_RESULT -ne 0 ]; then
    echo "Error during SSH session. Exit code: $SSH_RESULT"
    exit 
fi

echo "===== Nutanix cluster creation completed ====="
echo "Log in and install PC"
