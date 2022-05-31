param userManagedIdentityName string

param deploymentLabel string
param customScriptExtensionFiles array
param appZipPattern string

param location string
param vmssSku string
@minValue(1)
param maxInstances int
param nsgName string
param vnetName string
param vmssName string
param nicName string
param ipConfigName string
param autoscaleName string
param loadBalancerName string
param adminUsername string
@secure()
param adminPassword string

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-03-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'HTTP'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      // Enable RDP in the firewall for debugging purposes.
      /*
      {
        name: 'AllowCorpNetPublicRdp'
        properties: {
          priority: 101
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      */
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '172.27.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '172.27.0.0/16'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource userManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: userManagedIdentityName
}

resource loadBalancerIp 'Microsoft.Network/publicIPAddresses@2021-03-01' = {
  name: '${loadBalancerName}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmssName
    }
  }
}

var feIpConfigName = 'frontend-ip-config'
var probeName = 'http-probe'
var backendPoolName = 'backend-pool'

resource loadBalancer 'Microsoft.Network/loadBalancers@2021-03-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: feIpConfigName
        properties: {
          publicIPAddress: {
            id: loadBalancerIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTP'
        properties: {
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations/', loadBalancerName, feIpConfigName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools/', loadBalancerName, backendPoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes/', loadBalancerName, probeName)
          }
        }
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          port: 80
          protocol: 'Http'
          requestPath: '/'
          intervalInSeconds: 5
        }
      }
    ]
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2021-11-01' = {
  name: vmssName
  location: location
  sku: {
    name: vmssSku
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userManagedIdentity.id}': {}
    }
  }
  properties: {
    overprovision: false
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          diskSizeGB: skuInfo[vmssSku].diskSizeGB
          diffDiskSettings: {
            option: 'Local'
            placement: skuInfo[vmssSku].diffDiskPlacement
          }
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-core-smalldisk'
          version: 'latest'
        }
      }
      networkProfile: {
        healthProbe: {
          id: loadBalancer.properties.probes[0].id
        }
        networkInterfaceConfigurations: [
          {
            name: nicName
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: ipConfigName
                  properties: {
                    primary: true
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: loadBalancer.properties.backendAddressPools[0].id
                      }
                    ]
                    // Enable a public IP address so you can RDP into an instance for debugging purposes.
                    /*
                    publicIPAddressConfiguration: {
                      name: ipConfigName
                    }
                    */
                  }
                }
              ]
            }
          }
        ]
      }
      priority: 'Spot'
      osProfile: {
        computerNamePrefix: 'app'
        adminUsername: adminUsername
        adminPassword: adminPassword
      }
      extensionProfile: {
        extensionsTimeBudget: 'PT15M'
        extensions: [
          {
            name: 'InstallStandalone'
            properties: {
              publisher: 'Microsoft.Compute'
              type: 'CustomScriptExtension'
              typeHandlerVersion: '1.10'
              autoUpgradeMinorVersion: true
              settings: {
                fileUris: customScriptExtensionFiles
                commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File "${deploymentLabel}/Install-Standalone.ps1" -DeploymentLabel "${deploymentLabel}" -HostPattern "azure-functions-host-*.zip" -AppPattern "${appZipPattern}" -EnvPattern "*.env" -LocalHealthPort 80 -UserManagedIdentityClientId "${userManagedIdentity.properties.clientId}" -ExpandOSPartition'
              }
              protectedSettings: {
                managedIdentity: {
                  clientId: userManagedIdentity.properties.clientId
                }
              }
            }
          }
        ]
      }
    }
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT15M'
    }
    upgradePolicy: {
      mode: 'Automatic'
    }
  }
}

