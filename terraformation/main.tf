terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">=3.43.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "workshop-resource-group" {
  name = "Cohort25_TaiOla_Workshop_M12_Pt2"
}


resource "azurerm_service_plan" "workshop-asp" {
  name                = "taiola-terraformed-asp"
  resource_group_name = data.azurerm_resource_group.workshop-resource-group.name
  location            = data.azurerm_resource_group.workshop-resource-group.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "workshop-lwa" {
  name                = "workshop-lwa"
  resource_group_name = data.azurerm_resource_group.workshop-resource-group.name
  location            = azurerm_service_plan.workshop-asp.location
  service_plan_id     = azurerm_service_plan.workshop-asp.id

  site_config {
    application_stack {
      docker_image = "corndeldevopscourse/mod12app"
      docker_image_tag = "latest"
    }
  }

  app_settings = {
    "CONNECTION_STRING" = "Server=tcp:taiola-non-iac-sqlserver.database.windows.net,1433;Initial Catalog=taiola-non-iac-db;Persist Security Info=False;User ID=dbadmin;Password=${database_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    "DEPLOYMENT_METHOD" = "cli"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "True"
  }
}
