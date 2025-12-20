@description('ShortName is required for a unique storage account name. Only 5 characters.')
param shortName string

@description('Address prefixes for the virtual network.')
param vnetAddressPrefixes array = [
  '192.168.1.0/24'
]

@description('Name of the Azure Firewall subnet.')
param subnetAzureFirewallName string = 'AzureFirewallSubnet'

@description('Address prefix for the Azure Firewall subnet.')
param subnetAzureFirewallPrefix string = '192.168.1.0/26'

@description('Name of the storage subnet.')
param subnetStorageName string = 'storage'

@description('Address prefix for the storage subnet.')
param subnetStoragePrefix string = '192.168.1.64/27'

@description('Name of the web subnet.')
param subnetWebName string = 'app'

@description('Address prefix for the web subnet.')
param subnetWebPrefix string = '192.168.1.96/27'

@description('Name of the Azure Firewall management subnet.')
param subnetAzureFirewallManagementName string = 'AzureFirewallManagementSubnet'

@description('Address prefix for the Azure Firewall management subnet.')
param subnetAzureFirewallManagementPrefix string = '192.168.1.128/26'

@description('Private DNS zone name for the storage account.')
param pdnsName string = 'privatelink.file.core.windows.net'

@description('Blob name for the storage account.')
param blobName string = 'mcjavablob'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Current UTC time, used for resource naming.')
param time string = utcNow()

var mngEnvName = 'cenv-mcjava-${shortName}'
var cappsName = 'capp-mcjava-${shortName}'
var vnetName = 'vnet-mcjava-${shortName}'
var storageAccountName = 'mcjavafiles${shortName}'
var workspaceName = 'law-mcjava-${shortName}'
var cenvpipName = 'cenvpip-mcjava-${shortName}'
var azfwName = 'azfw-mcjava-${shortName}'
var azfwpName = 'azfwp-mcjava-${shortName}'
var azfwpipName = 'azfwpip-mcjava-${shortName}'

// Virtual Network (AVM Module)
module vnet 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: '${time}-privateVnet'
  params: {
    name: vnetName
    addressPrefixes: vnetAddressPrefixes
    subnets: [
      {
        name: subnetAzureFirewallName
        addressPrefix: subnetAzureFirewallPrefix
      }
      {
        name: subnetStorageName
        addressPrefix: subnetStoragePrefix
        privateLinkServiceNetworkPolicies: 'Enabled'
        defaultOutboundAccess: false
      }
      {
        name: subnetWebName
        addressPrefix: subnetWebPrefix
        delegation: 'Microsoft.App/environments'
      }
      {
        name: subnetAzureFirewallManagementName
        addressPrefix: subnetAzureFirewallManagementPrefix
      }
    ]
  }
}

// Private DNS Zone for Storage Account (AVM Module)
module pdnssto 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: '${time}-storagedns'
  params: {
    name: pdnsName
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnet.outputs.resourceId
      }
    ]
  }
}

// Azure Firewall Public IP (AVM Module)
module fwpip 'br/public:avm/res/network/public-ip-address:0.10.0' = {
  name: '${time}-azfwpipDeployment'
  params: {
    // Required parameters
    name: azfwpipName
    // Non-required parameters

    diagnosticSettings: []
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    roleAssignments: []
    skuName: 'Standard'
    skuTier: 'Regional'
  }
}

// Azure Firewall (AVM Module)
module azfw 'br/public:avm/res/network/azure-firewall:0.9.2' = {
  name: '${time}-azureFirewallDeployment'
  params: {
    // Required parameters
    name: azfwName
    azureSkuTier: 'Standard'
    virtualNetworkResourceId: vnet.outputs.resourceId
    location: location
    threatIntelMode: 'Alert'
    firewallPolicyId: firewallPolicy.outputs.resourceId
    publicIPResourceID: fwpip.outputs.resourceId
  }
}

