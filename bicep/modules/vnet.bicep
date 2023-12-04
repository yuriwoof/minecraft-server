@description('Location')
param location string = resourceGroup().location

@description('Name of the virtual network')
param virtualNetworkName string

@description('Address prefix of vnet')
param addressPrefix string

@description('Name of the subnet')
param subnetName string

@description('Address prefix of subnet')
param subnetAddressPrefix string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: virtualNetwork
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
  }
}
