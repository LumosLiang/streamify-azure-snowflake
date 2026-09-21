variable "subscription_id" {
  description = "Your Visual Studio Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region; southeastasia is Singapore."
  type        = string
  default     = "southeastasia"
}

variable "storage_account_name" {
  description = "Globally unique name: 3-24 lowercase letters and digits."
  type        = string
}

variable "admin_object_id" {
  description = "Microsoft Entra object ID of the user allowed to inspect Blob data."
  type        = string
}

variable "polaris_service_principal_object_id" {
  description = "Microsoft Entra object ID of the Polaris storage service principal."
  type        = string
}

variable "admin_username" {
  type    = string
  default = "streamify"
}

variable "ssh_public_key_path" {
  description = "Public key for SSH into the VMs, not an Azure login credential."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_source_cidr" {
  description = "Your Singapore public exit IPv4 followed by /32."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_source_cidr)) && can(regex("/32$", var.admin_source_cidr))
    error_message = "Use your actual public IPv4 followed by /32."
  }
}

variable "kafka_vm_size" {
  type    = string
  default = "Standard_D4as_v5"
}

variable "airflow_vm_size" {
  type    = string
  default = "Standard_E2as_v5"
}

variable "spark_vm_size" {
  description = "Size for each Spark Master/Worker VM."
  type        = string
  default     = "Standard_D2as_v5"
}
