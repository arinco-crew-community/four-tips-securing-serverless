# Securing your serverless applications in Azure - Part 3/4 Store application secrets in Key Vault

This is the fourth and last in a four part series of posts on securing your serverless application in Azure using bicep. In this series we take a look at how you can secure your serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. Validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

All of the commands in this blog post are expected to be run on a Linux shell.

This blog post expects that you have completed the setup and configuration in parts 1, 2, and 3.

[Securing your serverless applications in Azure - Tip 1/4 Enable Azure AD authentication]()
[Securing your serverless applications in Azure - Tip 2/4 Configure Managed Identity]()

## Tip 3 - Store application secrets in Key Vault

Another thing you may want to consider doing to secure your serverless applications in Azure is to store your application secrets in an Azure Key Vault. To do this you need to deploy a Azure Key Vault, store your application secrets in it and grant your Function App access to retrieve those secrets using Key Vault references.

Let's jump right in and deploy a Key Vault through our bicep template. To start with we need to add an Azure Key Vault resource to our `main.bicep`.

``` bicep

resource keyVault 'Microsoft.KeyVault/vaults@2021-04-01-preview' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

```

We also need to define a new `keyVaultName` variable. Let's do this at the top of the file under the `storageAccountName` variable.

``` bicep

var keyVaultName = 'secure${uniqueString(resourceGroup().id)}'

```

Now we need to grant our function app access to retrieve secrets from the Key Vault. To do this we will grant the Function App the `Key Vault Secret User`. This role has a GUID of `4633458b-17de-408a-b874-0445c86b69e6` which we can validate on in the Key Vault RBAC documentation [here](https://docs.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations).

We need to create two new variables at the top of our `main.bicep` file. The first variable `keyVaultSecretsUserRoleDefinitionGuid` is the GUID of the `Key Vault Secret User` and the second `keyVaultSecretsUserRoleDefinitionId` is a resource ID referencing the `Key Vault Secret User` role.

``` bicep

var keyVaultSecretsUserRoleDefinitionGuid = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsUserRoleDefinitionId = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${keyVaultSecretsUserRoleDefinitionGuid}'

```

Next we will add a role assignment resource granting the Function App the `Key Vault Secret User` for the Key Vault we are deploying.

``` bicep

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleDefinitionGuid, functionApp.name)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

```

Now let's move some of our sensitive values from our Function App configuration to our Key Vault and update their values to Key Vault references.

Let's start by creating a couple of new variables for the names of our Key Vault secrets. Place these at the top of  your bicep file.

``` bicep

var msProviderAuthSecretName = 'msProviderAuthSecret'
var storageAccountConnectionStringSecretName = 'storageAccountConnectionStringSecret'

```

Next let's create Key Vault secret resources and assign these value. Place the following snippet inside your Key Vault resource definition.

``` bicep

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

```

Finally we need to update our Function App configuration with Key Vault references. This will enable the Function App to retrieve the values from the Key Vault at runtime. We need to make the following three updates in the `appSettings` resource definition.

`MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`

``` bicep

MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${msProviderAuthSecretName})'


```

`AzureWebJobsStorage`

``` bicep

AzureWebJobsStorage: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageAccountConnectionStringSecretName})'

```

`WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`

``` bicep

WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageAccountConnectionStringSecretName})'

```

**Note: in order for WEBSITE_CONTENTAZUREFILECONNECTIONSTRING to be a Key Vault reference we need to set an additional value in our configuration WEBSITE_SKIP_CONTENTSHARE_VALIDATION to 1.**

We also need to ensure the content share is created in our Storage Account. Without this configuration value set and the content share created in our Storage Account our Function App will fail to start.

``` bicep

WEBSITE_SKIP_CONTENTSHARE_VALIDATION: '1'

```

Now we can test our API directly from AZ CLI again. Replacing `{appId}` and `{functionAppName}` with their respective values.

``` sh

appId={appId}
functionAppName={functionAppName}
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```
