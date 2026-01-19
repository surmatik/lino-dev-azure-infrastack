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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }

    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
  
  subscription_id = "2771fe12-797d-4e21-93ee-cdde0c0306f9"
}