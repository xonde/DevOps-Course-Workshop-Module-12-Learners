terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_linux_web_app" "example" {
  name                = "to-do-app-kl"
  resource_group_name = "LV21_KeithLeverton_ProjectExercise"
}

