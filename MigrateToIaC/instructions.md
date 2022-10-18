# 2. Moving existing cloud infrastructure to IaC

> Goal: Setup Terraform to manage an existing App Service and Database

## Outline

This exercise is separate from the morning exercise - you should find that some Azure resources have been created for you in a new resource group with a name ending in "M12_Pt2". This consists of an App Service and associated App Service Plan with "non-iac" in the name, along with an SQL Database and associated SQL Server.

During this exercise we will:

* Use Terraform to create a new App Service and associated App Service Plan
* Import the existing SQL Database and SQL Server so that we can manage them with Terraform

## Step 1: Setup

### Install terraform

* [Download terraform](https://www.terraform.io/downloads.html)
  * There is no installer, extract the zip and put terraform.exe in a folder that is on your PATH
  * Verify it is installed by running `terraform -version`
* Install an extension for Terraform in VSCode
  * There are a few options, any will do, we just want syntax highlighting

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
You should not add the `.terraform` directory to source control, although you can commit the `terraform.lock.hcl` which records the exact provider version used.

### Add your Resource Group

We are not going to have Terraform manage the Resource Group, and will instead just tell Terraform that it exists with a `data` block.

Add the following to your `main.tf`, using the resource group name for this part of the workshop, which should end with "M12_Pt2".

```terraform
data "azurerm_resource_group" "main" {
  name = "<Your resource group name>"
}
```

> Keep the quotes around the resource group name, but not the angle brackets.

Save your changes and run `terraform plan`. Terraform will connect to Azure and check that it can find the resource group. You should see an output like

```text
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

Running `terraform plan` will never make any changes, so it's always safe to run, unlike `terraform apply`.

## Step 2: Create a new App Service

First go and have a look at the existing resources for this exercise (in your "M12_Pt2" Resource Group) in the Azure portal.
We will be basing our Terraform config on these existing resources.

If you open up the existing App Service you should see a response like

```json
{"currentDate":"Tuesday, 26 October 2021 10:31","status":"Successfully connected to the db containing info for Module 12 Workshop","deploymentMethod":"cli"}
```

We're going to create a new instance of the App Service Plan and App Service that are managed by Terraform.

### App Service Plan (ASP)

Unlike with ARM templates we can't export Terraform from the Azure portal.
Fortunately it is a little easier to write ourselves.
To get you started, here is Terraform config for an App Service Plan.  
Add the following to your `main.tf` file, updating the name as appropriate:

```terraform
resource "azurerm_app_service_plan" "main" {
  name                = "<YourName>-terraformed-asp"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  kind                = "Linux"
  reserved            = true

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

* The existing App Service is running a Docker image. If you navigate to the App Service (not the App Service Plan) in the Azure portal and then click on "Deployment Center" you'll see the image name.
* The app_settings block will need to include the connection string for the database, which you can get from the "Configuration" tab in the Azure portal. This includes the database password, which we don't want in source control, but don't worry about this for now, we'll look at variables and secrets next.
* Set the `DEPLOYMENT_METHOD` environment variable (`app_setting`) to e.g. `"Terraform"`.
* Ignore the `connection_string` block in the Terraform documentation example. We will pass our connection string in via the `app_settings` block.
* You can use the `terraform fmt` command to format your `main.tf` file and `terraform validate` to check the configuration without taking the time to do a plan.

Note that App Service names need to be globally unique.

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

You could use `=` instead of `:` inside the `app_settings` block, this will work just as well.

</details>

## Step 3: Variables and secrets

Currently we are embedding the password for the database into our Terraform config as part of the connection string. That comes with a couple of problems:

* Anyone with access to our source code can also access our database
* We can't use different passwords for different environments without duplicating the Terraform config

In Terraform we can use variables to avoid hard coding values in our config, they act similarly to ARM Template parameters.
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

When you run `terraform plan` (or `terraform apply`) Terraform will ask you to give it the database password. Try running an apply with the correct password and make sure there aren't any changes - though Terraform might report it expects to change things because the variable has been marked as sensitive.

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
You'll want to add an `azurerm_sql_server` and `azurerm_sql_database` resource to your existing config.
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

**Do not delete your existing server or database!** If Terraform says it's going to destroy something then you still need to change your config to match Azure.

<details><summary>Answer</summary>

Your Terraform config should look like this:

```terraform

resource "azurerm_sql_server" "main" {
  name                         = "<your-name>-non-iac-sqlserver"
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "dbadmin"
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

Make sure the names of the resources exactly match what already exists in Azure.

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

If you run `terraform plan` now, after changing the database name, Terraform will error rather than offering to delete your database.

> If you remove the `prevent_destroy` directive from the configuration you'll be able to delete the resource again. That means if you remove the `azurerm_sql_database` resource completely Terraform will still try and destroy it.

### 4.5 Update connection string

Update the `CONNECTION_STRING` App Setting in the App Service Terraform configuration to reference your Database resources rather than being hard coded.

> Terraform resources export attributes that could be helpful here, for example `azurerm_sql_server` exports the [`fully_qualified_domain_name`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/sql_server#fully_qualified_domain_name) attribute.

## Next steps

You've reached the end of the exercise!

You can either:

* Carry on with the stretch goals below
* [Have a go at using Pulumi](./Pulumi/instructions.md), a Python based Infrastructure as Code tool

## (Stretch) Outputs

Terraform has a concept of [Output Values](https://www.terraform.io/docs/language/values/outputs.html) that are printed out when you run a plan or apply.
These are useful if there are values that you need to feed into another system, or if you start splitting up your Terraform config into modules.

Let's try it out. Add a new file called `outputs.tf` (this file name is also just convention), and add an output definition:

```terraform
output "webapp_hostname" {
  value = azurerm_app_service.main.default_site_hostname
}
```

If you run `terraform apply` you should see your site hostname printed out at the end of the console output.

## (Stretch) Random database password

Use the [`random_password`](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) resource to generate the database password, rather than passing it in as a variable.

Create the `random_password` resource in your `main.tf` file. You'll want to set `min_upper`, `min_lower` and `min_numeric` to at least 1 to make sure you satisfy the password requirements for Azure databases.

Make sure the random password `result` is used by both the Database Server and App Service, then `apply` the changes.

## (Stretch) Store state in Azure blob

Currently all of our infrastructure's state is being stored on your local machine so only you can make changes; neither you nor your teammates will appreciate that if you ever want to go on holiday! We should instead store our state in a shared location that other team members can access.

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

One of the big advantages of Infrastructure as Code is that it allows you to easily set up (and tear down) test environments that closely match your production infrastructure.
Let's set up a staging environment that matches out current infrastructure using our Terraform config.

We will need to give resources in our staging environment different names in Azure so they don't clash with our existing infrastructure.
It's up to you how you do this, but a common way is to define a "prefix" variable and start all the names of your resources with that prefix, e.g `name = "${var.prefix}-terraformed-asp"`.
If your existing resources don't have a common prefix, then your prefix can be the empty string for this set of infrastructure.

Once you've done that, we need a way of managing separate environments from the same Terraform config. One way of managing multiple environments with Terraform is using [workspaces](https://www.terraform.io/docs/language/state/workspaces.html).
Have a read of the documentation and create a new Terraform workspace.

Bring up another copy of your infrastructure with a different prefix, in this new workspace.

You'll need to find a way to migrate the data from the existing database across, or recreate it in the new database (it's only one table/row), as well as setting up a `azurerm_sql_firewall_rule` so that the App Service can talk to the database.
