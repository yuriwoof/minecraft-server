@description('Virtual Machine Name')
param vmName string

@description('Username for VM')
param adminUsername string = 'azureuser'

@description('Type of authentication to user on the VM.')
@allowed(['password', 'sshPublicKey'])
param authenticationType string = 'sshPublicKey'

@description('SSH Public Key to use for authentication')
@secure()
param adminPasswordOrKey string

@description('The Suse version for VM.')
@allowed(['ubuntu2204'])
param osVersion string = 'ubuntu2204'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Size of VM')
param vmSize string = 'Standard_D2_v4'

@description('Name of the virtual network')
param virtualNetworkName string

@description('Name of subnet')
param subnetName string

@description('Source address for security group')
param srcAddress string

var imageReference = {
  ubuntu2204: {
    publisher: 'Canonical'
    offer: '0001-com-ubuntu-server-jammy'
    sku: '22_04-lts-gen2'
    version: 'latest'
  }
}

var publicIPAddressName = '${vmName}-pip'
var networkInterfaceName = '${vmName}-nic'
var osDiskType = 'Standard_LRS'

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}

// for cloud-init custom data
var cloudInit = base64(loadTextContent('./installdocker.txt'))

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: virtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name:  'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: srcAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'mc-java'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 110
          protocol: 'Tcp'
          sourceAddressPrefix: srcAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '25565'
        }
      }
      {
        name: 'mc-bedrock'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 120
          protocol: 'Udp'
          sourceAddressPrefix: srcAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '19132'
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
          publicIPAddress: {
            id: publicIPAddress.id
          }
          
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
      }
      imageReference: imageReference[osVersion]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
      customData: cloudInit
    }
    //priority: 'Spot'
    //evictionPolicy: 'Deallocate'
    //billingProfile: {
    //  maxPrice: -1
    //}
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
