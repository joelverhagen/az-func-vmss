param location string = resourceGroup().location
param storageAccountName string
param userManagedIdentityName string = 'az-func-vmss'
@secure()
param workerZipUrl string
@secure()
param workerEnvUrl string
param deploymentLabel string = newGuid()
param spotWorkerDeploymentContainerName string = 'deployment'

param adminUsername string = 'az-func-vmss'
@secure()
param adminPassword string
param specs array = [ // An array of objects with these properties: "namePrefix", "location", "sku", "maxInstances"
  {
    namePrefix: 'az-func-vmss-0-'
    location: location
    sku: 'Standard_D2as_v4'
    maxInstances: 30
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

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storageAccountName}/default/${spotWorkerDeploymentContainerName}'
  dependsOn: [
    storageAccount
  ]
}

resource uploadBlobs 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${storageAccountName}-spot-worker-upload'
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
    arguments: '-ManagedIdentityClientId \'${userManagedIdentity.properties.clientId}\' -DeploymentLabel \'${deploymentLabel}\' -StorageAccountName \'${storageAccountName}\' -SpotWorkerDeploymentContainerName \'${spotWorkerDeploymentContainerName}\''
    primaryScriptUri: 'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/Set-SpotWorkerDeploymentFiles.ps1'
    supportingScriptUris: [
      'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/azure-functions-host-4.3.0-win-x64.zip'
      'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/Install-WorkerStandalone.ps1'
      workerZipUrl
      workerEnvUrl
    ]
    cleanupPreference: 'Always'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    deploymentContainer
  ]
}

var workersDeploymentLongName = '${deployment().name}-spot-worker-'

// Subtract 10 from the max length to account for the index appended to the module name
var workersDeploymentName = length(workersDeploymentLongName) > (64 - 10) ? '${guid(deployment().name)}-spot-worker-' : workersDeploymentLongName

module workers './spot-worker.bicep' = [for (spec, index) in specs: {
  name: '${workersDeploymentName}${index}'
  params: {
    userManagedIdentityName: userManagedIdentityName
    deploymentLabel: deploymentLabel
    customScriptExtensionFiles: uploadBlobs.properties.outputs.customScriptExtensionFiles
    location: spec.location
    vmssSku: spec.sku
    nsgName: '${spec.namePrefix}nsg'
    vnetName: '${spec.namePrefix}vnet'
    vmssName: '${spec.namePrefix}vmss'
    maxInstances: spec.maxInstances
    nicName: '${spec.namePrefix}nic'
    ipConfigName: '${spec.namePrefix}ip'
    autoscaleName: '${spec.namePrefix}autoscale'
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}]
