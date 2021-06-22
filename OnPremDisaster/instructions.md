# 1. Recover from on-premise disaster into the cloud with IaC

> Goal: Handle a dead on-premise web server by recreating it, and moving its database into Azure via a new Azure Resource Manager template.

## Overview

We have an on-premise web app, with a SQL database.
However, the server running the web app has broken! Fortunately, it's non-critical, and getting it back online isn't of utmost urgency. Rather than investing time and capital in fixing it, we'll just migrate it to the cloud sooner than we would previously have done.
Fortunately, a colleague has already changed the CI server to push the docker image for the web app to Docker Hub, so all we need to do now is set up the resources in Azure.

We need to create a standard app service / database setup:

- App Service & Plan
- Database Server
- Database

We will do this by creating ARM templates that define the infrastructure we need. Then, we need to restore data from the still existing on-premise database into the new cloud one, and deploy the app code.

## Setup

Make sure you have Azure CLI and Azure Data Studio with the [dacpac](https://docs.microsoft.com/en-us/sql/azure-data-studio/extensions/sql-server-dacpac-extension?view=sql-server-ver15) extension. 

You might also like to use the [ARM Tools](https://marketplace.visualstudio.com/items?itemName=msazurermtools.azurerm-vscode-tools) extension - it provides autocompletion and other useful features when working with ARM templates.

## Instructions

### Step 1: Create database backup
The first thing we need to do is create a backup of the "on-premises" database, so we can restore it to our new cloud environment. For the purposes of this exercise, the "on-premises" database will actually be another Azure DB, whose details will be provided to you.

We will connect to this database using Azure Data Studio, backup the database to a `BACPAC` file, then upload it to an Azure blob storage for later import.

> Azure SQL databases come with automated point-in-time backups, so `BACPAC` files are primarily used for moving databases from one server to another - as we're doing here. 

1. In the Azure portal, search for "Storage Accounts" in the top level search bar (in the blue bar, right at the top of the page)
2. Click "Create" to create a new Storage Account, and configure it:
   - Select your workshop resource group
   - Keep the default option for Performance (Standard) and select the "Locally-redundant" option for Redundancy.
3. Once created, browse to the Account, and select "Containers" in the sidebar.
4. Create a new container called "bacpac".
5. Open Azure Data Studio and connect to the "on-premise" database using the details provided by your tutor.
6. Right click on the database and chose "Data-tier Application Wizard".
7. Follow the steps to create a `.bacpac` backup of the database, and name it "database.bacpac".
8. Upload the file ("database.bacpac") to the container and account you just created.

Now, we have a `BACPAC` file in an Azure storage account - this is where it needs to be in order for us to restore the database.

### Step 2: Get ARM templates
We're ready to bring up our new architecture. The way we will do this is by provisioning resources in Azure using ARM templates. ARM (Azure Resource Manager) is the deployment and management system that allows you to create and modify resources in Azure, and ARM templates are JSON files which describe the resources you want. 

ARM templates are therefore declarative - you define what resources you need, the configuration they need to have, and when you deploy, the tooling will take imperative action to create the resource (if it doesn't exist), update the resource (if it exists, but is not as defined in your template), or do nothing (if the resource exists and is exactly as you already wanted it)!

This means that ARM templates are idempotent - you can deploy the same template multiple times, and (providing you enter the same parameters) you won't create duplicate resources. This is a very useful property for an IaC tool.

So you know what they look like, here is an example of an ARM template:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storagePrefix": {
      "type": "string",
      "minLength": 3,
      "maxLength": 11
    },
    "storageSKU": {
      "type": "string",
      "defaultValue": "Standard_LRS",
      "allowedValues": [
        "Standard_LRS",
        "Standard_GRS",
        "Standard_RAGRS",
        "Standard_ZRS",
        "Premium_LRS",
        "Premium_ZRS",
        "Standard_GZRS",
        "Standard_RAGZRS"
      ]
    },
    "location": {
      "type": "string",
      "defaultValue": "[resourceGroup().location]"
    },
    "appServicePlanName": {
      "type": "string",
      "defaultValue": "exampleplan"
    }
  },
  "variables": {
    "uniqueStorageName": "[concat(parameters('storagePrefix'), uniqueString(resourceGroup().id))]"
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2019-04-01",
      "name": "[variables('uniqueStorageName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "[parameters('storageSKU')]"
      },
      "kind": "StorageV2",
      "properties": {
        "supportsHttpsTrafficOnly": true
      }
    },
    {
      "type": "Microsoft.Web/serverfarms",
      "apiVersion": "2016-09-01",
      "name": "[parameters('appServicePlanName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "B1",
        "tier": "Basic",
        "size": "B1",
        "family": "B",
        "capacity": 1
      },
      "kind": "linux",
      "properties": {
        "perSiteScaling": false,
        "reserved": true,
        "targetWorkerCount": 0,
        "targetWorkerSizeId": 0
      }
    }
  ],
  "outputs": {
    "storageEndpoint": {
      "type": "object",
      "value": "[reference(variables('uniqueStorageName')).primaryEndpoints]"
    }
  }
}
```

That was a relatively small one - they can get somewhat verbose. Don't worry, the structure is pretty simple - ARM templates have a high-level structure that looks like the following:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "",
  "parameters": {  },
  "variables": {  },
  "functions": [  ],
  "resources": [  ],
  "outputs": {  }
}
```

