// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

// List of required parameters
param environmentCode string
param environmentTag string
param projectName string
param location string

param synapseMIPrincipalId string
// Guid to role definitions to be used during role
// assignments including the below roles definitions:
// Contributor
param synapseMIBatchAccountRoles array = [
  'b24988ac-6180-42a0-ab88-20f7382dd24c'
]

// Name parameters for infrastructure resources
param orchestrationResourceGroupName string = ''
param keyvaultName string = ''
param batchAccountName string = ''
param batchAccountAutoStorageAccountName string = ''
param acrName string = ''
param uamiName string = ''
param aksClusterName string = ''
param functionStorageAccountName string = ''

param pipelineResourceGroupName string
param pipelineLinkedSvcKeyVaultName string

// Mount options
param mountAccountName string
param mountAccountKey string
param mountFileUrl string

// Parameters with default values for Keyvault
param keyvaultSkuName string = 'Standard'
param objIdForKeyvaultAccessPolicyPolicy string = ''
param keyvaultCertPermission array = [
  'All'
]
param keyvaultKeyPermission array = [
  'All'
]
param keyvaultSecretPermission array = [
  'All'
]
param keyvaultStoragePermission array = [
  'All'
]
param keyvaultUsePublicIp bool = true
param keyvaultPublicNetworkAccess bool = true
param keyvaultEnabledForDeployment bool = true
param keyvaultEnabledForDiskEncryption bool = true
param keyvaultEnabledForTemplateDeployment bool = true
param keyvaultEnablePurgeProtection bool = true
param keyvaultEnableRbacAuthorization bool = false
param keyvaultEnableSoftDelete bool = true
param keyvaultSoftDeleteRetentionInDays int = 7

// Parameters with default values  for Batch Account
param allowedAuthenticationModesBatchSvc array = [
  'AAD'
  'SharedKey'
  'TaskAuthenticationToken'
]
param allowedAuthenticationModesUsrSub array = [
  'AAD'
  'TaskAuthenticationToken'
]

param batchAccountAutoStorageAuthenticationMode string = 'StorageKeys'
param batchAccountPoolAllocationMode string = 'BatchService'
param batchAccountPublicNetworkAccess bool = true

// Parameters with default values  for Data Fetch Batch Account Pool
param batchAccountCpuOnlyPoolName string = 'data-cpu-pool'
param batchAccountCpuOnlyPoolVmSize string = 'standard_d2s_v3'
param batchAccountCpuOnlyPoolDedicatedNodes int = 1
param batchAccountCpuOnlyPoolImageReferencePublisher string = 'microsoft-azure-batch'
param batchAccountCpuOnlyPoolImageReferenceOffer string = 'ubuntu-server-container'
param batchAccountCpuOnlyPoolImageReferenceSku string = '20-04-lts'
param batchAccountCpuOnlyPoolImageReferenceVersion string = 'latest'
param batchAccountCpuOnlyPoolStartTaskCommandLine string = '/bin/bash -c "apt-get update && apt-get install -y python3-pip && pip install requests && pip install azure-storage-blob && pip install pandas"'

param batchLogsDiagCategories array = [
  'allLogs'
]
param batchMetricsDiagCategories array = [
  'AllMetrics'
]
param logAnalyticsWorkspaceId string
param appInsightsInstrumentationKey string
// Parameters with default values for ACR
param acrSku string = 'Standard'

var namingPrefix = '${environmentCode}-${projectName}'
var orchestrationResourceGroupNameVar = empty(orchestrationResourceGroupName) ? '${namingPrefix}-rg' : orchestrationResourceGroupName
var nameSuffix = substring(uniqueString(orchestrationResourceGroupNameVar), 0, 6)
var uamiNameVar = empty(uamiName) ? '${namingPrefix}-umi' : uamiName
var keyvaultNameVar = empty(keyvaultName) ? '${namingPrefix}-kv' : keyvaultName
var batchAccountNameVar = empty(batchAccountName) ? '${environmentCode}${projectName}batchact' : batchAccountName
var batchAccountAutoStorageAccountNameVar = empty(batchAccountAutoStorageAccountName) ? 'batchacc${nameSuffix}' : batchAccountAutoStorageAccountName
var acrNameVar = empty(acrName) ? '${environmentCode}${projectName}acr' : acrName
var aksClusterNameVar = empty(aksClusterName) ? '${environmentCode}${projectName}aks' : aksClusterName
var functionStorageAccountNameVar = empty(functionStorageAccountName) ? 'funxacc${nameSuffix}' : functionStorageAccountName

