targetScope = 'resourceGroup'

var uniqueAppName = uniqueString(resourceGroup().id)
var functionAppName = 'secure-${uniqueAppName}'
var appServicePlanName = 'secure-asp'
var appInsightsName = 'secure-ai'
var sqlserverName = 'secure-${uniqueAppName}'
var storageAccountName = 'secure${uniqueAppName}'
var databaseName = 'secure-db'

var sqlAdministratorLogin = 'adminuser'
var sqlAdministratorLoginPassword = 'Ab!${uniqueString(resourceGroup().id)}${uniqueString(resourceGroup().id)}'

var sourceControlRepoUrl = 'https://github.com/arincoau/four-tips-securing-serverless.git'
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
  properties: {
    serverFarmId: appServicePlan.id
  }

  resource appSettings 'config@2021-01-15' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
      APPINSIGHTS_INSTRUMENTATIONKEY: '${applicationInsights.properties.InstrumentationKey}'
      WEBSITE_CONTENTSHARE: '${functionApp.name}'
      FUNCTIONS_EXTENSION_VERSION: '~3'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet'
      SCM_COMMAND_IDLE_TIMEOUT: '10000'
      WEBJOBS_IDLE_TIMEOUT: '10000'
    }
  }

  resource connectionstrings 'config@2021-01-15' = {
    name: 'connectionstrings'
    properties: {
      AdventureWorks: {
        type: 'SQLAzure'
        value: 'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Database=${databaseName};User ID=${sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword}'
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
