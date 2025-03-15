terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}


terraform {
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "akashfaldu"

    workspaces {
      name = "default"
    }
  }
}

locals {
  resource_group="app-grp"
  location="East US 2"
}

resource "azurerm_resource_group" "app_grp"{
  name=local.resource_group
  location=local.location
}

resource "azurerm_virtual_network" "app_network" {
  name                = "app-network"
  location            = local.location
  resource_group_name = azurerm_resource_group.app_grp.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "example" {
  name                 = "SubnetA"
  resource_group_name  = azurerm_resource_group.app_grp.name
  virtual_network_name = azurerm_virtual_network.app_network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "app_vm_ip" {
  name                = "app-vm-public-ip"
  location            = local.location
  resource_group_name = azurerm_resource_group.app_grp.name
  allocation_method   = "Dynamic"
}



resource "azurerm_network_interface" "app_interface" {
  name                = "app-interface"
  location            = local.location
  resource_group_name = local.resource_group

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app_vm_ip.id  # Attach the public IP here
  }

  depends_on = [
    azurerm_virtual_network.app_network
  ]
}


resource "azurerm_linux_virtual_machine" "app_vm" {
  name                = "appvm"
  resource_group_name = local.resource_group
  location            = local.location
  size                = "Standard_F2"
  admin_username      = "demousr"
  admin_password      = "Azure@123"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.app_interface.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.app_interface
  ]
}

#Blob Storage
resource "azurerm_storage_account" "stoacc" {
  name                     = "examplestoraccakash"
  resource_group_name      = azurerm_resource_group.app_grp.name
  location                 = azurerm_resource_group.app_grp.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "stocon" {
  name                  = "content"
  storage_account_name    = azurerm_storage_account.stoacc.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "stoblob" {
  name                   = "demo.txt"
  storage_account_name   = azurerm_storage_account.stoacc.name
  storage_container_name = azurerm_storage_container.stocon.name
  type                   = "Block"
  source                 = "demo.txt"
}



# Create a Storage File Share
resource "azurerm_storage_share" "fileshare" {
  name                 = "terraform-fileshare"
  storage_account_name = azurerm_storage_account.stoacc.name
  quota               = 50  # Size in GB
}

# Create a Custom Script Extension to Mount File Share
resource "azurerm_virtual_machine_extension" "mount_fileshare" {
  name                 = "mountFileShare"
  virtual_machine_id   = azurerm_linux_virtual_machine.app_vm.id
  publisher           = "Microsoft.Azure.Extensions"
  type                = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
      "commandToExecute": "mkdir /mnt/azure && sudo mount -t cifs //${azurerm_storage_account.stoacc.name}.file.core.windows.net/${azurerm_storage_share.fileshare.name} /mnt/azure -o vers=3.0,username=${azurerm_storage_account.stoacc.name},password=${azurerm_storage_account.stoacc.primary_access_key},dir_mode=0777,file_mode=0777"
    }
  SETTINGS
}


# SQL Server Configuration
resource "azurerm_sql_server" "sqlserver" {
  name                         = "sqlserverakash"
  resource_group_name          = azurerm_resource_group.app_grp.name
  location                     = azurerm_resource_group.app_grp.location
  version             = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "Azure@123"
}

resource "azurerm_sql_database" "app_db" {
  name                = "appdb"
  resource_group_name = azurerm_resource_group.app_grp.name
  location            = azurerm_resource_group.app_grp.location
  server_name         = azurerm_sql_server.sqlserver.name
   depends_on = [
     azurerm_sql_server.sqlserver
   ]
}

resource "azurerm_sql_firewall_rule" "app_server_firewall_rule" {
  name                = "app-server-firewall-rule"
  resource_group_name = azurerm_resource_group.app_grp.name
  server_name         = azurerm_sql_server.sqlserver.name
  start_ip_address    = azurerm_linux_virtual_machine.app_vm.public_ip_address
  end_ip_address      = azurerm_linux_virtual_machine.app_vm.public_ip_address
}


output "instance_ip" {
  value = azurerm_linux_virtual_machine.app_vm.public_ip_address
}
                                                                                         
