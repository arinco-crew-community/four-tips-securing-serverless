targetScope = 'resourceGroup'

param authClientId string

@secure()
param authClientSecret string

var functionAppName = 'secure-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'secure-asp'
var appInsightsName = 'secure-ai'
var sqlserverName = 'secure-${uniqueString(resourceGroup().id)}'
var storageAccountName = 'secure${uniqueString(resourceGroup().id)}'
var databaseName = 'secure-db'

var sqlAdministratorLogin = 'adminuser'
var sqlAdministratorLoginPassword = 'Ab!${uniqueString(resourceGroup().id)}${uniqueString(resourceGroup().id)}'

var sourceControlRepoUrl = 'https://github.com/arincoau/four-tips-securing-serverless'
var sourceControlBranch = 'main'

resource sqlServer 'Microsoft.Sql/servers@2019-06-01-preview' = {
  name: sqlserverName
  location: resourceGroup().location
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    version: '12.0'
  }

  resource firewallRules 'firewallRules@2021-02-01-preview' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }

  resource database 'databases@2021-02-01-preview' = {
    name: databaseName
    location: resourceGroup().location
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
  kind: 'Storage'
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
  }

  resource appSettings 'config@2021-01-15' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      APPINSIGHTS_INSTRUMENTATIONKEY: '${applicationInsights.properties.InstrumentationKey}'
      WEBSITE_SKIP_CONTENTSHARE_VALIDATION: '1'
      WEBSITE_CONTENTSHARE: '${functionApp.name}'
      FUNCTIONS_EXTENSION_VERSION: '~3'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet'
      SCM_COMMAND_IDLE_TIMEOUT: '10000'
      WEBJOBS_IDLE_TIMEOUT: '10000'
      MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: authClientSecret
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

  resource sourceControl 'sourcecontrols@2021-01-15' = {
    name: 'web'
    properties: {
      repoUrl: sourceControlRepoUrl
      branch: sourceControlBranch
      isManualIntegration: true
    }
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
        properties: {
          azureActiveDirectory: {
            properties: {
              validation: {
                properties: {
                  allowedAudiences: [
                    
                  ]
                }
              }
            }
          }
        }
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
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  kind: 'web'
  location: resourceGroup().location
  properties: {
    Application_Type: 'web'
  }
}

output functionAppTestUrl string = 'https://${functionApp.properties.defaultHostName}/api/TopFiveProducts'
output functionAppName string = '${functionApp.name}'
output sqlServerName string = '${sqlServer.name}'
