@description('Name of the blob as it is stored in the blob container')
param filename1 string = 'content'

@description('Name of the blob as it is stored in the blob container')
param filename2 string = 'index.html'

@description('Name of the blob as it is stored in the blob container')
param filename3 string = 'styles.css'

@description('UTC timestamp used to create distinct deployment scripts for each deployment')
param utcValue string = utcNow()

@description('Name of the blob container')
param containerName string = 'data'

@description('Name of the blob container')
param staticwebContainer string = '$web'

@description('Azure region where resources should be deployed')
param location string = resourceGroup().location

@description('Desired name of the storage account')
param storageAccountName string = uniqueString(resourceGroup().id, deployment().name, 'blob')

resource storage 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'

  resource blobService 'blobServices' = {
    name: 'default'

    resource data 'containers' = {
      name: containerName
    }

    resource staticweb 'containers' = {
      name: 
    }
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deployscript-upload-content-${utcValue}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.26.1'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storage.name
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storage.listKeys().keys[0].value
      }
      {
        name: 'CONTENT'
        value: loadTextContent('../data/content')
      }
    ]
     scriptContent: 'echo "$CONTENT" > ${filename} && az storage blob upload -f ${filename} -c "${containerName}" -n "secrets.json"'
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deployscript-upload-content-${utcValue}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.26.1'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storage.name
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storage.listKeys().keys[0].value
      }
      {
        name: 'CONTENT'
        value: loadTextContent('../data/index.html')
      }
    ]
     scriptContent: 'echo "$CONTENT" > ${filename2} && az storage blob upload -f ${filename2} -c "${containerName}" -n ${filename2}'
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deployscript-upload-content-${utcValue}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.26.1'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storage.name
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storage.listKeys().keys[0].value
      }
      {
        name: 'CONTENT'
        value: loadTextContent('../data/styles.css')
      }
    ]
     scriptContent: 'echo "$CONTENT" > ${filename3} && az storage blob upload -f ${filename3} -c "${containerName}" -n ${filename3}'
  }
}
