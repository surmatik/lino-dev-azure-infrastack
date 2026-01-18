variable "location" {
  type    = string
  default = "westeurope"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "Lino-DevInfra"
    Environment = "Dev"
    Owner       = "Lino"
    ManagedBy   = "Terraform"
  }
}