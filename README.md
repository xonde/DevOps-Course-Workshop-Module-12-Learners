# DevOps-Course-Workshop-Module-12-Learners

Workshop Repo for Module 12 of the DevOps Course

### Set up DB:

```
az sql server create -g rg-mod12 -n db-server-mod-12 -u username123 -p Password123 -e true
az sql server firewall-rule create -g rg-mod12 -s db-mod-12 -n azure-services --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
az sql db create -n db-mod-12 -s db-server-mod-12 -g rg-mod12 -e Basic
az webapp up -g rg-mod12 -n webapp-mod-12 --sku F1 -l uksouth
az webapp config appsettings set -n webapp-mod-12 --settings "CONNECTION_STRING=Server=tcp:<servername>.database.windows.net,1433;Database=<databasename>;User ID=<username>;Password=<password>;Encrypt=true;Connection Timeout=30;"" "DEPLOYMENT_METHOD=cli"


TODO: get something in the db, possibly use all these commands to get a sample bacpac in there:
https://docs.microsoft.com/en-us/azure/sql-database/scripts/sql-database-import-from-bacpac-cli