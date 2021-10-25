# 2. Moving existing cloud infrastructure to IaC

> Goal: Setup Terraform to manage a simple existing App Service and Database

_You should find that some resources (including an Azure App Service and an SQL DB) have been created for you in advance for this exercise and are available in your workshop resource group. Ask a trainer if you're not sure what resources that includes_

## Step 1: Setup

### Install terraform

* [Download terraform](https://www.terraform.io/downloads.html) and add it to your PATH
  * Verify it is installed by running `terraform -version`

### Set up the Azure provider

* Terraform will authenticate via the Azure CLI, so make sure you're still logged in to the "Softwire DevOps Academy" directory, check with: `az account show`
* Make a new folder and inside it create a file called `main.tf` with the following contents

```terraform
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

* From a terminal inside the folder, run `terraform init`

Terraform will automatically download the Azure provider and place it inside a new `.terraform` folder in the current directory.
You should not add the `.terraform` directory to source control, instead commit the `terraform.lock.hcl` which records the exact provider version used.

### Add your Resource Group

We are not going to have Terraform manage the Resource Group, and will instead just tell Terraform that it exists with a `data` block.

Add the following to your `main.tf`, using your Workshop Resource Group name.

```terraform
data "azurerm_resource_group" "main" {
  name = "<Your resource group name>"
}
```

Save your changes and run `terraform plan`. Terraform will connect to Azure and check that it can find the resource group. You should see an output like

```text
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Running `terraform plan` will never make any changes, so it's always safe to run, unlike `terraform apply`.

## Step 2: Create a new App Service

We're going to create a new instance of the App Service Plan and App Service that are managed by Terraform.
First go and have a look at the existing resources in the Azure portal.
If you open up the existing App Service you should see a response like

```json
{"currentDate":"Tuesday, 26 October 2021 10:31","status":"Successfully connected to the db containing info for Module 12 Workshop","deploymentMethod":"cli"}
```

For each of these we'll add a `resource` block to our Terraform config that represents a new resource in Azure.

### App Service Plan (ASP)

Add the following to your `main.tf` file, updating the name as appropriate:

```terraform
resource "azurerm_app_service_plan" "main" {
  name                = "<YourName>-terraformed-asp"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  kind                = "Linux"

  sku {
    tier = "Basic"
    size = "B1"
  }
}
```

Note how instead of specifying the location and resource group name directly, we reference the Resource Group data block above with `data.azurerm_resource_group.main`.
Here the name `"main"` is what we use to refer to the resource from within Terraform. The `name` property is what the resource will be called in Azure, which is just another property as far as Terraform is concerned.

Try running `terraform apply` and find your newly-created App Service Plan in Azure.

### App Service

Have a go at adding a new resource to `main.tf` for the App Service itself using Terraform's documentation: <https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_service>

You'll need to have a look at the configuration of the existing App Service in Azure in order to make sure it is set up the same. Once you're happy with it run `terraform plan` then `terraform apply`, find it in the Azure portal and check if it works like the existing one.

Hints:

* The existing App Service is running a Docker image. If you navigate to the App Service in the Azure portal and then click on "Deployment Center" you'll see the image name.
* The app_settings block will need to include the connection string for the database, which you can get from the "Configuration" tab in the Azure portal. This includes the database password, which we don't want in source control, but don't worry about this for now, we'll look at variables and secrets next.
* You can `terraform fmt` command to format your `main.tf` file and `terraform validate` to check the configuration without taking the time to do a plan.

<details><summary>Answer</summary>

```terraform
resource "azurerm_app_service" "main" {
  name                = "<YourName>-terraformed-app-service"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  app_service_plan_id = azurerm_app_service_plan.main.id

  site_config {
    app_command_line = ""
    linux_fx_version = "DOCKER|corndelldevopscourse/mod12app:latest"
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" : "True"
    "DEPLOYMENT_METHOD" : "Terraform"
    "CONNECTION_STRING" : "<Copy me from the existing app service>"
  }
}
```

Note that App Service names need to be globally unique.

</details>

## Step 3: Variables and secrets

Currently we are embedding the password for the database into our Terraform config. That comes with a couple of problems:

* Anyone with access to our source code can also access our database
* We can't use different passwords for different environments without duplicating the Terraform config

Let's define a new variable in `main.tf`:

```terraform
variable "database_password" {
  description = "Database password"
  sensitive   = true
}
```

> Note the `sensitive = true`. This makes sure Terraform will never include the value in its console output.

Now use this variable in our App Service definition instead of hardcoding it in the CONNECTION_STRING app_setting.
You can reference a variable in Terraform by prefixing its name with `var.`, and use `${...}` for interpolating strings, for example:

```terraform
  "CONNECTION_STRING" : "...Password=${var.database_password};..."
```

When you run `terraform plan` (or `terraform apply`) Terraform will ask you to give it the database password. Try running an apply with the correct password and make sure there aren't any changes.

### Tidying up

Traditionally variables are defined inside a separate file called `variables.tf`. This doesn't affect Terraform itself which looks at all `.tf` files in the directory it is run from, but makes it easier for other developers to find things.
Make a new file called `variables.tf` and move the `variable` block into there instead of `main.tf`.

We don't want to have to type in the password every time, so let's make a `terraform.tfvars` file as well with the following contents:

```tfvars
database_password = "<Your database password>"
```

The `terraform.tfvars` file is special and is automatically loaded when Terraform runs in that directory. You can also define other var files and then load them selectively with the `-var-file` command line parameter.

Make sure sensitive configuration files like this are not committed to source control!

## Step 4: Migrate the database

Now we're going to move the SQL Server and Database across to Terraform. Instead of creating a new database instance (and having to backup and restore to it), let's import the existing database into Terraform.

If you were importing a large number of existing resources you can use a tool such as [Terraformer](https://github.com/GoogleCloudPlatform/terraformer) to generate Terraform config.
Since we are only importing a couple of resources we are going to do it manually.

### 4.1 Create Terraform configuration

Start by adapting the example from [the docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/sql_database) to match what you see in the Azure portal.
You'll want an `azurerm_sql_server` and `azurerm_sql_database` resource.
Don't worry about getting every property just right yet, as long as you can run `terraform plan` without errors.

You should see that Terraform wants to create these as new resources when you run `terraform plan`.
Instead we want to migrate the existing database to be managed by Terraform, so we need to import them.

### 4.2 Import the existing resources

Import the existing server and database into Terraform, server first:

* Work out its id
  * browse to it in the Azure portal
  * hit JSON view in the top right
  * press copy next to the "Resource Id"
* Run `terraform import azurerm_sql_server.main <id from above>` (assuming you called the resource "main")

Then do the same for the database, using `azurerm_sql_database` in the import command.

> MinGW (Git Bash for Windows) users may need to disable path expansion to avoid the id being interpreted as a path. Run `export MSYS_NO_PATHCONV=1` in your terminal and then try the import again.

### 4.3 Match the existing resources

Run `terraform plan` again.
Terraform will make a plan to update the existing resources in Azure to match what you have specified in `main.tf`.
Instead update your configuration in `main.tf` so that it matches what is already in Azure and `terraform plan` outputs a (nearly) empty plan.

> Terraform will want to update `create_mode` of the database (which doesn't affect anything here) and the `administrator_login_password` even if it is not changing, since it cannot read the existing password from Azure.

Once you're happy with the changes run `terraform apply` and check your App Service still works.

<details><summary>Answer</summary>

Your Terraform config should look something like this:

```terraform

resource "azurerm_sql_server" "main" {
  name                         = "<your-name>-non-iac-sqlserver"
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "db"
  administrator_login_password = var.database_password
}

resource "azurerm_sql_database" "main" {
  name                = "<your-name>-non-iac-db"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  server_name         = azurerm_sql_server.main.name
  edition             = "Basic"
}
```

</details>

### 4.4 Prevent Destroy

Terraform is a powerful tool that makes it easy to create, change and destroy Cloud resources.
This is generally a great help when managing infrastructure, but also comes with risks.

For example, you might want to update the name of your database - try changing it in your Terraform config now.
If you run `terraform plan` you'll see that the plan involves destroying the existing database, then creating it with a different name, losing all your data in the process!

The [`prevent_destroy`](https://www.terraform.io/docs/language/meta-arguments/lifecycle.html#prevent_destroy) lifecycle argument can help prevent accidental data loss.
Add the following to your configuration for the `azurerm_sql_database` resource:

```terraform
lifecycle {
  prevent_destroy = true
}
```

If you run `terraform plan` now Terraform will error rather than offering to delete your database.

> If you remove the `prevent_destroy` directive from the configuration you'll be able to delete the resource again. That means if you remove the `azurerm_sql_database` resource completely Terraform will still try and destroy it.

### 4.5 Update connection string

Update the `CONNECTION_STRING` App Setting in the App Service Terraform configuration to reference your Database resources rather than being hard coded.

> Terraform resources export attributes that could be helpful here, for example `azurerm_sql_server` exports the [`fully_qualified_domain_name`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/sql_server#fully_qualified_domain_name) attribute.

## (Stretch) Random database password

Use the [`random_password`](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) resource to generate the database password, rather than passing it in as a variable.

Create the `random_password` resource in your `main.tf` file. You'll want to set `min_upper`, `min_lower` and `min_numeric` to at least 1 to make sure you satisfy the password requirements for Azure databases.

Make sure the random password `result` is used by both the Database Server and App Service, then `apply` the changes.

## (Stretch) Store state in Azure blob

Currently all of our infrastructure's state is being stored on your local machine so only you can make consistent changes; neither you nor your teammates will appreciate that if you ever want to go on holiday! We should instead store our state in a shared location that other team members can access.

* Create a Storage Account and Container in your resource group in the Azure portal (manually rather than through Terraform)
* Add the following inside your existing `terraform` block inside `main.tf`

```terraform
backend "azurerm" {
  resource_group_name  = "<resource group name>"
  storage_account_name = "<storage account name>"
  container_name       = "<container name>"
  key                  = "prod.terraform.tfstate"
}
```

* Run `terraform init -migrate-state`

Your Terraform state is now stored in the remote blob and can be used by other developers. Keep in mind that the remote state includes all the details about your infrastructure, including passwords, so you should be careful who you share access with.

## (Stretch) Add a staging environment

One of the big advantages of Infrastructure as Code is that it allows you to easily set up (and tear down) test environments that closely match your production infrastructure. We should make sure we have a staging environment that matches our production infrastructure. We already have a template for that infrastructure, so we'd like to parameterise it to be able to use it in multiple environments. Terraform's solution to managing this is using different [workspaces](https://www.terraform.io/docs/language/state/workspaces.html).

We'll be making our staging environment in the same resource group as our current resources, so will need to give them different names.
Make a new variable called "prefix" and use it to prefix the names of all your resources, e.g. `name = "${var.prefix}-terraformed-asp"`

Create a new Workspace with Terraform and spin up your new environment with a different prefix.
You'll need to find a way to migrate the data from the existing database across, or recreate it in the new database (it's only one table/row), as well as setting up a `azurerm_sql_firewall_rule` so that the App Service can talk to the database.
