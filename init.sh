if [ "$#" -ne 4 ]; then
    echo "Please ensure you provide four parameters: your resource-group, a unique db server name, a secure db password, and a unique webapp name."
    exit 1
fi

RESOURCE_GROUP="$1"
SQL_SERVER_NAME="$2"
SQL_SERVER_USERNAME="username123"
SQL_SERVER_PASSWORD="$3"
SQL_DATEBASE_NAME="mod-12-db"
WEBAPP_NAME="$4"

printf "RESOURCE_GROUP: $RESOURCE_GROUP\nSQL_SERVER_NAME: $SQL_SERVER_NAME\nSQL_SERVER_USERNAME: $SQL_SERVER_USERNAME\nSQL_SERVER_PASSWORD: $SQL_SERVER_PASSWORD\nSQL_DATEBASE_NAME: $SQL_DATEBASE_NAME\nWEBAPP_NAME: $WEBAPP_NAME\n\n"

read -p "Type 'y' to confirm: " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo
set -x

az sql server create -g $RESOURCE_GROUP -n $SQL_SERVER_NAME -u $SQL_SERVER_USERNAME -p $SQL_SERVER_PASSWORD -e true
if [ $? -ne 0 ]; then
    exit
fi

az sql server firewall-rule create -g $RESOURCE_GROUP -s $SQL_SERVER_NAME -n azure-services --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
if [ $? -ne 0 ]; then
    exit
fi

az sql db create -n $SQL_DATEBASE_NAME -s $SQL_SERVER_NAME -g $RESOURCE_GROUP -e Basic
if [ $? -ne 0 ]; then
    exit
fi

az webapp up -g $RESOURCE_GROUP -n $WEBAPP_NAME --sku F1 -l uksouth
if [ $? -ne 0 ]; then
    exit
fi

az webapp config appsettings set -n $WEBAPP_NAME --settings "CONNECTION_STRING=Server=tcp:$SQL_SERVER_NAME.database.windows.net,1433;Database=$SQL_DATEBASE_NAME;User ID=$SQL_SERVER_USERNAME;Password=$SQL_SERVER_PASSWORD;Encrypt=true;Connection Timeout=30;" "DEPLOYMENT_METHOD=cli"

