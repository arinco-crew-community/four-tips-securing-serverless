# Four tips for securing your serverless applications in Azure

In this blog post we will take a look at some tips for how you can secure your serverless Function Apps in Azure. We will start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. We will be configuring all these features using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

## Setup

We are going to start with a sample Azure Function that queries the Microsoft Northwind demo database. It will query it for the top 5 products, serialise them as JSON and return the result.

The Function code can we viewed [here](http://github.com)

Now lets start by deploying this code to a Function App using Bicep and the AZ CLI.

The first thing we need to do is create our `main.bicep` file and configure it to create our resource group.

``` bicep

```


## Tip 1 - Enable Azure AD authentication 

## Tip 2 - Configure a Managed Identity and grant access to Azure resources

## Tip 3 - Store application secrets in Key Vault

## Tip 4 - Deploy a private endpoint
