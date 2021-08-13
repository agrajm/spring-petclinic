# Setup for Petclinic on AKS

1. Deploy the infrastructure as in `setup.sh` with arguments for
   1. MySQL Server Name
   2. MySQL Admin User Name
   3. MySQL Admin Password
2. Typical usage:
```
./setup.sh <MySQLServerName> <AdminLogin> <Password>"
``` 
3. Populate the mysql database using `mysql` command line using the files `user.sql` and `schema.sql` in the resources folder
```
mysql -h <MySQLServerName>.mysql.database.azure.com -u <AdminLogin>@<MySQLServerName> -p < ../src/main/resources/db/mysql/user.sql
```
The above command is to be run once-only and you might need to alter the firewall rules on the MySQL server to be able to run this from your local dev machine.

The database schema and initial data will be populated by the Spring Boot application when it starts.


4. Connect to AKS cluster & Deploy Spring Boot App as Deployment
```
 az aks get-credentials --resource-group $ResourceGroup --name $AKSClusterName
```
Now we need to add the following environment variables to our PetClinic Deployment - these values are present in our key vault 
Before we do that, we need to enable the KeyVault integration with AKS 
# Enable the Secrets Store CSI Driver for Key Vault
# Register
```
az feature register \
--namespace "Microsoft.ContainerService" \
--name "AKS-AzureKeyVaultSecretsProvider"
```
# Verify
```
az feature list -o table \
--query "[?contains(name, 'Microsoft.ContainerService/AKS-AzureKeyVaultSecretsProvider')].{Name:name,State:properties.state}"
```
# Refersh
```
az provider register --namespace Microsoft.ContainerService
```
# Enable the Keyvault Secret Provider 
```
az aks enable-addons \
--addons azure-keyvault-secrets-provider \
--name $AKSClusterName \
--resource-group $ResourceGroup
```
It gives something like 
```
"addonProfiles": {
    "azureKeyvaultSecretsProvider": {
      "config": {
        "enableSecretRotation": "false"
      },
      "enabled": true,
      "identity": {
        "clientId": ".................",
        "objectId": "................",
        "resourceId": "/subscriptions/...../resourcegroups/<RGName>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<MI_Name>"
      }

```

Use the clientId from the user assigned MI that is created by the above command and assign that MI access on the keyvault created in the setup
KVSPClientId=<Your_Client_ID_From_Above_Command>

## Provide identity to access Azure Key Vault
```
az keyvault set-policy --name $KeyVaultName --secret-permissions get --spn $KVSPClientId
```

## Attach ACR
To be able to pull from your private ACR repo you must 'attach' the  repo to the AKS cluster
az aks update -n $AKSClusterName -g $ResourceGroup --attach-acr agraj

