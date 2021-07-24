# Four tips for securing your serverless applications in Azure

In this blog post we will take a look at some tips for how you can secure your serverless Function Apps in Azure. We will start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. We will be configuring all these features using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

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

Now we can deploy the resources in our bicep file by running the following command. When you execute the command it will prompt you for a username and password for the Azure SQL database.

``` sh

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

The command will output a URL that can be used to test the Function to ensure everything was configured correctly.

## Tip 1 - Enable Azure AD authentication

One of the first things that we can do to secure our Function Apps is to enable Azure AD authentication. Once we have Azure AD authentication, all requests to the Function App will need to provide a valid Azure AD bearer token. Any requests without a valid token will produce a 401 unauthorized result.

First thing let's create an app registration. We can do this by executing the commands below. These commands will do the following: create the app registration, update some of it's App ID  generate a password credential. You'll need to replace the `{functionAppName}` with the functionAppName output from the initial deployment.

``` sh
functionName={functionAppName}
appId=$(az ad app create --display-name $functionName-auth --reply-urls https://$functionName.azurewebsites.net/.auth/login/aad/callback --query appId --out tsv)
az ad app update --id $appId --identifier-uris api://$appId;
appCredential=$(az ad app credential reset --id $appId)
echo "authClientSecret=$appCredential"

```

## Tip 2 - Configure a Managed Identity and grant access to Azure resources

## Tip 3 - Store application secrets in Key Vault

## Tip 4 - Deploy a private endpoint