module keyVault '../modules/akv.bicep' = {
  name: '${namingPrefix}-akv'
  params: {
    environmentName: environmentTag
    keyVaultName: keyvaultNameVar
    location: location
    skuName:keyvaultSkuName
    objIdForAccessPolicyPolicy: objIdForKeyvaultAccessPolicyPolicy
    certPermission:keyvaultCertPermission
    keyPermission:keyvaultKeyPermission
    secretPermission:keyvaultSecretPermission
    storagePermission:keyvaultStoragePermission
    usePublicIp: keyvaultUsePublicIp
    publicNetworkAccess:keyvaultPublicNetworkAccess
    enabledForDeployment: keyvaultEnabledForDeployment
    enabledForDiskEncryption: keyvaultEnabledForDiskEncryption
    enabledForTemplateDeployment: keyvaultEnabledForTemplateDeployment
    enablePurgeProtection: keyvaultEnablePurgeProtection
    enableRbacAuthorization: keyvaultEnableRbacAuthorization
    enableSoftDelete: keyvaultEnableSoftDelete
    softDeleteRetentionInDays: keyvaultSoftDeleteRetentionInDays
  }
}

module batchAccountAutoStorageAccount '../modules/storage.bicep' = {
  name: '${namingPrefix}-batch-account-auto-storage'
  params: {
    storageAccountName: batchAccountAutoStorageAccountNameVar
    environmentName: environmentTag
    location: location
    storeType: 'batch'
  }
}

module batchStorageAccountCredentials '../modules/storage.credentials.to.keyvault.bicep' = {
  name: '${namingPrefix}-batch-storage-credentials'
  params: {
    environmentName: environmentTag
    storageAccountName: batchAccountAutoStorageAccountNameVar
    keyVaultName: keyvaultNameVar
    keyVaultResourceGroup: resourceGroup().name
    secretNamePrefix: 'Batch'
  }
  dependsOn: [
    keyVault
    batchAccountAutoStorageAccount
  ]
}

module uami '../modules/managed.identity.user.bicep' = {
  name: '${namingPrefix}-umi'
  params: {
    environmentName: environmentTag
    location: location
    uamiName: uamiNameVar
  }
}

module batchAccount '../modules/batch.account.bicep' = {
  name: '${namingPrefix}-batch-account'
  params: {
    environmentName: environmentTag
    location: location
    batchAccountName: toLower(batchAccountNameVar)
    userManagedIdentityId: uami.outputs.uamiId
    userManagedIdentityPrincipalId: uami.outputs.uamiPrincipalId
    allowedAuthenticationModes: batchAccountPoolAllocationMode == 'BatchService' ? allowedAuthenticationModesBatchSvc : allowedAuthenticationModesUsrSub
    autoStorageAuthenticationMode: batchAccountAutoStorageAuthenticationMode
    autoStorageAccountName: batchAccountAutoStorageAccountNameVar
    poolAllocationMode: batchAccountPoolAllocationMode
    publicNetworkAccess: batchAccountPublicNetworkAccess
    keyVaultName: keyvaultNameVar
  }
  dependsOn: [
    uami
    batchAccountAutoStorageAccount
    keyVault
  ]
}

module synapseIdentityForBatchAccess '../modules/batch.account.role.assignment.bicep' = [ for role in synapseMIBatchAccountRoles: {
  name: '${namingPrefix}-batch-account-role-assgn'
  params: {
    resourceName: toLower(batchAccountNameVar)
    principalId: synapseMIPrincipalId
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${role}'
  }
  dependsOn: [
    batchAccount
  ]
}]

module batchAccountPoolCheck '../modules/batch.account.pool.exists.bicep' = {
  name: '${namingPrefix}-batch-account-pool-exists'
  params: {
    batchAccountName: batchAccountNameVar
    batchPoolName: batchAccountCpuOnlyPoolName
    userManagedIdentityName: uami.name
    userManagedIdentityResourcegroupName: resourceGroup().name
    location: location
  }
  dependsOn: [
    batchAccountAutoStorageAccount
    batchAccount
  ]
}

module batchAccountCpuOnlyPool '../modules/batch.account.pools.bicep' = {
  name: '${namingPrefix}-batch-account-data-fetch-pool'
  params: {
    batchAccountName: batchAccountNameVar
    batchAccountPoolName: batchAccountCpuOnlyPoolName
    vmSize: batchAccountCpuOnlyPoolVmSize
    fixedScaleTargetDedicatedNodes: batchAccountCpuOnlyPoolDedicatedNodes
    imageReferencePublisher: batchAccountCpuOnlyPoolImageReferencePublisher
    imageReferenceOffer: batchAccountCpuOnlyPoolImageReferenceOffer
    imageReferenceSku: batchAccountCpuOnlyPoolImageReferenceSku
    imageReferenceVersion: batchAccountCpuOnlyPoolImageReferenceVersion
    startTaskCommandLine: batchAccountCpuOnlyPoolStartTaskCommandLine
    azureFileShareConfigurationAccountKey: mountAccountKey
    azureFileShareConfigurationAccountName: mountAccountName
    azureFileShareConfigurationAzureFileUrl: mountFileUrl
    azureFileShareConfigurationMountOptions: '-o vers=3.0,dir_mode=0777,file_mode=0777,sec=ntlmssp'
    azureFileShareConfigurationRelativeMountPath: 'S'
    batchPoolExists: batchAccountPoolCheck.outputs.batchPoolExists
  }
  dependsOn: [
    batchAccountAutoStorageAccount
    batchAccount
    batchAccountPoolCheck
  ]
}

