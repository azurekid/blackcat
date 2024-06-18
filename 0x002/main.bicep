targetScope = 'subscription'

param location string = deployment().location

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '0x002-blackcat'
  location: location
}

module blob 'modules/blob.bicep' = {
  name: 'blob-example'
  scope: rg
  params: {
    location: location
  }
}