// Firewall Policy (AVM Module)
module firewallPolicy 'br/public:avm/res/network/firewall-policy:0.3.4' = {
  name: 'firewallPolicyDeployment'
  params: {
    // Required parameters
    name: azfwpName
    // Non-required parameters
    allowSqlRedirect: true
    snat: {
      autoLearnPrivateRanges: 'Enabled'
    }
    location: location
    enableTelemetry: true
    enableProxy: true
    ruleCollectionGroups: [
      {
        priority: 1000
        name: 'outbound'
        ruleCollections: [
          {
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            action: {
              type: 'Allow'
            }
            rules: [
              {
                ruleType: 'ApplicationRule'
                name: 'vnet-outbound'
                protocols: [
                  {
                    protocolType: 'Https'
                    port: 443
                  }
                  {
                    protocolType: 'Http'
                    port: 80
                  }
                ]
                fqdnTags: []
                webCategories: []
                targetFqdns: [
                  '*'
                ]
                targetUrls: []
                terminateTLS: false
                sourceAddresses: [
                  subnetWebPrefix
                ]
                destinationAddresses: []
                sourceIpGroups: []
                httpHeadersToInsert: []
              }
            ]
            name: 'vnet-outbound'
            priority: 300
          }
          {
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            action: {
              type: 'Allow'
            }
            rules: [
              {
                ruleType: 'NetworkRule'
                name: 'nrc-containerapp-out'
                ipProtocols: [
                  'TCP'
                  'UDP'
                ]
                sourceAddresses: [
                  subnetWebPrefix
                ]
                sourceIpGroups: []
                destinationAddresses: [
                  'MicrosoftContainerRegistry'
                  'AzureFrontDoorFirstParty'
                  'AzureContainerRegistry'
                  'AzureActiveDirectory'
                  'AzureKeyVault'
                ]
                destinationIpGroups: []
                destinationFqdns: []
                destinationPorts: [
                  '80'
                  '443'
                ]
              }
            ]
            name: 'container-app-outbound'
            priority: 400
          }
        ]
      }
      {
        priority: 1100
        name: 'minecraft-server'
        ruleCollections: [
          {
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            action: {
              type: 'Allow'
            }
            rules: [
              {
                ruleType: 'NetworkRule'
                name: 'nrc-minecraft-server-in'
                ipProtocols: [
                  'TCP'
                ]
                sourceAddresses: [
                  '0.0.0.0/0'
                ]
                sourceIpGroups: []
                destinationAddresses: [
                  managedEnvironment.outputs.staticIp
                ]
                destinationIpGroups: []
                destinationFqdns: []
                destinationPorts: [
                  '25565'
                ]
              }
            ]
            name: 'minecraft-server-in'
            priority: 200
          }
          {
            ruleCollectionType: 'FirewallPolicyNatRuleCollection'
            action: {
              type: 'Dnat'
            }
            rules: [
              {
                ruleType: 'NatRule'
                name: 'minecraft-server'
                translatedAddress: managedEnvironment.outputs.staticIp
                translatedPort: '25565'
                ipProtocols: [
                  'TCP'
                ]
                sourceAddresses: [
                  '*'
                ]
                sourceIpGroups: []
                destinationAddresses: [
                  fwpip.outputs.ipAddress
                ]
                destinationPorts: [
                  '25565'
                ]
              }
            ]
            name: 'nat-minecraft-server'
            priority: 100
          }
        ]
      }
    ]
    tier: 'Standard'
  }
}

// Log Analytics Workspace (AVM Module) with Saved Searches
module workspace 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  name: '${time}-workspaceDeployment'
  params: {
    // Required parameters
    name: workspaceName
    // Non-required parameters
    location: location
  }
}