module acr '../modules/acr.bicep' = {
  name: '${namingPrefix}-acr'
  params: {
    environmentName: environmentTag
    location: location
    acrName: acrNameVar
    acrSku: acrSku
  }
}

module acrCredentials '../modules/acr.credentials.to.keyvault.bicep' = {
  name: '${namingPrefix}-acr-credentials'
  params: {
    environmentName: environmentTag
    acrName: acrNameVar
    keyVaultName: keyvaultNameVar

  }
  dependsOn: [
    keyVault
    acr
  ]
}

module batchAccountCredentials '../modules/batch.account.to.keyvault.bicep' = {
  name: '${namingPrefix}-batch-account-credentials'
  params: {
    environmentName: environmentTag
    batchAccoutName: toLower(batchAccountNameVar)
    keyVaultName: pipelineLinkedSvcKeyVaultName
    keyVaultResourceGroup: pipelineResourceGroupName
  }
  dependsOn: [
    keyVault
    batchAccount
  ]
}

module batchDiagnosticSettings '../modules/batch-diagnostic-settings.bicep' = {
  name: '${namingPrefix}-synapse-diag-settings'
  params: {
    batchAccountName: batchAccountNameVar
    logs: [for category in batchLogsDiagCategories: {
        category: null
        categoryGroup: category
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }]
    metrics: [for category in batchMetricsDiagCategories: {
        category: category
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
    }]
    workspaceId: logAnalyticsWorkspaceId
  }
  dependsOn: [
    batchAccount
  ]
}

module aksCluster '../modules/aks-cluster.bicep' = {
  name: '${namingPrefix}-aks'
  params: {
    environmentName: environmentTag
    clusterName: aksClusterNameVar
    location: location
    logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
  }
}

module attachACRtoAKS '../modules/aks-attach-acr.bicep' = {
  name: '${namingPrefix}-attachACRtoAKS'
  params: {
    kubeletIdentityId: aksCluster.outputs.kubeletIdentityId
    acrName:  acrNameVar
  }
}

module aksInvokerRoleDef '../modules/custom.roledef.bicep' = {
  name: '${namingPrefix}-AKSInvokerCustomRole'
  params: {
    actions: [
      'Microsoft.ContainerService/managedClusters/runcommand/action'
      'Microsoft.ContainerService/managedclusters/commandResults/read'
    ]
    roleDescription: 'Can invoke and read runcommand to/from AKS'
    roleName: 'custom-role-for-${aksClusterNameVar}'
  }
}

module aksCustomRoleAssignment '../modules/aks-invoker-role-assignment.bicep' = {
  name: 'custom-role-assignment-for-${aksClusterNameVar}'
  params: {
    principalId: synapseMIPrincipalId
    aksClusterName: aksClusterNameVar
    customRoleDefId: aksInvokerRoleDef.outputs.Id
  }
  dependsOn: [
    aksCluster
  ]
}

module functionAppStorageAccount '../modules/storage.bicep' = {
  name: '${namingPrefix}-functionapp-storage'
  params: {
    storageAccountName: functionStorageAccountNameVar
    environmentName: environmentTag
    location: location
    storeType: 'fapp-storage'
  }
}

module functionAppHostPlan '../modules/asp.bicep' = {
  name: '${namingPrefix}-asp'
  params: {
    aspName: '${namingPrefix}-asp'
    aspKind: 'linux'
    aspReserved: true
    mewCount: 1
    skuTier: 'Dynamic'
    skuSize: 'Y1'
    skuName: 'Y1'
    location: location
    environmentName: environmentTag
  }
}

module functionApp '../modules/functionapp.bicep' = {
  name: '${namingPrefix}-fapp'
  params: {
    functionAppName: '${namingPrefix}-fapp'
    functionName: 'base64EncodedZipContent'
    location: location
    serverFarmId: functionAppHostPlan.outputs.id
    appInsightsInstrumentationKey: appInsightsInstrumentationKey
    functionRuntime: 'python'
    storageAccountName: functionStorageAccountNameVar
    storageAccountKey: functionAppStorageAccount.outputs.primaryKey
    environmentName: environmentTag
    extendedSiteConfig : {
      use32BitWorkerProcess: false
      linuxFxVersion: 'Python|3.9'     
    }
  }
}

module base64EncodedZipContentFunction '../modules/function.bicep' = {
  name: '${namingPrefix}-base64fapp'
  params: {
    functionAppName: '${namingPrefix}-fapp'
    functionName: 'base64EncodedZipContent'
    functionFiles : {
      '__init__.py': loadTextContent('gen_base64_encoded_content.py')
    }
    functionLanguage: 'python'
  }
  dependsOn:[
    functionApp
  ]
}

module functionKey '../modules/akv.secrets.bicep' = {
  name: '${namingPrefix}-base64fapp-fkey'
  scope: resourceGroup(pipelineResourceGroupName)
  params: {
    environmentName: environmentTag
    keyVaultName: '${environmentCode}-pipeline-kv'
    secretName: 'GenBase64EncondingFunctionKey' 
    secretValue: base64EncodedZipContentFunction.outputs.functionkey
  }
}




