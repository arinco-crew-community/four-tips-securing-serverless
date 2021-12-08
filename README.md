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

## Tips

[Tip 1 - Enable Azure AD authentication](tip_1.md)

[Tip 2 - Configure a Managed Identity and grant access to Azure resources](tip_2.md)

[Tip 3 - Store application secrets in Key Vault](tip_3.md)

[Tip 4 - Deploy a private endpoint](tip_4.md)