It's important to know what each of these are.

`$schema` defines what version of the templating language you are using. Depending on the type of editor you use, or the scale of deployment you're performing, this can change.

`contentVersion` is for your use - you can put the version of the template in here, e.g. `"1.0.0.0"`.

`parameters` is a JSON object that specifies what each of the inputs to your template are. You will naturally want to parameterise your template - you will likely wish to re-use it to create different environments, or have different configurations. You can do this using parameters, which can be referred to later in the template. Parameters can take a default value, otherwise they must be specified when deployed - either from a `parameters.json` file, or elsewhere (e.g. at the command line). There are other useful things you can do with parameters too, such as defining a fixed set of values they're allowed to take on!

`variables` is a slightly misleading name - this is actually an object where you can set constants that you might want to use across the rest of your template. If you need to calculate a value (e.g. the name of a resource) by evaluating an expression (taking the date, converting to string, etc) then this is where you would want to do it.

`functions` allows you to create user-defined functions for use in the template.

`resources` will be a large part of the template - this is where you specify the resources that you want deployed or updated. Resources have types, names, and other data.

`outputs` allows you to specify values that you want to be returned after deployment. Generally, you will want to do this to retrieve information about the resources you've just deployed (e.g. the URL of a web service). 

You now know almost enough to write your own ARM template from scratch! However, this is normally not necessary, and is not what we'll be doing today. It is generally easier and less error-prone to work from and modify an existing template, and there are several ways in which you can get an existing template.

One way is to go to the Azure web portal, and go through the motions of manually creating the resource you want via the web interface. Then, at the final step before deployment, Azure will provide you with the option of downloading the ARM template that corresponds to the resource you've just said you wanted to make - convenient! It's all the ease of use and intuitiveness of manually provisioning resources with a wizard, but with all the benefits of version controlled IaC.

Let's do this now for each of the SQL Server and App Service resources you'll need to deploy.

#### SQL Server

1. Search for "SQL databases" in the top search bar and then click "create".
2. Configure the database settings
  a) Select your resource group
  b) Choose "Create new" for the server (set any value for the username and password you like - we are just here to generate a template).
  c) Hit "Configure database" and select the Basic tier.
3. Click "Review and create".
4. **The magic happens!** Rather than actually creating the resource, click "Download a template for automation".
5. Click the download button and extract the zip.

#### App service

6. Search for "App Services" in the top search bar and then click "create".
7. Choose Docker Container on Linux.
8. Create a new App Service Plan (change size to the Dev B1 Tier).
9. On the Docker tab choose Image Source "Docker Hub" and Image and Tag "corndelldevopscourse/mod12app:latest".
10. Click "Review and create".
11. **The magic happens (again)!** Rather than actually creating the resource, click "Download a template for automation".
12. Click the download button and extract the zip.

