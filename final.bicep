targetScope = 'resourceGroup'

param authClientId string

@secure()
param authClientSecret string

var uniqueAppName = uniqueString(resourceGroup().id)
var functionAppName = 'secure-${uniqueAppName}'
var appServicePlanName = 'secure-asp'
var appInsightsName = 'secure-ai'
var sqlserverName = 'secure-${uniqueAppName}'
var storageAccountName = 'secure${uniqueAppName}'
var databaseName = 'secure-db'
var keyVaultName = 'secure${uniqueAppName}'
var virtualNetworkName = 'secure-vnet'

var sqlAdministratorLogin = 'adminuser'
var sqlAdministratorLoginPassword = 'Ab!${uniqueString(resourceGroup().id)}${uniqueString(resourceGroup().id)}'

var keyVaultSecretsUserRoleDefinitionGuid = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsUserRoleDefinitionId = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${keyVaultSecretsUserRoleDefinitionGuid}'

var msProviderAuthSecretName = 'msProviderAuthSecret'
var storageAccountConnectionStringSecretName = 'storageAccountConnectionStringSecret'

var sourceControlRepoUrl = 'https://github.com/arincoau/four-tips-securing-serverless.git'
var sourceControlBranch = 'main'

var azureSqlPrivateDnsZone = 'privatelink.database.windows.net'
var keyVaultPrivateDnsZone = 'privatelink.vaultcore.azure.net'
var privateDnsZoneNames = [
  azureSqlPrivateDnsZone
  keyVaultPrivateDnsZone
]

resource sqlServer 'Microsoft.Sql/servers@2019-06-01-preview' = {
  name: sqlserverName
  location: resourceGroup().location
  properties: {
    publicNetworkAccess: 'Disabled'
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    version: '12.0'
  }

  resource database 'databases@2021-02-01-preview' = {
    name: databaseName
    location: resourceGroup().location
    sku: {
      name: 'Basic'
      tier: 'Basic'
    }
    properties: {
      sampleName: 'AdventureWorksLT'
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2018-02-01' = {
  name: appServicePlanName
  location: resourceGroup().location
  sku: {
    name: 'EP1'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName
  location: resourceGroup().location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  resource fileServices 'fileServices@2021-04-01' = {
    name: 'default'

    resource fileShare 'shares@2021-04-01' = {
      name: functionApp.name
    }
  }
}

resource functionApp 'Microsoft.Web/sites@2021-01-15' = {
  name: functionAppName
  location: resourceGroup().location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      vnetRouteAllEnabled: true
    }
  }

  resource appSettings 'config@2021-01-15' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageAccountConnectionStringSecretName})'      
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageAccountConnectionStringSecretName})'      
      APPINSIGHTS_INSTRUMENTATIONKEY: '${applicationInsights.properties.InstrumentationKey}'
      WEBSITE_CONTENTSHARE: '${functionApp.name}'
      WEBSITE_SKIP_CONTENTSHARE_VALIDATION: '1'
      FUNCTIONS_EXTENSION_VERSION: '~3'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet'
      SCM_COMMAND_IDLE_TIMEOUT: '10000'
      WEBJOBS_IDLE_TIMEOUT: '10000'
      MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${msProviderAuthSecretName})'      
      UseManagedIdentity: 'true'
    }
  }

  resource connectionstrings 'config@2021-01-15' = {
    name: 'connectionstrings'
    properties: {
      AdventureWorks: {
        type: 'SQLAzure'
        value: 'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Database=${databaseName}'
      }
    }
  }

  resource sourceControl 'sourcecontrols@2020-12-01' = {
    name: 'web'
    properties: {
      repoUrl: sourceControlRepoUrl
      branch: sourceControlBranch
      isManualIntegration: true
    }

    dependsOn: [
      appSettings
      connectionstrings
    ]
  }

  resource authSettings 'config@2020-12-01' = {
    name: 'authsettingsV2'
    properties: {
      globalValidation: {
        requireAuthentication: true
        unauthenticatedClientAction: 'Return401'
        redirectToProvider: 'azureactivedirectory'
      }
      
  
      identityProviders: {
        azureActiveDirectory: {
          enabled: true
          registration: {
            openIdIssuer: 'https://sts.windows.net/${subscription().tenantId}'
            clientId: authClientId
            clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          }
          validation: {
            allowedAudiences: [
              'api://${authClientId}'
            ]
          }
        }
      }
    }
  }

  resource functionAppVirtualNetwork 'networkConfig@2020-06-01' = {
    name: 'virtualNetwork'
    properties: {
      subnetResourceId: virtualNetwork.properties.subnets[0].id
      swiftSupported: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  kind: 'web'
  location: resourceGroup().location
  properties: {
    Application_Type: 'web'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }

  resource msProviderAuthSecret 'secrets@2021-04-01-preview' = {
    name: msProviderAuthSecretName
    properties: {
      value: authClientSecret
    }
  }
  
  resource storageAccountConnectionStringSecret 'secrets@2021-04-01-preview' = {
    name: storageAccountConnectionStringSecretName
    properties: {
      value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
    }
  }
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleDefinitionGuid, functionApp.name)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: virtualNetworkName
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'web'
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2018-09-01' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: privateDnsZoneName
  location: 'global'
  dependsOn: [
    virtualNetwork
  ]
}]

resource virtualNetworkLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (privateDnsZoneName, i) in privateDnsZoneNames: {
  parent: privateDnsZones[i]
  location: 'global'
  name: 'link-to-${virtualNetwork.name}'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}]

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${sqlServer.name}-sql-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${sqlServer.name}-sql-pe-conn'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', azureSqlPrivateDnsZone)
          }
        }
      ]
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${keyVault.name}-kv-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVault.name}-kv-pe-conn'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', keyVaultPrivateDnsZone)
          }
        }
      ]
    }
  }
}

output functionAppTestUrl string = 'https://${functionApp.properties.defaultHostName}/api/TopFiveProducts'
output functionAppName string = '${functionApp.name}'
output sqlServerName string = '${sqlServer.name}'
