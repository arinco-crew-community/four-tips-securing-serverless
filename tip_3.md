# Securing serverless applications in Azure - Part 3/4 Store application secrets in Key Vault

This is the third in a four part series of posts on securing serverless application in Azure using bicep. In this series we take a look at how you can secure serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. Validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](https://github.com/arincoau/four-tips-securing-serverless)

All of the commands in this blog post are expected to be run using Powershell.

This blog post expects that you have completed the setup and configuration in parts 1 and 2.

[Securing serverless applications in Azure - Part 1/4 Enable Azure AD authentication](https://arinco.com.au/blog/securing-serverless-applications-in-azure-part-1-4-enable-azure-ad-authentication)

[Securing serverless applications in Azure - Part 2/4 Configure Managed Identity](https://arinco.com.au/uncategorized/securing-serverless-applications-in-azure-part-2-4-configure-managed-identity)

## Tip 3 - Store application secrets in Key Vault

Another thing you may want to consider doing to secure a serverless applications in Azure is to store application secrets in an Azure Key Vault. To do this you will need to deploy a Azure Key Vault, store application secrets in it and grant a Function App access to retrieve those secrets using Key Vault references.

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

var keyVaultName = 'secure${uniqueAppName}'

```

Now we need to grant our function app access to retrieve secrets from the Key Vault. To do this we will grant the Function App the `Key Vault Secret User`. This role has a GUID of `4633458b-17de-408a-b874-0445c86b69e6` which we can validate on in the Key Vault RBAC documentation [here](https://docs.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli#azure-built-in-roles-for-key-vault-data-plane-operations).

We need to create two new variables at the top of our `main.bicep` file. The first variable `keyVaultSecretsUserRoleDefinitionGuid` is the GUID of the `Key Vault Secret User` and the second `keyVaultSecretsUserRoleDefinitionId` is a resource ID referencing the `Key Vault Secret User` role.

``` bicep

var keyVaultSecretsUserRoleDefinitionGuid = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsUserRoleDefinitionId = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${keyVaultSecretsUserRoleDefinitionGuid}'

```

Next we will add a role assignment resource granting the Function App the `Key Vault Secret User` for the Key Vault we are deploying.

``` bicep

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-08-01-preview' = {
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

We can now deploy our `main.bicep` file again to apply this configuration. We'll be prompted for for `authClientId` and `authClientSecret` values, these are the `appId` and `password` values respectively that were noted down earlier.

``` sh

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

Now we can test our API directly from AZ CLI again. Replacing `{appId}` and `{functionAppName}` with their respective values.

``` sh

appId={appId}
functionAppName={functionAppName}
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```

You should be returned a JSON response with the top 5 products from the API.

## Conclusion

In this blog post we looked at how you can store application secrets in Key Vault for a Azure Function App. Join me in the next blog post of this series where we look at how to deploy Private Endpoints for your Azure resources.
