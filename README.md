# Four tips for securing your serverless applications in Azure

In this blog post we will take a look at some tips for how you can secure your serverless Function Apps in Azure. We will start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. We will be configuring all these features using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

All of the commands in this blog post are expected to be run on a Linux shell.

## Setup

We are going to start with a sample Azure Function that queries the Microsoft AdventureWorks demonstration database. It will query the database for the top 5 products, serialise them as JSON and return the result. The Function App code can we viewed [here](http://github.com).

We will start with a pre-configured [main.bicep](https://raw.githubusercontent.com/arincoau/four-tips-securing-serverless/main/main.bicep) file. Which you can download [here](https://raw.githubusercontent.com/arincoau/four-tips-securing-serverless/main/main.bicep). This file contains the bicep configuration to deploy the following resource:

- Function App
- Storage Account
- Application Insights
- Azure SQL server
- Azure SQL database

The Function App code is deployed to the Function App using a source control reference to the github repo containing  the code. The deployment of the code can take a little while and you can view the progress in the `Deployment Centre` pane of the Function App.

Before we deploy the Azure resource we need to create a resource group.

``` sh

az group create --name secure-rg --location australiaeast

```

Now we can deploy the resources in our bicep file by running the following command.

``` sh

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

The command will output the name of the Function App and URL that can be used to test the Function to ensure everything was configured correctly.

## Tip 1 - Enable Azure AD authentication

One of the first things that we can do to secure our Function App is to enable Azure AD authentication. Once we have Azure AD authentication enabled, all requests to the Function App will need to provide a valid Azure AD bearer token. Any requests without a valid token will be returned a 401 unauthorized result.

First thing let's create an app registration. We can do this by executing the commands below. These commands will do the following: create the app registration, update some of it's App ID  generate a password credential. You'll need to replace the `{functionAppName}` with the functionAppName output from the initial deployment.

``` sh

functionName={functionAppName}
appId=$(az ad app create --display-name $functionName-auth --reply-urls https://$functionName.azurewebsites.net/.auth/login/aad/callback --query appId --out tsv)
az ad app update --id $appId --identifier-uris api://$appId;
appCredentials=$(az ad app credential reset --id $appId)
echo "$appCredentials"

```

Take note of the `appId` and `password` values in the output as we'll be using these later.  

Now let's update our bicep file with the required configuration for Azure AD authentication. At the top of the file add two new parameters. One named `authClientId` and the other `authClientSecret`. `authClientSecret` should be marked as a secure parameter.

``` bicep

param authClientId string

@secure()
param authClientSecret string

```

Next up let's add the authSettings configuration to the Function App site resource. This configuration should be nested within the functionApp resource definition.

``` bicep

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
      }
      validation: {
        allowedAudiences: [
          'api://${authClientId}'
        ]
      }
    }
  }
}

```

Finally let's add the authentication secret variable to the Function App config settings. The following should be added to the bottom of the appSettings resource, underneath `WEBJOBS_IDLE_TIMEOUT`.

``` bicep

MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: authClientSecret

```

And that's it, we've finished configuring Azure AD authentication for our Function App. We can now deploy our `main.bicep` file again to apply this configuration. We'll be prompted for for `authClientId` and `authClientSecret` values, these are the `appId` and `password` values respectively that were noted down earlier.

``` sh

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

Now let's go ahead and test our API. First let's test it without an authorization header. You'll need to replace `{functionAppName}` with the name of your function app.

``` sh

az rest -m get --header "Accept=application/json" -u "https://${functionAppName}.azurewebsites.net/api/TopFiveProducts" --skip-authorization-header

```

This command should return a result with `Unauthorized(You do not have permission to view this directory or page.)`

Now let's configure the AZ CLI to be an authorized client for our API. Replace `{appId}` with the `appId` from when the app registration was created.

``` sh
appId={appId}
objectId=$(az ad app show --id $appId --out tsv --query objectId)
apiPermission=$(az ad app show --id $appId -o tsv --query oauth2Permissions[0].id)
az rest -m PATCH -u https://graph.microsoft.com/beta/applications/$objectId --headers Content-Type=application/json -b "{'api':{'preAuthorizedApplications':[{'appId':'04b07795-8ddb-461a-bbee-02f9e1bf7b46','permissionIds':['$apiPermission']}]}}"

```

