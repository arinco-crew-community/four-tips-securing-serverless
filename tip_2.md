# Securing serverless applications in Azure - Part 2/4 Configure Managed Identity

This is the second in a four part series of posts on securing serverless application in Azure using bicep. In this series we take a look at how you can secure serverless Function Apps in Azure. We start with a sample Azure Function App, deploy it to Azure and then progressively enable each of these security features. Validating along the way that our changes have been successful and our app is secure. We configure (nearly) all of this using Azure Bicep and the AZ CLI. If you'd like to skip to code it's all available on GitHub [here](https://github.com/arincoau/four-tips-securing-serverless)

All of the commands in this blog post are expected to be run using Powershell.

This blog post expects that you have completed the setup and configuration in part 1. If you haven't done so, go check it out and then return here. [Securing serverless applications in Azure - Part 1/4 Enable Azure AD authentication](https://arinco.com.au/blog/securing-serverless-applications-in-azure-part-1-4-enable-azure-ad-authentication)

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

As you can see we expect a couple of environment variables to be set. The `UseManagedIdentity` variable indicates we expect the provided connection string to be a managed identity connection string. The `SQLAZURECONNSTR_AdventureWorks` variable is how connection string variables are retrieved in Azure Functions. We will need to add/update these variables in our Function App configuration.

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

``` powershell

az deployment group create --resource-group secure-rg --template-file main.bicep --query properties.outputs

```

The last thing we need to do is grant our Function App access to query our Azure SQL database.

We need to add ourselves as an administrator of the Azure SQL server. To do this we will use the AZ CLI and execute the following commands. You'll need to replace `{upn}` with the email address you use to authenticate with Azure. The `{sqlServer}` value needs to be replaced with the `sqlServerName` value output from the deployment.

``` powershell

$upn="{upn}"
$sqlServer="{sqlServer}"
$objectId=$(az ad user show --id $upn --out tsv --query objectId)
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

``` powershell

$appId="{appId}"
$functionAppName="{functionAppName}"
az rest -m get --header "Accept=application/json" -u "https://$functionAppName.azurewebsites.net/api/TopFiveProducts" --resource "api://$appId"

```

You should be returned a JSON response with the top 5 products from the API.

## Conclusion

In this blog post we looked at how you can configure a managed identity for a Azure Function App and grant access to an Azure SQL database. Join me in the next blog post of this series where we look at how you can store application secrets in Azure Key Vault.
