terraform {
  required_version = ">= 1.5.0"
  
  backend "azurerm" {
    resource_group_name  = "rg-lino-mgmt-dev"
    storage_account_name = "stlinodevstate001"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
    use_oidc             = true 
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = "2771fe12-797d-4e21-93ee-cdde0c0306f9" 
}

provider "archive" {}