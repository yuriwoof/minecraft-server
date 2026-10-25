targetScope = 'resourceGroup'

@description('AZD environment name used in resource names.')
@minLength(2)
@maxLength(15)
param environmentName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Comma-separated allowlist of Java player usernames.')
@secure()
@minLength(1)
param minecraftWhitelist string

@description('Comma-separated Java player usernames granted operator privileges.')
@secure()
@minLength(1)
param minecraftOperators string

@description('Minecraft version to run on Paper.')
param minecraftVersion string = '26.3'

var suffix = uniqueString(subscription().id, resourceGroup().id)
var environmentToken = toLower(replace(environmentName, '_', '-'))
var managedEnvironmentName = take('cae-mc-${environmentToken}-${suffix}', 60)
var containerAppName = take('mc-${environmentToken}-${suffix}', 32)
var storageAccountName = take('mc${suffix}', 24)
var logAnalyticsName = take('law-mc-${environmentToken}-${suffix}', 63)
var vnetName = take('vnet-mc-${environmentToken}-${suffix}', 64)
var filePrivateDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'
var fileShareName = 'worlddata'
var managedIdentitySmbRoleDefinitionId = 'a235d3ee-5935-4cfb-8cc5-a3303ad5995e'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
  }
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'aca-infrastructure'
  properties: {
    addressPrefix: '10.42.0.0/23'
    delegations: [
      {
        name: 'container-apps'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'private-endpoints'
  properties: {
    addressPrefix: '10.42.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource filePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: filePrivateDnsZoneName
  location: 'global'
}

resource filePrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: filePrivateDnsZone
  name: vnet.name
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
      defaultSharePermission: 'None'
      smbOAuthSettings: {
        isSmbOAuthEnabled: true
      }
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        authenticationMethods: 'Kerberos'
        channelEncryption: 'AES-256-GCM'
        encryptionInTransit: {
          required: true
        }
        kerberosTicketEncryption: 'AES-256'
        versions: 'SMB3.1.1'
      }
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource worldShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-01-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    accessTier: 'Hot'
    shareQuota: 100
  }
}

resource storageFilePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: take('pe-${storageAccountName}-file', 64)
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'azure-files'
        properties: {
          groupIds: [
            'file'
          ]
          privateLinkServiceId: storageAccount.id
          requestMessage: 'Private SMB access from the Container Apps environment.'
        }
      }
    ]
    subnet: {
      id: privateEndpointSubnet.id
    }
  }
}

resource storageFileDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-03-01' = {
  parent: storageFilePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azure-files'
        properties: {
          privateDnsZoneId: filePrivateDnsZone.id
        }
      }
    ]
  }
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2026-03-02-preview' = {
  name: managedEnvironmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnet.id
      internal: false
    }
    workloadProfiles: [
      {
        name: 'MC_D4'
        workloadProfileType: 'D4'
        minimumCount: 0
        maximumCount: 1
      }
    ]
  }
}

resource storageSmbAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedEnvironment.id, managedIdentitySmbRoleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', managedIdentitySmbRoleDefinitionId)
    principalId: managedEnvironment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource managedEnvironmentStorage 'Microsoft.App/managedEnvironments/storages@2026-03-02-preview' = {
  parent: managedEnvironment
  name: 'worlddata'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      identity: 'system'
      shareName: fileShareName
      accessMode: 'ReadWrite'
    }
  }
  dependsOn: [
    storageSmbAdminRole
    worldShare
    storageFileDnsZoneGroup
    filePrivateDnsVnetLink
  ]
}

resource minecraftServer 'Microsoft.App/containerApps@2025-01-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: managedEnvironment.id
    workloadProfileName: 'MC_D4'
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'minecraft-whitelist'
          value: minecraftWhitelist
        }
        {
          name: 'minecraft-operators'
          value: minecraftOperators
        }
      ]
      ingress: {
        external: true
        targetPort: 25565
        exposedPort: 25565
        transport: 'tcp'
      }
    }
    template: {
      terminationGracePeriodSeconds: 120
      containers: [
        {
          name: 'paper-server'
          image: 'itzg/minecraft-server:java25'
          resources: {
            cpu: json('2')
            memory: '4Gi'
          }
          env: [
            { name: 'EULA', value: 'TRUE' }
            { name: 'TYPE', value: 'PAPER' }
            { name: 'VERSION', value: minecraftVersion }
            { name: 'ONLINE_MODE', value: 'true' }
            { name: 'ENABLE_WHITELIST', value: 'true' }
            { name: 'ENFORCE_WHITELIST', value: 'true' }
            { name: 'WHITELIST', secretRef: 'minecraft-whitelist' }
            { name: 'OPS', secretRef: 'minecraft-operators' }
            { name: 'ENABLE_RCON', value: 'false' }
            { name: 'ENABLE_COMMAND_BLOCK', value: 'false' }
            { name: 'MAX_PLAYERS', value: '10' }
            { name: 'VIEW_DISTANCE', value: '8' }
            { name: 'SIMULATION_DISTANCE', value: '6' }
            { name: 'MEMORY', value: '3G' }
            { name: 'TZ', value: 'Asia/Tokyo' }
          ]
          volumeMounts: [
            {
              volumeName: 'worlddata'
              mountPath: '/data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'worlddata'
          storageType: 'AzureFile'
          storageName: last(split(managedEnvironmentStorage.id, '/'))
        }
      ]
    }
  }
}

output minecraftEndpoint string = '${minecraftServer.properties.configuration.ingress.fqdn}:25565'
output containerAppName string = minecraftServer.name
output storageAccountName string = storageAccount.name
output fileShareName string = fileShareName