Now we can test our API directly from AZ CLI. Replace `{appId}` with the `appId` from when the app registration was created and `{functionAppName}` with the name of your Function App.

``` sh
appId={appId}
functionAppName={functionAppName}
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```

You should be returned a JSON response with the top 5 products from the API.

## Tip 2 - Configure a Managed Identity and grant access to Azure resources

Something else you may want to consider is configuring a managed identity for you Function App. A managed identity allows you to grant access to other Azure resources without having to store credentials in code. Managed identities use certificate based authentication and their credentials are rotated every 45 days.

We're now going to look at how we can enable a managed identity for our Function App and grant the function app access to query our Azure SQL database.

The first thing we're going to do is enable managed identity for our Function App. All we need to do is to add the following snippet to our `functionApp` resource in `main.bicep` directly after `kind: 'functionapp'`.

``` bicep

identity: {
  type: 'SystemAssigned'
}

```

Next let's take a quick look at this snippet from the Function App code where we are setting the connection string and establishing the connection to the Azure SQL database.

``` cs

var connectionString = Environment.GetEnvironmentVariable($"SQLAZURECONNSTR_AdventureWorks}");
var useManagedIdentity = Environment.GetEnvironmentVariable("UseManagedIdentity") == "true";

await using var conn = new SqlConnection(connectionString);

if (useManagedIdentity)
{
    var tokenProvider = new AzureServiceTokenProvider();
    conn.AccessToken = await tokenProvider.GetAccessTokenAsync("https://database.windows.net/");
}

```

As you can see we expect a couple of environment variables to be set. The `UseManagedIdentity` variable indicates we expect the provided connection string to be a managed identity connection string. The `SQLAZURECONNSTR_AdventureWorks` variable is how we retrieve connection string variables in Azure Functions. We will need to add/update these variables in our Function App configuration. 

To do that we need to add the following snippet to the appSettings resource, underneath `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`.

``` bicep

UseManagedIdentity: 'true'

```

And set the `value` of our `AdventureWorks` connection string to the following.

``` bicep

'Server=tcp:${sqlServer.name}${environment().suffixes.sqlServerHostname},1433;Database=${databaseName}'

```

As you can see from the connection string we no longer require the username and password to be supplied for our AzureSQL Database.

We can now deploy our `main.bicep` file again to apply this configuration. We'll be prompted for for `authClientId` and `authClientSecret` values, these are the `appId` and `password` values respectively that were noted down earlier.

``` sh

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

The last thing we need to do is grant our Function App access to query our Azure SQL database. 

We need to add ourselves as an administrator of the Azure SQL server. To do this we will use the AZ CLI and execute the following commands. You'll need to replace `{upn}` with the email address you use to authenticate with Azure. The `{sqlServer}` value needs to be replaced with the `sqlServerName` value output from the deployment.

``` sh

upn={upn}
sqlServer=secure-ra5lwu4dye23e
objectId=$(az ad user show --id $upn --out tsv --query objectId)
az sql server ad-admin create --object-id $objectId --display-name $upn --resource-group secure-rg --server $sqlServer

```

Now we can grant the Function App the required permission to query our database.

1. Visit the [Azure Portal](http://portal.azure.com)
1. Login and navigate to the `secure-rg` resource group
1. Locate the `secure-db` Azure SQL database
1. Open the Query Editor (preview) pane
1. Click Continue as {Your email address}
1. Click Whitelist IP x.x.x.x on server secure-....
1. Click Continue as {Your email address}
1. Execute the following SQL statement replacing both `{functionAppName}` tokens with the name of your Function App.

``` sql

CREATE USER [{functionAppName}] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [{functionAppName}];
GO

```

Now we can test our API directly from AZ CLI again. Replacing `{appId}` and `{functionAppName}` with their respective values.

``` sh

appId={appId}
functionAppName={functionAppName}
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```

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

## Tip 4 - Deploy a private endpoint