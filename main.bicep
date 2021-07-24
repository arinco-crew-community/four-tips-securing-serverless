targetScope = 'resourceGroup'

param sqlAdministratorLogin string

@secure()
param sqlAdministratorLoginPassword string

var functionAppName = 'secure-${uniqueString(resourceGroup().id)}'
var appServicePlanName = 'secure-asp'
var appInsightsName = 'secure-ai'
var sqlserverName = 'secure-${uniqueString(resourceGroup().id)}'
var storageAccountName = 'secure${uniqueString(resourceGroup().id)}'
var databaseName = 'secure-db'

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
  properties: {
    serverFarmId: appServicePlan.id

    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, '2019-06-01').keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: '${applicationInsights.properties.InstrumentationKey}'
        }
        {
          name: 'WEBSITE_SKIP_CONTENTSHARE_VALIDATION'
          value: '1'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: functionAppName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'SCM_COMMAND_IDLE_TIMEOUT'
          value: '10000'
        }
        {
          name: 'WEBJOBS_IDLE_TIMEOUT'
          value: '10000'
        }
      ]
      connectionStrings: [
        {
          name: 'AdventureWorks'
          type: 'SQLAzure'
          connectionString: 'Server=tcp:${sqlServer.name}.${environment().suffixes.sqlServerHostname},1433;Database=${databaseName};User ID=${sqlAdministratorLogin};Password=${sqlAdministratorLoginPassword}'
        }
      ]
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
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  kind: 'web'
  location: resourceGroup().location
  properties: {
    Application_Type: 'web'
  }
}
