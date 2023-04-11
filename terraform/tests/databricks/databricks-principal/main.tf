/**
* Tests for the databricks-principal module
*/
provider "azurerm" {
  features {}
}

terraform {
  required_version = "~> 1.4"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.12"
    }
  }
}

# Minimum of variables required for the test
variable "azure_location" { default = "westeurope" }
variable "resource_group_name" { default = null }
variable "databricks_workspace_name" { default = null }

# Create a random string for test uniqueness
resource "random_string" "suffix" {
  length  = 10
  numeric = true
  lower   = true
  upper   = false
  special = false
}

# Create a random uuid to be used as the service principal client id
resource "random_uuid" "sp_client_id" {}

# Set the rest of the test variables using the random string
locals {
  resource_group_name       = var.resource_group_name == null ? "tftest-rg-${random_string.suffix.result}" : var.resource_group_name
  databricks_workspace_name = var.databricks_workspace_name == null ? "tftest-ws-${random_string.suffix.result}" : var.databricks_workspace_name
  group_defaults         = "TF Test ${random_string.suffix.result}"
  user_defaults          = "userdefault.${random_string.suffix.result}@example.com"
  user_with_group        = "usermember.${random_string.suffix.result}@example.com"
  user_with_entitlements = "userentitlements.${random_string.suffix.result}@example.com"
}

# Create an empty Resource Group to be used by the rest of the resources
data "azurerm_client_config" "current" {}

module "test_resource_group" {
  source              = "../../../modules/azure/resource-group"
  azure_location      = var.azure_location
  resource_group_name = local.resource_group_name
  owners              = [data.azurerm_client_config.current.object_id]
}

# Build a Databricks workspace with default parameters
module "test_databricks_workspace_defaults" {
  source              = "../../../modules/azure/databricks-workspace"
  resource_group_name = module.test_resource_group.name
  workspace_name      = local.databricks_workspace_name
}

# Marker for test dependencies
resource "null_resource" "test_dependencies" {
  triggers   = {
    uuid = random_uuid.sp_client_id.id
    ws   = module.test_databricks_workspace_defaults.id
  }
  depends_on = [
    random_uuid.sp_client_id,
    module.test_databricks_workspace_defaults
  ]
}

# Get information about the Databricks workspace
data "azurerm_databricks_workspace" "main" {
  name                = local.databricks_workspace_name
  resource_group_name = local.resource_group_name
  depends_on          = [null_resource.test_dependencies]
}

# Configure the Databricks Terraform provider
provider "databricks" {
  host = data.azurerm_databricks_workspace.main.workspace_url
}

# Build a Group with default parameters
module "test_group_defaults" {
  source               = "../../../modules/databricks/databricks-principal"
  principal_type       = "group"
  principal_identifier = local.group_defaults
  depends_on           = [null_resource.test_dependencies]
}

# Build a User with default parameters
module "test_user_defaults" {
  source               = "../../../modules/databricks/databricks-principal"
  principal_type       = "user"
  principal_identifier = local.user_defaults
  depends_on           = [null_resource.test_dependencies]
}

# Build a Service Principal with default parameters
module "test_sp_defaults" {
  source               = "../../../modules/databricks/databricks-principal"
  principal_type       = "service_principal"
  principal_identifier = random_uuid.sp_client_id.result
  depends_on           = [null_resource.test_dependencies]
}

# Build a User that is part of a group
module "test_user_with_group" {
  source               = "../../../modules/databricks/databricks-principal"
  principal_type       = "user"
  principal_identifier = local.user_with_group
  groups               = [local.group_defaults]
  depends_on           = [module.test_group_defaults]
}

# Build a User with all supported entitlements
module "test_user_with_entitlements" {
  source                     = "../../../modules/databricks/databricks-principal"
  principal_type             = "user"
  principal_identifier       = local.user_with_entitlements
  allow_cluster_create       = true
  allow_instance_pool_create = true
  databricks_sql_access      = true
  depends_on                 = [null_resource.test_dependencies]
}

# Terraform output
output "databricks_principal_tests" {
  value = {
    test_group_defaults = {
      id      = module.test_group_defaults.id
      name    = local.group_defaults
      groups  = module.test_group_defaults.membership
      details = module.test_group_defaults.details
    }
    test_user_defaults = {
      id      = module.test_user_defaults.id
      name    = local.user_defaults
      groups  = module.test_user_defaults.membership
      details = module.test_user_defaults.details
    }
    test_sp_defaults = {
      id      = module.test_sp_defaults.id
      name    = random_uuid.sp_client_id.result
      groups  = module.test_sp_defaults.membership
      details = module.test_sp_defaults.details
    }
    test_user_with_group = {
      id      = module.test_user_with_group.id
      name    = local.user_with_group
      groups  = module.test_user_with_group.membership
      details = module.test_user_with_group.details
    }
    test_user_with_entitlements = {
      id      = module.test_user_with_entitlements.id
      name    = local.user_with_entitlements
      groups  = module.test_user_with_entitlements.membership
      details = module.test_user_with_entitlements.details
    }
  }
}
