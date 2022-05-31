@description('The region to provision resources in. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('The storage account to upload deployment files to and use for the Azure Functions host.')
param storageAccountName string = 'azfuncvmss${uniqueString('funcvmss', resourceGroup().name)}'

@description('The prefix to use for the VMSS load balancer domain name labels. The FQDN will look something like \'{domainNamePrefix}-{index}.{region}.cloudapp.azure.com\'.')
param domainNamePrefix string = 'az-func-vmss-${uniqueString('funcvmss', resourceGroup().name)}-'

@description('The release name to use for the deployment scripts and the Azure Functions Host zip file. Found on https://github.com/joelverhagen/az-func-vmss/releases')
param gitHubReleaseName string = 'v0.0.1'

@description('A publicly accessibly URL (can be blob storage SAS) for the Azure Functions app zip file. Made with zipping the output of dotnet publish.')
param appZipUrl string = 'https://github.com/joelverhagen/az-func-vmss/releases/download/${gitHubReleaseName}/example-app-win-x64.zip'

@description('A publicly accessibly URL (can be blob storage SAS) for the app settings. Works like Docker environment files (.env).')
param appEnvUrl string = 'https://github.com/joelverhagen/az-func-vmss/releases/download/${gitHubReleaseName}/example-config.env'

@description('The name of the user managed identity to assign to the VMSS and use for deployment file uploads.')
param userManagedIdentityName string = 'az-func-vmss'

@description('The file name pattern used to find the appZipUrl file after downloading it. Defaults to the file name in URL.')
param appZipPattern string = last(split(split(appZipUrl, '?')[0], '/'))

@description('The deployment label to use as a directory name in the deployment blob storage container and on the VMSS disk.')
param deploymentLabel string = newGuid()

@description('The container name to use for holding deployment files (host, app, env, install script) for VMSS custom script extension files.')
param deploymentContainerName string = 'deployment'

@description('The admin username for the VMSS instances.')
param adminUsername string = 'azfuncvmss'

@description('The admin password for the VMSS instances.')
@secure()
param adminPassword string = 'AFV1!${uniqueString(newGuid())}${uniqueString(deployment().name)}${uniqueString(resourceGroup().name)}'

@description('The specs for the VMSS resources. An array of objects. Each object must have: namePrefix (string, prefix for VMSS resource names), location (string, location for the VMSS resources), sku (string, VMSS SKU), maxInstances (int, max instances for auto-scaling).')
param specs array = [
  {
    sku: 'Standard_D2as_v4'
    maxInstances: 30
    namePrefix: 'az-func-vmss-0-'
    location: location
  }
]

resource userManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userManagedIdentityName
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource blobPermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessBlob-${userManagedIdentity.id}-${storageAccount.id}')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource queuePermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessQueue-${userManagedIdentity.id}-${storageAccount.id}')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource tablePermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessTable-${userManagedIdentity.id}-${storageAccount.id}')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${deploymentContainerName}'
  dependsOn: [
    storageAccount
  ]
}

resource uploadBlobs 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${storageAccountName}-upload'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userManagedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '7.5'
    arguments: '-ManagedIdentityClientId \'${userManagedIdentity.properties.clientId}\' -DeploymentLabel \'${deploymentLabel}\' -StorageAccountName \'${storageAccountName}\' -DeploymentContainerName \'${deploymentContainerName}\''
    primaryScriptUri: 'https://github.com/joelverhagen/az-func-vmss/releases/download/${gitHubReleaseName}/Set-DeploymentFiles.ps1'
    supportingScriptUris: [
      'https://github.com/joelverhagen/az-func-vmss/releases/download/${gitHubReleaseName}/azure-functions-host-4.3.0-win-x64.zip'
      'https://github.com/joelverhagen/az-func-vmss/releases/download/${gitHubReleaseName}/Install-Standalone.ps1'
      appZipUrl
      appEnvUrl
    ]
    cleanupPreference: 'Always'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    deploymentContainer
  ]
}

var deploymentLongName = '${deployment().name}-worker-'

// Subtract 10 from the max length to account for the index appended to the module name
var deploymentName = length(deploymentLongName) > (64 - 10) ? '${guid(deployment().name)}-spot-worker-' : deploymentLongName

module workers './spot-worker.bicep' = [for (spec, index) in specs: {
  name: '${deploymentName}${index}'
  params: {
    userManagedIdentityName: userManagedIdentityName
    deploymentLabel: deploymentLabel
    customScriptExtensionFiles: uploadBlobs.properties.outputs.customScriptExtensionFiles
    appZipPattern: appZipPattern
    location: spec.location
    vmssSku: spec.sku
    domainNameLabel: '${domainNamePrefix}${index}'
    nsgName: '${spec.namePrefix}nsg'
    vnetName: '${spec.namePrefix}vnet'
    vmssName: '${spec.namePrefix}vmss'
    maxInstances: spec.maxInstances
    nicName: '${spec.namePrefix}nic'
    ipConfigName: '${spec.namePrefix}ip'
    autoscaleName: '${spec.namePrefix}autoscale'
    loadBalancerName: '${spec.namePrefix}lb'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}]

output fqdns array = [for (spec, index) in specs: workers[index].outputs.fqdn]
