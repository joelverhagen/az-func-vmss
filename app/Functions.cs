using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using System.Runtime.InteropServices;

namespace App
{
    public static class Functions
    {
        [FunctionName("hello")]
        public static IActionResult Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req)
        {
            return new OkObjectResult(
                $"Hello from VMSS instance {Environment.MachineName}, " +
                $"running as {RuntimeInformation.RuntimeIdentifier}!{Environment.NewLine}" +
                $"MyTestSetting = '{Environment.GetEnvironmentVariable("MyTestSetting")}'");
        }
    }
}
