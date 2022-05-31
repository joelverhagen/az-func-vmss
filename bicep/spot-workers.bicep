param location string = resourceGroup().location
param storageAccountName string
param userManagedIdentityName string = 'az-func-vmss'
param appZipPattern string = '*app*.zip'
@secure()
param appZipUrl string
@secure()
param appEnvUrl string
param deploymentLabel string = newGuid()
param deploymentContainerName string = 'deployment'

param adminUsername string = 'az-func-vmss'
@secure()
param adminPassword string
param specs array = [
  // An array of objects with these properties: "namePrefix", "location", "sku", "maxInstances"
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

resource blobPermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessBlob-${userManagedIdentity.id}')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource queuePermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessQueue-${userManagedIdentity.id}')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource tablePermissions 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid('AppCanAccessTable-${userManagedIdentity.id}')
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
    primaryScriptUri: 'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/Set-DeploymentFiles.ps1'
    supportingScriptUris: [
      'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/azure-functions-host-4.3.0-win-x64.zip'
      'https://github.com/joelverhagen/az-func-vmss/releases/download/azure-functions-host-4.3.0/Install-Standalone.ps1'
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
