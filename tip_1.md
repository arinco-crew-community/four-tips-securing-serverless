# Securing your serverless applications in Azure - Part 1/4 Enable Azure AD authentication

This is the first in a four part series of posts on securing your serverless application in Azure using bicep. In this series we take a look at how you can secure your serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. Validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

All of the commands in this blog post are expected to be run on a Linux shell.

Before we go ahead and configure Azure AD authentication we need a Function App to do this. Follow the setup steps below to deploy a sample Function App to Azure.

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

## Tip 1 - Enable Azure AD authentication

One of the first things that we can do to secure our Function App is to enable Azure AD authentication. Once we have Azure AD authentication enabled, all requests to the Function App will need to provide a valid Azure AD bearer token. Any requests without a valid token will be returned a 401 unauthorized result.

The command will output the name of the Function App and URL that can be used to test the Function to ensure everything was configured correctly.

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