Once you've extracted the zip, you'll notice that it contained two files! You should see a `template.json` file, and a `parameters.json` file.
We talked about parameters before - these are the inputs to your template that can change in order to make your template useful in other scenarios or environments. 

When you're deploying an ARM template, you can specify all the required parameters by hand (on the command line, or elsewhere). However, that's a little unwieldy, and a better option is often to also specify a second JSON file (alongside the template to be deployed) that defines all the parameters you want to pass in. This is what this `parameters.json` file is. If you look at the parameters declared at the top of the `template.json`, and the parameters specified in the `parameters.json`, you'll see the proof - they match up!

### Step 3: Combine your templates
We now have ARM templates that will provision the resources we need! However, the information is currently contained within two separate templates, and for such a simple architecture it would be better to have just one template. Fortunately, we are now armed with enough knowledge of the templates' anatomy to perform this merging operation ourselves.

Merge these into single `template.json` and `parameters.json` files:

1. Start with the SQL database files.
2. Copy and paste the parameters,  resources, and variables from the App Service `template.json` file into the applicable arrays in the final `template.json` file.
3. Copy and paste the parameters from the App Service `parameters.json` file into the parameters field in the final `parameters.json` file.
4. Make sure you haven't introduced any anomalies.

Hints:
* You will need to remove the duplicate `location` parameter in both files.
* You will want to ensure the latest of the two `$schema` values is used at the top of each file.

### Step 4: Add configuration

We're almost there, but a couple of changes are needed in order for the App Service to be able to talk to the Database.

This is what needs changing. Can you figure out what changes to make, and where?
* We need to set the parameter `allowAzureIps` to `true`.
* We need to set the parameter `dockerRegistryPassword` to `""`.
* We need to add a new variable called `connectionString`, with the value `"[concat('Server=tcp:', parameters('serverName'), '.database.windows.net,1433;Initial Catalog=', parameters('databaseName'), ';Persist Security Info=False;User ID=', parameters('administratorLogin'), ';Password=', parameters('administratorLoginPassword'), ';MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;')]"`
* We need to add two new values in the `appSettings` for the `siteConfig` for the web site. 
  * The name of the first will be `"CONNECTION_STRING"` and its value will need to come from the variable `connectionString` that we defined earlier.
  * The name of the second will be `"DEPLOYMENT_METHOD"` and its value will be `"ARM Template"`

Hints:
* You can specify that the value for an item should come from a parameter by using this syntax as the value: `"[variables('connectionString')]"`

<details><summary>Answer (spoilers!)</summary>

1. In `parameters.json`, set `allowAzureIps` to `true` and the value of `dockerRegistryPassword` to `""`.
2. Add the following to the `variables` object in `template.json`:

```json
"connectionString":
"[concat('Server=tcp:', parameters('serverName'), '.database.windows.net,1433;Initial Catalog=', parameters('databaseName'), ';Persist Security Info=False;User ID=', parameters('administratorLogin'), ';Password=', parameters('administratorLoginPassword'), ';MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;')]"
```

3. Then add the following to `appSettings` array in `template.json`:

```json
{
  "name": "CONNECTION_STRING",
  "value": "[variables('connectionString')]"
},
{
  "name": "DEPLOYMENT_METHOD",
  "value": "ARM Template"
},
```
</details>

### Step 5: Add backup to database

Sadly the Azure Portal won't allow direct use of the backup file we created, so we need to add it to the the ARM template ourselves.

