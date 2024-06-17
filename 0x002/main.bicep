targetScope = 'subscription'

@description('Deploy the blob example')
param blobExample bool = false

@description('Deploy the file share example')
param fileExample bool = true

param location string = deployment().location

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-upload-to-storage-example'
  location: location
  tags: {
    'application': 'azure-bicep-upload-data-to-storage'
  }
}

module blob 'modules/blob.bicep' = if (blobExample) {
  name: 'blob-example'
  scope: rg
  params: {
    location: location
  }
}

module file 'modules/file.bicep' = if (fileExample) {
  name: 'file-example'
  scope: rg
  params: {
    location: location
  }
}
