param resourceGroupNames array = [
    '0x001-blackcat'
]

targetScope = 'subscription'

resource resourceGroups 'Microsoft.Resources/resourceGroups@2022-09-01' = [for (name, index) in resourceGroupNames: {
    name: name
    location: 'eastus'
    tags: {
        environment: 'devsecops'
    }
}]