// Storage Account (AVM Module)
module storageAccount 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: '${time}-storageAccountDeployment'
  params: {
    // Required parameters
    name: storageAccountName
    // Non-required parameters
    allowSharedKeyAccess: true
    allowBlobPublicAccess: true
    blobServices: {
      automaticSnapshotPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 10
      containerDeleteRetentionPolicyEnabled: true
      containers: [
        {
          enableNfsV3AllSquash: true
          enableNfsV3RootSquash: true
          name: blobName
          publicAccess: 'None'
        }
      ]
      deleteRetentionPolicyDays: 9
      deleteRetentionPolicyEnabled: true
      diagnosticSettings: [
        {
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
          name: 'customSetting'

          workspaceResourceId: workspace.outputs.resourceId
        }
      ]
      lastAccessTimeTrackingPolicyEnabled: true
    }
    diagnosticSettings: [
      {
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: 'customSetting'

        workspaceResourceId: workspace.outputs.resourceId
      }
    ]
    enableHierarchicalNamespace: true
    enableNfsV3: true
    enableSftp: true
    fileServices: {
      diagnosticSettings: [
        {
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
          name: 'customSetting'
          workspaceResourceId: workspace.outputs.resourceId
        }
      ]
      shares: [
        {
          accessTier: 'Hot'
          name: 'mcjavashare'
          shareQuota: 5120
        }
      ]
    }
    largeFileSharesState: 'Enabled'
    localUsers: []
    location: location
    managedIdentities: {
      systemAssigned: true
    }
    managementPolicyRules: []
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: pdnssto.outputs.resourceId
            }
          ]
        }
        service: 'file'
        subnetResourceId: vnet.outputs.subnetResourceIds[1]
      }
    ]
    requireInfrastructureEncryption: true
    sasExpirationPeriod: '180.00:00:00'
    skuName: 'Standard_ZRS'
    tags: {
      SecurityControl : 'Ignore'
    }
  }
}

// Container Apps Managed Environment (AVM Module)
module managedEnvironment 'br/public:avm/res/app/managed-environment:0.8.1' = {
  name: '${time}-managedEnvironmentDeployment'
  params: {
    // Required parameters
    name: mngEnvName
    logAnalyticsWorkspaceResourceId: workspace.outputs.resourceId
    // Non-required parameters
    infrastructureSubnetId: vnet.outputs.subnetResourceIds[2]
    internal: true
    location: location
    storages: [
      {
        accessMode: 'ReadWrite'
        storageAccountName: storageAccount.outputs.name
        shareName: 'mcjavashare'
        kind: 'SMB'
      }
    ]
    platformReservedCidr: '172.17.17.0/24'
    platformReservedDnsIP: '172.17.17.17'
    workloadProfiles: [
      {
        maximumCount: 1
        minimumCount: 0
        name: 'CAW01'
        workloadProfileType: 'D4'
      }
    ]
  }
}

// Minecraft Container App (AVM Module)
module minecraft 'br/public:avm/res/app/container-app:0.12.0' = {
  name: '${time}-${cappsName}'
  params: {
    name: cappsName
    containers: [
      {
        image: 'docker.io/itzg/minecraft-server'
        name: 'minecraft-server'
        resources: {
          cpu: json('2')
          memory: '4Gi'
        }
        volumeMounts: [
          {
            volumeName: 'mcjavashare'
            mountPath: '/data'
          }
        ]
        env: [
          { name: 'EULA', value: 'true' }
          { name: 'MEMORY', value: '3G' }
          { name: 'OPS', value: 'mattffffff' }
          { name: 'VERSION', value: '1.21.11' }
          { name: 'VIEW_DISTANCE', value: '16' }
        ]
      }
    ]
    volumes: [
      {
        name: 'mcjavashare'
        storageName: 'mcjavashare'
        storageType: 'AzureFile'
      }
    ]
    ingressTargetPort: 25565
    workloadProfileName: 'CAW01'
    environmentResourceId: managedEnvironment.outputs.resourceId
    scaleMinReplicas: 1
    scaleMaxReplicas: 1
    exposedPort: 25565
    ingressTransport: 'tcp'
    trafficWeight: 100
    trafficLatestRevision: true
  }
}

// Output the Minecraft server endpoint
output minecraftEndpoint string = fwpip.outputs.ipAddress
