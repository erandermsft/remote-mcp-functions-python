@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}

param sourceStorageAccountName string
param subnetResourceId string

@description('Document Intelligence SKU. Defaults to S0.')
param sku object = {
  name: 'S0'
}
@description('Whether to enable public network access. Defaults to Enabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'
@description('Whether to disable local (key-based) authentication. Defaults to true.')
param disableLocalAuth bool = true

param managedIdentityPrincipalId string

var docIntelliUserRoleDefinitionId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services Document Intelligence User role ID
//assign docIntelliUserRoleDefinitionId to umi on Document Intelligence instance
resource docIntelliRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01'   =  {
    name: guid(documentIntelligence.id, managedIdentityPrincipalId, docIntelliUserRoleDefinitionId) // Use managed identity ID
    scope: documentIntelligence
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', docIntelliUserRoleDefinitionId)
      principalId: managedIdentityPrincipalId // Use managed identity ID
      principalType: 'ServicePrincipal' // Managed Identity is a Service Principal
    }
  }

resource sourceStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: sourceStorageAccountName
}

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'FormRecognizer'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: toLower(name)
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: publicNetworkAccess
  }
  sku: sku
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(documentIntelligence.id, sourceStorageAccount.name, 'StorageBlobDataContributor')
  scope: sourceStorageAccount
  properties: {
    principalId: documentIntelligence.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}

module docintelPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = {
  name: 'docintel-private-endpoint-deployment'
  params: {
    name: 'docintel-private-endpoint'
    location: location
    tags: tags
    subnetResourceId: subnetResourceId
    privateLinkServiceConnections: [
      {
        name: 'blobPrivateLinkConnection'
        properties: {
          privateLinkServiceId: documentIntelligence.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
    customDnsConfigs: []
    privateDnsZoneGroup: null
   
  }
}


@description('ID for the deployed Document Intelligence resource.')
output id string = documentIntelligence.id
@description('Name for the deployed Document Intelligence resource.')
output name string = documentIntelligence.name
@description('Endpoint for the deployed Document Intelligence resource.')
output endpoint string = documentIntelligence.properties.endpoint
@description('Host for the deployed Document Intelligence resource.')
output host string = split(documentIntelligence.properties.endpoint, '/')[2]
@description('Identity principal ID for the deployed Document Intelligence resource.')
output systemIdentityPrincipalId string = documentIntelligence.identity.principalId
