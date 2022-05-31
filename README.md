# az-func-vmss

An example of how you can run Azure Functions on Azure VM scale-sets (VMSS).

## Deploy

Publish your Functions app and zip the publish directory. Put your configuration in an a [environment file (.env)](https://docs.docker.com/compose/env-file/). Deploy it to a [spot VM](https://azure.microsoft.com/en-us/services/virtual-machines/spot/) scale set. Save 💰.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2Fjoelverhagen%2Faz-func-vmss%2Freleases%2Fdownload%2Fv0.0.2%2Fspot-workers.deploymentTemplate.json)

YMMV.

("YMMV" is enough to wash my hands of whatever trouble you kids get yourself into, eh?)