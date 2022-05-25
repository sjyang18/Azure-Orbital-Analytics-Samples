targetScope='subscription'

param environmentCode string
param location string
var monitorRgName = '${environmentCode}-monitor-rg'
var orcRgName = '${environmentCode}-orc-rg'
var functionStorageAccountName = '${environmentCode}fapp'
var environmentName = 'synapse-${environmentCode}'
var functionAppName = '${environmentCode}-orc-fapp'
var functionName = 'base64EncodedZipContent'

resource applicationInsights 'microsoft.insights/components@2020-02-02-preview' existing = {
  name: '${environmentCode}-monitor-appinsights'
  scope: resourceGroup(monitorRgName)
}

module storageAccount '../infra/modules/storage.bicep' = {
  name: '${environmentCode}-functionapp-storage'
  scope: resourceGroup(orcRgName)
  params: {
    storageAccountName: functionStorageAccountName
    environmentName: environmentCode
    location: location
    storeType: 'fapp-storage'
  }
}

module hostPlan '../infra/modules/asp.bicep' = {
  name: '${environmentCode}-orc-asp'
  scope: resourceGroup(orcRgName)
  params: {
    aspName: '${environmentCode}-asp'
    aspKind: 'linux'
    aspReserved: true
    mewCount: 1
    skuTier: 'Dynamic'
    skuSize: 'Y1'
    skuName: 'Y1'
    location: location
    environmentName: environmentCode
  }
}

module functionApp '../infra/modules/functionapp.bicep' = {
  name: '${environmentCode}-orc-fapp'
  scope: resourceGroup(orcRgName)
  params: {
    functionAppName: functionAppName
    functionName: 'base64EncodedZipContent'
    location: location
    serverFarmId: hostPlan.outputs.id
    appInsightsInstrumentationKey: applicationInsights.properties.InstrumentationKey
    functionRuntime: 'python'
    storageAccountName: functionStorageAccountName
    storageAccountKey: storageAccount.outputs.primaryKey
    environmentName: environmentName
    extendedSiteConfig : {
      use32BitWorkerProcess: false
      linuxFxVersion: 'Python|3.9'     
    }
  }
}

module base64EncodedZipContentFunction '../infra/modules/function.bicep' = {
  name: '${environmentCode}-base64fs'
  scope: resourceGroup(orcRgName)
  params: {
    functionAppName: functionAppName 
    functionName: functionName
    functionFiles : {
      '__init__.py': loadTextContent('gen_base64_encoded_content.py')
    }
    functionLanguage: 'python'
  }
  dependsOn:[
    functionApp
  ]
}

module functionKey '../infra/modules/akv.secrets.bicep' = {
  name: '${functionName}-key'
  scope: resourceGroup('${environmentCode}-pipeline-rg')
  params: {
    environmentName: environmentName
    keyVaultName: '${environmentCode}-pipeline-kv'
    secretName: 'GenBase64EncondingFunctionKey' 
    secretValue: base64EncodedZipContentFunction.outputs.functionkey
  }
}

