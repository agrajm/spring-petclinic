#!/bin/bash

if [ "$#" -ne 3 ];
    then echo "Usage: ./setup.sh <MySQLServerName> <AdminLogin> <Password>"
    # example - ./setup.sh spetcmysqlsvram2021 azureuser SpringPetC1234!
fi

ServerName=$1
AdminLogin=$2
Password=$3
ResourceGroup=springpetc
Location=southeastasia
AKSClusterName=springpetakscluster

az group create --name $ResourceGroup --location $Location

# Azure DB for MySQL - Basic edition for Dev
# Cannot use Basic Server if have to use Private Endpoints so switching to General Purpose Pricing Tier
az mysql server create \
    --resource-group $ResourceGroup \
    --name $ServerName \
    --location $Location \
    --admin-user $AdminLogin \
    --admin-password $Password \
    --sku-name GP_Gen5_2

# Server-rule Firewall rule
az mysql server firewall-rule create \
    --resource-group $ResourceGroup \
    --server $ServerName \
    --name AllowNoIP \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0

# Network
az network vnet create \
    --name k8s-vnet \
    --resource-group $ResourceGroup \
    --location $Location \
    --address-prefixes 172.10.0.0/16 \
    --subnet-name k8s-subnet \
    --subnet-prefixes 172.10.1.0/24

SubnetID=$(az network vnet show --name k8s-vnet -g $ResourceGroup | jq -r '.subnets[0].id')

# Log Analytics Workspace for logs
az monitor log-analytics workspace create \
    -g $ResourceGroup \
    -n springpetcLogs \
    -l $Location

LAWorkspaceID=$(az monitor log-analytics workspace list -g $ResourceGroup | jq -r '.[0].id')

# Control Plane MI
AKSCPMIIdentity=$(az identity create --name AKSControlPlaneMI --resource-group $ResourceGroup --query id -o tsv)

# Basic AKS Cluster
az aks create \
    --resource-group $ResourceGroup \
    --name $AKSClusterName \
    --node-count 1  \
    --enable-addons monitoring \
    --generate-ssh-keys \
    --network-plugin azure \
    --vnet-subnet-id $SubnetID \
    --docker-bridge-address 172.17.0.1/16 \
    --dns-service-ip 10.2.0.10 \
    --service-cidr 10.2.0.0/24 \
    --enable-managed-identity \
    --workspace-resource-id $LAWorkspaceID \
    --assign-identity $AKSCPMIIdentity

# The Az KeyVault Secrets CSI Store Provider can be enabled after cluster creation as well
# If you already have a Container Registry (ACR) you can attach that to AKS cluster now
# or later on as we do in Readme.md

# Private Endpoints for Azure SQL - Subnet
az network vnet subnet create \
    -g $ResourceGroup \
    --vnet-name k8s-vnet \
    -n PrivateEPSubnet \
    --disable-private-endpoint-network-policies true \
    --address-prefixes 172.10.2.0/26

MySQLServerID=$(az resource show -g $ResourceGroup -n $ServerName --resource-type "Microsoft.DBforMySQL/servers" --query "id" -o tsv)

az network private-endpoint create \
    --name mysqlPrivateEndpoint \
    --resource-group $ResourceGroup \
    --vnet-name k8s-vnet \
    --subnet PrivateEPSubnet \
    --private-connection-resource-id $MySQLServerID \
    --group-id mysqlServer \
    --connection-name myConnection

az network private-dns zone create --resource-group $ResourceGroup \
   --name  "privatelink.mysql.database.azure.com"

az network private-dns link vnet create --resource-group $ResourceGroup \
   --zone-name  "privatelink.mysql.database.azure.com"\
   --name MyDNSLink \
   --virtual-network k8s-vnet \
   --registration-enabled false

# Query for the network interface ID
networkInterfaceId=$(az network private-endpoint show --name mysqlPrivateEndpoint --resource-group $ResourceGroup --query 'networkInterfaces[0].id' -o tsv)

az resource show --ids $networkInterfaceId --api-version 2019-04-01 -o json
# Copy the content for privateIPAddress and FQDN matching the Azure database for MySQL name

# Create DNS records
az network private-dns record-set a create --name $ServerName --zone-name privatelink.mysql.database.azure.com --resource-group $ResourceGroup
az network private-dns record-set a add-record --record-set-name $ServerName --zone-name privatelink.mysql.database.azure.com --resource-group $ResourceGroup -a 172.10.2.4

# Put the DB secrets in Key Vault
KeyVaultName="springpetkv2021am"
az keyvault create \
    --name $KeyVaultName \
    --resource-group $ResourceGroup \
    --location $Location

MYSQL_DB_URL="jdbc:mysql://$ServerName.mysql.database.azure.com:3306/petclinic?useSSL=true&requireSSL=false"
az keyvault secret set \
    -n MYSQL-URL \
    --vault-name $KeyVaultName \
    --value $MYSQL_DB_URL

MYSQL_USER_LOGIN="$AdminLogin@$ServerName"
az keyvault secret set \
    -n MYSQL-USER \
    --vault-name $KeyVaultName \
    --value $MYSQL_USER_LOGIN

az keyvault secret set \
    -n MYSQL-PASS \
    --vault-name $KeyVaultName \
    --value $Password




# Next Steps
# Connect to AKS and deploy the app