We can follow the steps below which are derived from this guide: [https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-tutorial-deploy-sql-extensions-bacpac#edit-the-template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-tutorial-deploy-sql-extensions-bacpac#edit-the-template)

1. Add the following to `parameters` in `template.json`:

```json
  "importDatabase": {
    "type": "bool"
  },
 "storageAccountKey": {
    "type":"string",
    "metadata":{
      "description": "Specifies the key of the storage account where the BACPAC file is stored."
    }
  },
  "bacpacUrl": {
    "type":"string",
    "metadata":{
      "description": "Specifies the URL of the BACPAC file."
    }
  },
```

2. Add the following to the database in the template (just below the `"type": "databases"` line)

```json
"resources": [
  {
    "type": "extensions",
    "apiVersion": "2014-04-01",
    "name": "Import",
    "dependsOn": [
      "[resourceId('Microsoft.Sql/servers/databases', parameters('serverName'), parameters('databaseName'))]"
    ],
    "condition": "[parameters('importDatabase')]",
    "properties": {
      "storageKeyType": "StorageAccessKey",
      "storageKey": "[parameters('storageAccountKey')]",
      "storageUri": "[parameters('bacpacUrl')]",
      "administratorLogin": "[parameters('administratorLogin')]",
      "administratorLoginPassword": "[parameters('administratorLoginPassword')]",
      "operationMode": "Import"
    }
  }
]
```

3. Add the following to `parameters.json`

```json
"importDatabase": {
    "value": false
},
"storageAccountKey": {
    "value": ""
},
"bacpacUrl": {
    "value": "https://<storage_account_name>.blob.core.windows.net/bacpac/database.bacpac"
},
```

**Wait!** Did you notice? The directions got us to add a resource with the `condition` property. This allows us to specify a condition under which this resource will be provisioned as directed, or ignored entirely.  This is useful for a wide variety of reasons. So, before you move on - where is it added, how is it used, and why?

> Don't forget to update the bacpacUrl variable, and if you named your container or file differently (from bacpac/database.bacpac) you will need to ensure the URL matches your resource.

### Step 6: Deploy the template

Our template is finally ready to deploy! Here are the final steps we need to take.

1. Generate a password for the database. There are minimum complexity rules for this password, so make it long-ish (more than 7 characters), with numbers, symbols and both cases of letters.
2. Go to the storage account you created and copy the first key in the "Access Keys" section.
3. **It's time!** Run `az deployment group create --resource-group <resource_group> --template-file template.json --parameters parameters.json --parameters administratorLoginPassword=<db_password> --parameters storageAccountKey=<storage_access_key> --parameters importDatabase=true -c`
4. Confirm the deployment (this step is required by the `-c` parameter).
5. Confirm this worked by browsing to https://<webapp_name>.azurewebsites.net/

Hopefully, you now have a provisioned website! Or close to one - importing a `BACPAC` file can take a few minutes. If your site hasn't fully provisioned yet, feel free to make a start on the next step. Make sure you commit your code before continuing!

### Step 7: Tidy up

Hopefully, you've now seen that your template works. It was a lot less effort to start from an existing template or two than to write it all from scratch! But, there are some clear disadvantages, too.

The `template.json` and `parameters.json` have quite a lot of redundant code that we aren't planning on using.
In fact, some of it won't work without changes to the template.
The App Service won't be able to communicate by a private network just by configuring the database to.

We should tidy this up so it is possible to see what we intended.
If you search for the word "private" in `template.json`, you'll see it's only mentioned in some resources that are conditional on parameters like `enablePrivateEndpoint` which are all false in `parameters.json`. So: let's delete all those parameters, resources, and variables.

1. Delete any parameters, resources and variables with `private` in them, in both files.
2. Redeploy by running `az deployment group create --resource-group <resource_group_name> --template-file template.json --parameters parameters.json --parameters administratorLoginPassword=<password> -c` (the earlier command, but without the parameters required for importing a database).
3. You'll see that redeploying will make some changes to the existing resources (since the ARM Template doesn't exactly line up with the created resource) rather than try to recreate them. We can see them because the `-c` flag uses functionality called `what-if` ([https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-deploy-what-if?tabs=azure-powershell](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-deploy-what-if?tabs=azure-powershell)).

You can use `what-if` in order to simulate the effect of deploying a template, without actually deploying it.

### Step 8: Check out the site

The moment of truth.

Go to the created App Service in Azure Portal, and click on its URL.
If everything is setup correctly you should see the following JSON:

```json
{
  "status": "Successfully connected to the db containing info for Module 12 Workshop",
  "deploymentMethod": "ARM Template"
}
```
