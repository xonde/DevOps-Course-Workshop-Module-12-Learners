# 1. Moving existing cloud infrastructure to IaC

> Goal: Setup Pulumi to manage a simple existing App Service and Database

_(Pre-terraformed Azure webapp & db should be available)_

## Set up Pulumi

* [Install Pulumi](https://www.pulumi.com/docs/get-started/install/) 
* We'll use the local backend rather than signing up for pulumi `pulumi login --local`
* For passphrases just set any value for now e.g. "passphrase"
  * Run `export PULUMI_CONFIG_PASSPHRASE=passphrase` in shell or `$ENV:PULUMI_CONFIG_PASSPHRASE="passphrase"` in PowerShell.

## Create project

* `pulumi new azure-python`
* Name: e.g. `move-to-iac`
* Location: `uksouth`


## Import resources

* Confirm the correct status of the existing webapp by browsing to its URL via Azure portal.
* We need to import the existing resources.
* Starting with the resource group
  * First work out its id
      * browse to it in the Azure portal 
      * hit JSON view in the top right
      * Press copy next to the "Resource Id"
  * Then run `pulumi import azure-native:resources:ResourceGroup resource_group <id from above>`
  * This will generate some code that can be copy-pasted into the `__main.py__` file
  * You should delete the existing code and replace with the imported code
> Windows users may have better success using PowerShell, is using git-bash then all commands containing resource-ids need to be prepended with `MSYS_NO_PATHCONV=1`, as per [this known issue](https://stackoverflow.com/questions/54258996/git-bash-string-parameter-with-at-start-is-being-expanded-to-a-file-path).  

* Now repeat that process (appending the outputted code) for each of:
  * `azure-native:web:AppServicePlan`
  * `azure-native:web:WebApp`
  * `azure-native:sql:Server`
  * `azure-native:sql:Database`
* Replace all references to other names and ids with a reference to the other other resource e.g.:
  * `resource_group_name=resource_group.name`
  * `server_name=sqlserver.name`
  * `server_farm_id=app_service_plan.id`
* Remove all 'name' properties - pulumi will generate these for you

## Set up app-database connection
We're going to use the [RandomPassword](https://www.pulumi.com/docs/reference/pkg/random/randompassword/) resource to generate a new random database password.
* Install the provider
  * Add `pulumi-random>=3.1.1` as a new line in your `requirements.txt` file.
  * Run `pulumi-random>=3.1.1 ./venv/Scripts/pip install -r requirements.txt` to [update the dependencies](https://www.pulumi.com/docs/intro/languages/python/#packages) in Pulumi's virtual environment.
* Add a new variable to store the resource:
   ```python
    db_password = random.RandomPassword("db_password", length=16, special=True)
  ```
  > Beware of the location of variable initialisations in the file - they have to be placed above other resources that reference them.
* Use this resource's `result` output in the config for the sqlserver resource
  ```python
  sqlserver = azure_native.sql.Server("sqlserver",
    administrator_login="db",
    administrator_login_password=db_password.result,
    ...
  )
  ```
* Create the connection string as a new variable
  ```python
  connection_string = pulumi.Output.all(sqlserver.fully_qualified_domain_name, db.name, sqlserver.administrator_login, db_password.result) \
      .apply(lambda args: 
          f'Server=tcp:{args[0]},1433;Initial Catalog={args[1]};Persist Security Info=False;User ID={args[2]};Password={args[3]};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
      )
  ```
* Add it as an app setting for the Web App, along with a new value for the `DEPLOYMENT_METHOD` environment variable
  ```python
  site_config = azure_native.web.SiteConfigArgs(
    app_settings=[
        azure_native.web.NameValuePairArgs(name="CONNECTION_STRING", value=connection_string),
        azure_native.web.NameValuePairArgs(name="DEPLOYMENT_METHOD", value="pulumi")
    ]),

  ```

## Redeploy to confirm
* Run `pulumi up`
  > Only a `create` for the `db_password` and `update`s for the sqlserver and webapp should be necessary, if any `delete` or `replace` items are listed in the given preview then abort and double-check your configuration.
* Browse to your webapp's endpoint and confirm the database connection still works, and the `deploymentMethod` output has changed.
  > it may take a few minutes for the new database password to propogate, so if login fails then wait a bit and try again.