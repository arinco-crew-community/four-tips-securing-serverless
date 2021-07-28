# Four tips for Securing your serverless applications in Azure

Serverless applications and Platform as a Service (PaaS) services are awesome! They cost less, take less time to develop, are easier to deploy and can even increase developer productivity. However, these benefits don't come without some trade offs. By default serverless applications and PaaS services are publicly accessible, application secrets can be stored in code and authentication isn't automatically enabled.

In this blog post there are four tips on how to deal with some of these trade offs and secure your serverless applications and PaaS services in Azure. This post will be followed by a four part series of posts showing how to take these tips and progressively apply them to an Azure Function App. Validating along the way that the changes have been successful and the app is secure.  

## Tip 1 - Enable Azure AD authentication

One of the first things that you can do to secure our Function App is to enable Azure AD authentication. Once Azure AD authentication enabled, all requests to a Function App will need to provide a valid Azure AD bearer token. Any requests without a valid token will be denied access.

Some of the benefits of enabling Azure AD authentication are:

- Can be enabled through configuration without having to implement it yourself.
- Not dependent on a specific language, SDK or code.
- Authorization behaviour can be customised per your requirements.

## Tip 2 - Configure a Managed Identity and grant access to Azure resources

Another thing you may want to do to improve the security of Function Apps is to configure a managed identity for your Function App. A managed identity allows you to grant the Function App access to other Azure resources without having to store credentials in code. Managed identities use certificate based authentication and their credentials are rotated every 45 days.

Some of the benefits of using managed identities are:

- You no longer need to manage credentials to access your Azure resources.
- You can use your managed identity to access any resource that supports Azure AD authentication, including your own APIs!
- Credentials for managed identities are automatically rotated for you.

## Tip 3 - Store application secrets in Key Vault

The third tip to secure your serverless applications in Azure is to store your application secrets such as certificates or passwords in an Azure Key Vault. To do this you need to deploy a Azure Key Vault, store your application secrets in it and grant your Function App access to retrieve those secrets using an Azure AD roles.

Some of the benefits of using an Azure Key Vault are:

- Using Azure Key Vault allows you to centralise the storage of your secrets. Reducing the chance that they are leaked.
- Access to Key Vault requires authentication and authorization before a user (or application) can access.
- When integrating with Azure Monitor. Monitoring can be enabled to log who is accessing your Key Vault and when.

## Tip 4 - Deploy Private Endpoints for your Azure resources

The last tip to secure your serverless application in Azure is to deploy Private Endpoints for the Azure resources your Function App integrates with. Azure Private Endpoints enable you to secure access to your Platform as a Service (PaaS) Azure resources by deploying a network interface inside your Azure Virtual Network and linking this to your PaaS service. This effectively brings the services into your Virtual Network. Once deployed you can deny access to your resources from the internet and only allow access from your Private Endpoint.

Some of the benefits of using an Azure Private Endpoints are:

- Private Endpoint enable you to privately access Azure PaaS services from your Azure Virtual Networks.
- Privately access your Azure PaaS services from your on-premise network. When used in conjunction with ExpressRoute or a VPN connection, Private Endpoints can enable you to privately access your Azure PaaS services from your on-premises network.
- With Private Endpoints you can disable internet access to your resources. This helps to protect against data leakage risks. 

## Conclusion

This blog post has outlined some of the easiest and best ways to improve the security of serverless applications and PaaS services in Azure. It's highlighted some of the benefits of using them. Check out the first in the four part series where we take these tips and apply them to an Azure Function App.
