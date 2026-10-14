resource "azurerm_public_ip" "bastion" {
  name                = "pip-pandora-bas-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  name                = "bas-pandora-hub-01"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