resource autoscale 'Microsoft.Insights/autoscalesettings@2015-04-01' = {
  name: autoscaleName
  location: location
  properties: {
    enabled: true
    targetResourceLocation: location
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'default'
        capacity: {
          default: '1'
          minimum: '1'
          maximum: string(maxInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              cooldown: 'PT1M'
              value: '5'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThanOrEqual'
              threshold: 15
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              cooldown: 'PT2M'
              value: '10'
            }
          }
        ]
      }
    ]
  }
}

// Calculated using this resource: https://github.com/joelverhagen/data-azure-spot-vms/blob/main/vm-skus.csv
// If a SKU has both a CacheDisk and a ResourceDisk with a capacity of a least 30 GB, the larger is selected.
var skuInfo = {
  'Standard_D2a_v4': {
    diskSizeGB: 50
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2ads_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2as_v4': {
    diskSizeGB: 50
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_D2d_v4': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2d_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2ds_v4': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2ds_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D2s_v3': {
    diskSizeGB: 50
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_D4a_v4': {
    diskSizeGB: 100
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4ads_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4as_v4': {
    diskSizeGB: 100
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_D4d_v4': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4d_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4ds_v4': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4ds_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D4s_v3': {
    diskSizeGB: 100
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_D8a_v4': {
    diskSizeGB: 200
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8ads_v5': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8as_v4': {
    diskSizeGB: 200
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_D8d_v4': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8d_v5': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8ds_v4': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8ds_v5': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_D8s_v3': {
    diskSizeGB: 200
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DC2ads_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC2ds_v3': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC2s_v2': {
    diskSizeGB: 100
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC4ads_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC4ds_v3': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC4s_v2': {
    diskSizeGB: 200
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC8_v2': {
    diskSizeGB: 400
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DC8ads_v5': {
    diskSizeGB: 300
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_DS11_v2': {
    diskSizeGB: 72
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS11-1_v2': {
    diskSizeGB: 72
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS11': {
    diskSizeGB: 72
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS12_v2': {
    diskSizeGB: 144
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS12-1_v2': {
    diskSizeGB: 144
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS12-2_v2': {
    diskSizeGB: 144
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS12': {
    diskSizeGB: 144
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS2_v2': {
    diskSizeGB: 86
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS2': {
    diskSizeGB: 86
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS3_v2': {
    diskSizeGB: 172
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS3': {
    diskSizeGB: 172
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS4_v2': {
    diskSizeGB: 344
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_DS4': {
    diskSizeGB: 344
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E2a_v4': {
    diskSizeGB: 50
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2ads_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2as_v4': {
    diskSizeGB: 50
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E2bds_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2d_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2ds_v4': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2ds_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E2s_v3': {
    diskSizeGB: 50
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E4-2ads_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4-2as_v4': {
    diskSizeGB: 99
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E4-2ds_v4': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4-2ds_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4-2s_v3': {
    diskSizeGB: 100
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E4a_v4': {
    diskSizeGB: 100
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4ads_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4as_v4': {
    diskSizeGB: 100
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_E4bds_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4d_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4ds_v4': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4ds_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_E4s_v3': {
    diskSizeGB: 100
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_EC2ads_v5': {
    diskSizeGB: 75
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_EC4ads_v5': {
    diskSizeGB: 150
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_F16s_v2': {
    diskSizeGB: 256
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F16s': {
    diskSizeGB: 192
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F2s_v2': {
    diskSizeGB: 32
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F4s_v2': {
    diskSizeGB: 64
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F4s': {
    diskSizeGB: 48
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F8s_v2': {
    diskSizeGB: 128
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_F8s': {
    diskSizeGB: 96
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_GS1': {
    diskSizeGB: 264
    diffDiskPlacement: 'CacheDisk'
  }
  'Standard_L4s': {
    diskSizeGB: 678
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_NC4as_T4_v3': {
    diskSizeGB: 176
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_NV4as_v4': {
    diskSizeGB: 88
    diffDiskPlacement: 'ResourceDisk'
  }
  'Standard_NV8as_v4': {
    diskSizeGB: 176
    diffDiskPlacement: 'ResourceDisk'
  }
}
