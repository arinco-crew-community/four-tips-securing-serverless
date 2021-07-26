# Securing your serverless applications in Azure - Part 4/4 Deploy Private Endpoints

This is the third in a four part series of posts on securing your serverless application in Azure using bicep. In this series we take a look at how you can secure your serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. Validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](http://github.com)

All of the commands in this blog post are expected to be run on a Linux shell.

This blog post expects that you have completed the setup and configuration in parts 1 and 2.

[Securing your serverless applications in Azure - Tip 1/4 Enable Azure AD authentication]()
[Securing your serverless applications in Azure - Tip 2/4 Configure Managed Identity]()
[Securing your serverless applications in Azure - Tip 3/4 Store application secrets in Key Vault]()

## Tip 4 - Deploy Private Endpoints for your Azure resources