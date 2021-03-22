# DevOps-Course-Workshop-Module-12-Learners

Workshop Repo for Module 12 of the DevOps Course

### Set up DB:

```
$ az sql server create -g <resource_group_name> -n <db_server_name> -u <username> -p <password> -e true
$ az sql db create -n <database_name> -s <db_server_name> -g <resource_group_name> -e Basic
```

Then also create a connection string, a template will be outputted from this command:

```
$ az sql db show-connection-string -c ado.net -n <database_name> -s <db_server_name>
```

### Deploy to Azure App Services:

```
$ az webapp up -g <resource_group_name> -n <webapp_name> --sku F1
$ az webapp config appsettings set -n <webapp_name> --settings "CONNECTION_STRING=<connection_string" "DEPLOYMENT_METHOD=cli"
```
