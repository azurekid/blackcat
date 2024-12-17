param location string = resourceGroup().location
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

var containers = [
  'files'
  'backup'
  'images'
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true // Enable anonymous access at account level
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource containers_res 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in containers: {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'Container' // Set to 'Container' for full public read access or 'Blob' for anonymous read access to blobs only
    metadata: {}
  }
}]
