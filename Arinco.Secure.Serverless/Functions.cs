using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;

namespace Arinco.Secure.Serverless
{
    public static class Functions
    {
        [FunctionName("TopFiveProducts")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
            HttpRequest req,
            ILogger log)
        {
            log.LogInformation("TopFiveProducts function started processing a request.");

            var connectionString = Environment.GetEnvironmentVariable("SQLAZURECONNSTR_AdventureWorks");
            var useManagedIdentity = Environment.GetEnvironmentVariable("UseManagedIdentity") == "true";

            await using var conn = new SqlConnection(connectionString);

            if (useManagedIdentity)
            {
                var tokenProvider = new AzureServiceTokenProvider();
                conn.AccessToken = await tokenProvider.GetAccessTokenAsync("https://database.windows.net/");
            }

            conn.Open();

            const string statement = "select top 5 * from SalesLT.Product";
            await using var cmd = new SqlCommand(statement, conn);

            await using var reader = await cmd.ExecuteReaderAsync();

            var customers = ReaderToDictionary(reader);

            log.LogInformation("TopFiveProducts function finished processing a request.");
            return new OkObjectResult(customers);
        }

        public static IEnumerable<Dictionary<string, object>> ReaderToDictionary(SqlDataReader reader)
        {
            var results = new List<Dictionary<string, object>>();
            var cols = new List<string>();
            for (var i = 0; i < reader.FieldCount; i++)
            {
                cols.Add(reader.GetName(i));
            }

            while (reader.Read())
            {
                results.Add(cols.ToDictionary(col => col, col => reader[col]));
            }

            return results;
        }
    }
}
