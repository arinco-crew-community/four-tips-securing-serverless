# Securing your serverless applications in Azure - Part 4/4 Deploy Private Endpoints for your Azure resources

This is the fourth and last part in series of posts on securing serverless application in Azure using bicep. In this series we take a look at how you can secure serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features, validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](https://github.com/arincoau/four-tips-securing-serverless)

All of the commands in this blog post are expected to be run using Powershell.

This blog post expects that you have completed the setup and configuration in parts 1, 2 and 3.

[Securing serverless applications in Azure - Part 1/4 Enable Azure AD authentication](https://arinco.com.au/blog/securing-serverless-applications-in-azure-part-1-4-enable-azure-ad-authentication)

[Securing serverless applications in Azure - Part 2/4 Configure Managed Identity](https://arinco.com.au/uncategorized/securing-serverless-applications-in-azure-part-2-4-configure-managed-identity)

[Securing serverless applications in Azure - Part 3/4 Store application secrets in Key Vault](https://arinco.com.au/blog/securing-serverless-applications-in-azure-part-3-4-store-application-secrets-in-key-vault)

## Tip 4 - Deploy Private Endpoints for your Azure resources

The final tip to securing serverless applications in Azure is to deploy Private Endpoints for the Azure resources a Function App integrates with. Azure Private Endpoints enable you to secure access to your Platform as a Service (PaaS) Azure resources by deploying a network interface inside your Azure Virtual Network and linking this to your PaaS service. This effectively brings the services into your Virtual Network. Once deployed you can deny access to your resources from the internet and only allow access from your Private Endpoint.

Some of the benefits of using an Azure Private Endpoints are:

- Private Endpoint enable you to privately access Azure PaaS services from your Azure Virtual Networks.
- Privately access your Azure PaaS services from your on-premise network. When used in conjunction with ExpressRoute or a VPN connection, Private Endpoints can enable you to privately access your Azure PaaS services from your on-premises network.
- With Private Endpoints you can disable internet access to your resources. This helps to protect against data leakage risks.

Let's go ahead and configure private endpoints for the PaaS services. Before we configure the private endpoint though we need a virtual network to deploy them to. Let's go ahead and add a virtual network to `main.bicep`.

First let's introduce a new variable for the virtual network name. Place this at the top of the `main.bicep` file.

``` bicep

var virtualNetworkName = 'secure-vnet'

```

Now we can add the virtual network resource declaration by creating a virtual network with two subnets. One for our private endpoints and the other for the function app to access resources within the virtual network. Take note of the configuration of each subnet. On the private endpoint subnet we need to disable private endpoint network policies by setting `privateEndpointNetworkPolicies` to `Disabled`. Also the web subnet needs to be delegated to `Microsoft.Web/serverFarms` to allow virtual network integration.

``` bicep

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: virtualNetworkName
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'web'
        properties: {
          addressPrefix: '10.0.0.0/24'
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

```

Now we need to deploy the Private DNS Zones where the Private Endpoints A records will live. The Private DNS Zones enable resolution of the existing FQDN of a PaaS service to a private IP. See [here](https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-dns) for more info.

We need Private DNS Zones for each of the resource types we want to support. In our case these are:

- Azure SQL
  - privatelink.database.windows.net
- Azure Key Vault
  - privatelink.vaultcore.azure.net

**Note: Due to limitation in private endpoint access for function app storage account, private endpoints will not be configured for the storage account in this example.**

So let's start by defining an array variable of these at the top of `main.bicep`

``` bicep

var azureSqlPrivateDnsZone = 'privatelink.database.windows.net'
var keyVaultPrivateDnsZone = 'privatelink.vaultcore.azure.net'
var privateDnsZoneNames = [
  azureSqlPrivateDnsZone
  keyVaultPrivateDnsZone
]

```

Now we can define the Private DNS Zone resources in a loop. Place this resource loop at the root level of our bicep file.

``` bicep

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2018-09-01' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: privateDnsZoneName
  location: 'global'
  dependsOn: [
    virtualNetwork
  ]
}]

```

And link them back to the virtual network by placing this resource loop at the root level of our bicep file.

``` bicep

resource virtualNetworkLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (privateDnsZoneName, i) in privateDnsZoneNames: {
  parent: privateDnsZones[i]
  location: 'global'
  name: 'link-to-${virtualNetwork.name}'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}]

```

Now we can configure the Private Endpoints for each of the PaaS resources. Starting with Azure SQL we place this resource at the root level of our bicep file.

``` bicep

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${sqlServer.name}-sql-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${sqlServer.name}-sql-pe-conn'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', azureSqlPrivateDnsZone)
          }
        }
      ]
    }
  }
}

```

And now the Azure Key Vault

``` bicep

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2020-06-01' = {
  name: '${keyVault.name}-kv-pe'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVault.name}-kv-pe-conn'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }

  resource privateDnsZoneGroup 'privateDnsZoneGroups@2020-03-01' = {
    name: 'dnsgroup'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config'
          properties: {
            privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', keyVaultPrivateDnsZone)
          }
        }
      ]
    }
  }
}

```

Now we have private endpoints configured for each of our PaaS resources. We can now disable access to these resources from the internet. To do this we need to configure the firewall and network settings of each of the services.

Starting with Azure SQL we need to add the following to the `properties` section our `sqlServer` resource definition.

``` bicep

publicNetworkAccess: 'Disabled'

```

We also need to remove the `firewallRules` sub resource from the `sqlServer` resource. Remove the following section from the `main.bicep` file.

``` bicep

resource firewallRules 'firewallRules@2021-02-01-preview' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }

```

Now for Key Vault, we need to add the following to the `properties` section of the `keyVault` resource definition.

``` bicep

publicNetworkAccess: 'Disabled'
networkAcls: {
  bypass: 'None'
  defaultAction: 'Deny'
  ipRules: []
  virtualNetworkRules: []
}

```

The last thing we need to do is to configure Virtual Network integration for the Function App and connect it to the virtual network. It will then be able to access the PaaS services through their private endpoints.

To do this we need to add the following `networkConfig` resource as a sub resource to the `functionApp`.

``` bicep

resource functionAppVirtualNetwork 'networkConfig@2020-06-01' = {
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: virtualNetwork.properties.subnets[0].id
    swiftSupported: true
  }
}

```

Finally as we're using the default Azure DNS we need to instruct the Function App to route all traffic via the virtual network.

Add the following to the `properties` section of the `functionApp` resource.

``` bicep

siteConfig: {
  vnetRouteAllEnabled: true
}

```

We can now deploy the `main.bicep` file again to apply this configuration. We'll be prompted for for `authClientId` and `authClientSecret` values, these are the `appId` and `password` values respectively that were noted down earlier.

``` powershell

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

Now we can test the API directly from AZ CLI again. Replacing `{appId}` and `{functionAppName}` with their respective values.

``` powershell

$appId="{appId}"
$functionAppName="{functionAppName}"
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```

You should be returned a JSON response with the top 5 products from the API.

## Conclusion

In this blog post we looked at how you can deploy Private Endpoints for your Azure resources and enable access from a Function App. This is the last post in this series where we've look at how you can incrementally improve the security of your serverless application in Azure.
