terraform {
  required_version = ">= 1.16.0, < 2.0.0"
  # Separate from the original GCP terraform.tfstate; do not migrate GCP state.
  backend "local" {
    path = "azure.tfstate"
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.4.0"
    }
  }
}

# Authenticate locally using az login.
provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

# Same topology as the original: Kafka, Airflow, Spark Master and two Workers.
# Azure has no Dataproc resource; Spark nodes are ordinary VMs here.
locals {
  vm_sizes = {
    kafka          = var.kafka_vm_size
    airflow        = var.airflow_vm_size
    spark-master   = var.spark_vm_size
    spark-worker-1 = var.spark_vm_size
    spark-worker-2 = var.spark_vm_size
  }
  # Kafka retains broker data and container images locally, so only its OS disk
  # receives the additional 30 GiB.
  vm_os_disk_sizes = {
    kafka          = 62
    airflow        = 32
    spark-master   = 32
    spark-worker-1 = 32
    spark-worker-2 = 32
  }
  # Deterministic, globally unique, and avoids Azure SDK endpoint keywords.
  iceberg_storage_account_name = "stfice${substr(sha1(var.subscription_id), 0, 12)}"
}

resource "azurerm_resource_group" "main" {
  name     = "streamify-rg"
  location = var.location
}

# Azure VMs need a VNet, subnet and NIC; the GCP project used its default network.
resource "azurerm_virtual_network" "main" {
  name                = "streamify-vnet"
  address_space       = ["10.42.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "main" {
  name                 = "services"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_network_security_group" "main" {
  name                = "streamify-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  security_rule {
    name                       = "SSHFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }
  # Default rules allow private VNet traffic and deny other Internet ingress.
  # Kafka/Spark communicate using private IPs. Access web UIs through SSH tunnels.
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Public IPs provide SSH and outbound downloads without a separate NAT Gateway.
resource "azurerm_public_ip" "vm" {
  for_each            = local.vm_sizes
  name                = "streamify-${each.key}-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vm_sizes
  name                = "streamify-${each.key}-nic"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm[each.key].id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = local.vm_sizes
  name                            = "streamify-${each.key}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = each.value
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }
  identity { type = "SystemAssigned" }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = local.vm_os_disk_sizes[each.key]
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  depends_on = [azurerm_subnet_network_security_group_association.main]
}

# ADLS Gen2 (abfss://).
resource "azurerm_storage_account" "lake" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  # Authenticated access from the future Snowflake account on AWS.
  public_network_access_enabled = true
}

# Like the original bucket: events and checkpoint/ share one container.
resource "azurerm_storage_container" "lake" {
  name                  = "streamify"
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# Keep Iceberg on a separate HNS-enabled account from event files and checkpoints.
resource "azurerm_storage_account" "iceberg" {
  name                            = local.iceberg_storage_account_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
}

resource "azurerm_storage_container" "iceberg" {
  name                  = "streamify-iceberg"
  storage_account_id    = azurerm_storage_account.iceberg.id
  container_access_type = "private"
}

# Spark Structured Streaming state is kept outside the Polaris-managed table
# container so that checkpoint and Iceberg table lifecycles remain independent.
resource "azurerm_storage_container" "iceberg_checkpoints" {
  name                  = "streamify-checkpoints"
  storage_account_id    = azurerm_storage_account.iceberg.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "polaris_iceberg_storage" {
  # Polaris creates user-delegation SAS tokens before it can downscope them to
  # an HNS directory. Azure authorizes that signing action at account scope.
  scope                = azurerm_storage_account.iceberg.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.polaris_service_principal_object_id
  principal_type       = "ServicePrincipal"
}

# Runtime identities: no downloaded service-account key is needed.
resource "azurerm_role_assignment" "spark_storage" {
  for_each             = toset(["spark-master", "spark-worker-1", "spark-worker-2"])
  scope                = azurerm_storage_container.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.vm[each.key].identity[0].principal_id
}

resource "azurerm_role_assignment" "spark_iceberg_checkpoint_storage" {
  for_each             = toset(["spark-master", "spark-worker-1", "spark-worker-2"])
  scope                = azurerm_storage_container.iceberg_checkpoints.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.vm[each.key].identity[0].principal_id
}

resource "azurerm_role_assignment" "airflow_storage" {
  scope                = azurerm_storage_container.lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_virtual_machine.vm["airflow"].identity[0].principal_id
}

resource "azurerm_role_assignment" "admin_storage_reader" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.admin_object_id
  principal_type       = "User"
}

resource "azurerm_role_assignment" "admin_iceberg_storage_reader" {
  scope                = azurerm_storage_account.iceberg.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.admin_object_id
  principal_type       = "User"
}
